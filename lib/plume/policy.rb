# frozen_string_literal: true

module Plume
	# Declares which tables an untrusted SELECT may read, and rewrites the SELECT so that each
	# declared table is replaced by a subquery that only shows the permitted columns and rows.
	# Whatever is not declared is denied. Built per request, for one user, so scopes are plain SQL
	# with that user's values in them:
	#
	#   policy = Plume::Policy.new(catalog:) do |p|
	#     p.table :projects, read: :all
	#     p.table :users, read: %i[id name]
	#     p.table :posts, scope: "account_id = 1"
	#   end
	#   policy.scope("SELECT title FROM posts") # => SELECT title FROM (SELECT ... FROM "posts" WHERE (account_id = 1)) AS "posts"
	class Policy
		# What a statement may not do. `node` is the part of it that was refused, where there is one
		class Denied < StandardError
			attr_reader :node

			def initialize(message = nil, node: nil)
				@node = node
				super(message)
			end
		end

		# The rewrite left a declared table unsubstituted. A bug here, not in the SQL given
		class RewriteError < StandardError; end

		# `columns` are the visible ones, `limited` is whether that is fewer than the table has,
		# `scope` is `[:where, sql]` or `[:select, sql]`, or nil
		Rule = Data.define(:table, :columns, :limited, :scope) do
			def rewritten? = limited || !scope.nil?
		end

		def initialize(catalog:)
			@catalog = catalog
			@rules = {}
			@functions = []
			yield self if block_given?
		end

		def table(*names, read: :all, scope: nil)
			raise FrozenError, "can't modify frozen #{self.class}" if frozen?

			names.each do |name|
				table = @catalog.table(name.to_s) or raise ArgumentError, "no table #{name} in the catalog"
				visible = (read == :all) ? table.columns : Array(read).map { |c| existing_column(table, c) }
				limited = (table.columns - visible).any?
				@rules[key(table.name)] = Rule.new(table: table.name, columns: visible.freeze, limited:, scope: parse_scope(scope))
			end
			self
		end

		def functions(*names)
			raise FrozenError, "can't modify frozen #{self.class}" if frozen?

			@functions.concat(names.map { |n| n.to_s.downcase(:ascii) })
			self
		end

		def freeze
			@rules.each_value(&:freeze).freeze
			@functions.freeze
			super
		end

		# The SQL with every declared table swapped for its scoped subquery
		def scope(sql)
			statements = Plume.parse(sql)
			stmt = statements.first
			raise Denied.new("expected exactly one statement, got #{statements.size}") unless statements.size == 1
			raise Denied.new("only SELECT is allowed, got #{stmt.class.name.delete_prefix("Plume::")}", node: stmt) unless SelectStatement === stmt

			reads =
				begin
					Plume.reads(stmt, catalog: @catalog)
				rescue Analysis::Error => e
					raise Denied.new(e.message)
				end
			check(stmt, reads)

			substitutes = {}.compare_by_identity
			ctes = reads.ctes.to_set { |name| name.downcase(:ascii) }
			result = stmt.transform do |node, _parent|
				next node unless TableName === node

				rule = rule_for(node)
				next node if rule.nil? || shadowed?(node, ctes)
				next node unless rule.rewritten?

				substitute(node, rule).tap { |sub| substitutes[sub] = true }
			end
			verify(result, substitutes, ctes)
			result.to_sql
		end

		private

		def key(name) = name.to_s.downcase(:ascii)

		def existing_column(table, name)
			table.columns.find { |c| Catalog.same_name?(c, name) } or raise ArgumentError, "no column #{name} in #{table.name}"
		end

		# A WHERE fragment, or a whole SELECT as SQL or as something that prints as one
		def parse_scope(scope)
			return nil if scope.nil?

			sql = scope.respond_to?(:to_sql) ? scope.to_sql : scope.to_s
			if sql.match?(/\A\s*(select|with|values)\b/i)
				stmts = Plume.parse(sql)
				raise ArgumentError, "a scope must be one SELECT" unless stmts.size == 1 && SelectStatement === stmts.first

				[:select, no_variables(stmts.first).to_sql].freeze
			else
				core = Plume.parse("SELECT 1 WHERE #{sql}\n").first.body
				raise ArgumentError, "not a WHERE condition: #{sql}" unless SelectCore === core && core.source.nil? && core.columns.size == 1

				[:where, no_variables(core.condition).to_sql].freeze
			end
		rescue SyntaxError => e
			raise ArgumentError, "the scope does not parse: #{e.message}"
		end

		def no_variables(node)
			raise ArgumentError, "a scope cannot have bind parameters" if node.walk.any? { |n, _| Variable === n }

			node
		end

		def rule_for(node)
			return nil unless node.schema.nil? || Catalog.same_name?(node.schema, "main")

			@rules[key(node.table)]
		end

		# A name that a CTE defines, unqualified, is the CTE and not the table
		def shadowed?(node, ctes) = node.schema.nil? && ctes.include?(key(node.table))

		def check(stmt, reads)
			if (view = reads.views.first)
				raise Denied.new("not allowed to read view #{view}, a view cannot be scoped\n#{excerpt(find(stmt, TableName, view))}", node: find(stmt, TableName, view))
			end

			reads.functions.each do |function|
				next if @functions.include?(function)

				node = find(stmt, TableFunction, function)
				raise Denied.new("not allowed to call #{function}\n#{excerpt(node)}", node:)
			end

			reads.references.each do |ref|
				rule = @rules[key(ref.table_key)]
				raise Denied.new("not allowed to read #{ref.table_key}\n#{excerpt(ref.node)}", node: ref.node) if rule.nil?

				# A star is cut down to the visible columns by the substitute
				next if ref.column.nil? || StarResultColumn === ref.node
				next if rule.columns.any? { |c| Catalog.same_name?(c, ref.column) }

				raise Denied.new(
					"not allowed to read #{ref.table_key}.#{ref.column}\n#{excerpt(ref.node)}\nvisible columns: #{rule.columns.join(", ")}",
					node: ref.node,
				)
			end

			# A CTE named like a declared table next to a read of that table cannot be told apart by name
			ctes = reads.ctes.to_set { |name| name.downcase(:ascii) }
			reads.references.each do |ref|
				next unless TableName === ref.node && ref.node.schema.nil? && ctes.include?(key(ref.node.table))

				raise Denied.new("#{ref.node.table} is both a table and a WITH name here\n#{excerpt(ref.node)}", node: ref.node)
			end
		end

		def substitute(node, rule)
			columns = rule.columns.map { |c| quote(c) }.join(", ")
			kind, sql = rule.scope
			from = (kind == :select) ? "(#{sql})" : quote(rule.table)
			inner = "SELECT #{columns} FROM #{from}#{" WHERE (#{sql})" if kind == :where}"
			SubquerySource.new(select: Plume.parse(inner).first, alias: node.alias || node.table)
		end

		# Nothing outside the substitutes may still name a table that had to be rewritten
		def verify(result, substitutes, ctes)
			stack = [result]
			while (node = stack.pop)
				next if substitutes.key?(node)

				if TableName === node && (rule = rule_for(node))&.rewritten? && !shadowed?(node, ctes)
					raise RewriteError, "#{rule.table} was left in the rewritten SQL"
				end
				stack.concat(node.children)
			end
		end

		def find(stmt, klass, name)
			stmt.walk.find { |n, _| klass === n && Catalog.same_name?(n.name, name.to_s.split(".").last) }&.first
		end

		def excerpt(node) = Analysis.excerpt(node)

		def quote(identifier) = %("#{identifier.to_s.gsub('"', '""')}")
	end
end
