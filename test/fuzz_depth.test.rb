# frozen_string_literal: true

require_relative "support/fuzz"

random = Fuzz.random("depth")

# JRuby and TruffleRuby run out of stack far sooner, partly inside their own Java code where it
# does not even come out as a SystemStackError, and their JITs warm up while the timings run.
# They get shallow nesting and no timings
FULL_DEPTH = RUBY_ENGINE == "ruby"
catalog = Plume::Catalog.from_sql("CREATE TABLE t (a, b)")

# Ways to wrap an expression in another one, nested in random order to random depths, past
# SQLite's limit of 1000 and past where the parser runs out of stack. Whatever happens has to
# be a parse or a SyntaxError, and whatever parses has to print, walk and be analyzed
WRAPPERS = [
	"(%s)", "NOT %s", "- %s", "~%s", "abs(%s)", "CAST(%s AS INT)", "%s + 1", "1 * %s", "a = %s",
	"CASE WHEN %s THEN 1 END", "CASE a WHEN 1 THEN %s ELSE 2 END", "%s COLLATE nocase", "%s -> 'x'",
	"%s BETWEEN 1 AND 2", "%s IS NULL", "%s LIKE 'x'", "%s IN (1, 2)", "a IN (%s)", "(SELECT %s)",
	"EXISTS (SELECT %s FROM t)", "(SELECT a FROM t WHERE a = %s)", "coalesce(1, %s) OVER ()"
].freeze

cases = Array.new(60) do
	depth = FULL_DEPTH ? [random.rand(1..50), random.rand(900..1100), random.rand(1..4000)].sample(random:) : random.rand(1..200)
	wrappers = WRAPPERS.sample(1 + random.rand(4), random:)
	expression = Array.new(depth) { wrappers.sample(random:) }.reduce("a") { |inner, wrapper| format(wrapper, inner) }
	["SELECT #{expression} FROM t", depth, wrappers]
end

cases.each do |sql, depth, wrappers|
	test Fuzz.describe("#{depth} deep in #{wrappers.join(", ")}") do
		begin
			statements = Plume.parse(sql)
		rescue Plume::SyntaxError
			next success!
		end

		# Comparing trees this deep would run out of stack itself, so what is compared is
		# that the printed SQL parses into something that prints the same
		begin
			printed = statements.map(&:to_sql).join(";\n")
		rescue Plume::Printer::Error
			next success!
		end
		begin
			assert_equal Plume.parse(printed).map(&:to_sql).join(";\n"), printed
		rescue Plume::SyntaxError => e
			# The printer puts parentheses around every operand it nests, and parsing those
			# takes more stack than the original did. Running out of it is all that may happen
			assert_equal e.message, "statement nested too deeply"
		end
		assert statements.first.each_node.count > depth

		begin
			Plume.access(statements.first, catalog:)
		rescue Plume::Analysis::Error
			nil
		end
	end
end

# Performance cliffs: each statement grows eight times over, and so may the time it takes to
# parse, print and analyze it - but not much more, or something went quadratic, as building
# trees once did when a type check hashed every node it checked
GROWING = {
	"operator chain" => [100, -> (n) { "SELECT #{(["a"] * n).join(" + ")} FROM t" }],
	"parentheses" => [100, -> (n) { "SELECT #{"(" * n}a#{")" * n} FROM t" }],
	"NOT" => [100, -> (n) { "SELECT #{"NOT " * n}a FROM t" }],
	"function calls" => [25, -> (n) { "SELECT #{"abs(" * n}a#{")" * n} FROM t" }],
	"CASE" => [25, -> (n) { "SELECT #{"CASE WHEN a THEN " * n}1#{" END" * n} FROM t" }],
	"IN subqueries" => [25, -> (n) { "SELECT a FROM t WHERE a IN #{"(SELECT a FROM t WHERE a IN " * n}(1)#{")" * n}" }],
	"FROM subqueries" => [25, -> (n) { "SELECT * FROM #{"(SELECT * FROM " * n}t#{")" * n}" }],
	"UNION" => [50, -> (n) { (["SELECT a FROM t"] * n).join(" UNION ") }],
	"joins" => [8, -> (n) { "SELECT 1 FROM t#{(2..n).map { |i| " JOIN t AS t#{i} ON t#{i}.a = t.a" }.join}" }],
	"CTEs" => [100, -> (n) { "WITH c0 AS (SELECT a FROM t)#{(1...n).map { |i| ", c#{i} AS (SELECT a FROM c#{i - 1})" }.join} SELECT a FROM c#{n - 1}" }],
	"IN list" => [400, -> (n) { "SELECT a FROM t WHERE a IN (#{(1..n).to_a.join(", ")})" }],
	"result columns" => [200, -> (n) { "SELECT #{(1..n).map { |i| "a AS c#{i}" }.join(", ")} FROM t" }],
	"VALUES rows" => [400, -> (n) { "INSERT INTO t (a) VALUES #{(["(1)"] * n).join(", ")}" }],
	"statements" => [200, -> (n) { "SELECT a FROM t;" * n }],
	"string" => [5000, -> (n) { "SELECT '#{"x''" * n}'" }],
	"quoted name" => [5000, -> (n) { "SELECT \"#{"a\"\"" * n}\" FROM t" }],
	"comment" => [5000, -> (n) { "SELECT 1 /* #{"* / " * n} */" }],
}.freeze

GROWING.each do |name, (n, statement)|
	next unless FULL_DEPTH

	test "#{name} take time in proportion to their size" do
		small, large = [n, n * 8].map do |size|
			sql = statement.(size)
			# The fastest of a few runs, for the least noise
			Array.new(3) do
				started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
				Plume.parse(sql).each do |parsed|
					parsed.to_sql
					Plume.access(parsed, catalog:) if Plume::Analysis::Resolver::STATEMENTS.any? { |klass| klass === parsed }
				end
				Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
			end.min
		end

		# Linear would be 8, quadratic 64
		assert(large / small < 24) { "#{n} took #{(small * 1000).round(1)}ms, #{n * 8} took #{(large * 1000).round(1)}ms" }
	end
end
