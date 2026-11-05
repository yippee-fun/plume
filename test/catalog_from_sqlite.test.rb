# frozen_string_literal: true

require "sqlite3"

test "the catalog knows generated columns from a database" do
	db = SQLite3::Database.new(":memory:")
	db.execute("CREATE TABLE totals (a INT, b INT, total INT GENERATED ALWAYS AS (a + b) STORED, half INT AS (a / 2))")

	assert_equal Plume::Catalog.from_sqlite(db).table("totals").generated_columns, ["total", "half"]
end
