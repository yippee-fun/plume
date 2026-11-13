# frozen_string_literal: true

require_relative "support/fixture_corpus"

test "constants become parameters in place, and the rest is kept as written" do
	sql = "SELECT a, -1, +2.5, x'ab', 'it''s' FROM t /* note */ WHERE b IN (1, 2) LIMIT 10"

	assert_equal Plume.normalize(sql), "SELECT a, ?, ?, ?, ? FROM t /* note */ WHERE b IN (?, ?) LIMIT ?"
end

test "NULL, TRUE, FALSE and CURRENT_* stay, and so do column positions in ORDER BY and GROUP BY" do
	sql = "SELECT a IS NULL, b = TRUE, current_date FROM t GROUP BY 1 ORDER BY 2, count(*) OVER (ORDER BY 1)"

	assert_equal Plume.normalize(sql), "SELECT a IS NULL, b = TRUE, current_date FROM t GROUP BY 1 ORDER BY 2, count(*) OVER (ORDER BY ?)"
	assert_equal Plume.normalize("SELECT a FROM (SELECT a FROM t ORDER BY 1) ORDER BY 1.5"), "SELECT a FROM (SELECT a FROM t ORDER BY 1) ORDER BY ?"
end

test "only DML is normalized, statement by statement" do
	sql = "UPDATE t SET a = 1; CREATE TABLE x (a DEFAULT 1); PRAGMA cache_size = 10; EXPLAIN SELECT 2"

	assert_equal Plume.normalize(sql), "UPDATE t SET a = ?; CREATE TABLE x (a DEFAULT 1); PRAGMA cache_size = 10; EXPLAIN SELECT ?"
end

test "a parsed tree normalizes into a tree" do
	tree = Plume.normalize(Plume.parse("select * from t where name = 'é' and id = ?3").first)

	assert_equal tree.to_sql, "SELECT * FROM t WHERE (name = ?) AND (id = ?3)"
end

test "SQL that is not valid UTF-8 normalizes byte for byte" do
	sql = (+"SELECT \"\xFF\", 1").force_encoding(Encoding::UTF_8)

	assert_equal Plume.normalize(sql).b, (+"SELECT \"\xFF\", ?").b
end

# The normalized text must parse into what normalizing the tree gives
FixtureCorpus.baseline.each_slice(200).with_index do |paths, i|
	test "normalizing text and trees agrees across fixtures, batch #{i}" do
		paths.each do |path|
			sql = FixtureCorpus.read(path)
			statements = Plume.parse(sql)
			next unless statements.any? { |s| Plume::Normalize.constants(s).any? }

			assert_equal AstShape.of(Plume.parse(Plume.normalize(sql))), AstShape.of(statements.map { |s| Plume.normalize(s) })
		end
	end
end
