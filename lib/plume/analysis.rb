# frozen_string_literal: true

module Plume
	# Static analysis on top of the AST. The first question it answers is "which tables and
	# columns would this statement read?", see `Plume.reads`; the second is what it would
	# write, see `Plume.writes`.
	module Analysis
		autoload :Resolver, "plume/analysis/resolver"

		# A read or write of one column, or of a table as a whole when `column` is nil - which is
		# what `SELECT count(*) FROM t` or `DELETE FROM t` amount to.
		#
		# For reads, `usage` is `:projected` when the value itself can leave the statement - in the
		# result rows, through RETURNING, or copied into a column being written - and `:referenced`
		# when it is only used to filter, join, sort or group. For writes it is `:insert`,
		# `:update` or `:delete`.
		Reference = Data.define(:schema, :table, :column, :usage, :node) do
			def table_key = Analysis.table_key(schema, table)
		end

		Unresolved = Data.define(:name, :reason, :node) do
			def message
				excerpt = Analysis.excerpt(node)
				excerpt ? "#{reason}: #{name}\n#{excerpt}" : "#{reason}: #{name}"
			end
		end

		# The source line `node` sits on with a caret under it, for error messages
		def self.excerpt(node)
			loc = node&.location
			Plume.excerpt(node.full_source, *loc) if loc && node.full_source
		end

		class Error < StandardError
			attr_reader :unresolved

			def initialize(message = nil, unresolved: [])
				@unresolved = unresolved
				super(message || unresolved.map(&:message).join("\n"))
			end
		end

		# Tables in the main schema are keyed by their bare name, any other schema
		# (temp, attached databases) is spelled out as "schema.table"
		def self.table_key(schema, table)
			(schema.nil? || schema.casecmp("main")&.zero?) ? table : "#{schema}.#{table}"
		end

		class References
			# `ctes` are the names the statement's WITH clauses define, `aliases` maps each table alias
			# to the table, view, CTE or function it stands for - all spelled as written, and none from
			# inside the views read. Reads and Writes of one statement share them
			attr_reader :statement, :references, :unresolved, :ctes, :aliases

			def initialize(statement, unresolved = [], ctes = Set.new, aliases = {})
				@statement = statement
				@references = []
				@unresolved = unresolved
				@ctes = ctes
				@aliases = aliases
			end

			# Every base table touched, including ones touched only as a whole
			def tables(usage = nil) = @references.select { |r| usage.nil? || r.usage == usage }.to_set(&:table_key)

			# `{ "table" => Set["column", …] }`, optionally narrowed to one usage
			def columns(usage = nil)
				@references.each_with_object({}) do |ref, acc|
					next if ref.column.nil? || (usage && ref.usage != usage)

					(acc[ref.table_key] ||= Set.new) << ref.column
				end
			end

			def resolved? = @unresolved.empty?

			def inspect
				"#<#{self.class.name} columns=#{columns.transform_values(&:to_a).inspect} unresolved=#{@unresolved.size}>"
			end
		end

		class Reads < References
			# `functions` are the table-valued ones in FROM, `calls` every other function called -
			# including those LIKE, GLOB, REGEXP, MATCH, `->`, `->>` and CURRENT_* call - as SQLite's
			# authorizer reports them
			attr_reader :views, :functions, :calls

			def initialize(...)
				super
				@views = Set.new
				@functions = Set.new
				@calls = Set.new
			end

			def projected = columns(:projected)
			def referenced = columns(:referenced)
		end

		class Writes < References
			# INSERT without a column list writes every column; without a catalog that is "*"
			def inserted = columns(:insert)
			def updated = columns(:update)
			def deleted = tables(:delete)
		end

		# What a run of statements reads, writes and does, as `Plume.summary` gives it. `accesses` has one
		# entry per statement, the rest is merged across them
		class Summary
			attr_reader :statements, :accesses

			def initialize(statements, accesses)
				@statements = statements
				@accesses = accesses
			end

			# Each statement's node class, like "SelectStatement" or "CreateTableStatement"
			def statement_types = @statements.map { |s| s.class.name.delete_prefix("Plume::") }

			# Every base table read or written, or only those touched in one way: `:projected`,
			# `:referenced`, `:insert`, `:update` or `:delete`
			def tables(usage = nil) = each_side.reduce(Set.new) { |all, refs| all | refs.tables(usage) }

			def reads = @accesses.map(&:reads)
			def writes = @accesses.map(&:writes)
			def actions = @accesses.flat_map(&:actions)
			def views = union(reads, :views)
			def functions = union(reads, :functions)
			def calls = union(reads, :calls)
			def ctes = union(reads, :ctes)
			def aliases = reads.reduce({}) { |all, r| all.merge(r.aliases) }
			def unresolved = reads.flat_map(&:unresolved)
			def resolved? = unresolved.empty?

			private

			def each_side = reads + writes
			def union(list, name) = list.reduce(Set.new) { |all, r| all | r.public_send(name) }
		end

		# Something a statement does besides reading and writing rows, named as SQLite's authorizer
		# names it: `action` is its action code as a symbol (`:create_table`, `:drop_temp_index`,
		# `:alter_table`, `:pragma`, `:transaction`…), and `name`, `detail` and `schema` are the
		# arguments the authorizer gets with it - for `:create_index`, the index, its table and the schema
		Action = Data.define(:action, :name, :detail, :schema, :node)

		Access = Data.define(:reads, :writes, :actions) do
			def unresolved = reads.unresolved
			def resolved? = reads.resolved?
		end
	end

	module Analysis
		# Which tables and columns `sql` - a single SELECT, INSERT, UPDATE or DELETE - would read.
		# Instead of SQL you can pass what you already parsed: a statement node, or the array
		# `Plume.parse` returns, so the same SQL does not get parsed twice.
		#
		# Without a catalog, columns of tables cannot be enumerated: `SELECT *` comes back as a read
		# of the column "*", and an unqualified column with more than one table in scope is ambiguous.
		#
		# With `strict: true` (the default) anything that cannot be attributed raises
		# `Plume::Analysis::Error`; with `strict: false` it is listed in `Reads#unresolved` instead.
		def self.reads(sql, catalog: nil, strict: true) = access(sql, catalog:, strict:).reads

		# Which tables and columns an INSERT, UPDATE or DELETE would write, with the same arguments
		# and strictness as `reads`. A SELECT writes nothing. The triggers a statement fires are not looked into, so rows
		# they write elsewhere - or the rows a REPLACE deletes - are not reported.
		def self.writes(sql, catalog: nil, strict: true) = access(sql, catalog:, strict:).writes

		# Like `reads`, but also reports what an INSERT, UPDATE or DELETE writes, and in `actions` what
		# any other statement does - creating, dropping and altering things, pragmas, transactions. A
		# CREATE TRIGGER is analyzed for what its WHEN and body do each time it fires, a CREATE TABLE … AS
		# reads what its SELECT reads, a CREATE INDEX reads what it indexes, DROP TABLE deletes the rows
		def self.access(sql, catalog: nil, strict: true)
			statements = statements(sql)
			raise Error, "expected exactly one statement, got #{statements.size}" unless statements.size == 1

			statement = statements.first
			access = begin
				Resolver.new(catalog:).analyze(statement)
			rescue *STACK_EXHAUSTED
				# As with parsing, how deep the resolver can go depends on the stack the caller has left
				raise Error, "statement nested too deeply"
			end
			raise Error.new(unresolved: access.unresolved) if strict && !access.resolved?

			access
		end

		# Reads and writes for any number of statements, a migration or a whole log line - with the
		# same arguments as `access`. Each statement sees the schema as the statements before it left
		# it: a copy of the catalog is changed as they create, alter and drop things, and the catalog
		# passed in stays as it was
		def self.summary(sql, catalog: nil, strict: true)
			statements = statements(sql)
			catalog = catalog&.dup
			accesses = statements.map do |statement|
				access(statement, catalog:, strict:).tap { catalog&.apply(statement) }
			end
			Summary.new(statements, accesses)
		end

		def self.statements(sql)
			case sql
			when Node then [sql]
			when Array then sql
			else Parser.new(sql).parse
			end
		end
		private_class_method :statements
	end
end
