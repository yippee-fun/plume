# frozen_string_literal: true

require_relative "ast_shape"

module FixtureCorpus
	extend self

	ROOT = File.expand_path("../..", __dir__)
	BASELINE_PATH = File.join(ROOT, "fixtures/passing.txt")
	REJECTED_PATH = File.join(ROOT, "fixtures/rejected.txt")

	def paths
		Dir.glob("fixtures/**/*.sql", base: ROOT).sort
	end

	def read(path)
		File.read(File.join(ROOT, path))
	end

	def classify(path) = plume_verdict(read(path)).first

	# The check test/fixtures.test.rb makes - parse, print, parse again, same tree - and on a
	# thread like the test, whose smaller stack can overflow where the main thread's does not.
	# Returns the verdict (:pass, :fail or :reject) and the statements, when they parsed
	def plume_verdict(sql)
		Thread.new do
			statements = begin
				Plume::Parser.new(sql).parse
			rescue Plume::SyntaxError
				next [:reject, nil]
			end
			# Printing what parsed into something that does not parse back is a failure, not a rejection
			printed = statements.map(&:to_sql).join(";\n")
			[(AstShape.of(Plume.parse(printed)) == AstShape.of(statements)) ? :pass : :fail, statements]
		rescue StandardError, SystemStackError
			[:fail, nil]
		end.value
	end

	def leading_keyword(path)
		Plume.tokenize(read(path)).first || :EMPTY
	rescue
		:UNLEXABLE
	end

	# What SQLite's parser rejects - most as a syntax error, some in words of their own. Any other
	# error ("no such table", "ambiguous column name"...) comes after the statement parsed
	SQLITE_SYNTAX_ERROR = Regexp.union(
		"syntax error", "unrecognized token", "incomplete input", "clause should come after",
		"is required before", "unknown join type", "unknown table option", "prohibited in PRIMARY KEY",
		"unsupported frame specification", "variable number must be between",
	)

	# Whether SQLite itself rejects the fixture as malformed - the corpus comes from SQLite's
	# test suite, which feeds it plenty of deliberately broken SQL. Statements are prepared one
	# at a time, since a "no such table" in one would otherwise stop us from checking the next
	def sqlite_rejects?(path) = statements(read(path)).any? { |sql| sqlite_rejects_statement?(sql) }

	# SQLite stops at a table or database it cannot find before reaching some errors of its parser -
	# a DISTINCT aggregate's arguments, a syntax error in a trigger's body - so what is missing is
	# made, in a database of its own, and the statement prepared again
	def sqlite_rejects_statement?(sql)
		db = sqlite
		tries = 0
		begin
			db.prepare(sql).close
			false
		rescue SQLite3::Exception => e
			return true if e.message.match?(SQLITE_SYNTAX_ERROR)

			db = SQLite3::Database.new(":memory:") if db.equal?(sqlite)
			retry if (tries += 1) < 8 && make_missing(db, e.message)
			false
		ensure
			db.close unless db.equal?(sqlite)
		end
	end

	# Makes the table or database an error says is missing, and whether it could
	def make_missing(db, message)
		if (name = message[/\Ano such table: (.+?):?$/, 1])
			schema, table = name.include?(".") ? name.split(".", 2) : [nil, name]
			make_missing(db, "unknown database #{schema}") if schema && !%w[main temp].include?(schema)
			db.execute("CREATE TABLE #{[schema, table].compact.map { |part| quote(part) }.join(".")}(a)")
		elsif (schema = message[/\Aunknown database (.+?):?$/, 1])
			db.execute("ATTACH ':memory:' AS #{quote(schema)}")
		else
			return false
		end
		true
	rescue SQLite3::Exception
		false
	end

	def quote(name) = %("#{name.gsub('"', '""')}")

	# sqlite3_complete knows that semicolons inside a trigger body do not end the statement
	def statements(sql)
		chunks = []
		buffer = +""
		sql.split(/(?<=;)/).each do |piece|
			buffer << piece
			next unless sqlite.complete?(buffer)

			chunks << buffer
			buffer = +""
		end
		chunks << buffer unless buffer.strip.empty?
		chunks.reject { |c| c.gsub(/--[^\n]*/, "").strip.delete(";").empty? }
	end

	def sqlite
		require "sqlite3"
		@sqlite ||= SQLite3::Database.new(":memory:")
	end

	def baseline = lines(BASELINE_PATH)

	def rejected = lines(REJECTED_PATH)

	def lines(path) = File.exist?(path) ? File.readlines(path, chomp: true) : []
end
