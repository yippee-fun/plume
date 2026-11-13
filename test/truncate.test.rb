# frozen_string_literal: true

require_relative "support/fixture_corpus"

SQL_TO_TRUNCATE = "WITH recent AS (SELECT id, title, body FROM posts WHERE created_at > date('now', '-7 days')) " \
	"SELECT r.id, r.title, u.name, u.email FROM recent r JOIN users u ON u.id = r.user_id WHERE u.active = 1 AND r.title LIKE '%x%'"

test "SQL that fits is left alone" do
	assert_equal Plume.truncate("SELECT 1", 8), "SELECT 1"
end

test "the most deeply nested parts go first, then the longest" do
	assert_equal Plume.truncate(SQL_TO_TRUNCATE, 200),
		"WITH recent AS (SELECT id, title, body FROM posts WHERE ...) SELECT r.id, r.title, u.name, u.email FROM recent r JOIN users u ON u.id = r.user_id WHERE u.active = 1 AND r.title LIKE '%x%'"
	assert_equal Plume.truncate(SQL_TO_TRUNCATE, 150),
		"WITH recent AS (...) SELECT r.id, r.title, u.name, u.email FROM recent r JOIN users u ON u.id = r.user_id WHERE u.active = 1 AND r.title LIKE '%x%'"
	assert_equal Plume.truncate(SQL_TO_TRUNCATE, 100), "WITH recent AS (...) SELECT ... FROM recent r JOIN users u ON u.id = r.user_id WHERE ..."
end

test "when leaving parts out is not enough, the end is cut off" do
	assert_equal Plume.truncate(SQL_TO_TRUNCATE, 60), "WITH recent AS (...) SELECT ... FROM recent r JOIN users ..."
	assert_equal Plume.truncate(SQL_TO_TRUNCATE, 2), ".."
end

test "VALUES rows, INSERT columns and UPDATE assignments can go" do
	assert_equal Plume.truncate("INSERT INTO t (a, b, c, d) VALUES (1, 2, 3, 4), (5, 6, 7, 8), (9, 10, 11, 12)", 30), "INSERT INTO t (...) VALUES ..."
	assert_equal Plume.truncate("UPDATE accounts SET balance = balance - 100, updated_at = datetime('now') WHERE id = 42", 60),
		"UPDATE accounts SET ... WHERE id = 42"
end

test "a parsed tree is printed and then truncated" do
	assert_equal Plume.truncate(Plume.parse("select a, b, c from t where x = 1").first, 27), "SELECT ... FROM t WHERE ..."
end

FixtureCorpus.baseline.each_slice(500).with_index do |paths, i|
	test "truncating never goes over the length, and keeps short SQL whole, batch #{i}" do
		paths.each_with_index do |path, j|
			sql = FixtureCorpus.read(path)
			max = [8, 40, 100][j % 3]

			assert(Plume.truncate(sql, max).length <= max)
			assert_equal Plume.truncate(sql, sql.length), sql
		end
	end
end
