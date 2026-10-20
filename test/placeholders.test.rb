# frozen_string_literal: true

# Numbered parameters run from ?1 to SQLite's default SQLITE_MAX_VARIABLE_NUMBER, 32766.
# SQLite refuses the rest while parsing, with "variable number must be between ?1 and ?32766"
["?0", "?00", "?32767", "?1000000", "?99999999999999999999"].each do |param|
	test "#{param} is out of range" do
		assert_raises(Plume::SyntaxError) { Plume.parse("SELECT #{param}") }
	end
end

test "numbered parameters at either end of the range parse" do
	assert_equal parse_stmt("SELECT ?1, ?01, ?32766").to_sql, "SELECT ?1, ?01, ?32766"
end

# `LIMIT ?, ?` binds the offset first. Printed as `LIMIT ? OFFSET ?` it would bind the limit first
test "LIMIT with a comma keeps its parameters in order" do
	[
		"SELECT a FROM t LIMIT ?, ?",
		"SELECT a FROM t ORDER BY a LIMIT :offset, ?",
		"UPDATE t SET a = 1 LIMIT ?, ?",
		"DELETE FROM t LIMIT ?, ?",
	].each { |sql| assert_equal parse_stmt(sql).to_sql, sql }
	assert_equal parse_stmt("SELECT a FROM t LIMIT ? OFFSET ?").to_sql, "SELECT a FROM t LIMIT ? OFFSET ?"
end
