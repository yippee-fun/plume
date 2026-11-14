# frozen_string_literal: true

module Plume
	# What the read analysis knows about a database: its tables with their columns, its views,
	# and which table each index and trigger belongs to. Names are matched case-insensitively, the way SQLite matches identifiers, and
	# reported in the spelling they were declared with.
	class Catalog
		ROWID_NAMES = %w[rowid oid _rowid_].freeze

		# `columns` is nil when they cannot be known, like a CREATE TABLE … AS SELECT * from a table
		# the catalog lacks; any column name is then taken as written. `generated_columns` are among
		# `columns` too, since they can be read like any other, but nothing can write to them.
		# `module_name` is set for a virtual table, like "fts5"
		Table = Data.define(:schema, :name, :columns, :hidden_columns, :generated_columns, :rowid_alias, :without_rowid, :module_name) do
			def column(name)
				return name.to_s unless columns

				needle = name.to_s.downcase(:ascii)
				columns.find { |c| c.downcase(:ascii) == needle } || hidden_columns.find { |c| c.downcase(:ascii) == needle }
			end

			def rowid? = !without_rowid
		end

		View = Data.define(:schema, :name, :columns, :select)
		Index = Data.define(:schema, :name, :table)
		Trigger = Data.define(:schema, :name, :table)

		def self.from_sql(sql) = new.load_sql(sql)

		# Whether two names are one to SQLite, which folds the case of A-Z only. Compared as bytes, so a
		# name that is not valid UTF-8 compares too - JRuby's casecmp? raises for one
		def self.same_name?(a, b) = !a.nil? && !b.nil? && a.to_s.b.casecmp?(b.to_s.b)

		# The indexes SQLite makes for a table's UNIQUE and PRIMARY KEY constraints, in the order it
		# makes them - all but the rowid's own primary key, even where two cover the same columns
		def self.autoindexes(statement)
			return [] if statement.select_statement

			alias_column = new.__send__(:rowid_alias, statement)&.downcase(:ascii)
			constraints = statement.columns.flat_map do |column|
				(column.constraints || []).select { |c| UniqueColumnConstraint === c || (PrimaryKeyColumnConstraint === c && column.name.downcase(:ascii) != alias_column) }
			end
			constraints += (statement.constraints || []).select do |c|
				UniqueTableConstraint === c || (PrimaryKeyTableConstraint === c && !(alias_column && c.columns.size == 1))
			end
			Array.new(constraints.size) { |i| "sqlite_autoindex_#{statement.table.name}_#{i + 1}" }
		end

		# Takes a sqlite3-ruby `SQLite3::Database` (or anything with a compatible `#execute`)
		def self.from_sqlite(db) = new.load_sqlite(db)

		def initialize
			@tables = {}
			@views = {}
			@indexes = {}
			@triggers = {}
		end

		def add_table(name, columns, schema: "main", hidden_columns: [], generated_columns: [], rowid_alias: nil, without_rowid: false, module_name: nil)
			table = Table.new(schema:, name:, columns: columns&.freeze, hidden_columns: hidden_columns.freeze, generated_columns: generated_columns.freeze, rowid_alias:, without_rowid:, module_name:)
			@tables[key(schema, name)] = table
		end

		# `select` is a `SelectStatement` or the SQL for one
		def add_view(name, select, columns: nil, schema: "main")
			select = Parser.new(select).parse.first if String === select
			@views[key(schema, name)] = View.new(schema:, name:, columns: columns&.freeze, select:)
		end

		# `table` is the name of the table the index or trigger is on, in the same schema
		def add_index(name, table, schema: "main") = @indexes[key(schema, name)] = Index.new(schema:, name:, table:)
		def add_trigger(name, table, schema: "main") = @triggers[key(schema, name)] = Trigger.new(schema:, name:, table:)

		# Unqualified names are looked up the way SQLite does: temp first, then main,
		# then attached databases in the order they were added
		def table(name, schema: nil) = lookup(@tables, name, schema)
		def view(name, schema: nil) = lookup(@views, name, schema)
		def index(name, schema: nil) = lookup(@indexes, name, schema)
		def trigger(name, schema: nil) = lookup(@triggers, name, schema)

		def tables = @tables.values
		def views = @views.values
		def indexes = @indexes.values
		def triggers = @triggers.values

		# Statements other than CREATE (inserts, pragmas…) do not change the schema, and are skipped
		# without being parsed
		def load_sql(sql)
			Catalog.split_statements(sql).each do |statement_sql|
				leading = Plume.tokenize(statement_sql).first(3) - [:TEMP, :TEMPORARY]
				next unless leading[0] == :CREATE && (leading[1] in :TABLE | :VIEW | :INDEX | :UNIQUE | :TRIGGER | :VIRTUAL)

				apply(Parser.new(statement_sql).parse.first)
			end
			self
		end

		# Changes the catalog the way running `statement` would change the schema: CREATE adds,
		# DROP removes, ALTER TABLE renames, adds and drops columns. Other statements change nothing
		def apply(statement)
			case statement
			when CreateTableStatement then add_create_table(statement) unless statement.if_not_exists && table(statement.table.name, schema: statement.table.schema)
			when CreateViewStatement then add_create_view(statement) unless statement.if_not_exists && view(statement.view.name, schema: statement.view.schema)
			when CreateVirtualTableStatement
				add_table(statement.table.name, nil, schema: statement.table.schema || "main", module_name: statement.module_name)
			when CreateIndexStatement
				schema = statement.index.schema || table(statement.table)&.schema || "main"
				add_index(statement.index.name, statement.table, schema:)
			when CreateTriggerStatement
				schema = statement.trigger.schema || (statement.temporary ? "temp" : table(statement.table.table)&.schema || "main")
				add_trigger(statement.trigger.name, statement.table.table, schema:)
			when DropStatement then drop(statement.type, statement.target)
			when AlterTableStatement then alter(statement)
			end
			self
		end

		def initialize_copy(other)
			super
			@tables = @tables.dup
			@views = @views.dup
			@indexes = @indexes.dup
			@triggers = @triggers.dup
		end

		def load_sqlite(db)
			db.execute("PRAGMA database_list").each do |(_seq, schema, _file)|
				master = (schema == "temp") ? "sqlite_temp_master" : "#{quote(schema)}.sqlite_master"
				db.execute("SELECT type, name, tbl_name, sql FROM #{master} WHERE type IN ('table', 'view', 'index', 'trigger')").each do |(type, name, table, sql)|
					next if name.start_with?("sqlite_")

					case type
					when "view"
						statement = Parser.new(sql).parse.first
						add_view(name, statement.select, columns: statement.column_names, schema:)
					when "index" then add_index(name, table, schema:)
					when "trigger" then add_trigger(name, table, schema:)
					else add_sqlite_table(db, schema, name, sql)
					end
				end
			end
			self
		end

		# Splits SQL into statements, keeping trigger bodies (`BEGIN …; …; END`) in one piece
		def self.split_statements(sql) = Plume.split(sql)

		private

		def drop(type, target)
			collection = { TABLE: @tables, VIEW: @views, INDEX: @indexes, TRIGGER: @triggers }.fetch(type)
			object = lookup(collection, target.table, target.schema) or return
			collection.delete(key(object.schema, object.name))
			return unless type == :TABLE || type == :VIEW

			# A table takes its indexes and triggers with it, a view its triggers
			[@indexes, @triggers].each do |dependents|
				dependents.delete_if { |_, d| Catalog.same_name?(d.schema, object.schema) && Catalog.same_name?(d.table, object.name) }
			end
		end

		def alter(statement)
			table = table(statement.table.table, schema: statement.table.schema) or return
			columns = table.columns
			rename = -> (list, from, to) { list&.map { |c| Catalog.same_name?(c, from) ? to : c } }

			changed =
				case statement.action
				when :RENAME_TABLE then return rename_table(table, statement.new_name)
				when :ADD_COLUMN
					definition = statement.column_definition
					generated = definition.constraints&.any?(GeneratedAsColumnConstraint)
					table.with(columns: columns && [*columns, definition.name].freeze, generated_columns: generated ? [*table.generated_columns, definition.name].freeze : table.generated_columns)
				when :RENAME_COLUMN
					from, to = statement.column, statement.new_name
					table.with(
						columns: rename.(columns, from, to)&.freeze, generated_columns: rename.(table.generated_columns, from, to).freeze,
						rowid_alias: Catalog.same_name?(table.rowid_alias, from) ? to : table.rowid_alias,
					)
				when :DROP_COLUMN
					gone = -> (list) { list&.reject { |c| Catalog.same_name?(c, statement.column) }&.freeze }
					table.with(columns: gone.(columns), generated_columns: gone.(table.generated_columns))
				else return
				end
			@tables[key(table.schema, table.name)] = changed
		end

		def rename_table(table, new_name)
			@tables.delete(key(table.schema, table.name))
			@tables[key(table.schema, new_name)] = table.with(name: new_name)
			old_prefix = "sqlite_autoindex_#{table.name}_"
			@indexes.transform_values! { |i| (Catalog.same_name?(i.schema, table.schema) && Catalog.same_name?(i.table, table.name)) ? i.with(table: new_name) : i }
			@indexes.keys.each do |k|
				index = @indexes[k]
				next unless index.name.start_with?(old_prefix) && index.table == new_name

				@indexes.delete(k)
				renamed = index.with(name: index.name.sub(old_prefix, "sqlite_autoindex_#{new_name}_"))
				@indexes[key(renamed.schema, renamed.name)] = renamed
			end
			@triggers.transform_values! { |t| (Catalog.same_name?(t.schema, table.schema) && Catalog.same_name?(t.table, table.name)) ? t.with(table: new_name) : t }
		end

		def key(schema, name) = [schema.to_s.downcase(:ascii), name.to_s.downcase(:ascii)].freeze

		def lookup(collection, name, schema)
			return collection[key(schema, name)] if schema

			collection[key("temp", name)] || collection[key("main", name)] ||
				collection.find { |(_s, n), _| n == name.to_s.downcase(:ascii) }&.last
		end

		def schema_of(name, statement) = name.schema || (statement.temporary ? "temp" : "main")

		def add_create_table(statement)
			schema = schema_of(statement.table, statement)
			name = statement.table.name

			if statement.select_statement
				columns = Analysis::Resolver.new(catalog: self).output_columns(statement.select_statement)
				add_table(name, (columns unless columns.include?(nil)), schema:)
				return
			end

			columns = statement.columns.map(&:name)
			generated = statement.columns.select { |c| c.constraints&.any?(GeneratedAsColumnConstraint) }.map(&:name)
			add_table(name, columns, schema:, generated_columns: generated, rowid_alias: rowid_alias(statement), without_rowid: statement.without_row_id)
			Catalog.autoindexes(statement).each { |index| add_index(index, name, schema:) }
		end

		def add_create_view(statement)
			schema = schema_of(statement.view, statement)
			add_view(statement.view.name, statement.select, columns: statement.column_names, schema:)
		end

		# A column becomes another name for the rowid when it is the whole primary key and is
		# declared as exactly INTEGER - not INT, not BIGINT. See https://www.sqlite.org/lang_createtable.html#rowid
		def rowid_alias(statement)
			return if statement.without_row_id

			candidate = statement.columns.find do |column|
				column.constraints&.any? { |c| PrimaryKeyColumnConstraint === c && c.direction != :DESC }
			end

			unless candidate
				table_pk = statement.constraints&.find { |c| PrimaryKeyTableConstraint === c }
				if table_pk && table_pk.columns.size == 1
					pk_name = table_pk.columns[0].name.downcase(:ascii)
					candidate = statement.columns.find { |c| c.name.downcase(:ascii) == pk_name }
				end
			end

			candidate.name if Catalog.same_name?(candidate&.type&.text, "INTEGER")
		end

		def add_sqlite_table(db, schema, name, sql)
			info = db.execute("PRAGMA #{quote(schema)}.table_xinfo(#{quote(name)})")
			# hidden is 0 for ordinary columns, 1 for hidden virtual table columns, 2 and 3 for generated ones
			columns = info.reject { |row| row[6] == 1 }.map { |row| row[1] }
			hidden = info.select { |row| row[6] == 1 }.map { |row| row[1] }
			generated = info.select { |row| row[6] == 2 || row[6] == 3 }.map { |row| row[1] }
			without_rowid = sql.to_s.match?(/\bWITHOUT\s+ROWID\s*;?\s*\z/i)
			pk_rows = info.select { |row| row[5].to_i > 0 }
			rowid_alias = pk_rows[0][1] if !without_rowid && pk_rows.size == 1 && Catalog.same_name?(pk_rows[0][2].to_s, "INTEGER")

			statement = Parser.new(sql).parse.first
			module_name = statement.module_name if CreateVirtualTableStatement === statement
			add_table(name, columns, schema:, hidden_columns: hidden, generated_columns: generated, rowid_alias:, without_rowid:, module_name:)
			# The schema has no row for a WITHOUT ROWID table's primary key, though SQLite counts it as an index
			Catalog.autoindexes(statement).each { |index| add_index(index, name, schema:) } if CreateTableStatement === statement
		end

		def quote(identifier) = %("#{identifier.to_s.gsub('"', '""')}")
	end
end
