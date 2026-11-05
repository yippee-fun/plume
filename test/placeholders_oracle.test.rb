# frozen_string_literal: true

# The cases of test/placeholders.test.rb held against SQLite: it must take what we take, refuse
# what we refuse, count and name the same parameters, read the same columns, and give the same
# answers for the printed statement as for the original with the same values bound by position

require "sqlite3"
require_relative "support/authorizer_oracle"
require_relative "support/placeholder_cases"

class Quickdraw::Test
	# How SQLite numbers parameters: `?` takes the next number, `?N` takes N, and a name keeps
	# the number it first got. The count and the names, in the shape of `Statement#named_params`
	def sqlite_numbering(names)
		slots = {}
		count = 0
		names.each do |name|
			if name == "?"
				count += 1
			elsif (n = name[/\A\?(\d+)\z/, 1]&.to_i)
				slots[n] ||= name
				count = n if n > count
			elsif !slots.value?(name)
				slots[count += 1] = name
			end
		end
		[count, slots.sort.map(&:last).reject { |name| name.start_with?("?") }.map { |name| name[1..] }]
	end

	def sqlite_parameters(db, sql)
		statement = db.prepare(sql)
		[statement.bind_parameter_count, statement.named_params]
	ensure
		statement&.close
	end

	def placeholder_db
		db = SQLite3::Database.new(":memory:")
		db.execute_batch(PlaceholderCases::SCHEMA)
		db.execute_batch(<<~SQL)
			INSERT INTO t VALUES (1, 2, 3, '{"x": 1, "y": [1, 2]}'), (2, 3, 4, '[1, 2, 3]'), (3, 1, 2, '{}'), (4, 4, 4, NULL), (5, 'x', 'y', '2');
			INSERT INTO u VALUES (1, 1), (2, 2), (3, 'z');
		SQL
		db
	end

	# What running it with 1, 2, 3... bound by position does, undone afterwards
	def outcome(db, sql)
		db.transaction
		statement = db.prepare(sql)
		statement.bind_parameter_count.times { |i| statement.bind_param(i + 1, i + 1) }
		rows = statement.to_a
		[rows, db.execute("SELECT * FROM t ORDER BY rowid"), db.execute("SELECT * FROM u ORDER BY rowid")]
	rescue SQLite3::Exception => e
		e.message
	ensure
		statement&.close
		db.rollback if db.transaction_active?
	end
end

SQLITE_MALFORMED = Regexp.union("syntax error", "unrecognized token", "incomplete input", "variable number must be between")

PlaceholderCases::SPELLINGS.each do |param|
	test "SQLite takes #{param} as one parameter" do
		db = SQLite3::Database.new(":memory:")
		sql = "SELECT #{param}"
		names = PlaceholderCases.variables(Plume.parse(sql)).map(&:name)

		assert_equal sqlite_parameters(db, sql), sqlite_numbering(names)
	ensure
		db&.close
	end
end

PlaceholderCases::BOUNDARIES.each do |sql, printed, names|
	test "SQLite ends parameters where we do: #{sql.inspect}" do
		db = placeholder_db

		assert_equal sqlite_parameters(db, sql), sqlite_numbering(names)
		assert_equal sqlite_parameters(db, printed), sqlite_numbering(names)
		assert_equal outcome(db, printed), outcome(db, sql)
	ensure
		db&.close
	end
end

PlaceholderCases::STATEMENTS.each do |sql, _|
	test "SQLite agrees on the parameters in #{sql}" do
		db = placeholder_db
		statement = Plume.parse(sql).first
		printed = statement.to_sql
		expected = sqlite_numbering(PlaceholderCases.variables(statement).map(&:name))

		assert_equal sqlite_parameters(db, sql), expected
		assert_equal sqlite_parameters(db, printed), expected
		next unless PlaceholderCases.analyzable?(statement)

		assert_equal outcome(db, printed), outcome(db, sql)

		oracle = AuthorizerOracle.new(PlaceholderCases::SCHEMA)
		reads = Plume.access(sql, catalog: oracle.catalog).reads
		sqlite = oracle.reads(sql)
		sqlite.columns.each { |table, columns| assert_equal reads.columns[table] & columns, columns }
		assert sqlite.tables <= reads.tables
		extra = reads.references.reject do |ref|
			ref.column.nil? || sqlite.columns[ref.table_key]&.include?(ref.column) || Plume::Join === ref.node
		end
		assert(extra.empty?) { "we report #{extra.map { |r| "#{r.table_key}.#{r.column}" }.uniq.join(", ")} but SQLite does not" }
	ensure
		oracle&.close
		db&.close
	end
end

PlaceholderCases::REJECTED.each do |sql|
	test "SQLite rejects #{sql.inspect} too" do
		db = placeholder_db
		error = assert_raises(SQLite3::Exception) { db.prepare(sql).close }

		assert(error.message.match?(SQLITE_MALFORMED)) { error.message }
	ensure
		db&.close
	end
end

# Random runs of the characters parameters are made of, and of those around them. Plume must
# refuse exactly what SQLite refuses as malformed, with a SyntaxError and nothing else, and
# where both take it, count the parameters as SQLite does
FUZZ_ALPHABET = ["?", ":", "@", "$", "#", "::", "a", "e", "x", "_", "é", "0", "1", "9", "(", ")", "[", "]", " ", "'", %("), ".", ",", "-", "+", "*", "="].freeze

fuzz_db = SQLite3::Database.new(":memory:")
random = Random.new(20261020)
fuzz_cases = Array.new(3000) do
	sql = "SELECT #{Array.new(random.rand(1..7)) { FUZZ_ALPHABET.sample(random:) }.join}"
	statement = fuzz_db.prepare(sql)
	[sql, statement.bind_parameter_count]
rescue SQLite3::Exception => e
	[sql, e.message.match?(SQLITE_MALFORMED) ? :malformed : :refused_later]
ensure
	statement&.close
end
# quickdraw forks its workers, which must not inherit an open connection
fuzz_db.close

fuzz_cases.uniq.each do |sql, sqlite|
	test "fuzz: #{sql.inspect}" do
		if sqlite == :malformed
			assert_raises(Plume::SyntaxError) { Plume.parse(sql) }
		else
			names = PlaceholderCases.variables(Plume.parse(sql)).map(&:name)
			assert_equal sqlite_numbering(names)[0], sqlite if Integer === sqlite
		end
	end
end
