# frozen_string_literal: true

require_relative "support/fixture_corpus"

test "each clause starts a line, and a clause too long for the line puts an item per line" do
	sql = "select a, b from t join u on u.id = t.u_id where a = 1 order by b limit 5"

	assert_equal Plume.parse(sql).first.to_sql(pretty: true), <<~SQL.chomp
		SELECT a, b
		FROM t
		JOIN u ON u.id = t.u_id
		WHERE a = 1
		ORDER BY b
		LIMIT 5
	SQL
	assert_equal Plume.parse("select aaaa, bbbb, cccc from t").first.to_sql(pretty: true, max_line_length: 12, indent_size: 2), <<~SQL.chomp
		SELECT
		  aaaa,
		  bbbb,
		  cccc
		FROM t
	SQL
end

test "a long AND chain puts an operand per line, and subqueries are indented in their parentheses" do
	sql = "select a from t where a in (select b from u where c = 1) and d = 2 and e = 3"

	assert_equal Plume.parse(sql).first.to_sql(pretty: true, max_line_length: 40), <<~SQL.chomp
		SELECT a
		FROM t
		WHERE (a IN (
		        SELECT b
		        FROM u
		        WHERE c = 1
		    ))
		    AND (d = 2)
		    AND (e = 3)
	SQL
end

test "commas can lead the lines" do
	assert_equal Plume.parse("select aaaa, bbbb from t").first.to_sql(pretty: true, max_line_length: 10, commas_start_of_line: true, indent_size: 2), <<~SQL.chomp
		SELECT
		    aaaa
		  , bbbb
		FROM t
	SQL
end

test "table definitions put a column per line, and trigger bodies are indented" do
	assert_equal Plume.parse("create table t (id integer primary key, name text) strict").first.to_sql(pretty: true), <<~SQL.chomp
		CREATE TABLE t (
		    id integer PRIMARY KEY,
		    name text
		) STRICT
	SQL
	assert_equal Plume.parse("create trigger tr after insert on t begin delete from u; end").first.to_sql(pretty: true), <<~SQL.chomp
		CREATE TRIGGER tr AFTER INSERT ON t
		BEGIN
		    DELETE FROM u;
		END
	SQL
end

# Laid out narrow, so most clauses break, the SQL must still parse into the same tree
FixtureCorpus.baseline.each_slice(500).with_index do |paths, i|
	test "pretty SQL parses into the same tree across fixtures, batch #{i}" do
		paths.each_with_index do |path, j|
			statements = Plume.parse(FixtureCorpus.read(path))
			pretty = statements.map { |s| s.to_sql(pretty: true, max_line_length: 20, commas_start_of_line: j.odd?) }.join(";\n")

			assert_equal AstShape.of(Plume.parse(pretty)), AstShape.of(statements)
		end
	end
end
