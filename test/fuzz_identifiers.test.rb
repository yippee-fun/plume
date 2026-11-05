# frozen_string_literal: true

require_relative "support/fuzz"
require_relative "support/authorizer_oracle"

random = Fuzz.random("identifiers")

# Tables and columns with awkward names, and statements over them written with awkward
# quoting. Whatever SQLite accepts must parse, print back, keep every name exactly as
# SQLite has it, and read and write what SQLite's authorizer says it does
cases = Array.new(150) do
	names = Array.new(6) { Fuzz.name(random) }.uniq { |n| n.downcase(:ascii) } # what SQLite takes for the same name
	next if names.size < 6

	table, other, a, b, c, as = names
	q = -> (n) { Fuzz.quote(n, random) }
	schema = "CREATE TABLE #{q.(table)} (#{q.(a)}, #{q.(b)}); CREATE TABLE #{q.(other)} (#{q.(c)})"
	statements = [
		"SELECT #{q.(a)} FROM #{q.(table)} WHERE #{q.(b)} = 1",
		"SELECT #{q.(as)}.#{q.(b)} FROM #{q.(table)} AS #{q.(as)}",
		"SELECT #{q.(a)} AS #{q.(as)} FROM #{q.(table)} ORDER BY #{q.(as)}",
		"SELECT * FROM #{q.(other)} WHERE #{q.(c)} IN (SELECT #{q.(b)} FROM #{q.(table)})",
		"WITH #{q.(as)}(#{q.(c)}) AS (SELECT #{q.(a)} FROM #{q.(table)}) SELECT #{q.(c)} FROM #{q.(as)}",
		"UPDATE #{q.(table)} SET #{q.(a)} = #{q.(b)} WHERE #{q.(b)} > 0",
		"INSERT INTO #{q.(table)} (#{q.(b)}) SELECT #{q.(c)} FROM #{q.(other)}",
		"DELETE FROM #{q.(other)} WHERE #{q.(c)} IS NULL",
	]

	begin
		oracle = AuthorizerOracle.new(schema)
	rescue SQLite3::Exception
		next # names SQLite will not take, like sqlite_ ones
	end
	statements = statements.filter_map do |sql|
		[sql, oracle.reads(sql)]
	rescue SQLite3::Exception
		nil
	end
	catalog = oracle.catalog
	oracle.close
	[schema, catalog, statements]
end.compact

cases.each do |schema, catalog, statements|
	test Fuzz.describe(schema) do
		ours = Plume::Catalog.from_sql(schema)
		assert_equal ours.tables.map { |t| [t.name, t.columns] }, catalog.tables.map { |t| [t.name, t.columns] }
	end

	statements.each do |sql, expected|
		test Fuzz.describe(sql) do
			round_trip(sql)

			access = Plume.access(sql, catalog:)
			assert_equal sorted(access.reads.columns), sorted(expected.columns)
			assert_equal access.writes.tables(:insert), expected.inserted
			assert_equal sorted(access.writes.updated), sorted(expected.updated)
			assert_equal access.writes.deleted, expected.deleted
		end
	end
end
