# frozen_string_literal: true

module Plume
	module Analysis
		# Walks a SELECT, works out what every table and column reference points at, and records
		# the reads of base tables. Views and CTEs are looked through: their bodies are analyzed
		# once they are referenced, and everything those bodies read counts as read - whether or
		# not the outer query ends up using it. That matches what SQLite's authorizer reports.
		class Resolver
			# One entry in a FROM clause.
			#   kind :table   - a base table, reads are recorded against it
			#        :derived - CTE, view or subquery, its body has been analyzed already
			#        :function - table-valued function, nothing to record
			#        :group   - an aliased `(a JOIN b) AS x`, columns live in `inner_sources`
			# `columns` is nil when we cannot know them (no catalog, unknown function)
			# `qualified_only` sources answer to `name.column` but never to a bare column name -
			# that is how the `excluded` row of an upsert behaves
			Source = Struct.new(:name, :kind, :schema, :table, :columns, :inner_sources, :merged, :qualified_only, :node, keyword_init: true) do
				def self.table(name, table, node) = new(name:, kind: :table, schema: table.schema, table:, columns: table.columns, node:)

				def matches?(qualifier, schema_qualifier)
					return false unless name&.casecmp(qualifier)&.zero?
					return true unless schema_qualifier

					schema&.casecmp(schema_qualifier)&.zero? || (schema.nil? && schema_qualifier.casecmp("main")&.zero?)
				end

				def column(name)
					return unless columns
					return table.column(name) if table

					needle = name.downcase(:ascii)
					columns.find { |c| c&.downcase(:ascii) == needle }
				end
			end

			Scope = Struct.new(:sources, :parent, :ctes, :aliases, keyword_init: true) do
				def each_up
					scope = self
					while scope
						yield scope
						scope = scope.parent
					end
				end
			end

			Cte = Struct.new(:node, :scope, :analyzed, :columns, :in_progress, keyword_init: true)

			# The columns of json_each and json_tree are fixed, see https://www.sqlite.org/json1.html#jeach
			JSON_TABLE_COLUMNS = %w[key value type atom id parent fullkey path json root].freeze
			FUNCTION_COLUMNS = {
				"json_each" => JSON_TABLE_COLUMNS,
				"json_tree" => JSON_TABLE_COLUMNS,
				"jsonb_each" => JSON_TABLE_COLUMNS,
				"jsonb_tree" => JSON_TABLE_COLUMNS,
				"generate_series" => %w[value start stop step].freeze,
			}.freeze

			STATEMENTS = [SelectStatement, InsertStatement, UpdateStatement, DeleteStatement, CreateTriggerStatement].freeze # analyzed for reads and writes

			# What SQLite calls for these operators and keywords, as its authorizer names them
			OPERATOR_FUNCTIONS = {
				LIKE: "like", NOT_LIKE: "like", GLOB: "glob", NOT_GLOB: "glob", REGEXP: "regexp", NOT_REGEXP: "regexp",
				MATCH: "match", NOT_MATCH: "match", EXTRACT: "->", RETRIEVE: "->>",
			}.freeze

			# SQLite's own limit, which also keeps resolving names across a join from going quadratic
			MAX_JOIN_TABLES = 64

			def initialize(catalog: nil)
				@catalog = catalog
			end

			def analyze(statement)
				start(statement)

				case statement
				when SelectStatement then select(statement, parent: nil, usage: :projected)
				when InsertStatement then insert(statement)
				when UpdateStatement then update(statement)
				when DeleteStatement then delete(statement)
				when CreateTriggerStatement then trigger(statement)
				when ExplainStatement then return analyze(statement.statement)
				else schema_statement(statement)
				end

				Access.new(reads: @reads, writes: @writes, actions: @actions.freeze)
			end

			# Names of the columns a select produces, nil for the ones we cannot name
			def output_columns(statement)
				start(statement)
				select(statement, parent: nil, usage: :projected) || []
			end

			private

			def start(statement)
				@reads = Reads.new(statement)
				@writes = Writes.new(statement, @reads.unresolved, @reads.ctes, @reads.aliases)
				@actions = []
				# By identity: a view holds its parsed select, and hashing that hashes the whole tree
				@expanding_views = Set.new.compare_by_identity
			end

			def with_scope(with_clause, parent)
				scope = Scope.new(sources: [], parent:, ctes: {})
				with_clause&.ctes&.each do |cte|
					scope.ctes[cte.name.downcase(:ascii)] = Cte.new(node: cte, scope:, analyzed: Set.new)
					@reads.ctes << cte.name if @expanding_views.empty?
				end
				scope
			end

			# -- INSERT, UPDATE, DELETE

			def insert(statement, parent: nil)
				outer = with_scope(statement.with_clause, parent)
				# The rows being inserted cannot see the target table, upserts and RETURNING can
				select(statement.select, parent: outer, usage: :projected) if statement.select

				scope = Scope.new(sources: [], parent: outer, ctes: {}, aliases: {})
				target = add_target(statement.table, scope)

				if statement.default_values
					write(target, nil, :insert, statement.table)
				elsif statement.columns
					statement.columns.each { |column| write(target, column.column, :insert, column) }
				elsif target&.columns
					# A VALUES row without a column list has no slot for generated columns
					(target.columns - (target.table&.generated_columns || [])).each { |column| write(target, column, :insert, statement.table) }
				else
					write(target, "*", :insert, statement.table)
				end

				statement.upserts&.each do |upsert|
					excluded = Source.new(name: "excluded", kind: :derived, columns: target&.columns, qualified_only: true, node: upsert)
					upsert_scope = Scope.new(sources: [target, excluded].compact, parent: outer, ctes: {}, aliases: {})

					upsert.targets&.each { |term| expression(term.expression, upsert_scope, :referenced) }
					expression(upsert.target_condition, upsert_scope, :referenced)
					assign(upsert.assignments, target, upsert_scope)
					expression(upsert.condition, upsert_scope, :referenced)
				end

				returning(statement.returning, scope, target)
			end

			def update(statement, parent: nil)
				outer = with_scope(statement.with_clause, parent)
				scope = Scope.new(sources: [], parent: outer, ctes: {}, aliases: {})
				target = add_target(statement.table, scope)
				if statement.source
					# Pairing the target's rows with FROM's reads the target, named columns or not
					record(target.schema, target.table&.name || statement.table.table, nil, :referenced, statement.table) if target&.kind == :table
					add_from(statement.source, scope, :projected)
				end

				assign(statement.assignments, target, scope)
				expression(statement.condition, scope, :referenced)
				returning(statement.returning, scope, target)
				tail(statement, scope)
			end

			def delete(statement, parent: nil)
				outer = with_scope(statement.with_clause, parent)
				scope = Scope.new(sources: [], parent: outer, ctes: {}, aliases: {})
				target = add_target(statement.table, scope)

				write(target, nil, :delete, statement.table)
				expression(statement.condition, scope, :referenced)
				returning(statement.returning, scope, target)
				tail(statement, scope)
			end

			# -- schema changes and the rest

			def schema_statement(statement)
				case statement
				when CreateTableStatement
					schema = new_schema(statement.table, statement.temporary)
					act(:create_table, temp: schema, name: statement.table.name, node: statement)
					Catalog.autoindexes(statement).each { |index| act(:create_index, temp: schema, name: index, detail: statement.table.name, node: statement) }
					select(statement.select_statement, parent: nil, usage: :projected) if statement.select_statement
				when CreateViewStatement
					# SQLite checks a view's body when the view is used, not when it is made
					act(:create_view, temp: new_schema(statement.view, statement.temporary), name: statement.view.name, node: statement)
				when CreateIndexStatement then create_index(statement)
				when CreateVirtualTableStatement
					act(:create_vtable, name: statement.table.name, detail: statement.module_name, schema: new_schema(statement.table, false), node: statement)
				when DropStatement then drop(statement)
				when AlterTableStatement
					table = @catalog&.table(statement.table.table, schema: statement.table.schema)
					detail = statement.column if statement.action == :DROP_COLUMN
					act(:alter_table, name: table&.name || statement.table.table, detail:, schema: table&.schema || statement.table.schema || "main", node: statement)
				when PragmaStatement
					act(:pragma, name: statement.name, detail: pragma_value(statement), schema: statement.schema, node: statement)
				when BeginStatement then act(:transaction, name: "BEGIN", node: statement)
				when CommitStatement then act(:transaction, name: "COMMIT", node: statement)
				when RollbackStatement
					if statement.savepoint
						act(:savepoint, name: "ROLLBACK", detail: statement.savepoint, node: statement)
					else
						act(:transaction, name: "ROLLBACK", node: statement)
					end
				when SavepointStatement then act(:savepoint, name: "BEGIN", detail: statement.name, node: statement)
				when ReleaseStatement then act(:savepoint, name: "RELEASE", detail: statement.name, node: statement)
				when AttachStatement then act(:attach, name: plain_value(statement.file), node: statement)
				when DetachStatement then act(:detach, name: plain_value(statement.schema), node: statement)
				when ReindexStatement then reindex(statement)
				when AnalyzeStatement then analyze_tables(statement)
				end
			end

			def create_index(statement)
				schema = statement.index.schema
				table_node = TableName.new(schema:, table: statement.table)
				act(:create_index, temp: new_schema(statement.index, false, on: table_node), name: statement.index.name, detail: statement.table, node: statement)
				scope = Scope.new(sources: [], parent: nil, ctes: {}, aliases: {})
				add_table_source(table_node, scope, :referenced)
				# The table's rows are read to fill the index, which only an authorizer sees as columns
				@reads.references.pop if @reads.references.last&.column.nil?
				statement.columns&.each { |term| expression(term.expression, scope, :referenced) }
				expression(statement.condition, scope, :referenced)
				act(:reindex, name: statement.index.name, schema: @actions.last.schema, node: statement)
			end

			def drop(statement)
				target = statement.target
				case statement.type
				when :TABLE
					table = @catalog&.table(target.table, schema: target.schema)
					if table&.module_name
						act(:drop_vtable, name: table.name, detail: table.module_name, schema: table.schema, node: statement)
					else
						act(:drop_table, temp: table&.schema || target.schema || "main", name: table&.name || target.table, node: statement)
					end
					@writes.references << Reference.new(schema: table&.schema || target.schema, table: table&.name || target.table, column: nil, usage: :delete, node: statement)
					drop_triggers(table, statement)
				when :VIEW
					view = @catalog&.view(target.table, schema: target.schema)
					act(:drop_view, temp: view&.schema || target.schema || "main", name: view&.name || target.table, node: statement)
					drop_triggers(view, statement)
				when :INDEX
					index = @catalog&.index(target.table, schema: target.schema)
					act(:drop_index, temp: index&.schema || target.schema || "main", name: index&.name || target.table, detail: index&.table, node: statement)
				when :TRIGGER
					trigger = @catalog&.trigger(target.table, schema: target.schema)
					act(:drop_trigger, temp: trigger&.schema || target.schema || "main", name: trigger&.name || target.table, detail: trigger&.table, node: statement)
				end
			end

			# Dropping a table or view drops its triggers, newest first
			def drop_triggers(object, statement)
				return unless object

				triggers = @catalog.triggers.select { |t| t.schema.casecmp?(object.schema) && t.table.casecmp?(object.name) }
				triggers.reverse_each { |t| act(:drop_trigger, temp: t.schema, name: t.name, detail: t.table, node: statement) }
			end

			# `temp:` takes the schema and makes the action its _temp_ variant when that schema is temp
			def act(action, node:, name: nil, detail: nil, schema: nil, temp: nil)
				if temp
					schema = temp
					action = action.name.sub(/\A(create|drop)_/) { "#{$1}_temp_" }.to_sym if temp.casecmp?("temp")
				end
				@actions << Action.new(action:, name:, detail:, schema:, node:)
			end

			# Where a new object goes: the schema it names, temp for TEMP, or the schema of the table it is on
			def new_schema(name, temporary, on: nil)
				return name.schema if name.schema
				return "temp" if temporary
				return @catalog&.table(on.table)&.schema || "main" if on

				"main"
			end

			# REINDEX names an index, a table whose indexes to rebuild, or a collation - and SQLite's
			# authorizer is asked about each index rebuilt. Without a catalog only a name is known
			def reindex(statement)
				target = statement.target
				return target && act(:reindex, name: target.table, schema: target.schema || "main", node: statement) unless @catalog

				indexes =
					if target.nil? then @catalog.indexes
					elsif (index = @catalog.index(target.table, schema: target.schema)) then [index]
					elsif (table = @catalog.table(target.table, schema: target.schema))
						@catalog.indexes.select { |i| i.schema == table.schema && i.table.casecmp?(table.name) }
					else
						[]
					end
				indexes.each { |i| act(:reindex, name: i.name, schema: i.schema, node: statement) }
			end

			# ANALYZE names a table, an index, a schema, or nothing for every schema but temp
			def analyze_tables(statement)
				target = statement.target
				return target && act(:analyze, name: target.table, schema: target.schema || "main", node: statement) unless @catalog

				tables =
					if target.nil? then @catalog.tables.reject { |t| t.schema.casecmp?("temp") }
					elsif (table = @catalog.table(target.table, schema: target.schema)) then [table]
					elsif (index = @catalog.index(target.table, schema: target.schema)) then [@catalog.table(index.table, schema: index.schema)].compact
					elsif target.schema.nil? then @catalog.tables.select { |t| t.schema.casecmp?(target.table) }
					else
						[]
					end
				tables.each { |t| act(:analyze, name: t.name, schema: t.schema, node: statement) unless t.module_name }
			end

			# SQLite hands the authorizer a PRAGMA's value as text, unquoted and without a plus sign
			def pragma_value(statement)
				src = statement.value_tk_src or return
				(src.match?(/\A['"]/) ? statement.value_tk_val.to_s : src.delete_prefix("+"))
			end

			# ATTACH and DETACH name a file or schema with any expression; a plain string or name is told
			def plain_value(node)
				case node
				when LiteralExpression then node.value.to_s
				when ColumnName then node.column
				end
			end

			# What a trigger's WHEN and body read and write each time it fires. NEW and OLD stand for
			# the row of the table it is on, and reading them reads that table, as SQLite's authorizer has it
			def trigger(statement)
				on_schema = @catalog&.table(statement.table.table, schema: statement.table.schema)&.schema
				act(:create_trigger, temp: statement.trigger.schema || (statement.temporary ? "temp" : on_schema || "main"), name: statement.trigger.name, detail: statement.table.table, node: statement)
				scope = Scope.new(sources: [], parent: nil, ctes: {}, aliases: {})
				if (on = trigger_table(statement.table))
					rows = [("new" unless statement.event == :DELETE), ("old" unless statement.event == :INSERT)].compact
					rows.each { |name| scope.sources << on.dup.tap { |row| row.name, row.qualified_only = name, true } }
				end

				expression(statement.condition, scope, :referenced)
				statement.statements.each do |body|
					case body
					when SelectStatement then select(body, parent: scope, usage: :projected)
					when InsertStatement then insert(body, parent: scope)
					when UpdateStatement then update(body, parent: scope)
					when DeleteStatement then delete(body, parent: scope)
					end
				end
			end

			# The table or view a trigger is on, which it neither reads nor writes by being on it
			def trigger_table(node)
				scope = Scope.new(sources: [], parent: nil, ctes: {}, aliases: {})
				add_target(node, scope)
			end

			# Assigned values end up in the table, so whatever they read counts as projected
			def assign(assignments, target, scope)
				assignments&.each do |assignment|
					assignment.columns.each { |column| write(target, column.column, :update, column) }
					expression(assignment.value, scope, :projected)
				end
			end

			# A bare * in RETURNING means the target's columns only, not those of an UPDATE's FROM
			def returning(clause, scope, target)
				clause&.columns&.each do |column|
					if StarResultColumn === column && column.table.nil?
						star_source(target, :projected, column, skip_merged: false) if target
					elsif StarResultColumn === column
						star(column, scope, :projected)
					else
						expression(column.result, scope, :projected)
					end
				end
			end

			def tail(statement, scope)
				statement.orderings&.each { |term| expression(term.expression, scope, :referenced) }
				expression(statement.limit, scope, :referenced)
				expression(statement.offset, scope, :referenced)
			end

			# The table an INSERT, UPDATE or DELETE writes to. CTEs never stand in for it, and
			# writing to it is not a read, so it joins the scope without recording one
			def add_target(node, scope)
				name = node.alias || node.table
				alias_of(node.alias, node.schema, node.table)
				source =
					if @catalog.nil?
						Source.new(name:, kind: :table, schema: node.schema, node:)
					elsif (table = @catalog.table(node.table, schema: node.schema))
						Source.table(name, table, node)
					elsif (view = @catalog.view(node.table, schema: node.schema))
						# Writable only through INSTEAD OF triggers, which we do not look into
						@reads.views << Analysis.table_key(view.schema, view.name)
						Source.new(name:, kind: :derived, schema: view.schema, columns: view.columns, node:)
					else
						unresolved(node.table, "no such table", node)
						return
					end
				scope.sources << source
				source
			end

			def write(target, column, action, node)
				return unless target

				if target.table
					if column && column != "*"
						canonical = target.column(column)
						# SQLite's authorizer names a write to the rowid "ROWID" however it was spelled, alias or not
						canonical ||= "ROWID" if Catalog::ROWID_NAMES.include?(column.downcase(:ascii)) && target.table.rowid?
						return unresolved(column, "no such column in #{target.table.name}", node) unless canonical

						column = canonical
					end
					@writes.references << Reference.new(schema: target.table.schema, table: target.table.name, column:, usage: action, node:)
				else
					@writes.references << Reference.new(schema: target.schema, table: target.node.table, column:, usage: action, node:)
				end
			end

			def select(statement, parent:, usage:)
				scope = with_scope(statement.with_clause, parent)

				names = nil
				core_scope = nil
				statement.cores.each do |core|
					core_names, core_scope = select_core(core, parent: scope, usage:)
					names ||= core_names
				end

				# ORDER BY of a compound can only name result columns, which reads nothing new
				if statement.cores.size == 1 && core_scope
					statement.orderings&.each do |term|
						expression(term.expression, core_scope, :referenced, aliases: :first)
					end
				end
				expression(statement.limit, scope, :referenced)
				expression(statement.offset, scope, :referenced)

				names
			end

			def select_core(core, parent:, usage:)
				scope = Scope.new(sources: [], parent:, ctes: {}, aliases: {})

				if ValuesClause === core
					core.rows.each { |row| row.values.each { |v| expression(v, scope, usage) } }
					width = core.rows.first.values.size
					return [Array.new(width) { |i| "column#{i + 1}" }, scope]
				end

				add_from(core.source, scope, usage) if core.source

				core.columns.each do |column|
					scope.aliases[column.alias.downcase(:ascii)] = column.result if ResultColumn === column && column.alias
				end

				names = []
				core.columns.each do |column|
					if StarResultColumn === column
						expanded = star(column, scope, usage)
						expanded ? names.concat(expanded) : names << nil
					else
						expression(column.result, scope, usage)
						names << output_name(column)
					end
				end

				expression(core.condition, scope, :referenced, aliases: :fallback)
				core.groupings&.each { |g| expression(g, scope, :referenced, aliases: :fallback) }
				expression(core.having, scope, :referenced, aliases: :fallback)
				core.windows&.each do |window|
					window.partitions&.each { |p| expression(p, scope, :referenced) }
					window.orderings&.each { |o| expression(o.expression, scope, :referenced) }
				end

				[names, scope]
			end

			def output_name(column)
				return column.alias if column.alias

				case (result = column.result)
				when ColumnName then result.column
				when Node then result.source_text
				end
			end

			# -- FROM

			def add_from(source, scope, usage)
				add_source(source, scope, usage)
				tables = scope.sources.sum { |s| join_tables(s) }
				raise Error, "at most #{MAX_JOIN_TABLES} tables in a join" if tables > MAX_JOIN_TABLES
			end

			def join_tables(source) = (source.kind == :group) ? source.inner_sources.sum { |s| join_tables(s) } : 1

			def add_source(source, scope, usage)
				case source
				when JoinClause
					add_source(source.left, scope, usage)
					source.joins.each do |join|
						left_sources = scope.sources.dup
						add_source(join.source, scope, usage)
						join_constraint(join, left_sources, scope.sources.last, scope)
					end
				when TableName then add_table_source(source, scope, usage)
				when TableFunction
					alias_of(source.alias, source.schema, source.function)
					source.arguments&.each { |a| expression(a, scope, :referenced) }
					# Any virtual table can be called like this, `fts('query')` reads the fts table
					if @catalog && (table = @catalog.table(source.function, schema: source.schema))
						record(table.schema, table.name, nil, usage, source)
						scope.sources << Source.table(source.alias || source.function, table, source)
						return
					end

					@reads.functions << source.function.downcase(:ascii)
					scope.sources << Source.new(
						name: source.alias || source.function, kind: :function,
						columns: FUNCTION_COLUMNS[source.function.downcase(:ascii)], node: source,
					)
				when SubquerySource
					# A FROM subquery sees the enclosing queries, but not its siblings in this FROM
					names = select(source.select, parent: scope.parent, usage:)
					scope.sources << Source.new(name: source.alias, kind: :derived, columns: names, node: source)
				when ParentheticalSource
					if source.alias
						inner = Scope.new(sources: [], parent: scope.parent, ctes: {})
						add_source(source.source, inner, usage)
						scope.sources << Source.new(name: source.alias, kind: :group, inner_sources: inner.sources, node: source)
					else
						add_source(source.source, scope, usage)
					end
				end
			end

			def add_table_source(source, scope, usage)
				name = source.alias || source.table
				alias_of(source.alias, source.schema, source.table)

				if source.schema.nil? && (cte = find_cte(source.table, scope))
					columns = analyze_cte(cte, usage)
					scope.sources << Source.new(name:, kind: :derived, columns:, node: source)
				elsif @catalog.nil?
					record(source.schema, source.table, nil, usage, source)
					scope.sources << Source.new(name:, kind: :table, schema: source.schema, table: nil, node: source)
				elsif (table = @catalog.table(source.table, schema: source.schema))
					record(table.schema, table.name, nil, usage, source)
					scope.sources << Source.table(name, table, source)
				elsif (view = @catalog.view(source.table, schema: source.schema))
					@reads.views << Analysis.table_key(view.schema, view.name)
					if @expanding_views.include?(view)
						unresolved(source.table, "circularly defined view", source)
					else
						@expanding_views << view
						# A view's body starts a scope chain of its own, so the CTEs of the query using it stay out of sight
						names = select(view.select, parent: nil, usage:)
						@expanding_views.delete(view)
					end
					scope.sources << Source.new(name:, kind: :derived, columns: view.columns || names, node: source)
				else
					unresolved(source.table, "no such table", source)
					scope.sources << Source.new(name:, kind: :table, schema: source.schema, node: source)
				end
			end

			def find_cte(name, scope)
				needle = name.downcase(:ascii)
				scope.each_up do |s|
					return s.ctes[needle] if s.ctes&.key?(needle)
				end
				nil
			end

			def analyze_cte(cte, usage)
				declared = cte.node.column_names
				# A recursive CTE refers to itself, we know its columns at best from the declaration
				return declared || cte.columns if cte.in_progress || cte.analyzed.include?(usage)

				cte.in_progress = true
				names = select(cte.node.select, parent: cte.scope, usage:)
				cte.in_progress = false
				cte.analyzed << usage
				cte.columns = names
				declared || names
			end

			def join_constraint(join, left_sources, right, scope)
				shared =
					case join.constraint
					when JoinUsingConstraint then join.constraint.column_names
					else
						if join.operator.natural
							if right.columns.nil? || left_sources.any? { |s| s.columns.nil? }
								unresolved(right.name.to_s, "cannot work out the columns of a NATURAL JOIN without a catalog", join)
								[]
							else
								right.columns.select { |c| left_sources.any? { |s| s.column(c) } }
							end
						else
							expression(join.constraint.expression, scope, :referenced) if JoinOnConstraint === join.constraint
							[]
						end
					end

				# Both sides of USING and NATURAL are compared, even though SQLite's authorizer
				# does not report the right-hand one
				shared.each do |column|
					left = left_sources.find { |s| s.column(column) } || left_sources.find { |s| s.columns.nil? }
					read_through(left, column, :referenced, join) if left
					read_through(right, column, :referenced, join)
					(right.merged ||= Set.new) << column.downcase(:ascii)
				end
			end

			def star(column, scope, usage)
				sources =
					if column.table
						found = scope.sources.find { |s| s.matches?(column.table, nil) }
						unless found
							unresolved("#{column.table}.*", "no such table", column)
							return nil
						end
						[found]
					else
						scope.sources
					end

				names = []
				sources.each do |source|
					expanded = star_source(source, usage, column, skip_merged: column.table.nil?)
					expanded ? names.concat(expanded) : (return nil)
				end
				names
			end

			def star_source(source, usage, node, skip_merged:)
				case source.kind
				when :group
					source.inner_sources.flat_map { |m| star_source(m, usage, node, skip_merged:) || [] }
				when :table
					if source.columns.nil?
						record(source.schema, source.node.table, "*", usage, node)
						nil
					else
						columns = source.columns.reject { |c| skip_merged && source.merged&.include?(c.downcase(:ascii)) }
						columns.each { |c| record(source.table.schema, source.table.name, c, usage, node) }
						columns
					end
				else
					source.columns&.reject { |c| skip_merged && c && source.merged&.include?(c.downcase(:ascii)) }
				end
			end

			# -- expressions

			def expression(node, scope, usage, aliases: :none)
				case node
				when nil, Variable then nil
				when LiteralExpression
					@reads.calls << node.value.name.downcase if node.value in :CURRENT_DATE | :CURRENT_TIME | :CURRENT_TIMESTAMP
				when ColumnName then column(node, scope, usage, aliases)
				when FunctionReference
					@reads.calls << node.function.downcase(:ascii)
					node.children.each { |child| expression(child, scope, usage, aliases:) }
				when SelectStatement then select(node, parent: scope, usage:)
				when TableName then whole_table(node, scope)
				when Node
					if node.respond_to?(:operator) && (function = OPERATOR_FUNCTIONS[node.operator])
						@reads.calls << function
					end
					node.children.each { |child| expression(child, scope, usage, aliases:) }
				end
			end

			# `x IN t` compares against the single column of t
			def whole_table(node, scope)
				fake = Scope.new(sources: [], parent: scope, ctes: {})
				add_table_source(node, fake, :referenced)
				source = fake.sources.last
				star_source(source, :referenced, node, skip_merged: false) if source
			end

			def column(node, scope, usage, aliases)
				name = node.column

				if node.table
					scope.each_up do |s|
						source = s.sources.find { |src| src.matches?(node.table, node.schema) }
						return read_through(source, name, usage, node) if source
					end
					return unresolved(qualified_name(node), "no such table: #{node.table}", node)
				end

				return if aliases == :first && scope.aliases&.key?(name.downcase(:ascii))

				scope.each_up do |s|
					return if resolve_in(s, name, usage, node)
					return if s.equal?(scope) && aliases == :fallback && s.aliases&.key?(name.downcase(:ascii))
					return if rowid(s, name, usage, node)
				end

				# SQLite reads an unresolvable "double-quoted" identifier as a string literal
				return if node.column_tk_src&.start_with?('"')

				unresolved(name, "no such column", node)
			end

			def resolve_in(scope, name, usage, node)
				candidates = scope.sources.reject(&:qualified_only)
				known = candidates.select { |s| source_has?(s, name) }
				unknown = candidates.select { |s| source_unknown?(s) }

				if known.size == 1 && unknown.empty?
					read_through(known.first, name, usage, node)
				elsif known.size > 1 && unknown.empty?
					# A USING/NATURAL column belongs to both sides and is not ambiguous
					merged = known.select { |s| s.merged&.include?(name.downcase(:ascii)) }
					if merged.any?
						read_through((known - merged).first || known.first, name, usage, node)
					else
						unresolved(name, "ambiguous column name", node)
					end
				elsif known.empty? && unknown.size == 1
					read_through(unknown.first, name, usage, node)
				elsif unknown.any? && (known.size + unknown.size) > 1
					unresolved(name, "ambiguous column name without a catalog", node)
				else
					return false
				end
				true
			end

			def source_has?(source, name)
				return source.inner_sources.any? { |m| source_has?(m, name) } if source.kind == :group

				!!source.column(name)
			end

			def source_unknown?(source)
				return source.inner_sources.any? { |m| source_unknown?(m) } if source.kind == :group

				source.columns.nil?
			end

			def rowid(scope, name, usage, node)
				return false unless Catalog::ROWID_NAMES.include?(name.downcase(:ascii))

				candidates = scope.sources.select { |s| s.kind == :table && (s.table.nil? || s.table.rowid?) }
				return false unless candidates.size == 1

				read_through(candidates.first, name, usage, node)
				true
			end

			def read_through(source, name, usage, node)
				case source.kind
				when :table
					if source.table
						column = source.table.column(name)
						column ||= source.table.rowid_alias || "rowid" if Catalog::ROWID_NAMES.include?(name.downcase(:ascii)) && source.table.rowid?
						return unresolved(name, "no such column in #{source.table.name}", node) unless column

						record(source.table.schema, source.table.name, column, usage, node)
					else
						record(source.schema, source.node.table, name, usage, node)
					end
				when :group
					member = source.inner_sources.find { |m| source_has?(m, name) } || source.inner_sources.find { |m| source_unknown?(m) }
					member ? read_through(member, name, usage, node) : unresolved(name, "no such column", node)
				when :derived, :function
					if source.columns && !source.column(name) && !source.columns.include?(nil)
						unresolved(name, "no such column in #{source.name}", node)
					end
				end
				true
			end

			def alias_of(name, schema, table)
				@reads.aliases[name] = Analysis.table_key(schema, table) if name && @expanding_views.empty?
			end

			def record(schema, table, column, usage, node)
				@reads.references << Reference.new(schema:, table:, column:, usage:, node:)
			end

			def unresolved(name, reason, node)
				@reads.unresolved << Unresolved.new(name:, reason:, node:)
				true
			end

			def qualified_name(node) = [node.schema, node.table, node.column].compact.join(".")
		end
	end
end
