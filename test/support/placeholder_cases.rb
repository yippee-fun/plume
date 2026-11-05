# frozen_string_literal: true

# Bind parameters in every spelling SQLite's tokenizer takes and in the places its grammar takes
# them, shared by test/placeholders.test.rb and the SQLite-backed test/placeholders_oracle.test.rb
module PlaceholderCases
	SCHEMA = <<~SQL
		CREATE TABLE t (a, b, c, j);
		CREATE TABLE u (a PRIMARY KEY, b);
	SQL

	# Each one a whole parameter. After `$`, `:`, `@` and `#` alike SQLite takes Tcl's spellings:
	# `::` namespaces anywhere in the name, and an array index in parentheses that runs to the
	# first ")" or space - with whatever else it holds, quotes and semicolons included
	SPELLINGS = [
		"?", "?1", "?01", "?999", "?32766",
		":name", ":1", ":_", ":é", ":a$b", ":1_000",
		"@name", "@1",
		"$name", "$1", "$1a", "$a$b", "$é",
		"#a",
		"$a::b", "$a::b::c", "$::a", "$a::", ":a::b", "@a::b",
		"$a(b)", "@a(x)", ":a(x)", "#a(x)", "$a::b(c)", "$a::(x)",
		"$a()", "$a(()", "$a(-)", "$a('x')", "$a([x])", "$a(;)", %{$a(")}
	].freeze

	# Where one parameter ends and the next token begins: SQL, how it prints, its parameters
	BOUNDARIES = [
		["SELECT ?a", "SELECT ? AS a", ["?"]],
		["SELECT ?NNN", "SELECT ? AS NNN", ["?"]],
		["SELECT ?1a", "SELECT ?1 AS a", ["?1"]],
		["SELECT ?1e5", "SELECT ?1 AS e5", ["?1"]],
		["SELECT ?1_000", "SELECT ?1 AS _000", ["?1"]],
		["SELECT $a(b)c", "SELECT $a(b) AS c", ["$a(b)"]],
		["SELECT ? 'x'", "SELECT ? AS x", ["?"]],
		["SELECT ?--?", "SELECT ?", ["?"]],
		["SELECT ?=?", "SELECT ? = ?", ["?", "?"]],
		["SELECT ?<>?", "SELECT ? != ?", ["?", "?"]],
		["SELECT ?-?", "SELECT ? - ?", ["?", "?"]],
		["SELECT a FROM t WHERE a=?AND b=?", "SELECT a FROM t WHERE (a = ?) AND (b = ?)", ["?", "?"]],
		["SELECT a FROM t WHERE a=?1AND b=1", "SELECT a FROM t WHERE (a = ?1) AND (b = 1)", ["?1"]],
		["select\t:x\nfrom t", "SELECT :x FROM t", [":x"]],
	].freeze

	# Statements as `to_sql` prints them, each with its parameters in source order
	STATEMENTS = [
		["SELECT a FROM t WHERE (a = ?) AND (b > :b)", ["?", ":b"]],
		["SELECT a FROM t LIMIT ? OFFSET ?", ["?", "?"]],
		["SELECT a FROM t LIMIT ?, ?", ["?", "?"]],
		["SELECT a FROM t ORDER BY a LIMIT :offset, ?", [":offset", "?"]],
		["SELECT a FROM t LIMIT -?", ["?"]],
		["INSERT INTO t (a, b) VALUES (?, :b), ($c, @d)", ["?", ":b", "$c", "@d"]],
		["REPLACE INTO t (a) VALUES (?)", ["?"]],
		["UPDATE t SET a = ?, b = :b WHERE c = $c", ["?", ":b", "$c"]],
		["UPDATE t SET (a, b) = (?, ?) WHERE c = ?", ["?", "?", "?"]],
		["UPDATE t SET a = x.v FROM (SELECT ? AS v) AS x", ["?"]],
		["DELETE FROM t WHERE a IN (?, ?, ?)", ["?", "?", "?"]],
		["SELECT a FROM t WHERE a IN (?)", ["?"]],
		["SELECT a FROM t WHERE a IN (SELECT b FROM u WHERE a = ?)", ["?"]],
		["SELECT ? IN (SELECT a FROM t)", ["?"]],
		["SELECT a FROM t WHERE EXISTS (SELECT 1 FROM u WHERE u.a = ?)", ["?"]],
		["SELECT (SELECT ?) + (SELECT :a)", ["?", ":a"]],
		["SELECT * FROM (SELECT a FROM t WHERE b = ?) WHERE a = ?", ["?", "?"]],
		["WITH c(x) AS (SELECT ?) SELECT x FROM c WHERE x = :y", ["?", ":y"]],
		["SELECT coalesce(?, a), max(?, ?) FROM t", ["?", "?", "?"]],
		["SELECT printf(?, ?), iif(?, 1, 2)", ["?", "?", "?"]],
		["SELECT strftime(?, ?, ?), date(:d, '+1 day')", ["?", "?", "?", ":d"]],
		["SELECT CASE ? WHEN :x THEN ? ELSE @y END", ["?", ":x", "?", "@y"]],
		["SELECT CASE WHEN a = ? THEN ? END FROM t", ["?", "?"]],
		["SELECT a FROM t ORDER BY ?", ["?"]],
		["SELECT a FROM t ORDER BY a COLLATE NOCASE, ? DESC", ["?"]],
		["SELECT a FROM t GROUP BY a HAVING count(*) > ?", ["?"]],
		["SELECT row_number() OVER (ORDER BY ?) FROM t", ["?"]],
		["SELECT sum(a) OVER (ORDER BY a ROWS BETWEEN ? PRECEDING AND ? FOLLOWING) FROM t", ["?", "?"]],
		["SELECT sum(a) FILTER (WHERE b = ?) FROM t", ["?"]],
		["SELECT group_concat(a, ? ORDER BY ?) FROM t", ["?", "?"]],
		["SELECT count(DISTINCT ?) FROM t", ["?"]],
		["INSERT INTO u (a, b) VALUES (?, ?) ON CONFLICT (a) DO UPDATE SET b = :b WHERE excluded.b != ?", ["?", "?", ":b", "?"]],
		["INSERT INTO u (a, b) VALUES (?, ?) ON CONFLICT (a) DO UPDATE SET (a, b) = (:x, :y)", ["?", "?", ":x", ":y"]],
		["INSERT INTO u (a, b) SELECT ?, ? WHERE TRUE ON CONFLICT DO NOTHING", ["?", "?"]],
		["INSERT INTO t (a) VALUES (?) RETURNING a, ?", ["?", "?"]],
		["UPDATE t SET a = ? RETURNING ?", ["?", "?"]],
		["DELETE FROM t WHERE a = ? RETURNING *, :x", ["?", ":x"]],
		["SELECT CAST(? AS INTEGER), CAST(:x AS TEXT)", ["?", ":x"]],
		["SELECT a FROM t WHERE a LIKE ? ESCAPE ?", ["?", "?"]],
		["SELECT a FROM t WHERE a NOT LIKE :p ESCAPE '\\'", [":p"]],
		["SELECT a FROM t WHERE (a GLOB ?) OR (b GLOB ?)", ["?", "?"]],
		["SELECT a FROM t WHERE a BETWEEN ? AND ?", ["?", "?"]],
		["SELECT ? NOT BETWEEN ? AND ?", ["?", "?", "?"]],
		["SELECT ? IS NULL, ? ISNULL, ? NOTNULL, ? IS NOT ?", ["?", "?", "?", "?", "?"]],
		["SELECT a FROM t WHERE (a IS ?) AND (b IS NOT ?)", ["?", "?"]],
		["SELECT -?, +?, ~?, NOT ?", ["?", "?", "?", "?"]],
		["SELECT ? || ?, ? COLLATE NOCASE", ["?", "?", "?"]],
		["SELECT json_extract(j, ?), j -> ?, j ->> :path FROM t", ["?", "?", ":path"]],
		["SELECT json_extract(j, '$.' || ?) FROM t", ["?"]],
		["SELECT a FROM t, json_each(?) WHERE a = json_each.value", ["?"]],
		["SELECT * FROM json_each(:doc, '$.x')", [":doc"]],
		["VALUES (?, ?), (:a, :b)", ["?", "?", ":a", ":b"]],
		["SELECT a FROM t UNION SELECT ? ORDER BY 1 LIMIT ?", ["?", "?"]],
		["SELECT a FROM t WHERE (a, b) = (?, ?)", ["?", "?"]],
		["SELECT a FROM t WHERE (a, b) IN (VALUES (?, ?))", ["?", "?"]],
		["SELECT a FROM t JOIN u USING (a) WHERE (t.b = ?) AND (u.b = :b)", ["?", ":b"]],
		# Numbered and named ones share numbers: SQLite numbers these 1, 1, 2, 3, 4, 2
		["SELECT ?1, ?1, :a, @a, $a, :a", ["?1", "?1", ":a", "@a", "$a", ":a"]],
		["SELECT ?2, :a", ["?2", ":a"]],
		["SELECT :a, ?1", [":a", "?1"]],
		["SELECT ?, ?2, ?", ["?", "?2", "?"]],
		# Parameters spelled like the columns around them are still parameters
		["SELECT a FROM t WHERE a = @a", ["@a"]],
		["SELECT a FROM t WHERE c = $x(b)", ["$x(b)"]],
		["SELECT a FROM t WHERE c = :t::b", [":t::b"]],
		["ATTACH DATABASE ? AS x", ["?"]],
		["ATTACH DATABASE :file AS :name", [":file", ":name"]],
		["DETACH DATABASE ?", ["?"]],
		["VACUUM INTO ?", ["?"]],
		["EXPLAIN SELECT ?", ["?"]],
		["EXPLAIN QUERY PLAN SELECT a FROM t WHERE a = ?", ["?"]],
	].freeze

	# SQLite refuses all of these as malformed
	REJECTED = [
		"SELECT :", "SELECT @", "SELECT $", "SELECT #", "SELECT #1", "SELECT @::", "SELECT :::", "SELECT ::a",
		"SELECT @@a", %(SELECT $"a"), "SELECT :[a]", "SELECT $a(", "SELECT $a(b", "SELECT $a(b c)",
		"SELECT $a::b(c d)", "SELECT $a(b\n); SELECT 1",
		"SELECT ?0", "SELECT ?00", "SELECT ?0x1", "SELECT ?32767", "SELECT ?1000000", "SELECT ?99999999999999999999",
		"SELECT ? ?", "SELECT ?:a", "SELECT ?$a", "SELECT ?/*x*/?", "SELECT ?1.5", "SELECT ?(1)",
		"SELECT ?.a", "SELECT :a.b", "SELECT $a.b", "SELECT @a.b", "SELECT $a:b", "SELECT $a:::b", "SELECT $a::b:c",
		"SELECT $x(y)(z)", "SELECT a FROM t WHERE a = $x(y)z", "SELECT a FROM t WHERE a=:aAND b=1",
		"PRAGMA cache_size = ?", "CREATE TABLE z (a DEFAULT ?)", "CREATE TABLE ? (a)",
		"SELECT a FROM t WHERE a IN ?", "SELECT a COLLATE ? FROM t", "SELECT CAST(? AS ?)", "SELECT ? AS ?",
		"SELECT * FROM t AS ?", "SELECT * FROM ?", "SELECT a FROM t INDEXED BY ?", "SELECT count(?) OVER ?",
		"DELETE FROM ?", "UPDATE t SET ? = 1", "INSERT INTO t (?) VALUES (1)", "INSERT INTO t ?"
	].freeze

	ANALYZABLE = [Plume::SelectStatement, Plume::InsertStatement, Plume::UpdateStatement, Plume::DeleteStatement].freeze

	extend self

	# The parameters of a parse, in the order they appear in the source
	def variables(statements)
		Array(statements).flat_map { |s| s.each_node.grep(Plume::Variable) }.sort_by { |v| v.location[0] }
	end

	# Whether Plume.access takes it
	def analyzable?(statement) = ANALYZABLE.any? { |klass| klass === statement }
end
