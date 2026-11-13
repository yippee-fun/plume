# frozen_string_literal: true

require "sqlite3"

# Asks SQLite which columns a statement reads, by preparing it with an authorizer
# callback installed. Used to check Plume.reads against the real thing.
class AuthorizerOracle
	SQLITE_DELETE = 9
	SQLITE_INSERT = 18
	SQLITE_READ = 20
	SQLITE_UPDATE = 23
	SQLITE_FUNCTION = 31
	# The action codes that are neither reads nor writes of rows, by the names Plume gives them
	ACTIONS = {
		1 => :create_index, 2 => :create_table, 3 => :create_temp_index, 4 => :create_temp_table, 5 => :create_temp_trigger,
		6 => :create_temp_view, 7 => :create_trigger, 8 => :create_view, 10 => :drop_index, 11 => :drop_table,
		12 => :drop_temp_index, 13 => :drop_temp_table, 14 => :drop_temp_trigger, 15 => :drop_temp_view, 16 => :drop_trigger,
		17 => :drop_view, 19 => :pragma, 22 => :transaction, 24 => :attach, 25 => :detach, 26 => :alter_table,
		27 => :reindex, 28 => :analyze, 29 => :create_vtable, 30 => :drop_vtable, 32 => :savepoint,
	}.freeze

	Result = Data.define(:tables, :columns, :inserted, :updated, :deleted, :calls, :actions)

	attr_reader :db, :catalog

	def initialize(schema_sql)
		@db = SQLite3::Database.new(":memory:")
		@db.execute_batch(schema_sql)
		@catalog = Plume::Catalog.from_sqlite(@db)
		@events = []
		@db.authorizer = proc do |action, table, column, schema, trigger|
			# The names come as bytes, and are UTF-8 since the schema was. A function's name comes second
			@events << [action, table&.dup&.force_encoding(Encoding::UTF_8), column&.dup&.force_encoding(Encoding::UTF_8), trigger, schema]
			0
		end
	end

	def close = @db.close

	# Only base tables count - views and eponymous virtual tables like json_each
	# show up in the callback too, but Plume reports those separately
	# With `trigger:`, only what that trigger does when `sql` fires it. SQLite names the innermost
	# trigger _or view_ behind each access, so without one everything counts
	def reads(sql, trigger: nil)
		@events.clear
		@db.prepare(sql).close
		@events.select! { |event| event[3] == trigger } if trigger
		# SQLite folds the case of ASCII letters only
		known = @catalog.tables.to_h { |t| [t.name.downcase(:ascii), t.name] }

		tables = Set.new
		columns = Hash.new { |h, k| h[k] = Set.new }
		inserted = Set.new
		updated = Hash.new { |h, k| h[k] = Set.new }
		deleted = Set.new
		calls = @events.filter_map { |action, _, name, *| name if action == SQLITE_FUNCTION }.to_set
		# ALTER TABLE gives the schema first and the table second, and puts a dropped column where the schema goes
		actions = @events.filter_map do |action, first, second, _trigger, schema|
			next unless (name = ACTIONS[action])

			(name == :alter_table) ? [name, second, schema, first] : [name, first, second, schema]
		end
		# For INSERT and DELETE the table comes as the first argument, the second is the schema
		@events.each do |action, table, column, *|
			next unless table && (name = known[table.downcase(:ascii)])

			case action
			when SQLITE_INSERT then inserted << name
			when SQLITE_DELETE then deleted << name
			when SQLITE_UPDATE then updated[name] << column
			when SQLITE_READ
				tables << name
				columns[name] << (column.casecmp?("rowid") ? "rowid" : column) unless column.nil? || column.empty?
			end
		end
		Result.new(tables:, columns: columns.to_h, inserted:, updated: updated.to_h, deleted:, calls:, actions:)
	end
end
