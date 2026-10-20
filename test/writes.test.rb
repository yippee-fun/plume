# frozen_string_literal: true

require "sqlite3"

WRITES_SCHEMA = <<~SQL
	CREATE TABLE users (id INTEGER PRIMARY KEY, email TEXT, secret TEXT, team_id INT);
	CREATE TABLE teams (id INTEGER PRIMARY KEY, name TEXT);
	CREATE TABLE totals (a INT, b INT, total INT GENERATED ALWAYS AS (a + b));
	CREATE TABLE log (msg TEXT);
	CREATE VIEW user_emails AS SELECT id, email FROM users;
	CREATE TRIGGER users_log AFTER INSERT ON users BEGIN INSERT INTO log (msg) VALUES (new.email); END;
SQL

class Quickdraw::Test
	def writes(sql, **) = Plume.writes(sql, catalog: Plume::Catalog.from_sql(WRITES_SCHEMA), **)
end

# -- INSERT

test "insert with a column list writes those columns" do
	w = writes("insert into users (email, secret) values (?, ?)")

	assert_equal sorted(w.columns), { "users" => ["email", "secret"] }
	assert_equal sorted(w.inserted), { "users" => ["email", "secret"] }
	assert_equal w.tables.to_a, ["users"]
	assert_equal w.updated, {}
	assert_equal w.deleted.to_a, []
end

test "insert without a column list writes every column of the table" do
	assert_equal sorted(writes("insert into users values (1, 'a', 'b', 2)").columns),
		{ "users" => ["email", "id", "secret", "team_id"] }
end

test "insert without a column list leaves out generated columns" do
	assert_equal sorted(writes("insert into totals values (1, 2)").columns), { "totals" => ["a", "b"] }
end

test "the catalog knows generated columns, from SQL and from a database" do
	db = SQLite3::Database.new(":memory:")
	db.execute("CREATE TABLE totals (a INT, b INT, total INT GENERATED ALWAYS AS (a + b) STORED, half INT AS (a / 2))")

	assert_equal Plume::Catalog.from_sql(WRITES_SCHEMA).table("totals").generated_columns, ["total"]
	assert_equal Plume::Catalog.from_sqlite(db).table("totals").generated_columns, ["total", "half"]
end

test "insert without a column list and without a catalog writes *" do
	assert_equal Plume.writes("insert into users values (1, 2)").columns, { "users" => Set["*"] }
end

test "insert default values writes the table but names no columns" do
	w = writes("insert into users default values")

	assert_equal w.tables(:insert).to_a, ["users"]
	assert_equal w.columns, {}
end

test "insert ... select writes only the target" do
	w = writes("insert into users (email) select name from teams")

	assert_equal sorted(w.columns), { "users" => ["email"] }
	assert_equal w.tables.to_a, ["users"]
end

test "replace and insert or replace write like an insert" do
	# The rows a REPLACE deletes to make room are not reported, as SQLite's authorizer does not
	["replace into users (id, email) values (1, ?)", "insert or replace into users (id, email) values (1, ?)"].each do |sql|
		w = writes(sql)

		assert_equal sorted(w.inserted), { "users" => ["email", "id"] }
		assert_equal w.deleted.to_a, []
	end
end

test "an upsert writes the inserted columns and the ones DO UPDATE sets" do
	w = writes("insert into users (id, email) values (1, ?) on conflict (id) do update set secret = excluded.secret, team_id = 2")

	assert_equal sorted(w.inserted), { "users" => ["email", "id"] }
	assert_equal sorted(w.updated), { "users" => ["secret", "team_id"] }
	assert_equal sorted(w.columns), { "users" => ["email", "id", "secret", "team_id"] }
end

test "an upsert that does nothing writes only the inserted columns" do
	w = writes("insert into users (id) values (1) on conflict do nothing")

	assert_equal sorted(w.columns), { "users" => ["id"] }
	assert_equal w.updated, {}
end

# -- UPDATE

test "update writes the columns it sets" do
	w = writes("update users set email = lower(email), secret = null where id = ?")

	assert_equal sorted(w.updated), { "users" => ["email", "secret"] }
	assert_equal w.tables(:update).to_a, ["users"]
end

test "update with a row value writes every column in the list" do
	assert_equal sorted(writes("update users set (email, secret) = (select name, name from teams)").updated),
		{ "users" => ["email", "secret"] }
end

test "update ... from writes only the target, through its alias" do
	w = writes("update users as u set team_id = t.id from teams t where t.name = u.email")

	assert_equal sorted(w.columns), { "users" => ["team_id"] }
	assert_equal w.tables.to_a, ["users"]
end

test "update reports column names as the catalog spells them" do
	assert_equal sorted(writes("update USERS set EMAIL = ?").updated), { "users" => ["email"] }
end

test "schema-qualified targets are keyed by schema outside main" do
	assert_equal sorted(writes("update main.users set email = ?").updated), { "users" => ["email"] }
	assert_equal sorted(Plume.writes("update aux.users set email = ?").updated), { "aux.users" => ["email"] }
end

# -- DELETE

test "delete writes the whole table" do
	w = writes("delete from users where id = ?")

	assert_equal w.deleted.to_a, ["users"]
	assert_equal w.tables.to_a, ["users"]
	assert_equal w.columns, {}
end

# -- around the edges

test "returning does not add writes" do
	w = writes("update users set email = ? where id = ? returning *")

	assert_equal sorted(w.columns), { "users" => ["email"] }
end

test "a CTE is read, not written, and never stands in for the target" do
	w = writes("with gone as (select id from teams where name is null) delete from users where team_id in gone")

	assert_equal w.deleted.to_a, ["users"]

	w = writes("with users as (select 1 as id) delete from users")

	assert_equal w.deleted.to_a, ["users"]
end

test "triggers are not expanded" do
	# users_log inserts into log, which SQLite would run but we do not look into
	assert_equal writes("insert into users (email) values (?)").tables.to_a, ["users"]
end

test "a select writes nothing" do
	w = writes("select * from users")

	assert_equal w.tables.to_a, []
	assert_equal w.columns, {}
end

test "writing to a view reports the view, as only its INSTEAD OF triggers could say more" do
	assert_equal sorted(writes("insert into user_emails (email) values (?)").columns), { "user_emails" => ["email"] }
end

test "an unknown table or column raises in strict mode, like reads" do
	assert_raises(Plume::Analysis::Error) { writes("insert into nope (a) values (1)") }
	assert_raises(Plume::Analysis::Error) { writes("update users set nope = 1") }
end

test "an unknown table or column is listed as unresolved when not strict" do
	w = writes("update users set nope = 1, email = ?", strict: false)

	assert_equal sorted(w.updated), { "users" => ["email"] }
	assert_equal w.unresolved.map(&:name), ["nope"]
end

test "anything goes without a catalog" do
	assert_equal Plume.writes("insert into nope (a) values (1)").columns, { "nope" => Set["a"] }
end

test "writes takes an already parsed statement" do
	statement = Plume.parse("delete from users").first

	assert_equal writes(statement).deleted.to_a, ["users"]
end
