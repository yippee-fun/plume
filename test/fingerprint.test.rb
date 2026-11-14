# frozen_string_literal: true

require_relative "support/fixture_corpus"

{
	"values, parameters, case, spacing and parentheses" => [
		"SELECT a FROM t WHERE b = 1", "select A from T where (b) = 'x'", "SELECT a FROM t WHERE b = ?",
		"SELECT a FROM t WHERE b = :name", "SELECT  a\nFROM t WHERE b = -5"
	],
	"IN lists of any length" => ["SELECT a FROM t WHERE b IN (1, 2, 3)", "SELECT a FROM t WHERE b IN (?)", "SELECT a FROM t WHERE b IN (4,5)"],
	"VALUES with any number of rows" => ["INSERT INTO t VALUES (1, 2), (3, 4)", "INSERT INTO t VALUES (?, ?)"],
}.each do |what, queries|
	test "one fingerprint whatever the #{what}" do
		assert_equal queries.map { |q| Plume.fingerprint(q) }.uniq.size, 1
	end
end

test "different queries have different fingerprints" do
	queries = [
		"SELECT a FROM t ORDER BY 1", "SELECT a FROM t ORDER BY 2", "SELECT b FROM t WHERE b = 1", "SELECT a FROM t WHERE b = 1",
		"SELECT a FROM t WHERE b IN (1, c)", "SELECT 'x' AS y", "SELECT 'x' AS z", "SELECT a FROM t WHERE b = 1 AND c = 2",
		"SELECT a FROM t WHERE (b = 1 AND c) = 2", "INSERT INTO t VALUES (1, 2), (3)", "CREATE TABLE t (a DEFAULT 'X')", "CREATE TABLE t (a DEFAULT 'x')"
	]

	assert_equal queries.map { |q| Plume.fingerprint(q) }.uniq.size, queries.size
end

# Changing this is a breaking change: fingerprints get stored
test "a fingerprint stays the same from one release to the next" do
	assert_equal Plume.fingerprint("SELECT a FROM t WHERE b = 1"), "860427e5c317a9d6"
end

test "a fingerprint takes SQL, a statement or a list of them" do
	sql = "SELECT 1; SELECT 2"

	assert_equal Plume.fingerprint(Plume.parse(sql)), Plume.fingerprint(sql)
	assert_equal Plume.fingerprint(Plume.parse("SELECT 1").first), Plume.fingerprint("SELECT 1")
end

# What is printed, or normalized, is still the same query
FixtureCorpus.baseline.each_slice(200).with_index do |paths, i|
	test "printing and normalizing keep the fingerprint across fixtures, batch #{i}" do
		paths.each do |path|
			sql = FixtureCorpus.read(path)
			fingerprint = Plume.fingerprint(sql)

			assert_equal Plume.fingerprint(Plume.parse(sql).map(&:to_sql).join(";\n")), fingerprint
			assert_equal Plume.fingerprint(Plume.normalize(sql)), fingerprint
		end
	end
end
