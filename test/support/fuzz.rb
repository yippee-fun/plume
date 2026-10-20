# frozen_string_literal: true

require "zlib"

# One seed for all the fuzz tests of a run. quickdraw has no seed a test can read yet,
# so set SEED= to replay a failure, and every fuzz test names the seed it ran with
module Fuzz
	extend self

	SEED = Integer(ENV.fetch("SEED") { Random.new_seed % 1_000_000 })
	puts "Fuzzing with SEED=#{SEED}"

	# Files load in a shuffled order, so each takes its own generator, salted with its name
	def random(salt) = Random.new(SEED + Zlib.crc32(salt))

	# For test descriptions, which is where quickdraw shows what failed
	def describe(sql) = "SEED=#{SEED} #{sql.inspect[0, 300]}"

	# Spellings SQLite has to cope with in a name: quotes of every kind, keywords, things that look
	# like comments, bind parameters or statement ends, and unicode that renders oddly or not at all
	NAME_PARTS = [
		"a", "b", "x1", "_", "1", "0x1", "1e5", "$", "id", "rowid", "oid", "_rowid_", "main", "temp",
		"select", "SELECT", "from", "where", "table", "null", "true", "false", "current_time",
		"\"", "\"\"", "'", "''", "`", "``", "[", "]", ".", ",", ";", "(", ")", "*", "=", "||", "->", "->>",
		" ", "  ", "\t", "\n", "\r\n", "\f", "--", "-- x\n", "/*", "*/", "/* x */",
		"?", "?1", ":a", "@a", "$a", "#a",
		"é", "É", "ß", "ẞ", "ǅ", "Σ", "σ", "ς", "ﬃ", "İ", "ı", "ſ", "\u212a", "日本", "🙂", "👩‍💻", "🏳️‍🌈", "e\u0301",
		"\u200b", "\u200d", "\u200e", "\u202e", "\u2028", "\u00a0", "\u3000", "\ufeff", "\u{e0041}",
		"שלום", "مرحبا", "\u{1F1F3}\u{1F1F1}"
	].freeze

	def name(random)
		Array.new(1 + random.rand(4)) { NAME_PARTS.sample(random:) }.join
	end

	# A name and one way to write it that SQLite reads back as that name,
	# or nil when there is no such way - [] cannot hold a ], for instance
	def quote(name, random)
		styles = [-> { %("#{name.gsub('"', '""')}") }, -> { "`#{name.gsub("`", "``")}`" }]
		styles << -> { "[#{name}]" } unless name.include?("]")
		styles << -> { name } if name.match?(/\A[A-Za-z_\u0080-\u{10FFFF}][A-Za-z0-9_$\u0080-\u{10FFFF}]*\z/) && !Plume::Lexer::KEYWORDS.include?(name.upcase.to_sym)
		styles.sample(random:).call
	end
end
