# frozen_string_literal: true

# Reads#calls held to the functions SQLite's authorizer says a statement calls

require_relative "support/authorizer_oracle"

CALLS_SCHEMA = <<~SQL
	CREATE TABLE t (a PRIMARY KEY, b, c);
	CREATE TABLE u (a, d);
	CREATE VIEW v AS SELECT upper(a) AS up, b FROM t;
SQL

[
	"SELECT lower(a), LOWER(b), count(*), sum(b) OVER (), total(c) FILTER (WHERE a) FROM t",
	"SELECT a FROM t WHERE a LIKE 'x' OR b NOT LIKE 'y' ESCAPE '!' OR c GLOB 'z' OR a NOT GLOB 'w'",
	"SELECT a -> '$.x', a ->> '$.y', current_date, CURRENT_TIME, current_timestamp FROM t",
	"SELECT coalesce(a, b), ifnull(a, 1), iif(a, 1, 2), nullif(a, b), likelihood(a, 0.5), unlikely(b), likely(c) FROM t",
	"SELECT CAST(a AS INT), a COLLATE nocase, a IS DISTINCT FROM b, a BETWEEN 1 AND 2, CASE a WHEN 1 THEN 2 END FROM t",
	"SELECT up FROM v",
	"SELECT * FROM t WHERE a IN (SELECT max(d) FROM u) AND EXISTS (SELECT min(a) FROM u WHERE u.a = abs(t.a))",
	"SELECT group_concat(a, ',') AS g FROM t GROUP BY lower(b) HAVING count(*) > 1 ORDER BY length(g)",
	"WITH w AS (SELECT hex(a) AS h FROM t) SELECT upper(h) FROM w",
	"SELECT a FROM t LIMIT abs(-1) OFFSET round(1.5)",
	"SELECT row_number() OVER w, rank() OVER (PARTITION BY lower(a) ORDER BY b) FROM t WINDOW w AS (ORDER BY c)",
	"SELECT * FROM json_each('[1]') AS j, t WHERE j.value = t.a",
	"SELECT date('now'), strftime('%s', a), printf('%d', b), format('%s', c) FROM t",
	"INSERT INTO t VALUES (abs(1), random(), upper('x'))",
	"INSERT INTO t SELECT lower(a), d, 1 FROM u",
	"INSERT INTO t (a) VALUES (1) ON CONFLICT DO UPDATE SET b = coalesce(excluded.b, 0) WHERE c IS NOT NULL",
	"UPDATE t SET a = round(b) WHERE b LIKE 'x' RETURNING hex(a), lower(b)",
	"UPDATE t SET a = u.d FROM u WHERE u.a = trim(t.b)",
	"DELETE FROM t WHERE a = (SELECT max(a) FROM u) RETURNING typeof(b)",
	"SELECT a FROM t ORDER BY a COLLATE nocase, upper(b) DESC",
].each do |sql|
	test "we call the functions SQLite does: #{sql}" do
		oracle = AuthorizerOracle.new(CALLS_SCHEMA)

		assert_equal Plume.reads(sql, catalog: oracle.catalog).calls, oracle.reads(sql).calls
	ensure
		oracle&.close
	end
end
