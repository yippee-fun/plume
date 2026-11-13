# frozen_string_literal: true

# What Plume.access says a statement does besides reading and writing rows, held to the actions
# SQLite's authorizer is asked about - along with what CREATE TABLE … AS, CREATE INDEX and DROP read and write

require_relative "support/authorizer_oracle"

ACTIONS_SCHEMA = <<~SQL
	CREATE TABLE t (a, b, c);
	CREATE TABLE u (d);
	CREATE TEMP TABLE tt (e);
	CREATE INDEX ti ON t (a);
	CREATE INDEX tti ON tt (e);
	CREATE VIEW v AS SELECT a FROM t;
	CREATE TEMP VIEW tv AS SELECT d FROM u;
	CREATE TRIGGER tr AFTER INSERT ON t BEGIN SELECT 1; END;
	CREATE TEMP TRIGGER ttr AFTER INSERT ON tt BEGIN SELECT 1; END;
	CREATE VIRTUAL TABLE f USING fts5(x);
SQL

[
	"CREATE TABLE x (a)", "CREATE TEMP TABLE x (a)", "CREATE TABLE IF NOT EXISTS x (a PRIMARY KEY) WITHOUT ROWID",
	"CREATE TABLE x (a INTEGER PRIMARY KEY DESC, b UNIQUE, c, UNIQUE (b, c))", "CREATE TABLE x (a, b, PRIMARY KEY (b), UNIQUE (b))",
	"CREATE TABLE x (a INTEGER, b, PRIMARY KEY (a), UNIQUE (b))", "CREATE TEMP TABLE x (a UNIQUE)",
	"CREATE TABLE x AS SELECT a, upper(b) FROM t WHERE c > 1", "CREATE TEMPORARY TABLE x AS SELECT d FROM u",
	"CREATE VIEW w AS SELECT b FROM t WHERE a > 1", "CREATE TEMP VIEW w (z) AS SELECT d FROM u",
	"CREATE INDEX i2 ON t (b, lower(a)) WHERE a > 0", "CREATE UNIQUE INDEX IF NOT EXISTS i3 ON t (c DESC)", "CREATE INDEX i4 ON tt (e)",
	"CREATE TRIGGER tr2 BEFORE DELETE ON t BEGIN SELECT 1; END", "CREATE TEMP TRIGGER tr3 AFTER UPDATE ON u BEGIN SELECT 1; END",
	"CREATE TRIGGER tr4 AFTER INSERT ON tt BEGIN SELECT 1; END",
	"CREATE VIRTUAL TABLE g USING fts5(y)",
	"DROP TABLE u", "DROP TABLE IF EXISTS tt", "DROP TABLE f", "DROP VIEW v", "DROP VIEW tv",
	"DROP INDEX ti", "DROP INDEX tti", "DROP TRIGGER tr", "DROP TRIGGER ttr",
	"ALTER TABLE t RENAME TO t2", "ALTER TABLE t ADD COLUMN z", "ALTER TABLE t RENAME COLUMN a TO z", "ALTER TABLE t DROP COLUMN b",
	"PRAGMA table_info(t)", "PRAGMA cache_size = 10", "PRAGMA cache_size = -10", "PRAGMA main.cache_size", "PRAGMA foreign_keys = ON",
	"PRAGMA journal_mode = 'wal'", "PRAGMA user_version",
	"BEGIN", "BEGIN IMMEDIATE TRANSACTION", "COMMIT", "END", "ROLLBACK", "SAVEPOINT s", "RELEASE s", "RELEASE SAVEPOINT s", "ROLLBACK TO s",
	"ATTACH 'x.db' AS other", "ATTACH DATABASE ':memory:' AS other", "DETACH aux", "DETACH DATABASE aux",
	"REINDEX ti", "REINDEX t", "REINDEX", "REINDEX nocase", "ANALYZE t", "ANALYZE", "ANALYZE main", "ANALYZE ti", "VACUUM",
	"EXPLAIN SELECT a FROM t", "EXPLAIN QUERY PLAN DELETE FROM u"
].each do |sql|
	test "we do what SQLite says: #{sql}" do
		oracle = AuthorizerOracle.new(ACTIONS_SCHEMA)
		oracle.db.execute("ATTACH ':memory:' AS aux")
		expected = oracle.reads(sql)
		access = Plume.access(sql, catalog: oracle.catalog)

		# ANALYZE makes sqlite_stat1 the first time, and SQLite goes through a schema's tables in its own order
		actions = expected.actions.reject { |_, name, *| name.start_with?("sqlite_stat") }
		assert_equal access.actions.map { |a| [a.action, a.name, a.detail, a.schema] }.sort_by(&:inspect), actions.sort_by(&:inspect)
		assert_equal access.reads.references.each_with_object({}) { |r, h| (h[r.table] ||= Set.new) << r.column if r.column }, expected.columns
		# The oracle knows tables by their bare names
		assert_equal access.writes.references.to_set(&:table), expected.deleted
		# ALTER TABLE rewrites the schema with SQL functions of SQLite's own
		assert_equal access.reads.calls, expected.calls unless sql.start_with?("ALTER")
	ensure
		oracle&.close
	end
end
