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
