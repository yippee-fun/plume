# frozen_string_literal: true

# Bind parameters: every spelling SQLite takes, in every place it takes them. Each must lex as
# one VARIABLE, parse as a Plume::Variable named exactly as written, print back unchanged and in
# the same order (SQLite numbers `?` by position), and never count as a read.
# test/placeholders_oracle.test.rb holds the same cases against SQLite itself

require_relative "support/placeholder_cases"

PLACEHOLDER_CATALOG = Plume::Catalog.from_sql(PlaceholderCases::SCHEMA)

class Quickdraw::Test
	def variables(sql) = PlaceholderCases.variables(Plume.parse(sql))

	# The statement with each parameter replaced by NULL, which reads nothing either
	def without_parameters(sql)
		out = sql.b
		variables(sql).reverse_each do |v|
			beg, fin = v.location
			out[beg...fin] = "NULL"
		end
		out.force_encoding(sql.encoding)
	end

	def access_facts(sql)
		access = Plume.access(sql, catalog: PLACEHOLDER_CATALOG)
		[sorted(access.reads.columns), access.reads.tables, access.writes.tables(:insert), access.writes.updated, access.writes.deleted]
	end
end

PlaceholderCases::SPELLINGS.each do |param|
	test "#{param} is one parameter" do
		assert_equal lex(param, with_values: true), [[:VARIABLE, param]]

		sql = "SELECT #{param}"
		vars = variables(sql)
		assert_equal vars.map(&:name), [param]
		assert_equal vars[0].source_text, param
		assert_equal parse_stmt(sql).to_sql, sql
	end
end

PlaceholderCases::BOUNDARIES.each do |sql, printed, names|
	test "parameters end where SQLite ends them: #{sql.inspect}" do
		assert_equal variables(sql).map(&:name), names
		assert_equal parse_stmt(sql).to_sql, printed
	end
end

PlaceholderCases::STATEMENTS.each do |sql, names|
	test "parameters in #{sql}" do
		statement = parse_stmt(sql)
		vars = PlaceholderCases.variables(statement)

		assert_equal vars.map(&:name), names
		assert vars.all? { |v| v.source_text == v.name }
		assert_equal statement.to_sql, sql

		# Renamed by position, they must print in that same order
		vars.each_with_index { |v, i| v.name = ":p#{i}" }
		assert_equal variables(statement.to_sql).map(&:name), Array.new(vars.size) { |i| ":p#{i}" }

		if PlaceholderCases.analyzable?(statement)
			assert_equal access_facts(sql), access_facts(without_parameters(sql))
		end
	end
end

test "a parameter spelled like a column reads no column" do
	{
		"SELECT a FROM t WHERE a = @a" => { "t" => ["a"] },
		"SELECT a FROM t WHERE c = $x(b)" => { "t" => ["a", "c"] },
		"SELECT a FROM t WHERE c = :t::b" => { "t" => ["a", "c"] },
		"UPDATE t SET a = :b WHERE c = $j" => { "t" => ["c"] },
	}.each do |sql, columns|
		assert_equal sorted(Plume.access(sql, catalog: PLACEHOLDER_CATALOG).reads.columns), columns
	end
end

PlaceholderCases::REJECTED.each do |sql|
	test "rejects #{sql.inspect}" do
		assert_raises(Plume::SyntaxError) { Plume.parse(sql) }
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
