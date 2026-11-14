# frozen_string_literal: true

require "sqlite3"

POLICY_SCHEMA = <<~SQL
	CREATE TABLE users (id INTEGER PRIMARY KEY, account_id INT, name TEXT, email TEXT);
	CREATE TABLE posts (id INTEGER PRIMARY KEY, account_id INT, user_id INT, title TEXT, body TEXT);
	CREATE TABLE projects (id INTEGER PRIMARY KEY, name TEXT);
	CREATE TABLE missions (id INTEGER PRIMARY KEY, name TEXT);
	CREATE TABLE reviews (id INTEGER PRIMARY KEY, reviewer_id INT, due_at TEXT, verdict TEXT);
	CREATE TABLE notes (id INTEGER PRIMARY KEY, account_id INT, body TEXT);
	CREATE TABLE secrets (id INTEGER PRIMARY KEY, token TEXT);
	CREATE VIEW all_posts AS SELECT id, title FROM posts;
	INSERT INTO users VALUES (1, 1, 'ann', 'ann@one'), (2, 1, 'bob', 'bob@one'), (3, 2, 'cat', 'cat@two'), (4, 2, 'dan', 'dan@two');
	INSERT INTO posts VALUES (1, 1, 1, 'a1', 'ab1'), (2, 1, 2, 'b1', 'bb1'), (3, 2, 3, 'c2', 'cb2'), (4, 2, 4, 'd2', 'db2');
	INSERT INTO projects VALUES (1, 'p1'), (2, 'p2');
	INSERT INTO missions VALUES (1, 'm1');
	INSERT INTO reviews VALUES (1, 49, 'mon', 'good'), (2, 50, 'tue', 'bad'), (3, 49, 'wed', 'meh');
	INSERT INTO notes VALUES (1, 1, 'n1'), (2, 2, 'n2');
	INSERT INTO secrets VALUES (1, 'tok');
SQL

class Quickdraw::Test
	def policy_db
		@policy_db ||= SQLite3::Database.new(":memory:").tap { |db| db.execute_batch(POLICY_SCHEMA) }
	end

	def policy_catalog = Plume::Catalog.from_sqlite(policy_db)

	# Account 1's view of the world
	def build_policy
		Plume::Policy.new(catalog: policy_catalog) do |p|
			p.table :users, read: %i[id name], scope: "account_id = 1"
			p.table :posts, read: :all, scope: "account_id = 1"
			p.table :projects, :missions, read: :all
			p.functions :json_each
		end
	end

	def scoped(sql, *binds, policy: build_policy) = policy_db.execute(policy.scope(sql), binds)

	def denied(sql, policy: build_policy)
		policy.scope(sql)
		flunk "expected #{sql} to be denied"
	rescue Plume::Policy::Denied => e
		e
	end
end

test "a join of two scoped tables with aliases" do
	rows = scoped("SELECT p.title, u.name FROM posts p JOIN users u ON u.id = p.user_id ORDER BY p.id")

	assert_equal rows, [["a1", "ann"], ["b1", "bob"]]
end

test "OR 1=1 does not widen the scope" do
	assert_equal scoped("SELECT id FROM posts WHERE id = 3 OR 1=1 ORDER BY id"), [[1], [2]]
	assert_equal scoped("SELECT id FROM posts WHERE 1=1 OR id = 3 ORDER BY id"), [[1], [2]]
end

test "a subquery in WHERE is scoped" do
	rows = scoped("SELECT id FROM posts WHERE user_id IN (SELECT id FROM users) ORDER BY id")
	assert_equal rows, [[1], [2]]

	rows = scoped("SELECT name FROM users WHERE id NOT IN (SELECT user_id FROM posts WHERE title = 'c2') ORDER BY id")
	assert_equal rows, [["ann"], ["bob"]]
end

test "a correlated scalar subquery is scoped" do
	rows = scoped("SELECT u.name, (SELECT count(*) FROM posts p WHERE p.user_id = u.id) FROM users u ORDER BY u.id")

	assert_equal rows, [["ann", 1], ["bob", 1]]
	assert_equal scoped("SELECT (SELECT count(*) FROM users)"), [[2]]
end

test "every arm of a UNION is scoped" do
	rows = scoped("SELECT title FROM posts UNION ALL SELECT name FROM users UNION SELECT name FROM projects ORDER BY 1")

	assert_equal rows, [["a1"], ["ann"], ["b1"], ["bob"], ["p1"], ["p2"]]
end

test "a CTE shadowing a table name is left alone" do
	assert_equal scoped("WITH posts AS (SELECT 'mine' AS title) SELECT title FROM posts"), [["mine"]]
	assert_equal scoped("WITH users AS (SELECT 1 AS id, 'cte' AS name) SELECT name FROM users"), [["cte"]]
end

test "a CTE reading a table is scoped" do
	assert_equal scoped("WITH x AS (SELECT * FROM posts) SELECT id FROM x ORDER BY id"), [[1], [2]]
end

test "a CTE named like a table that is also read as that table is denied" do
	e = denied("SELECT id FROM posts WHERE id IN (WITH posts AS (SELECT 3 AS id) SELECT id FROM posts)")

	assert_includes e.message, "both a table and a WITH name"
end

test "a main-qualified table is scoped" do
	assert_equal scoped("SELECT id FROM main.posts ORDER BY id"), [[1], [2]]
	assert_equal scoped("SELECT p.id FROM MAIN.Posts AS p ORDER BY p.id"), [[1], [2]]
end

test "quoted identifiers as ActiveRecord writes them, with binds" do
	rows = scoped(%(SELECT "posts".* FROM "posts" WHERE "posts"."account_id" = ? ORDER BY "posts"."id"), 2)
	assert_equal rows, [] # account 2 is out of scope

	rows = scoped(%(SELECT "posts".* FROM "posts" WHERE "posts"."account_id" = ? AND "posts"."id" > ? ORDER BY "posts"."id"), 1, 1)
	assert_equal rows, [[2, 1, 2, "b1", "bb1"]]
end

test "SELECT * only shows the columns that may be read" do
	rows = scoped("SELECT * FROM users ORDER BY id")
	assert_equal rows, [[1, "ann"], [2, "bob"]]

	rows = scoped("SELECT u.* FROM users u ORDER BY id")
	assert_equal rows, [[1, "ann"], [2, "bob"]]
end

test "count(*) of a column-limited table is fine" do
	assert_equal scoped("SELECT count(*) FROM users"), [[2]]
end

test "a hidden column in WHERE is denied" do
	e = denied("SELECT id FROM users WHERE email LIKE '%@two'")

	assert_includes e.message, "not allowed to read users.email"
	assert_includes e.message, "visible columns: id, name"
	assert_includes e.message, "^"
	assert Plume::ColumnName === e.node
end

test "a hidden column anywhere else is denied" do
	denied("SELECT email FROM users")
	denied("SELECT id FROM users ORDER BY email")
	denied("SELECT id FROM users GROUP BY email")
	denied("SELECT u.email FROM users u")
	denied("SELECT id FROM posts WHERE user_id IN (SELECT id FROM users WHERE email = 'x')")
	denied("SELECT * FROM users u JOIN users v USING (email)")
end

test "an undeclared table is denied" do
	e = denied("SELECT token FROM secrets")

	assert_includes e.message, "not allowed to read secrets"
	assert_includes e.message, "SELECT token FROM secrets"
	assert Plume::TableName === e.node
	denied("SELECT 1 FROM posts, secrets")
	denied("SELECT 1 FROM posts WHERE EXISTS (SELECT 1 FROM secrets)")
	denied("SELECT * FROM temp.posts")
end

test "sqlite_master is denied" do
	denied("SELECT sql FROM sqlite_master")
	denied("SELECT sql FROM main.sqlite_schema")
end

test "a table-valued function that is not allowed is denied" do
	e = denied("SELECT name FROM pragma_table_info('users')")
	assert_includes e.message, "pragma_table_info"

	denied("SELECT * FROM dbstat")
	denied("SELECT * FROM dbstat('main')")
	denied("SELECT * FROM sqlite_dbpage")
end

test "an allowed table-valued function passes" do
	assert_equal scoped(%(SELECT value FROM json_each('[1,2]') ORDER BY 1)), [[1], [2]]
	assert_equal scoped(%(SELECT p.id, j.value FROM posts p, json_each('[7]') j ORDER BY p.id)), [[1, 7], [2, 7]]
end

test "a view is denied" do
	e = denied("SELECT title FROM all_posts")

	assert_includes e.message, "view all_posts"
	assert Plume::TableName === e.node
end

test "anything but a single SELECT is denied" do
	denied("DELETE FROM posts")
	denied("INSERT INTO posts (title) VALUES ('x')")
	denied("UPDATE posts SET title = 'x'")
	denied("PRAGMA table_info(users)")
	denied("ATTACH DATABASE ':memory:' AS other")
	denied("SELECT id FROM posts; SELECT id FROM posts")
	denied("SELECT id FROM posts; DELETE FROM posts")
	denied("")
	denied("EXPLAIN SELECT id FROM posts")
end

test "a syntax error is not hidden" do
	assert_raises(Plume::SyntaxError) { build_policy.scope("SELECT FROM WHERE") }
end

test "a table that is unknown to the catalog is denied" do
	denied("SELECT * FROM nonesuch")
	denied("SELECT nonesuch FROM posts")
end

test "the scope as a full SELECT" do
	policy = Plume::Policy.new(catalog: policy_catalog) do |p|
		p.table :reviews, read: %i[id due_at], scope: "SELECT * FROM reviews WHERE reviewer_id = 49"
	end

	assert_equal scoped("SELECT * FROM reviews ORDER BY id", policy:), [[1, "mon"], [3, "wed"]]
	assert_equal scoped("SELECT id FROM reviews WHERE id = 2 OR 1=1", policy:), [[1], [3]]
	denied("SELECT verdict FROM reviews", policy:)
end

test "the scope as an object with to_sql" do
	relation = Struct.new(:to_sql).new(%(SELECT "notes".* FROM "notes" WHERE "notes"."account_id" = 2))
	policy = Plume::Policy.new(catalog: policy_catalog) { |p| p.table :notes, scope: relation }

	assert_equal scoped("SELECT body FROM notes", policy:), [["n2"]]
	assert_equal scoped("SELECT * FROM notes", policy:), [[2, 2, "n2"]]
end

test "the scope as a WHERE fragment with several conditions" do
	policy = Plume::Policy.new(catalog: policy_catalog) { |p| p.table :posts, scope: "account_id = 1 OR user_id = 3" }

	assert_equal scoped("SELECT id FROM posts ORDER BY id", policy:), [[1], [2], [3]]
end

test "a scope that is not what it says is refused when declared" do
	catalog = policy_catalog
	policy = Plume::Policy.new(catalog:)

	assert_raises(ArgumentError) { policy.table :posts, scope: "1) OR (1" }
	assert_raises(ArgumentError) { policy.table :posts, scope: "account_id = ?" }
	assert_raises(ArgumentError) { policy.table :posts, scope: "SELECT 1; DELETE FROM posts" }
	assert_raises(ArgumentError) { policy.table :nonesuch }
	assert_raises(ArgumentError) { policy.table :users, read: %i[nonesuch] }
end

test "a table with read: :all and no scope is left as it is" do
	sql = build_policy.scope("SELECT p.name FROM projects p JOIN missions m ON m.id = p.id")

	refute_includes sql, "(SELECT"
	assert_equal policy_db.execute(sql), [["p1"]]
end

test "a frozen policy refuses new rules" do
	policy = build_policy.freeze

	assert_raises(FrozenError) { policy.table :secrets }
	assert_raises(FrozenError) { policy.functions :json_tree }
	assert_equal scoped("SELECT id FROM posts ORDER BY id", policy:), [[1], [2]]
end

test "the block gets the policy as its argument" do
	policy = Plume::Policy.new(catalog: policy_catalog) { |p| p.table :projects, read: :all }

	assert_equal scoped("SELECT name FROM projects ORDER BY 1", policy:), [["p1"], ["p2"]]
end

test "a condition that is always true in front of a scoped subquery widens nothing" do
	rows = scoped("SELECT title FROM posts WHERE 1 OR user_id IN (SELECT id FROM users) ORDER BY id")

	assert_equal rows, [["a1"], ["b1"]]
end

test "a hidden column inside an aggregate in a scalar subquery is denied" do
	e = denied("SELECT (SELECT group_concat(email) FROM users) FROM projects")

	assert_includes e.message, "not allowed to read users.email"
end

test "a NATURAL JOIN over a hidden column is denied" do
	e = denied("SELECT u.* FROM users u NATURAL JOIN posts")

	assert_includes e.message, "not allowed to read users.account_id" # the join compares it, even if nobody selects it
end

test "the rowid next to a hidden column is denied with the column" do
	e = denied("SELECT users.rowid, account_id FROM users")

	assert_includes e.message, "not allowed to read users.account_id"
end

test "an INDEXED BY hint is dropped along with the table it was on" do
	sql = build_policy.scope("SELECT name FROM users INDEXED BY some_index ORDER BY id")

	refute_includes sql, "INDEXED"
	assert_equal policy_db.execute(sql), [["ann"], ["bob"]]
end

# Both are rough edges rather than features: the substitute is a subquery, which has
# no rowid and is not in a schema. SQLite refuses the query, so nothing is read
test "the rowid of a substituted table is not there" do
	sql = build_policy.scope("SELECT rowid, * FROM users")

	assert_raises(SQLite3::SQLException) { policy_db.execute(sql) }
end

test "a column qualified with its schema does not resolve once the table is substituted" do
	sql = build_policy.scope("SELECT main.users.id FROM main.users")

	assert_raises(SQLite3::SQLException) { policy_db.execute(sql) }
end

test "no column outside the policy is read by SQLite whatever the query" do
	allowed = { "users" => %w[id name account_id], "posts" => %w[id account_id user_id title body], "projects" => %w[id name], "missions" => %w[id name] }
	seen = []
	policy_db.authorizer = -> (action, a, b, _db, _via) {
		seen << [a, b] if action == 20 && !a.start_with?("sqlite_")
		true
	}

	[
		"SELECT * FROM users",
		"SELECT u.*, p.* FROM users u, posts p",
		"SELECT id FROM users WHERE id = 3 OR 1=1",
		"SELECT name FROM users UNION SELECT name FROM projects",
		"SELECT (SELECT count(*) FROM users) FROM posts",
		"SELECT * FROM users NATURAL JOIN posts",
		"SELECT * FROM users u JOIN posts p USING (id)",
		"WITH x AS (SELECT * FROM users) SELECT * FROM x",
		"SELECT * FROM (SELECT * FROM users)",
		"SELECT count(*), max(name) FROM users GROUP BY account_id HAVING count(*) > 0",
		"SELECT name FROM users ORDER BY id DESC LIMIT 1",
		"SELECT * FROM main.users WHERE name IN (SELECT title FROM posts)",
		"SELECT email FROM users",
		"SELECT * FROM secrets",
		"SELECT rowid, * FROM users",
		"SELECT * FROM sqlite_master",
		"SELECT * FROM pragma_table_info('users')",
		"SELECT users.email FROM users",
		"SELECT * FROM users WHERE email IS NOT NULL",
		"SELECT json_extract(email, '$') FROM users",
		"SELECT 1 FROM users u WHERE EXISTS (SELECT 1 FROM users v WHERE v.email = u.email)",
	].each do |sql|
		policy_db.execute(build_policy.scope(sql))
	rescue Plume::Policy::Denied, Plume::SyntaxError, SQLite3::Exception
		next # refused, which reads nothing, or SQLite itself does not run it
	end

	outside = seen.reject { |table, column| allowed.fetch(table, []).include?(column) }
	assert_equal outside, []
	refute_includes seen, ["users", "email"]
	assert seen.any?
end
