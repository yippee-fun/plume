# frozen_string_literal: true

module Plume
	# What the read analysis knows about a database: its tables with their columns, and its
	# views. Names are matched case-insensitively, the way SQLite matches identifiers, and
	# reported in the spelling they were declared with.
	class Catalog
		ROWID_NAMES = %w[rowid oid _rowid_].freeze

		# `columns` is nil when they cannot be known, like a CREATE TABLE … AS SELECT * from a table
		# the catalog lacks; any column name is then taken as written
		Table = Data.define(:schema, :name, :columns, :hidden_columns, :rowid_alias, :without_rowid) do
			def column(name)
				return name.to_s unless columns

				needle = name.to_s.downcase(:ascii)
				columns.find { |c| c.downcase(:ascii) == needle } || hidden_columns.find { |c| c.downcase(:ascii) == needle }
			end

			def rowid? = !without_rowid
		end

		View = Data.define(:schema, :name, :columns, :select)

		def self.from_sql(sql) = new.load_sql(sql)

		# Takes a sqlite3-ruby `SQLite3::Database` (or anything with a compatible `#execute`)
		def self.from_sqlite(db) = new.load_sqlite(db)

		def initialize
			@tables = {}
			@views = {}
		end

		def add_table(name, columns, schema: "main", hidden_columns: [], rowid_alias: nil, without_rowid: false)
			table = Table.new(schema:, name:, columns: columns.freeze, hidden_columns: hidden_columns.freeze, rowid_alias:, without_rowid:)
			@tables[key(schema, name)] = table
		end

		# `select` is a `SelectStatement` or the SQL for one
		def add_view(name, select, columns: nil, schema: "main")
			select = Parser.new(select).parse.first if String === select
			@views[key(schema, name)] = View.new(schema:, name:, columns: columns&.freeze, select:)
		end

		# Unqualified names are looked up the way SQLite does: temp first, then main,
		# then attached databases in the order they were added
		def table(name, schema: nil) = lookup(@tables, name, schema)
		def view(name, schema: nil) = lookup(@views, name, schema)

		def tables = @tables.values
		def views = @views.values

		# Statements other than CREATE TABLE and CREATE VIEW (indexes, triggers, inserts…) do not
		# change what can be read, and are skipped without being parsed
		def load_sql(sql)
			Catalog.split_statements(sql).each do |statement_sql|
				leading = Plume.tokenize(statement_sql).first(3) - [:TEMP, :TEMPORARY]
				next unless leading[0] == :CREATE && (leading[1] in :TABLE | :VIEW)

				case (statement = Parser.new(statement_sql).parse.first)
				when CreateTableStatement then add_create_table(statement)
				when CreateViewStatement then add_create_view(statement)
				end
			end
			self
		end

		def load_sqlite(db)
			db.execute("PRAGMA database_list").each do |(_seq, schema, _file)|
				master = (schema == "temp") ? "sqlite_temp_master" : "#{quote(schema)}.sqlite_master"
				db.execute("SELECT type, name, sql FROM #{master} WHERE type IN ('table', 'view')").each do |(type, name, sql)|
					next if name.start_with?("sqlite_")

					if type == "view"
						statement = Parser.new(sql).parse.first
						add_view(name, statement.select, columns: statement.column_names, schema:)
					else
						add_sqlite_table(db, schema, name, sql)
					end
				end
			end
			self
		end

		# Splits SQL into statements on top-level semicolons, keeping trigger bodies
		# (`BEGIN …; …; END`) in one piece
		def self.split_statements(sql)
			lexer = Lexer.new(sql, skip_spaces: true)
			statements = []
			start = 0
			recent = []
			trigger_depth = 0
			in_trigger = false

			while (token = lexer.next_token)
				recent = [*recent.last(2), token]
				in_trigger = true if token == :TRIGGER && recent.include?(:CREATE)

				if in_trigger && token == :BEGIN
					trigger_depth += 1
				elsif in_trigger && token == :END && trigger_depth > 0
					trigger_depth -= 1
					in_trigger = false if trigger_depth.zero?
				elsif token == :SEMI && trigger_depth.zero?
					statements << sql.byteslice(start, lexer.cursor - start)
					start = lexer.cursor
				end
			end
			statements << sql.byteslice(start, sql.bytesize - start)
			statements.reject { |s| Plume.tokenize(s).reject { |t| t == :SEMI }.empty? }
		end

		private

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
			add_table(name, columns, schema:, rowid_alias: rowid_alias(statement), without_rowid: statement.without_row_id)
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

			candidate.name if candidate&.type&.text&.casecmp?("INTEGER")
		end

		def add_sqlite_table(db, schema, name, sql)
			info = db.execute("PRAGMA #{quote(schema)}.table_xinfo(#{quote(name)})")
			# hidden is 0 for ordinary columns, 1 for hidden virtual table columns, 2 and 3 for generated ones
			columns = info.reject { |row| row[6] == 1 }.map { |row| row[1] }
			hidden = info.select { |row| row[6] == 1 }.map { |row| row[1] }
			without_rowid = sql.to_s.match?(/\bWITHOUT\s+ROWID\s*;?\s*\z/i)
			pk_rows = info.select { |row| row[5].to_i > 0 }
			rowid_alias = pk_rows[0][1] if !without_rowid && pk_rows.size == 1 && pk_rows[0][2].to_s.casecmp?("INTEGER")

			add_table(name, columns, schema:, hidden_columns: hidden, rowid_alias:, without_rowid:)
		end

		def quote(identifier) = %("#{identifier.to_s.gsub('"', '""')}")
	end
end
