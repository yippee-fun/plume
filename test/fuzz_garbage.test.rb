# frozen_string_literal: true

require "timeout"
require_relative "support/fuzz"
require_relative "support/fixture_corpus"

random = Fuzz.random("garbage")

# Bytes that trip lexers up: NULs, stray UTF-8 continuation and lead bytes, overlong and
# surrogate encodings, a byte order mark, quote and comment openers left unclosed
NASTY_BYTES = [
	"\0", "\x80", "\xC0\x80", "\xC3", "\xE2\x82", "\xED\xA0\x80", "\xF4\x90\x80\x80", "\xFF", "\xFE\xFF",
	"\xEF\xBB\xBF", "'", "\"", "`", "[", "]", "/*", "*/", "--", "\n", "\r", "\\", "x'", "X'0", "0x", "1e", "1_", "_1",
	"?", "?0", "?1000000000000", ":", "@", "$", "$a::(", "#", "(", ")", ";", ",", ".", "-", "->>", "||", "!"
].map(&:b).freeze

# How a statement gets broken: a slice cut out, repeated or moved, a nasty byte or
# a token from elsewhere put in, the end cut off
mutate = lambda do |sql, random, tokens|
	sql = sql.b
	at = random.rand(sql.bytesize + 1)
	len = random.rand(1..12)
	case random.rand(6)
	when 0 then sql.byteslice(0, at) + sql.byteslice((at + len)..).to_s
	when 1 then sql.byteslice(0, at) + (sql.byteslice(at, len).to_s * random.rand(2..4)) + sql.byteslice(at..).to_s
	when 2 then sql.byteslice(0, at) + NASTY_BYTES.sample(random:) + sql.byteslice(at..).to_s
	when 3 then sql.byteslice(0, at) + " #{tokens.sample(random:)} " + sql.byteslice(at..).to_s
	when 4 then sql.byteslice(0, at)
	else
		cut = sql.byteslice(at, len).to_s
		rest = sql.byteslice(0, at) + sql.byteslice((at + len)..).to_s
		to = random.rand(rest.bytesize + 1)
		rest.byteslice(0, to) + cut + rest.byteslice(to..).to_s
	end
end

paths = FixtureCorpus.baseline.sample(300, random:)
statements = paths.map { |path| FixtureCorpus.read(path) }.select { |sql| sql.bytesize < 4_000 }
tokens = statements.flat_map { |sql| sql.split(/\s+/) }.uniq.reject(&:empty?)

inputs = statements.flat_map do |sql|
	Array.new(3) { (1 + random.rand(3)).times.reduce(sql) { |s, _| mutate.(s, random, tokens) } }
end
inputs += Array.new(200) { Array.new(random.rand(1..40)) { NASTY_BYTES.sample(random:) }.join }
inputs += Array.new(100) { random.bytes(random.rand(1..200)) }

# Garbage is lexed and parsed both as the bytes it is and as (most likely broken) UTF-8
inputs = inputs.flat_map { |sql| [sql.b, sql.dup.force_encoding(Encoding::UTF_8)] }

inputs.each do |sql|
	test Fuzz.describe(sql) do
		Timeout.timeout(10) do
			begin
				Plume.tokenize(sql)
			rescue Plume::SyntaxError
				nil
			end

			begin
				parsed = Plume.parse(sql)
			rescue Plume::SyntaxError
				next
			end

			# What parsed prints, and prints as something that parses again into the same tree
			printed = parsed.map(&:to_sql).join(";\n")
			assert_equal AstShape.of(Plume.parse(printed)), AstShape.of(parsed)

			parsed.each do |statement|
				Plume.access(statement, strict: false)
			rescue Plume::Analysis::Error
				nil
			end
		end
	end
end
