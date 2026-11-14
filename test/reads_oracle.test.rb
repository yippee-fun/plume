# frozen_string_literal: true

require_relative "support/authorizer_oracle"
require_relative "support/query_generator"

oracle = AuthorizerOracle.new(File.read(File.expand_path("../fixtures/schemas/rubyvideo/structure.sql", __dir__)))

# Every read SQLite reports must be one we report. We may report more, but only the join
# columns of USING and NATURAL joins, which the authorizer does not mention. Writes must match
# exactly, down to the updated columns - SQLite does not name the columns of an INSERT
cases = [1, 2, 3, 4].flat_map do |seed|
	generator = QueryGenerator.new(oracle.catalog, seed:)
	Array.new(200) do |i|
		sql = i.even? ? generator.query : generator.statement
		[seed, i, sql, oracle.reads(sql)]
	rescue SQLite3::Exception
		nil # the generator does produce the odd query SQLite rejects
	end.compact
end
# quickdraw forks its workers, which must not inherit an open connection
oracle.close

catalog = oracle.catalog

cases.each do |seed, i, sql, expected|
	test "seed #{seed} query #{i}: #{sql}" do
		access = Plume.access(sql, catalog:)
		reads = access.reads
		writes = access.writes
		ours = reads.columns

		missing = expected.columns.flat_map { |t, cs| (cs - (ours[t] || Set.new)).map { |c| "#{t}.#{c}" } }
		assert(missing.empty?) { "SQLite reads #{missing.join(", ")} but we do not" }
		assert(expected.tables <= reads.tables) { "SQLite reads tables #{(expected.tables - reads.tables).to_a}" }

		extra = reads.references.reject do |ref|
			ref.column.nil? || expected.columns[ref.table_key]&.include?(ref.column) || Plume::Join === ref.node
		end
		assert(extra.empty?) { "we report #{extra.map { |r| "#{r.table_key}.#{r.column}" }.uniq.join(", ")} but SQLite does not" }

		assert_equal writes.tables(:insert), expected.inserted
		assert_equal writes.updated, expected.updated
		assert_equal writes.deleted, expected.deleted
		assert_equal reads.calls, expected.calls
	end
end
