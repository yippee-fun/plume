# frozen_string_literal: true

CHECKED_SCHEMA = <<~SQL
	CREATE TABLE plans (id INTEGER PRIMARY KEY, name TEXT);
	CREATE TABLE accounts (id INTEGER PRIMARY KEY, name TEXT, plan_id INT);
	CREATE TABLE users (id INTEGER PRIMARY KEY, account_id INT, name TEXT, email TEXT);
	CREATE TABLE invoices (id INTEGER PRIMARY KEY, account_id INT, user_id INT, total_cents INT, paid_at TEXT);
	CREATE TABLE secrets (id INTEGER PRIMARY KEY, token TEXT);
SQL

class Quickdraw::Test
	# Account 1, with every table of its own pinned to it
	def checked_policy
		Plume::Policy.new(catalog: Plume::Catalog.from_sql(CHECKED_SCHEMA)) do |p|
			p.table :plans
			p.table :accounts, scope: { id: 1 }
			p.table :users, :invoices, scope: { account_id: 1 }
		end.freeze
	end

	def passes(sql, binds = []) = assert_equal([sql, checked_policy.check!(sql, binds)], [sql, true])

	def refused(sql, binds = [], with: nil)
		checked_policy.check!(sql, binds)
		failure! { "expected #{sql} to be refused" }
	rescue Plume::Policy::Denied => e
		assert_includes e.message, with if with
		e
	end
end

test "a read held to the account by its WHERE passes, with the value written out or bound" do
	passes %(SELECT * FROM invoices WHERE account_id = 1)
	passes %(SELECT * FROM invoices WHERE 1 = account_id)
	passes %(SELECT "invoices".* FROM "invoices" WHERE "invoices"."account_id" = ? AND "invoices"."id" = ? LIMIT ?), [1, 5, 1]
	passes %(SELECT * FROM invoices i WHERE i.account_id IN (1) AND (paid_at IS NULL OR total_cents > 5))
	passes %(SELECT name FROM accounts WHERE id = ?), [1]
end

test "a read that is not held to the account is refused, and nothing is rewritten for it" do
	e = refused %(SELECT SUM("invoices"."total_cents") FROM "invoices"), with: "invoices is read without account_id = 1"

	assert_includes e.message, "^"
	assert Plume::TableName === e.node
	refused %(SELECT "invoices".* FROM "invoices" WHERE "invoices"."id" = ? LIMIT ?), [5, 1]
end

test "the value has to be this account's" do
	refused %(SELECT * FROM invoices WHERE account_id = 2)
	refused %(SELECT * FROM invoices WHERE account_id = ?), [2]
	refused %(SELECT * FROM invoices WHERE account_id = ?) # nothing bound says nothing
	refused %(SELECT * FROM invoices WHERE account_id IN (1, 2))
	refused %(SELECT * FROM invoices WHERE account_id = '1') # SQLite would compare them as equal, we do not guess
end

test "a condition the rows can get around does not count" do
	refused %(SELECT * FROM invoices WHERE account_id = 1 OR 1=1)
	refused %(SELECT * FROM invoices WHERE NOT (account_id <> 1))
	refused %(SELECT * FROM invoices WHERE account_id = 1 OR account_id = 1)
	refused %(SELECT * FROM invoices WHERE user_id = 1)
	passes %(SELECT * FROM invoices WHERE (account_id = 1 OR 1=1) AND account_id = 1)
end

test "every table in a join has to be held, directly or through one that is" do
	passes %(SELECT "accounts".* FROM "accounts" INNER JOIN "invoices" ON "invoices"."account_id" = "accounts"."id" WHERE "accounts"."id" = ?), [1]
	passes %(SELECT u.name FROM users u LEFT JOIN invoices i ON i.user_id = u.id AND i.account_id = u.account_id WHERE u.account_id = 1)
	passes %(SELECT u.name, p.name FROM users u, accounts a, plans p WHERE u.account_id = 1 AND a.id = u.account_id AND p.id = a.plan_id)
	refused %(SELECT "accounts".* FROM "accounts" INNER JOIN "invoices" ON "invoices"."user_id" = "accounts"."id" WHERE "accounts"."id" = ?), [1], with: "invoices is read"
	refused %(SELECT i.id FROM invoices i JOIN users u ON u.id = i.user_id WHERE i.account_id = 1), with: "users is read"
end

test "the ON of a join only holds the table that join brings in" do
	refused %(SELECT u.name FROM invoices i LEFT JOIN users u ON i.account_id = 1 AND u.account_id = 1), with: "invoices is read"
	refused %(SELECT u.name FROM users u RIGHT JOIN invoices i ON u.account_id = 1 AND i.account_id = 1) # a RIGHT JOIN keeps what its ON did not match
end

test "a bare column name only counts when there is one table to mean" do
	refused %(SELECT 1 FROM users, invoices WHERE account_id = 1)
end

test "subqueries, CTEs and the arms of a UNION are each checked" do
	passes %(SELECT * FROM invoices WHERE account_id = 1 AND user_id IN (SELECT id FROM users WHERE account_id = 1))
	refused %(SELECT * FROM invoices WHERE account_id = 1 AND user_id IN (SELECT id FROM users)), with: "users is read"
	refused %(SELECT * FROM invoices WHERE account_id = 1 UNION ALL SELECT * FROM invoices)
	refused %(WITH x AS (SELECT * FROM invoices) SELECT * FROM x)
	passes %(WITH x AS (SELECT * FROM invoices WHERE account_id = 1) SELECT * FROM x)
end

test "a table without a scope is read freely, and one outside the policy is not there" do
	passes %(SELECT name FROM plans)
	refused %(SELECT * FROM secrets), with: "no such table: secrets"
end

test "an UPDATE or DELETE has to be held to the account too" do
	passes %(UPDATE "invoices" SET "total_cents" = ? WHERE "invoices"."account_id" = ? AND "invoices"."id" = ?), [0, 1, 5]
	passes %(DELETE FROM "users" WHERE "users"."account_id" = ? AND "users"."id" = ?), [1, 3]
	refused %(UPDATE "invoices" SET "total_cents" = ? WHERE "invoices"."id" = ?), [0, 5], with: "invoices is updated without account_id = 1"
	refused %(DELETE FROM "users" WHERE "users"."account_id" = ?), [2], with: "users is deleted from without account_id = 1"
	refused %(DELETE FROM users)
end

test "a row cannot be moved to another account" do
	refused %(UPDATE "invoices" SET "account_id" = ? WHERE "invoices"."account_id" = ?), [2, 1], with: "account_id of invoices cannot be changed"
	refused %(INSERT INTO invoices (account_id, total_cents) VALUES (1, 5) ON CONFLICT (id) DO UPDATE SET account_id = 2)
end

test "an INSERT has to put the account in every row" do
	passes %(INSERT INTO "invoices" ("account_id", "total_cents") VALUES (?, ?) RETURNING "id"), [1, 5]
	passes %(INSERT INTO invoices (total_cents, account_id) VALUES (5, 1), (6, 1))
	passes %(INSERT INTO plans (name) VALUES ('pro'))
	refused %(INSERT INTO "invoices" ("account_id", "total_cents") VALUES (?, ?)), [2, 5], with: "invoices is inserted into without account_id = 1"
	refused %(INSERT INTO invoices (total_cents, account_id) VALUES (5, 1), (6, 2))
	refused %(INSERT INTO "invoices" ("total_cents") VALUES (?)), [5]
	refused %(INSERT INTO invoices SELECT * FROM invoices WHERE account_id = 1)
	refused %(INSERT INTO invoices DEFAULT VALUES)
end

test "transactions pass, everything else that is not rows is refused" do
	["BEGIN immediate TRANSACTION", "COMMIT TRANSACTION", "ROLLBACK", "SAVEPOINT active_record_1", "RELEASE SAVEPOINT active_record_1"].each { |sql| passes sql }
	refused %(PRAGMA table_info(users)), with: "only reading and writing rows"
	refused %(DROP TABLE invoices)
	refused %(SELECT 1; SELECT 2)
end

test "a scope that is not a column and a value can be applied but not checked" do
	policy = Plume::Policy.new(catalog: Plume::Catalog.from_sql(CHECKED_SCHEMA)) { |p| p.table :invoices, scope: "account_id = 1" }

	assert_raises(Plume::Policy::Denied) { policy.check!("SELECT * FROM invoices WHERE account_id = 1") }
	assert_raises(Plume::Policy::Denied) { policy.check!("INSERT INTO invoices (account_id) VALUES (1)") }
	assert_raises(Plume::Policy::Denied) { policy.check!("DELETE FROM invoices WHERE account_id = 1") }
	assert_includes policy.scope("SELECT id FROM invoices"), "account_id = 1"
end

test "a column and value scope is applied by scope as well" do
	assert_equal checked_policy.scope("SELECT id FROM invoices"), %(SELECT id FROM (SELECT id, account_id, user_id, total_cents, paid_at FROM invoices WHERE (account_id = 1)) AS invoices)
	assert_raises(ArgumentError) { Plume::Policy.new(catalog: Plume::Catalog.from_sql(CHECKED_SCHEMA)).table(:invoices, scope: { account_id: 1, id: 2 }) }
end
