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
			(schema.nil? || schema.casecmp?("main")) ? table : "#{schema}.#{table}"
		end

		class References
			attr_reader :statement, :references, :unresolved

			def initialize(statement, unresolved = [])
				@statement = statement
				@references = []
				@unresolved = unresolved
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
			attr_reader :views, :functions

			def initialize(...)
				super
				@views = Set.new
				@functions = Set.new
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

		Access = Data.define(:reads, :writes) do
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
		# and strictness as `reads`. A SELECT writes nothing. Triggers are not looked into, so rows
		# they write elsewhere - or the rows a REPLACE deletes - are not reported.
		def self.writes(sql, catalog: nil, strict: true) = access(sql, catalog:, strict:).writes

		# Like `reads`, but also reports what an INSERT, UPDATE or DELETE writes
		def self.access(sql, catalog: nil, strict: true)
			statements =
				case sql
				when Node then [sql]
				when Array then sql
				else Parser.new(sql).parse
				end
			raise Error, "expected exactly one statement, got #{statements.size}" unless statements.size == 1

			statement = statements.first
			unless Resolver::STATEMENTS.any? { |klass| klass === statement }
				raise Error, "only SELECT, INSERT, UPDATE and DELETE can be analyzed, got #{statement.class.name}"
			end

			access = Resolver.new(catalog:).analyze(statement)
			raise Error.new(unresolved: access.unresolved) if strict && !access.resolved?

			access
		end
	end
end
