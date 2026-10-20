# frozen_string_literal: true

require "sqlite3"

# Asks SQLite which columns a statement reads, by preparing it with an authorizer
# callback installed. Used to check Plume.reads against the real thing.
class AuthorizerOracle
	SQLITE_DELETE = 9
	SQLITE_INSERT = 18
	SQLITE_READ = 20
	SQLITE_UPDATE = 23

	Result = Data.define(:tables, :columns, :inserted, :updated, :deleted)

	attr_reader :db, :catalog

	def initialize(schema_sql)
		@db = SQLite3::Database.new(":memory:")
		@db.execute_batch(schema_sql)
		@catalog = Plume::Catalog.from_sqlite(@db)
		@events = []
		@db.authorizer = proc do |action, table, column, *|
			# The names come as bytes, and are UTF-8 since the schema was
			@events << [action, table&.dup&.force_encoding(Encoding::UTF_8), column&.dup&.force_encoding(Encoding::UTF_8)]
			0
		end
	end

	def close = @db.close

	# Only base tables count - views and eponymous virtual tables like json_each
	# show up in the callback too, but Plume reports those separately
	def reads(sql)
		@events.clear
		@db.prepare(sql).close
		# SQLite folds the case of ASCII letters only
		known = @catalog.tables.to_h { |t| [t.name.downcase(:ascii), t.name] }

		tables = Set.new
		columns = Hash.new { |h, k| h[k] = Set.new }
		inserted = Set.new
		updated = Hash.new { |h, k| h[k] = Set.new }
		deleted = Set.new
		# For INSERT and DELETE the table comes as the first argument, the second is the schema
		@events.each do |action, table, column|
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
		Result.new(tables:, columns: columns.to_h, inserted:, updated: updated.to_h, deleted:)
	end
end
