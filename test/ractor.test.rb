# frozen_string_literal: true

Plume.eager_load!

RACTOR_SCHEMA = <<~SQL
	CREATE TABLE users (id INTEGER PRIMARY KEY, email TEXT, secret TEXT, team_id INT);
	CREATE TABLE teams (id INTEGER PRIMARY KEY, name TEXT);
	CREATE VIEW team_emails AS SELECT t.name, u.email FROM users u JOIN teams t ON t.id = u.team_id;
SQL

RACTOR_SQL = [
	"SELECT u.email, count(*) FROM users u JOIN teams t ON t.id = u.team_id WHERE t.name LIKE ? GROUP BY 1",
	"WITH recent AS (SELECT id FROM users ORDER BY id DESC LIMIT 10) SELECT email FROM users WHERE id IN recent",
	"SELECT name, email FROM team_emails WHERE (email IS NOT NULL) UNION ALL SELECT name, NULL FROM teams",
	"UPDATE users SET secret = (SELECT name FROM teams WHERE teams.id = users.team_id) WHERE id = ?",
	"INSERT INTO teams (name) SELECT email FROM users WHERE id = 1 RETURNING id",
	"DELETE FROM users WHERE team_id NOT IN (SELECT id FROM teams)",
	"SELECT CASE WHEN a THEN 1 ELSE -2 END, CAST(x AS TEXT) COLLATE nocase FROM json_each(?)",
].freeze

class Quickdraw::Test
	# Ractors warn that they are experimental the first time one is started
	def in_ractors(count, *args, &block)
		experimental, Warning[:experimental] = Warning[:experimental], false
		ractors = Array.new(count) { Ractor.new(*args, &block) }
		ractors.map { |r| r.respond_to?(:value) ? r.value : r.take }
	ensure
		Warning[:experimental] = experimental
	end

	def ractor_catalog = Ractor.make_shareable(Plume::Catalog.from_sql(RACTOR_SCHEMA))
end

# On a module, so the main Ractor and the Ractors under test compute the same summaries
module RactorSummary
	def self.syntax(sql)
		tree = Plume.parse(sql)
		[Plume.tokenize(sql), tree.map(&:to_sql), tree.flat_map { |s| s.each_node.map { |n| n.class.name } }]
	end

	def self.access(sql, catalog)
		access = Plume.access(sql, catalog:)
		[access.reads.projected, access.reads.referenced, access.writes.columns, access.writes.tables]
	end
end

test "tokenize, parse, to_sql and walk in several Ractors at once give the same results as in the main Ractor" do
	results = in_ractors(4, RACTOR_SQL) { |sqls| sqls.map { |sql| RactorSummary.syntax(sql) } }

	expected = RACTOR_SQL.map { |sql| RactorSummary.syntax(sql) }
	results.each { |result| assert_equal result, expected }
end

test "trees parsed in a Ractor come back equal to the ones parsed in the main Ractor" do
	copied, shared = in_ractors(1, RACTOR_SQL) do |sqls|
		[sqls.map { |sql| Plume.parse(sql) }, Ractor.make_shareable(sqls.map { |sql| Plume.parse(sql) })]
	end.first

	expected = RACTOR_SQL.map { |sql| Plume.parse(sql) }
	assert_equal copied, expected
	assert_equal shared, expected
	assert Ractor.shareable?(shared)
end

test "syntax errors raise inside a Ractor with the same message as in the main Ractor" do
	message = in_ractors(1) do
		Plume.parse("SELECT FROM WHERE")
	rescue Plume::SyntaxError => e
		e.message
	end.first

	assert_equal message, assert_raises(Plume::SyntaxError) { Plume.parse("SELECT FROM WHERE") }.message
end

test "a catalog made shareable in the main Ractor serves reads and access in several Ractors" do
	catalog = ractor_catalog
	assert Ractor.shareable?(catalog)

	results = in_ractors(4, RACTOR_SQL.first(6), catalog) { |sqls, cat| sqls.map { |sql| RactorSummary.access(sql, cat) } }

	expected = RACTOR_SQL.first(6).map { |sql| RactorSummary.access(sql, catalog) }
	results.each { |result| assert_equal result, expected }
	# The view is read through to the tables under it
	assert_equal sorted(expected[2][0]), { "teams" => ["name"], "users" => ["email"] }
end

test "Plume.reads in a Ractor returns references to the nodes they were found at" do
	catalog = ractor_catalog
	reads = in_ractors(1, catalog) do |cat|
		Plume.reads("SELECT email FROM users WHERE id = 1", catalog: cat)
	end.first

	expected = Plume.reads("SELECT email FROM users WHERE id = 1", catalog:)
	assert_equal reads.references.map { |r| [r.table, r.column, r.usage, r.node.to_sql] },
		expected.references.map { |r| [r.table, r.column, r.usage, r.node.to_sql] }
	assert_equal reads.references.map(&:node), expected.references.map(&:node)
end

test "a tree made shareable can still be read, printed, walked and analyzed" do
	sql = RACTOR_SQL.first
	tree = Ractor.make_shareable(Plume.parse(sql))
	statement = tree.first

	assert statement.frozen?
	assert statement.body.condition.frozen?
	assert_equal statement.to_sql, Plume.parse(sql).first.to_sql
	assert_equal statement.each_node.count, Plume.parse(sql).first.each_node.count
	assert_equal statement.body.columns.first.result.column, "email"
	refute_equal statement.location, nil

	reads = Plume::Analysis::Resolver.new(catalog: ractor_catalog).analyze(statement).reads
	assert_equal sorted(reads.columns), { "teams" => ["id", "name"], "users" => ["email", "team_id"] }

	printed = in_ractors(2, statement) { |s| [s.to_sql, s.each_node.count] }
	printed.each { |result| assert_equal result, [statement.to_sql, statement.each_node.count] }
end

test "trees that are not frozen can still be edited after eager_load!" do
	statement = Plume.parse("SELECT a FROM t WHERE b = 1").first
	statement.body.condition = Plume.parse("SELECT c > 2").first.body.columns.first.result

	assert_equal statement.to_sql, "SELECT a FROM t WHERE c > 2"
	assert_raises(Literal::TypeError) { statement.body.condition = Object.new }
end

test "every Plume constant and node class can be read from a Ractor after eager_load!" do
	constants = (Plume.constants - [:SQLiteGrammar]).map { |name| Plume.const_get(name) }
	nodes = constants.select { |c| Class === c && c <= Plume::Node }

	constants.each { |c| assert Ractor.shareable?(c) }
	nodes.each { |klass| assert Ractor.shareable?(klass.literal_properties) }

	counts = in_ractors(1, nodes) { |classes| classes.map { |klass| klass.literal_properties.size } }.first
	assert_equal counts, nodes.map { |klass| klass.literal_properties.size }
end
