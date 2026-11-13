# frozen_string_literal: true

# What Plume.access says a trigger reads, writes and calls, held to what SQLite's authorizer
# reports for that trigger when a statement fires it

require_relative "support/authorizer_oracle"

TRIGGERS_SCHEMA = <<~SQL
	CREATE TABLE t (a, b, c);
	CREATE TABLE log (x, y);
	CREATE TABLE u (k PRIMARY KEY, v);
	CREATE VIEW tv AS SELECT a, b FROM t;
SQL

{
	"CREATE TRIGGER tr AFTER INSERT ON t BEGIN INSERT INTO log VALUES (new.a, new.b); END" => "INSERT INTO t DEFAULT VALUES",
	"CREATE TRIGGER tr BEFORE DELETE ON t WHEN old.c IS NOT NULL BEGIN DELETE FROM u WHERE k = old.a; END" => "DELETE FROM t",
	"CREATE TRIGGER tr AFTER UPDATE OF a ON t FOR EACH ROW WHEN new.b > old.b BEGIN " \
		"INSERT INTO log VALUES (new.a, lower(old.c)); UPDATE u SET v = new.c WHERE k = old.a; " \
		"DELETE FROM u WHERE k = (SELECT max(x) FROM log); END" => "UPDATE t SET a = 1",
	"CREATE TRIGGER tr AFTER UPDATE ON t BEGIN SELECT RAISE(ABORT, 'no') WHERE new.a <> old.a; END" => "UPDATE t SET b = 2",
	"CREATE TRIGGER tr AFTER INSERT ON t BEGIN INSERT INTO u (k, v) SELECT x, y FROM log WHERE x = new.a ON CONFLICT (k) DO UPDATE SET v = excluded.v + new.b; END" => "INSERT INTO t DEFAULT VALUES",
	"CREATE TRIGGER tr AFTER INSERT ON t BEGIN UPDATE log SET y = (SELECT count(*) FROM u WHERE u.v = new.c) WHERE x IN (SELECT k FROM u); END" => "INSERT INTO t DEFAULT VALUES",
	"CREATE TRIGGER tr INSTEAD OF INSERT ON tv BEGIN INSERT INTO t (a, b) VALUES (new.a, upper(new.b)); END" => "INSERT INTO tv DEFAULT VALUES",
}.each do |trigger, firing|
	test "a trigger does what SQLite says it does: #{trigger}" do
		oracle = AuthorizerOracle.new("#{TRIGGERS_SCHEMA}#{trigger};")
		access = Plume.access(trigger, catalog: oracle.catalog)
		expected = oracle.reads(firing, trigger: "tr")

		assert_equal access.reads.columns, expected.columns
		assert_equal access.reads.tables, expected.tables
		assert_equal access.writes.tables(:insert), expected.inserted
		assert_equal access.writes.updated, expected.updated
		assert_equal access.writes.deleted, expected.deleted
		assert_equal access.reads.calls, expected.calls
	ensure
		oracle&.close
	end
end
