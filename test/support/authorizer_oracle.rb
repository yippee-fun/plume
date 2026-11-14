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

	Result = Data.define(:tables, :columns, :inserted, :updated, :deleted, :calls)

	attr_reader :db, :catalog

	def initialize(schema_sql)
		@db = SQLite3::Database.new(":memory:")
		@db.execute_batch(schema_sql)
		@catalog = Plume::Catalog.from_sqlite(@db)
		@events = []
		@db.authorizer = proc do |action, table, column, _schema, trigger|
			# The names come as bytes, and are UTF-8 since the schema was. A function's name comes second
			@events << [action, table&.dup&.force_encoding(Encoding::UTF_8), column&.dup&.force_encoding(Encoding::UTF_8), trigger]
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
		@events.select! { |*, name| name == trigger } if trigger
		# SQLite folds the case of ASCII letters only
		known = @catalog.tables.to_h { |t| [t.name.downcase(:ascii), t.name] }

		tables = Set.new
		columns = Hash.new { |h, k| h[k] = Set.new }
		inserted = Set.new
		updated = Hash.new { |h, k| h[k] = Set.new }
		deleted = Set.new
		calls = @events.filter_map { |action, _, name, _| name if action == SQLITE_FUNCTION }.to_set
		# For INSERT and DELETE the table comes as the first argument, the second is the schema
		@events.each do |action, table, column, _trigger|
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
		Result.new(tables:, columns: columns.to_h, inserted:, updated: updated.to_h, deleted:, calls:)
	end
end
