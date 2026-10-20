# frozen_string_literal: true

SCHEMA = <<~SQL
	CREATE TABLE users (id INTEGER PRIMARY KEY, email TEXT, secret TEXT, team_id INT);
	CREATE TABLE teams (id INTEGER PRIMARY KEY, name TEXT);
	CREATE TABLE tags (k TEXT PRIMARY KEY, v TEXT) WITHOUT ROWID;
	CREATE TABLE plain (a INT PRIMARY KEY, b TEXT);
	CREATE VIEW user_emails AS SELECT id, email FROM users;
	CREATE INDEX users_email ON users (email);
	CREATE TRIGGER t AFTER INSERT ON users BEGIN SELECT 1; SELECT 2; END;
SQL

class Quickdraw::Test
	def catalog = (@catalog ||= Plume::Catalog.from_sql(SCHEMA))

	def reads(sql, **) = Plume.reads(sql, catalog:, **)
end

# -- catalog

test "catalog from SQL knows tables, views and rowid aliases" do
	assert_equal catalog.tables.map(&:name), ["users", "teams", "tags", "plain"]
	assert_equal catalog.views.map(&:name), ["user_emails"]
	assert_equal catalog.table("USERS").columns, ["id", "email", "secret", "team_id"]
	assert_equal catalog.table("users").rowid_alias, "id"
	# Only a column declared exactly INTEGER aliases the rowid
	assert_equal catalog.table("plain").rowid_alias, nil
	refute catalog.table("tags").rowid?
end

test "catalog from SQL takes columns of CREATE TABLE AS from the select" do
	catalog = Plume::Catalog.from_sql("CREATE TABLE a (x, y); CREATE TABLE b AS SELECT x, y AS z, x + 1 FROM a")

	assert_equal catalog.table("b").columns, ["x", "z", "x + 1"]
end

# SQLite folds the case of ASCII letters only, so these are two tables and two columns
test "catalog tells apart names that differ in the case of non-ASCII letters" do
	catalog = Plume::Catalog.from_sql(%(CREATE TABLE "Σ" ("É"); CREATE TABLE "σ" ("é")))

	assert_equal catalog.tables.map(&:name), ["Σ", "σ"]
	assert_equal sorted(Plume.reads(%(SELECT "É" FROM "Σ"), catalog:).columns), { "Σ" => ["É"] }
	assert_equal sorted(Plume.reads(%(SELECT "é" FROM "σ"), catalog:).columns), { "σ" => ["é"] }
	assert_raises(Plume::Analysis::Error) { Plume.reads("SELECT é FROM Σ", catalog:) }
end

test "split_statements keeps trigger bodies whole" do
	statements = Plume::Catalog.split_statements(SCHEMA)

	assert_equal statements.size, 7
	assert statements.last.include?("SELECT 2; END")
end

# -- what gets read

test "select email from users where id = ?" do
	r = reads("select email from users where id = ?")

	assert_equal r.tables.to_a, ["users"]
	assert_equal sorted(r.projected), { "users" => ["email"] }
	assert_equal sorted(r.referenced), { "users" => ["id"] }
end

test "select count(*) from users" do
	r = reads("select count(*) from users")

	assert_equal r.tables.to_a, ["users"]
	assert_equal r.columns, {}
end

test "select * from users" do
	assert_equal sorted(reads("select * from users").projected), { "users" => ["email", "id", "secret", "team_id"] }
end

test "select t.*, u.email from teams t, users u" do
	assert_equal sorted(reads("select t.*, u.email from teams t, users u").projected),
		{ "teams" => ["id", "name"], "users" => ["email"] }
end

test "select u.email, t.name from users u join teams t on t.id = u.team_id order by t.name" do
	r = reads("select u.email, t.name from users u join teams t on t.id = u.team_id order by t.name")

	assert_equal sorted(r.projected), { "users" => ["email"], "teams" => ["name"] }
	assert_equal sorted(r.referenced), { "teams" => ["id", "name"], "users" => ["team_id"] }
end

test "select name from users join teams using (id)" do
	r = reads("select name from users join teams using (id)")

	# Both sides of a USING are read, even though SQLite's authorizer only reports one
	assert_equal sorted(r.referenced), { "users" => ["id"], "teams" => ["id"] }
end

test "select * from users natural join teams" do
	r = reads("select * from users natural join teams")

	assert_equal sorted(r.referenced), { "users" => ["id"], "teams" => ["id"] }
	# The merged column appears once in the output
	assert_equal sorted(r.projected), { "users" => ["email", "id", "secret", "team_id"], "teams" => ["name"] }
end

test "select rowid, oid, _rowid_ from users" do
	assert_equal sorted(reads("select rowid, oid, _rowid_ from users").projected), { "users" => ["id"] }
end

test "select rowid from plain" do
	assert_equal sorted(reads("select rowid from plain").projected), { "plain" => ["rowid"] }
end

test "select rowid from tags" do
	r = reads("select rowid from tags", strict: false)

	assert_equal r.unresolved.map(&:name), ["rowid"]
end

test "select email as e from users order by e" do
	r = reads("select email as e from users order by e")

	assert_equal sorted(r.columns), { "users" => ["email"] }
end

test "select email as e from users where e like '%@x'" do
	# SQLite lets WHERE fall back to result aliases
	assert reads("select email as e from users where e like '%@x'").resolved?
end

test "select email from users where \"nope\" = 1" do
	# An unresolvable double-quoted identifier is a string in SQLite
	assert reads("select email from users where \"nope\" = 1").resolved?
end

# -- nesting

test "select email from users u where exists (select 1 from teams t where t.id = u.team_id)" do
	r = reads("select email from users u where exists (select 1 from teams t where t.id = u.team_id)")

	assert_equal sorted(r.projected), { "users" => ["email"] }
	assert_equal sorted(r.referenced), { "teams" => ["id"], "users" => ["team_id"] }
end

test "select id from users where team_id in (select id from teams where name = 'x')" do
	r = reads("select id from users where team_id in (select id from teams where name = 'x')")

	# Columns selected by a filtering subquery only filter
	assert_equal sorted(r.referenced), { "users" => ["team_id"], "teams" => ["id", "name"] }
	assert_equal sorted(r.projected), { "users" => ["id"] }
end

test "select (select name from teams where id = team_id) from users" do
	r = reads("select (select name from teams where id = team_id) from users")

	assert_equal sorted(r.projected), { "teams" => ["name"] }
	assert_equal sorted(r.referenced), { "teams" => ["id"], "users" => ["team_id"] }
end

test "select s.e from (select email as e, secret from users) s" do
	r = reads("select s.e from (select email as e, secret from users) s")

	# Everything the subquery selects is read, used further up or not
	assert_equal sorted(r.projected), { "users" => ["email", "secret"] }
end

test "select s.missing from (select email from users) s" do
	r = reads("select s.missing from (select email from users) s", strict: false)

	assert_equal r.unresolved.map(&:reason), ["no such column in s"]
end

# -- CTEs and views

test "with x as (select secret from users) select 1" do
	# An unused CTE is never evaluated
	assert_equal reads("with x as (select secret from users) select 1").tables.to_a, []
end

test "with x as (select id, secret from users) select id from x" do
	assert_equal sorted(reads("with x as (select id, secret from users) select id from x").projected),
		{ "users" => ["id", "secret"] }
end

test "with x(a) as (select email from users) select a from x where a is not null" do
	assert reads("with x(a) as (select email from users) select a from x where a is not null").resolved?
end

test "with recursive n(i) as (select 1 union all select i + 1 from n where i < 5) select i from n" do
	r = reads("with recursive n(i) as (select 1 union all select i + 1 from n where i < 5) select i from n")

	assert r.resolved?
	assert_equal r.tables.to_a, []
end

test "with users as (select 1 as id) select id from users" do
	# A CTE shadows the table it is named after
	assert_equal reads("with users as (select 1 as id) select id from users").tables.to_a, []
end

test "select email from user_emails" do
	r = reads("select email from user_emails")

	assert_equal r.views.to_a, ["user_emails"]
	assert_equal sorted(r.projected), { "users" => ["email", "id"] }
end

# -- table-valued functions

test "select j.value, u.email from users u, json_each(u.secret) j" do
	r = reads("select j.value, u.email from users u, json_each(u.secret) j")

	assert_equal r.functions.to_a, ["json_each"]
	assert_equal sorted(r.columns), { "users" => ["email", "secret"] }
end

# -- strictness

test "select nope from users raises with a pointer at the culprit" do
	error = begin
		reads("select nope from users")
		nil
	rescue Plume::Analysis::Error => e
		e
	end

	assert_equal error.unresolved.map(&:name), ["nope"]
	assert_equal error.message, "no such column: nope\n  select nope from users\n         ^^^^"
end

test "select id from users, teams is ambiguous" do
	assert_equal reads("select id from users, teams", strict: false).unresolved.map(&:reason), ["ambiguous column name"]
end

test "select * from nowhere" do
	assert_equal reads("select * from nowhere", strict: false).unresolved.map(&:reason), ["no such table"]
end

test "views that select from each other are reported, not followed forever" do
	catalog = Plume::Catalog.from_sql("CREATE VIEW v1 AS SELECT * FROM v2; CREATE VIEW v2 AS SELECT * FROM v1;")

	assert_equal Plume.reads("select * from v1", catalog:, strict: false).unresolved.map(&:reason), ["circularly defined view"]
end

test "a view may be used twice in one query" do
	assert_equal sorted(reads("select a.id, b.email from user_emails a, user_emails b").columns), { "users" => ["email", "id"] }
end

test "a table made from a select whose columns cannot be known takes any column" do
	catalog = Plume::Catalog.from_sql("CREATE TABLE c AS SELECT * FROM missing")

	assert_equal sorted(Plume.reads("select q from c", catalog:).columns), { "c" => ["q"] }
	assert_equal sorted(Plume.access("insert into c values (1)", catalog:).writes.inserted), { "c" => ["*"] }
end

test "only a single SELECT is analyzed" do
	["select 1; select 2", "create table x (a)"].each do |sql|
		raised = begin
			Plume.reads(sql)
			false
		rescue Plume::Analysis::Error
			true
		end
		assert raised
	end
end

# -- without a catalog

test "select * from users u join teams t on t.id = u.team_id, without a catalog" do
	r = Plume.reads("select u.*, t.name from users u join teams t on t.id = u.team_id")

	assert_equal sorted(r.projected), { "users" => ["*"], "teams" => ["name"] }
	assert_equal sorted(r.referenced), { "teams" => ["id"], "users" => ["team_id"] }
end

test "select email from users where id = 1, without a catalog" do
	assert_equal sorted(Plume.reads("select email from users where id = 1").columns), { "users" => ["email", "id"] }
end

test "select email from users, teams, without a catalog" do
	r = Plume.reads("select email from users, teams", strict: false)

	assert_equal r.unresolved.map(&:reason), ["ambiguous column name without a catalog"]
end

test "select email from aux.users, without a catalog" do
	assert_equal Plume.reads("select email from aux.users").columns.keys, ["aux.users"]
end
