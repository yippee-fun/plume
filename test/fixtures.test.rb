# frozen_string_literal: true

require_relative "support/fixture_corpus"

# Only fixtures recorded in fixtures/passing.txt are held to parsing - run
# `bin/fixture-report --write` to move the ratchet once more of them parse.
# Each must also survive the trip back to SQL: printing and parsing again gives the same tree.
# And the trip through Node#dump and Plume.load, which must give it back down to every position
FixtureCorpus.baseline.each do |path|
	test path do
		sql = FixtureCorpus.read(path)
		round_trip(sql)

		original = Plume.parse(sql)
		loaded = Plume.load(original.map(&:dump))
		assert_equal AstShape.of(loaded), AstShape.of(original)
		assert_equal loaded.flat_map { |s| s.each_node.map(&:location) }, original.flat_map { |s| s.each_node.map(&:location) }
	end
end

# And the ones SQLite rejects as malformed, recorded in fixtures/rejected.txt, are held to a SyntaxError
FixtureCorpus.rejected.each do |path|
	test path do
		assert_raises(Plume::SyntaxError) { Plume.parse(FixtureCorpus.read(path)) }
	end
end
