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
		# `pin` is `[column, value]` when the scope is that one column having that one value
		Rule = Data.define(:table, :columns, :limited, :scope, :pin) do
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
				@rules[key(table.name)] = Rule.new(table: table.name, columns: visible.freeze, limited:, scope: parse_scope(scope), pin: pin_of(table, scope))
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

			reads = resolve(stmt)

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

		# The catalog as this policy lets it be seen: the declared tables, with the columns that may be read
		def restricted_catalog = @catalog.restricted(@rules.values.to_h { |rule| [rule.table, rule.limited ? rule.columns : :all] })

		# The same as CREATE TABLE statements, to show whoever writes the SQL what there is to query
		def restricted_schema = restricted_catalog.tables.filter_map(&:to_sql).join(";\n")

		# Changes nothing and runs nothing: raises unless `sql` already keeps to the policy on its own.
		# Every table with a `{column => value}` scope has to be held to that value where it is read or
		# written, by a condition the rows cannot get around. `binds` are the values for the `?`s
		def check!(sql, binds = [])
			statements = Plume.parse(sql)
			stmt = statements.first
			raise Denied.new("expected exactly one statement, got #{statements.size}") unless statements.size == 1
			return true if TRANSACTIONS.any? { |kind| kind === stmt }

			unless ROWS.any? { |kind| kind === stmt }
				raise Denied.new("only reading and writing rows is allowed, got #{stmt.class.name.delete_prefix("Plume::")}", node: stmt)
			end

			reads = resolve(stmt)
			Pins.new(stmt, reads.ctes, bound(stmt, binds), method(:rule_for)).check!
			true
		end

		private

		TRANSACTIONS = [BeginStatement, CommitStatement, RollbackStatement, SavepointStatement, ReleaseStatement].freeze
		ROWS = [SelectStatement, InsertStatement, UpdateStatement, DeleteStatement].freeze
		private_constant :TRANSACTIONS, :ROWS

		# Each `?` of the statement with the value it will be given
		def bound(stmt, binds)
			Plume.parameters(stmt).each_with_object({}.compare_by_identity) do |parameter, values|
				values[parameter.node] = binds[parameter.number - 1] if parameter.number <= binds.size
			end
		end

		def pin_of(table, scope)
			return nil unless Hash === scope
			raise ArgumentError, "a scope of one column and one value, got #{scope.inspect}" unless scope.size == 1

			column, value = scope.first
			raise ArgumentError, "a scope value is a number or a string, got #{value.inspect}" unless Integer === value || String === value

			[existing_column(table, column), value].freeze
		end

		def key(name) = name.to_s.downcase(:ascii)

		def existing_column(table, name)
			table.columns.find { |c| Catalog.same_name?(c, name) } or raise ArgumentError, "no column #{name} in #{table.name}"
		end

		# A WHERE fragment, or a whole SELECT as SQL or as something that prints as one
		def parse_scope(scope)
			return nil if scope.nil?

			if Hash === scope
				column, value = scope.first
				scope = "#{quote(column)} = #{(String === value) ? "'#{value.gsub("'", "''")}'" : Integer(value)}"
			end
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

		# The statement is analyzed against the restricted catalog, so anything outside the policy
		# is simply not there - and names resolve the way they will in the rewritten SQL
		def resolve(stmt)
			restricted = restricted_catalog
			reads =
				begin
					Plume.reads(stmt, catalog: restricted)
				rescue Analysis::Error => e
					raise Denied.new([e.message, visible(stmt, restricted)].compact.join("\n"), node: e.unresolved.first&.node)
				end

			reads.functions.each do |function|
				next if @functions.include?(function)

				node = find(stmt, TableFunction, function)
				raise Denied.new("not allowed to call #{function}\n#{excerpt(node)}", node:)
			end

			# A CTE named like a declared table next to a read of that table cannot be told apart by name
			ctes = reads.ctes.to_set { |name| name.downcase(:ascii) }
			reads.references.each do |ref|
				next unless TableName === ref.node && ref.node.schema.nil? && ctes.include?(key(ref.node.table))

				raise Denied.new("#{ref.node.table} is both a table and a WITH name here\n#{excerpt(ref.node)}", node: ref.node)
			end
			reads
		end

		def visible(stmt, restricted)
			tables = stmt.walk.filter_map { |node, _| restricted.table(node.table, schema: node.schema) if TableName === node }.uniq
			"visible: #{tables.map { |t| "#{t.name} (#{t.columns.join(", ")})" }.join(", ")}" if tables.any?
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

		# Whether every table that has a pin is held to it wherever the statement touches it.
		# Only what cannot be got around counts: a top-level AND term of the WHERE, or of the ON
		# of the join that brings the table in, saying `column = value` or `column IN (value)` -
		# or saying the column equals the pinned column of another table that is held already.
		# An OR, a subquery or anything else that would need thinking about does not count
		class Pins
			UNKNOWN = Object.new.freeze
			Source = Struct.new(:table, :rule, :terms)

			def initialize(stmt, ctes, bound, rule_for)
				@stmt = stmt
				@ctes = ctes.to_set { |name| name.downcase(:ascii) }
				@bound = bound
				@rule_for = rule_for
			end

			def check!
				@stmt.walk do |node, _parent|
					case node
					when SelectCore then held!(sources(node.source), node.condition, "read")
					when UpdateStatement
						held!([[node.table, []], *sources(node.source)], node.condition, "updated")
						unchanged!(node.table, node.assignments)
					when DeleteStatement then held!([[node.table, []]], node.condition, "deleted from")
					when InsertStatement then inserted!(node)
					end
				end
			end

			private

			# Every table named in a FROM, each with the terms of the ON that brought it in
			def sources(source)
				case source
				when TableName then [[source, []]]
				when ParentheticalSource then sources(source.source)
				when JoinClause
					sources(source.left) + source.joins.flat_map do |join|
						# What a RIGHT or FULL join keeps of this side, its ON did not filter
						filters = JoinOnConstraint === join.constraint && %i[INNER LEFT CROSS COMMA].include?(join.operator.kind)
						on = filters ? terms(join.constraint.expression) : []
						sources(join.source).map { |table, own| [table, own + on] }
					end
				else []
				end
			end

			def terms(expression)
				case expression
				when nil then []
				when ParentheticalExpression then (Array === expression.value) ? [expression] : terms(expression.value)
				when BinaryExpression then (expression.operator == :ALL) ? terms(expression.left) + terms(expression.right) : [expression]
				else [expression]
				end
			end

			def held!(tables, condition, verb)
				where = terms(condition)
				all = tables.map { |table, on| Source.new(table, rule(table), where + on) }
				pinned = all.select { |s| s.rule&.pin }
				unpinnable = all.find { |s| s.rule&.scope && !s.rule.pin }
				raise Denied.new("#{unpinnable.rule.table} has a scope that cannot be checked, only applied", node: unpinnable.table) if unpinnable

				held = {}.compare_by_identity
				loop do
					newly = pinned.reject { |s| held[s] }.select { |s| s.terms.any? { |term| pins?(term, s, all, held) } }
					break if newly.empty?

					newly.each { |s| held[s] = true }
				end

				loose = pinned.find { |s| !held[s] } or return
				column, value = loose.rule.pin
				raise Denied.new("#{loose.rule.table} is #{verb} without #{column} = #{value.inspect}\n#{Analysis.excerpt(loose.table)}", node: loose.table)
			end

			def rule(table)
				return nil if table.schema.nil? && @ctes.include?(table.table.downcase(:ascii))

				@rule_for.(table)
			end

			def pins?(term, source, all, held)
				return false unless BinaryExpression === term

				column = source.rule.pin.first
				case term.operator
				when :EQUALS
					[[term.left, term.right], [term.right, term.left]].any? do |mine, other|
						next false unless names?(mine, source, column, all)

						same?(other, source) || all.any? { |o| held[o] && o.rule.pin[1] == source.rule.pin[1] && names?(other, o, o.rule.pin[0], all) }
					end
				when :IN
					list = term.right.value if ParentheticalExpression === term.right
					names?(term.left, source, column, all) && Array === list && list.any? && list.all? { |item| same?(item, source) }
				else false
				end
			end

			# Whether `node` is this column of this source. A bare column name only says so when there is nothing else in the FROM
			def names?(node, source, column, all)
				return false unless ColumnName === node && Catalog.same_name?(node.column, column)
				return all.size == 1 if node.table.nil?

				Catalog.same_name?(node.table, source.table.alias || source.table.table) && (node.schema.nil? || source.table.alias.nil?)
			end

			def same?(node, source) = value(node) == source.rule.pin[1]

			def value(node)
				case node
				when LiteralExpression then node.value
				when Variable then @bound.fetch(node, UNKNOWN)
				when ParentheticalExpression then (Array === node.value) ? UNKNOWN : value(node.value)
				else UNKNOWN
				end
			end

			def unchanged!(table, assignments)
				pin = rule(table)&.pin or return
				moved = assignments.flat_map(&:columns).find { |c| Catalog.same_name?(c.column, pin[0]) } or return
				raise Denied.new("#{pin[0]} of #{table.table} cannot be changed\n#{Analysis.excerpt(moved)}", node: moved)
			end

			def inserted!(stmt)
				rule = rule(stmt.table) or return
				raise Denied.new("#{rule.table} has a scope that cannot be checked, only applied", node: stmt.table) if rule.scope && !rule.pin

				pin = rule.pin or return
				column, wanted = pin
				at = stmt.columns&.index { |c| Catalog.same_name?(c.column, column) }
				rows = stmt.select&.body
				ok = at && ValuesClause === rows && rows.rows.all? { |row| value(row.values[at]) == wanted }
				raise Denied.new("#{stmt.table.table} is inserted into without #{column} = #{wanted.inspect}\n#{Analysis.excerpt(stmt.table)}", node: stmt.table) unless ok

				(stmt.upserts || []).each { |upsert| unchanged!(stmt.table, upsert.assignments || []) }
			end
		end
		private_constant :Pins
	end
end
