# frozen_string_literal: true

ACCESS_SCHEMA = <<~SQL
	CREATE TABLE users (id INTEGER PRIMARY KEY, email TEXT, secret TEXT, team_id INT);
	CREATE TABLE teams (id INTEGER PRIMARY KEY, name TEXT);
SQL

class Quickdraw::Test
	def access(sql, **) = Plume.access(sql, catalog: Plume::Catalog.from_sql(ACCESS_SCHEMA), **)
end

test "insert into users (email) values (?)" do
	a = access("insert into users (email) values (?)")

	assert_equal sorted(a.writes.inserted), { "users" => ["email"] }
	assert_equal a.reads.tables.to_a, []
end

test "insert into users values (1, 'a', 'b', 2)" do
	assert_equal sorted(access("insert into users values (1, 'a', 'b', 2)").writes.inserted),
		{ "users" => ["email", "id", "secret", "team_id"] }
end

test "insert into users default values" do
	a = access("insert into users default values")

	assert_equal a.writes.tables(:insert).to_a, ["users"]
	assert_equal a.writes.inserted, {}
end

test "insert into users (email, secret) select name, name from teams where id = ?" do
	a = access("insert into users (email, secret) select name, name from teams where id = ?")

	# Copying a value into another table lets it out just as much as returning it does
	assert_equal sorted(a.reads.projected), { "teams" => ["name"] }
	assert_equal sorted(a.reads.referenced), { "teams" => ["id"] }
end

test "insert into users (id) values (1) on conflict (id) do update set secret = excluded.secret where users.email is null returning team_id" do
	a = access("insert into users (id) values (1) on conflict (id) do update set secret = excluded.secret where users.email is null returning team_id")

	assert_equal sorted(a.writes.inserted), { "users" => ["id"] }
	assert_equal sorted(a.writes.updated), { "users" => ["secret"] }
	# excluded.secret is the row we tried to insert, not a read of users
	assert_equal sorted(a.reads.referenced), { "users" => ["email", "id"] }
	assert_equal sorted(a.reads.projected), { "users" => ["team_id"] }
end

test "insert into users as u (id) values (1) on conflict do update set secret = email" do
	a = access("insert into users as u (id) values (1) on conflict do update set secret = email")

	# A bare name in DO UPDATE is the existing row, never `excluded`
	assert_equal sorted(a.reads.projected), { "users" => ["email"] }
end

test "update users set email = upper(secret) where id = ?" do
	a = access("update users set email = upper(secret) where id = ?")

	assert_equal sorted(a.writes.updated), { "users" => ["email"] }
	assert_equal sorted(a.reads.projected), { "users" => ["secret"] }
	assert_equal sorted(a.reads.referenced), { "users" => ["id"] }
end

test "update users as u set team_id = t.id from teams t where t.name = u.email returning *" do
	a = access("update users as u set team_id = t.id from teams t where t.name = u.email returning *")

	# RETURNING * is the target's columns only
	assert_equal sorted(a.reads.projected), { "teams" => ["id"], "users" => ["email", "id", "secret", "team_id"] }
end

test "update users set (email, secret) = (select name, name from teams)" do
	assert_equal sorted(access("update users set (email, secret) = (select name, name from teams)").writes.updated),
		{ "users" => ["email", "secret"] }
end

test "delete from users" do
	a = access("delete from users")

	assert_equal a.writes.deleted.to_a, ["users"]
	assert_equal a.reads.tables.to_a, []
end

test "with gone as (select id from teams where name is null) delete from users where team_id in gone returning email" do
	a = access("with gone as (select id from teams where name is null) delete from users where team_id in gone returning email")

	assert_equal sorted(a.reads.referenced), { "teams" => ["id", "name"], "users" => ["team_id"] }
	assert_equal sorted(a.reads.projected), { "users" => ["email"] }
end

test "with users as (select 1 as id) delete from users" do
	# The target of a write is always a real table, CTEs do not stand in for it
	assert_equal access("with users as (select 1 as id) delete from users").writes.deleted.to_a, ["users"]
end

test "update users set nope = 1" do
	assert_equal access("update users set nope = 1", strict: false).unresolved.map(&:reason), ["no such column in users"]
end

test "insert into users select * from teams, without a catalog" do
	a = Plume.access("insert into users select * from teams")

	assert_equal sorted(a.writes.inserted), { "users" => ["*"] }
	assert_equal sorted(a.reads.projected), { "teams" => ["*"] }
end

test "Plume.reads takes DML too" do
	assert_equal sorted(Plume.reads("delete from t where a = 1").referenced), { "t" => ["a"] }
end

test "an already parsed statement can be analyzed without parsing it again" do
	sql = "update users set email = upper(secret) where id = ?"
	catalog = Plume::Catalog.from_sql(ACCESS_SCHEMA)
	from_sql = Plume.access(sql, catalog:)

	[Plume.parse(sql), Plume.parse(sql).first].each do |parsed|
		a = Plume.access(parsed, catalog:)

		assert_equal a.writes.updated, from_sql.writes.updated
		assert_equal a.reads.columns, from_sql.reads.columns
		assert_equal Plume.reads(parsed, catalog:).columns, from_sql.reads.columns
	end
end

test "an edited tree is analyzed as edited" do
	statement = Plume.parse("select email from users").first
	statement.body.condition = Plume::BinaryExpression.new(
		operator: :EQUALS, left: Plume::ColumnName.new(column: "team_id"), right: Plume::Variable.new(name: "?"),
	)

	assert_equal sorted(access(statement).reads.referenced), { "users" => ["team_id"] }
end

test "a parsed list of several statements is refused like SQL with several statements" do
	assert_raises(Plume::Analysis::Error) { Plume.access(Plume.parse("select 1; select 2")) }
end

# Whether it is too deep depends on the stack, but running out of it must not show
test "a statement too deep for the resolver's stack is an analysis error" do
	sql = "SELECT * FROM #{"(SELECT * FROM " * 999}t#{")" * 999}"
	result = Thread.new do
		Plume.access(Plume.parse(sql))
	rescue Plume::Analysis::Error, Plume::SyntaxError => e
		e # some Rubies run out of stack parsing it already
	end.value

	assert([Plume::Analysis::Error, Plume::SyntaxError, Plume::Analysis::Access].any? { |kind| kind === result }) { result.inspect[0, 200] }
end

test "a join may have 64 tables, as in SQLite" do
	access("SELECT 1 FROM users#{(2..64).map { |i| " JOIN users AS u#{i} ON u#{i}.id = users.id" }.join}")

	error = assert_raises(Plume::Analysis::Error) { access("SELECT 1 FROM users, (#{(["teams"] * 64).join(", ")})") }
	assert_equal error.message, "at most 64 tables in a join"
end
