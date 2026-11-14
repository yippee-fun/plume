# frozen_string_literal: true

require_relative "support/fixture_corpus"

test "split finds statements by their tokens, without semicolons or what lies around them" do
	assert_equal Plume.split("SELECT 1; /* note */ SELECT  2 ;;  "), ["SELECT 1", "SELECT  2"]
	assert_equal Plume.split("SELECT 1; SELEC garbage (; SELECT 3", with_positions: true), [["SELECT 1", 0, 8], ["SELEC garbage (", 10, 25], ["SELECT 3", 27, 35]]
end

test "a trigger's body stays whole, CASE ... END inside it too" do
	sql = "CREATE TEMP TRIGGER tr AFTER INSERT ON t WHEN new.a BEGIN SELECT CASE WHEN 1 THEN 2 END; SELECT 3; END; SELECT 4"

	assert_equal Plume.split(sql), ["CREATE TEMP TRIGGER tr AFTER INSERT ON t WHEN new.a BEGIN SELECT CASE WHEN 1 THEN 2 END; SELECT 3; END", "SELECT 4"]
end

test "a table named trigger is not a trigger, and BEGIN after it is a transaction" do
	assert_equal Plume.split("CREATE TABLE trigger (a); BEGIN; SELECT 1; COMMIT"), ["CREATE TABLE trigger (a)", "BEGIN", "SELECT 1", "COMMIT"]
end

FixtureCorpus.baseline.each_slice(500).with_index do |paths, i|
	test "split agrees with the parser on where statements are, batch #{i}" do
		paths.each do |path|
			sql = FixtureCorpus.read(path)

			parsed = Plume.parse(sql)
			pieces = Plume.split(sql, with_positions: true)

			assert_equal pieces.map { |_, beg, _| beg }, parsed.map { |s| s.location[0] }
			assert_equal AstShape.of(pieces.map { |text, *| Plume.parse(text).first }), AstShape.of(parsed)
		end
	end
end
