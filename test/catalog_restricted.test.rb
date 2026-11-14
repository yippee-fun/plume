# frozen_string_literal: true

require "sqlite3"

RESTRICTED_SCHEMA = <<~SQL
	CREATE TABLE accounts (id INTEGER PRIMARY KEY, name TEXT);
	CREATE TABLE secrets (id INTEGER PRIMARY KEY, token TEXT);
	CREATE TABLE users (
		id INTEGER PRIMARY KEY,
		account_id INT NOT NULL REFERENCES accounts(id),
		name TEXT DEFAULT 'x',
		email TEXT UNIQUE,
		secret_id INT REFERENCES secrets(id),
		shout TEXT GENERATED ALWAYS AS (upper(name)),
		both TEXT GENERATED ALWAYS AS (name || email),
		CHECK (length(email) > 3),
		CHECK (length(name) > 0),
		UNIQUE (name, email),
		FOREIGN KEY (account_id) REFERENCES accounts(id)
	);
	CREATE INDEX users_email ON users (email);
	CREATE INDEX accounts_name ON accounts (name);
	CREATE VIEW everyone AS SELECT * FROM users;
	CREATE TRIGGER touch AFTER UPDATE ON users BEGIN SELECT 1; END;
SQL

class Quickdraw::Test
	def restricted_from_sql = Plume::Catalog.from_sql(RESTRICTED_SCHEMA)

	def restricted_from_sqlite
		Plume::Catalog.from_sqlite(SQLite3::Database.new(":memory:").tap { |db| db.execute_batch(RESTRICTED_SCHEMA) })
	end
end

test "only the tables and columns named are left" do
	[restricted_from_sql, restricted_from_sqlite].each do |catalog|
		restricted = catalog.restricted("users" => %w[name id], "accounts" => :all)

		assert_equal restricted.tables.map(&:name).sort, %w[accounts users]
		assert_equal restricted.table("users").columns, %w[id name] # in the table's order, not the order asked for
		assert_equal restricted.table("accounts").columns, %w[id name]
		assert_equal restricted.table("secrets"), nil
		assert_equal restricted.views, []
		assert_equal restricted.triggers, []
		assert_equal restricted.indexes.map(&:name), ["accounts_name"]
	end
end

test "the catalog it came from stays whole" do
	catalog = restricted_from_sql
	catalog.restricted("users" => %w[id])

	assert_equal catalog.table("users").columns.size, 7
	assert_equal catalog.views.size, 1
	assert_includes catalog.table("users").to_sql, "email TEXT UNIQUE"
end

test "analysis against it does not find what was left out" do
	restricted = restricted_from_sql.restricted("users" => %w[id name])

	assert_equal Plume.reads("SELECT * FROM users", catalog: restricted).columns, { "users" => Set["id", "name"] }
	assert_raises(Plume::Analysis::Error) { Plume.reads("SELECT email FROM users", catalog: restricted) }
	assert_raises(Plume::Analysis::Error) { Plume.reads("SELECT * FROM secrets", catalog: restricted) }
	assert_raises(Plume::Analysis::Error) { Plume.reads("SELECT * FROM everyone", catalog: restricted) }
end

test "a table prints with the constraints that still have something to name" do
	[restricted_from_sql, restricted_from_sqlite].each do |catalog|
		restricted = catalog.restricted("users" => %w[id account_id name secret_id shout both], "accounts" => :all)
		sql = restricted.table("users").to_sql

		assert_includes sql, "account_id INT NOT NULL REFERENCES accounts (id)"
		assert_includes sql, "secret_id INT," # the table it pointed at is not in this catalog
		assert_includes sql, "shout TEXT GENERATED ALWAYS AS (upper(name))"
		assert_includes sql, "both TEXT," # generated from email, which is gone
		assert_includes sql, "CHECK (length(name) > 0)"
		refute_includes sql, "email"
		refute_includes sql, "secrets"

		SQLite3::Database.new(":memory:").execute_batch(restricted.tables.map(&:to_sql).join(";\n")) # SQLite takes it
	end
end

test "a table altered after it was created prints its column names only" do
	catalog = restricted_from_sql
	catalog.apply(Plume.parse("ALTER TABLE accounts ADD COLUMN plan TEXT").first)

	assert_equal catalog.table("accounts").to_sql, %(CREATE TABLE "accounts" ("id", "name", "plan"))
end

test "a table or column that is not there cannot be asked for" do
	assert_raises(ArgumentError) { restricted_from_sql.restricted("nonesuch" => :all) }
	assert_raises(ArgumentError) { restricted_from_sql.restricted("users" => %w[nonesuch]) }
end
