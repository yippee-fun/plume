# frozen_string_literal: true

module Plume
	#	Map ASCII strings to an enumerator of token symbols.
	#		adapted from: https://github.com/sqlite/sqlite/blob/master/src/tokenize.c
	class Lexer
		#	Character classes for tokenizing
		#		adapted from: https://github.com/sqlite/sqlite/blob/master/src/tokenize.c
		TYPES = [
			:X,					# The letter 'x', or start of BLOB literal
			:KYWD0,			# First letter of a keyword
			:KYWD,			# Alphabetics or '_'.  Usable in a keyword
			:DIGIT,			# Digits
			:DOLLAR,		# '$'
			:VARALPHA,	# '@', '#', ':'.  Alphabetic SQL variables
			:VARNUM,		# '?'.  Numeric SQL variables
			:SPACE,			# Space characters
			:QUOTE,			# '"', '\'', or '`'.  String literals, quoted ids
			:QUOTE2,		# '['.   [...] style quoted ids
			:PIPE,			# '|'.   Bitwise OR or concatenate
			:MINUS,			# '-'.  Minus or SQL-style comment
			:LT,				# '<'.  Part of < or <= or <>
			:GT,				# '>'.  Part of > or >=
			:EQ,				# '='.  Part of = or ==
			:BANG,			# '!'.  Part of !=
			:SLASH,			# '/'.  / or c-style comment
			:LP,				# '('
			:RP,				# ')'
			:SEMI,			# ';'
			:PLUS,			# '+'
			:STAR,			# '*'
			:PERCENT,		# '%'
			:COMMA,			# ','
			:AND,				# '&'
			:TILDA,			# '~'
			:DOT,				# '.'
			:ID,				# unicode characters usable in IDs
			:ILLEGAL,		# Illegal character
			:NUL,				# 0x00
			:BOM,				# First byte of UTF8 BOM:  0xEF 0xBB 0xBF
		].freeze

		#	All the keywords of the SQL language in SQLite's dialect
		#		adapted from: https://github.com/sqlite/sqlite/blob/master/tool/mkkeywordhash.c
		KEYWORDS = Set[
			:ABORT,
			:ACTION,
			:ADD,
			:AFTER,
			:ALL,
			:ALTER,
			:ALWAYS,
			:ANALYZE,
			:AND,
			:AS,
			:ASC,
			:ATTACH,
			:AUTOINCREMENT,
			:BEFORE,
			:BEGIN,
			:BETWEEN,
			:BY,
			:CASCADE,
			:CASE,
			:CAST,
			:CHECK,
			:COLLATE,
			:COLUMN,
			:COMMIT,
			:CONFLICT,
			:CONSTRAINT,
			:CREATE,
			:CROSS,
			:CURRENT,
			:CURRENT_DATE,
			:CURRENT_TIME,
			:CURRENT_TIMESTAMP,
			:DATABASE,
			:DEFAULT,
			:DEFERRED,
			:DEFERRABLE,
			:DELETE,
			:DESC,
			:DETACH,
			:DISTINCT,
			:DO,
			:DROP,
			:END,
			:EACH,
			:ELSE,
			:ESCAPE,
			:EXCEPT,
			:EXCLUSIVE,
			:EXCLUDE,
			:EXISTS,
			:EXPLAIN,
			:FAIL,
			:FILTER,
			:FIRST,
			:FOLLOWING,
			:FOR,
			:FOREIGN,
			:FROM,
			:FULL,
			:GENERATED,
			:GLOB,
			:GROUP,
			:GROUPS,
			:HAVING,
			:IF,
			:IGNORE,
			:IMMEDIATE,
			:IN,
			:INDEX,
			:INDEXED,
			:INITIALLY,
			:INNER,
			:INSERT,
			:INSTEAD,
			:INTERSECT,
			:INTO,
			:IS,
			:ISNULL,
			:JOIN,
			:KEY,
			:LAST,
			:LEFT,
			:LIKE,
			:LIMIT,
			:MATCH,
			:MATERIALIZED,
			:NATURAL,
			:NO,
			:NOT,
			:NOTHING,
			:NOTNULL,
			:NULL,
			:NULLS,
			:OF,
			:OFFSET,
			:ON,
			:OR,
			:ORDER,
			:OTHERS,
			:OUTER,
			:OVER,
			:PARTITION,
			:PLAN,
			:PRAGMA,
			:PRECEDING,
			:PRIMARY,
			:QUERY,
			:RAISE,
			:RANGE,
			:RECURSIVE,
			:REFERENCES,
			:REGEXP,
			:REINDEX,
			:RELEASE,
			:RENAME,
			:REPLACE,
			:RESTRICT,
			:RETURNING,
			:RIGHT,
			:ROLLBACK,
			:ROW,
			:ROWID,
			:ROWS,
			:SAVEPOINT,
			:SELECT,
			:SET,
			:STORED,
			:STRICT,
			:TABLE,
			:TEMP,
			:TEMPORARY,
			:THEN,
			:TIES,
			:TO,
			:TRANSACTION,
			:TRIGGER,
			:UNBOUNDED,
			:UNION,
			:UNIQUE,
			:UPDATE,
			:USING,
			:VACUUM,
			:VALUES,
			:VIEW,
			:VIRTUAL,
			:WHEN,
			:WHERE,
			:WINDOW,
			:WITH,
			:WITHIN,
			:WITHOUT,
			:TRUE,
			:FALSE,
		].freeze

		# Maps ASCII characters to their respective character types
		# Each element's index maps to the byte value of that character
		CHARACTER_TYPES = %i[
			NULL			ILLEGAL		ILLEGAL		ILLEGAL		ILLEGAL		ILLEGAL		ILLEGAL		ILLEGAL
			ILLEGAL		SPACE			SPACE			ILLEGAL		SPACE			SPACE			ILLEGAL		ILLEGAL
			ILLEGAL		ILLEGAL		ILLEGAL		ILLEGAL		ILLEGAL		ILLEGAL		ILLEGAL		ILLEGAL
			ILLEGAL		ILLEGAL		ILLEGAL		ILLEGAL		ILLEGAL		ILLEGAL		ILLEGAL		ILLEGAL
			SPACE			BANG			QUOTE			VARALPHA	DOLLAR		PERCENT		AND				QUOTE
			LP				RP				STAR			PLUS			COMMA			MINUS			DOT				SLASH
			DIGIT			DIGIT			DIGIT			DIGIT			DIGIT			DIGIT			DIGIT			DIGIT
			DIGIT			DIGIT			VARALPHA	SEMI			LT				EQ				GT				VARNUM
			VARALPHA	KYWD0			KYWD0			KYWD0			KYWD0			KYWD0			KYWD0			KYWD0
			KYWD0			KYWD0			KYWD0			KYWD0			KYWD0			KYWD0			KYWD0			KYWD0
			KYWD0			KYWD0			KYWD0			KYWD0			KYWD0			KYWD0			KYWD0			KYWD0
			X					KYWD			KYWD			QUOTE2		ILLEGAL		ILLEGAL		ILLEGAL		KYWD
			QUOTE			KYWD0			KYWD0			KYWD0			KYWD0			KYWD0			KYWD0			KYWD0
			KYWD0			KYWD0			KYWD0			KYWD0			KYWD0			KYWD0			KYWD0			KYWD0
			KYWD0			KYWD0			KYWD0			KYWD0			KYWD0			KYWD0			KYWD0			KYWD0
			X					KYWD			KYWD			ILLEGAL		PIPE			ILLEGAL		TILDA			ILLEGAL
			ID				ID				ID				ID				ID				ID				ID				ID
			ID				ID				ID				ID				ID				ID				ID				ID
			ID				ID				ID				ID				ID				ID				ID				ID
			ID				ID				ID				ID				ID				ID				ID				ID
			ID				ID				ID				ID				ID				ID				ID				ID
			ID				ID				ID				ID				ID				ID				ID				ID
			ID				ID				ID				ID				ID				ID				ID				ID
			ID				ID				ID				ID				ID				ID				ID				ID
			ID				ID				ID				ID				ID				ID				ID				ID
			ID				ID				ID				ID				ID				ID				ID				ID
			ID				ID				ID				ID				ID				ID				ID				ID
			ID				ID				ID				ID				ID				ID				ID				ID
			ID				ID				ID				ID				ID				ID				ID				ID
			ID				ID				ID				ID				ID				ID				ID				BOM
			ID				ID				ID				ID				ID				ID				ID				ID
			ID				ID				ID				ID				ID				ID				ID				ID
		].freeze

		# The following 256 element lookup table encodes the characteristics
		# of each ASCII character in a bitmask:
		#
		#		space?		0x01
		#		alpha?		0x02
		#		digit?		0x04
		#		alnum?		0x06
		#		xdigit?		0x08
		#		to_upper	0x20
		#		id?				0x40
		#		quote?		0x80
		#
		# Bit 0x40 is set if the character is non-alphanumeric and can be used in an
		# SQLite identifier. Identifiers are alphanumerics, "_", "$", and any
		# non-ASCII UTF character. Hence the test for whether or not a character is
		# part of an identifier is 0x46.
		CHARACTER_FLAGS = [
			0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,  # 00..07    ........
			0x00, 0x01, 0x01, 0x01, 0x01, 0x01, 0x00, 0x00,  # 08..0f    ........
			0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,  # 10..17    ........
			0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,  # 18..1f    ........
			0x01, 0x00, 0x80, 0x00, 0x40, 0x00, 0x00, 0x80,  # 20..27     !"#$%&'
			0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,  # 28..2f    ()*+,-./
			0x0c, 0x0c, 0x0c, 0x0c, 0x0c, 0x0c, 0x0c, 0x0c,  # 30..37    01234567
			0x0c, 0x0c, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,  # 38..3f    89:;<=>?
			0x00, 0x0a, 0x0a, 0x0a, 0x0a, 0x0a, 0x0a, 0x02,  # 40..47    @ABCDEFG
			0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02,  # 48..4f    HIJKLMNO
			0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02, 0x02,  # 50..57    PQRSTUVW
			0x02, 0x02, 0x02, 0x80, 0x00, 0x00, 0x00, 0x40,  # 58..5f    XYZ[\]^_
			0x80, 0x2a, 0x2a, 0x2a, 0x2a, 0x2a, 0x2a, 0x22,  # 60..67    `abcdefg
			0x22, 0x22, 0x22, 0x22, 0x22, 0x22, 0x22, 0x22,  # 68..6f    hijklmno
			0x22, 0x22, 0x22, 0x22, 0x22, 0x22, 0x22, 0x22,  # 70..77    pqrstuvw
			0x22, 0x22, 0x22, 0x00, 0x00, 0x00, 0x00, 0x00,  # 78..7f    xyz{|}~.
			0x40, 0x40, 0x40, 0x40, 0x40, 0x40, 0x40, 0x40,  # 80..87    ........
			0x40, 0x40, 0x40, 0x40, 0x40, 0x40, 0x40, 0x40,  # 88..8f    ........
			0x40, 0x40, 0x40, 0x40, 0x40, 0x40, 0x40, 0x40,  # 90..97    ........
			0x40, 0x40, 0x40, 0x40, 0x40, 0x40, 0x40, 0x40,  # 98..9f    ........
			0x40, 0x40, 0x40, 0x40, 0x40, 0x40, 0x40, 0x40,  # a0..a7    ........
			0x40, 0x40, 0x40, 0x40, 0x40, 0x40, 0x40, 0x40,  # a8..af    ........
			0x40, 0x40, 0x40, 0x40, 0x40, 0x40, 0x40, 0x40,  # b0..b7    ........
			0x40, 0x40, 0x40, 0x40, 0x40, 0x40, 0x40, 0x40,  # b8..bf    ........
			0x40, 0x40, 0x40, 0x40, 0x40, 0x40, 0x40, 0x40,  # c0..c7    ........
			0x40, 0x40, 0x40, 0x40, 0x40, 0x40, 0x40, 0x40,  # c8..cf    ........
			0x40, 0x40, 0x40, 0x40, 0x40, 0x40, 0x40, 0x40,  # d0..d7    ........
			0x40, 0x40, 0x40, 0x40, 0x40, 0x40, 0x40, 0x40,  # d8..df    ........
			0x40, 0x40, 0x40, 0x40, 0x40, 0x40, 0x40, 0x40,  # e0..e7    ........
			0x40, 0x40, 0x40, 0x40, 0x40, 0x40, 0x40, 0x40,  # e8..ef    ........
			0x40, 0x40, 0x40, 0x40, 0x40, 0x40, 0x40, 0x40,  # f0..f7    ........
			0x40, 0x40, 0x40, 0x40, 0x40, 0x40, 0x40, 0x40   # f8..ff    ........
		].freeze

		SINGLE_CHAR_TOKENS = [].tap do |it|
			it[0]		=	:ILLEGAL	# \0
			it[37]	=	:REM			# %
			it[38]	=	:BITAND		# &
			it[40]	=	:LP				# (
			it[41]	=	:RP				# )
			it[42]	=	:STAR			# *
			it[43]	=	:PLUS			# +
			it[44]	=	:COMMA		# ,
			it[59]	=	:SEMI			# ;
			it[126]	=	:BITNOT		# ~
		end.freeze

		attr_reader :sql
		attr_accessor :cursor, :anchor

		def initialize(sql, skip_spaces: false)
			# Freezing the caller's string would leave them with a frozen string they did not ask for
			@sql =
				case sql.encoding
				when Encoding::UTF_8, Encoding::ASCII_8BIT then sql.frozen? ? sql : sql.dup.freeze
				else sql.encode(Encoding::UTF_8).freeze
				end
			@skip_spaces = skip_spaces
			@cursor, @anchor = 0
		end

		def next_token
			@anchor = @cursor
			token = lex_next_token
			return next_token if token == :SPACE && @skip_spaces
			token
		end

		def value
			@sql.byteslice(@anchor, (@cursor - @anchor))
		end

		private

		def lex_next_token
			current_byte = scan

			return nil if current_byte.nil?
			if (token = SINGLE_CHAR_TOKENS[current_byte])
				return token
			end

			character_type = CHARACTER_TYPES[current_byte]
			case character_type
			when :SPACE
				# useless branch conditions to drive branch test coverage results
				nil if current_byte == 32 # " "
				nil if current_byte == 9  # "\t"
				nil if current_byte == 10 # "\n"
				nil if current_byte == 12 # "\f"
				nil if current_byte == 13 # "\r"

				step until (b = peek).nil? || !space?(b)

				:SPACE
			when :MINUS
				if peek == 45 # "-"
					step
					step until (b = peek).nil? || b == 10 # "\n"

					:SPACE # IMP: R-22934-2513
				elsif peek == 62 # ">"
					# differentiate between different pointers
					if peek(1) == 62 # ">"
						step(2)
						:PTR2
					else
						step
						:PTR1
					end
				else
					:MINUS
				end
			when :SLASH
				return :SLASH if peek.nil? # EOF
				return :SLASH if peek != 42 # "*"

				step # we know it's a `/*` comment so consume the "*"
				step until (b = peek).nil? || (b == 42 && peek(1) == 47) # consume until EOF or "*/"
				step(2) if peek == 42 && peek(1) == 47 # consume the "*/"

				:SPACE # comments are encoded as SPACE tokens [IMP: R-22934-2513]
			when :EQ
				step if peek == 61 # "="
				:EQ
			when :LT
				return step && :LE if peek == 61 # "="
				return step && :NE if peek == 62 # ">"
				return step && :LSHIFT if peek == 60 # "<"

				:LT
			when :GT
				return step && :GE if peek == 61 # "="
				return step && :RSHIFT if peek == 62 # ">"

				:GT
			when :BANG
				return step && :NE if peek == 61 # "="

				:ILLEGAL
			when :PIPE
				return step && :CONCAT if peek == 124 # "|"

				:BITOR
			when :QUOTE
				# useless branch conditions to drive brach test coverage results
				nil if current_byte == 96 # "`"
				nil if current_byte == 39 # "'"
				nil if current_byte == 34 # '"'

				while (b = scan)
					next unless b == current_byte
					# you can use the same quote to escape itself
					(peek == current_byte) ? step : break
				end

				return :STRING if b == 39 # "'"
				return :ILLEGAL if b.nil?

				:ID
			when :DOT, :DIGIT
				# If the current character is a "." and the next character is either EOF or not a digit,
				# then this token is simply the "." character.
				if character_type == :DOT && ((b = peek).nil? || !digit?(b))
					return :DOT
				end

				# useless branch conditions to drive brach test coverage results
				nil if current_byte == 46 # "."
				nil if current_byte == 48 # "0"
				nil if current_byte == 49 # "1"
				nil if current_byte == 50 # "2"
				nil if current_byte == 51 # "3"
				nil if current_byte == 52 # "4"
				nil if current_byte == 53 # "5"
				nil if current_byte == 54 # "6"
				nil if current_byte == 55 # "7"
				nil if current_byte == 56 # "8"
				nil if current_byte == 57 # "9"

				token_type = (character_type == :DOT) ? :FLOAT : :INTEGER
				if current_byte == 48 && ((b = peek) == 120 || b == 88) && xdigit?(peek(1)) # "0" and "x" or "X"
					step(2) # consume the "x" or "X" and the first hex digit
					while (b = peek)
						if xdigit?(b)
							step && next
						elsif b == 95 # "_"
							token_type = :QNUMBER
							step && next
						else
							break
						end
					end

					return token_type
				end

				while (b = peek)
					if digit?(b)
						step && next
					elsif b == 95 # "_"
						token_type = :QNUMBER
						step && next
					else
						break
					end
				end

				if peek == 46 # "."
					step
					token_type = :FLOAT if token_type == :INTEGER

					while (b = peek)
						if digit?(b)
							step && next
						elsif b == 95 # "_"
							token_type = :QNUMBER
							step && next
						else
							break
						end
					end
				end

				if (peek == 101 || peek == 69) && ( # "e" or "E"
					digit?(peek(1)) || (
						(peek(1) == 43 || peek(1) == 45) && digit?(peek(2)) # "+" or "-"
					)
				)
					step(2)
					token_type = :FLOAT if token_type == :INTEGER

					while (b = peek)
						if digit?(b)
							step && next
						elsif b == 95 # "_"
							token_type = :QNUMBER
							step && next
						else
							break
						end
					end
				end

				while id?(peek)
					token_type = :ILLEGAL
					step
				end

				token_type
			when :QUOTE2
				step until (b = peek).nil? || b == 93 # "]"

				final = scan
				return :ILLEGAL if final.nil?

				:ID
			when :VARNUM
				step while digit?(peek)

				:VARIABLE
			when :DOLLAR, :VARALPHA
				# useless branch conditions to drive brach test coverage results
				nil if current_byte == 35 # "#"
				nil if current_byte == 36 # "$"
				nil if current_byte == 58 # ":"
				nil if current_byte == 64 # "@"

				n = 0
				token_type = :VARIABLE
				until (b = peek).nil?
					if id?(b)
						n += 1
					elsif n > 0 && b == 40 # "("
						step
						step until (b = peek).nil? || space?(b) || b == 41 # ")"

						if peek == 41 # ")"
							step
						else
							token_type = :ILLEGAL
						end

						break
					elsif b == 58 && peek(1) == 58 # ":"
						step
					else
						break
					end
					step
				end

				if n == 0
					token_type = :ILLEGAL
				end

				token_type
			when :KYWD0
				# If the next character is not a keyword character, consume all the id characters and return it as an id
				kywd = TYPES.index(:KYWD)
				if (b = peek) && (type = CHARACTER_TYPES[b]) && TYPES.index(type) > kywd
					step while id?(peek)

					return :ID
				end

				# Consume all the keyword characters
				step while (b = peek) && (type = CHARACTER_TYPES[b]) && TYPES.index(type) <= kywd

				# This token started out using characters that can appear in keywords,
				# but now there is a character not allowed within keywords,
				# so this must be an identifier instead
				if (b = peek) && id?(b)
					step while id?(peek)

					return :ID
				end

				# Check if the token is a keyword
				token = value.to_sym.upcase
				KEYWORDS.include?(token) ? token : :ID
			when :X
				# useless branch conditions to drive brach test coverage results
				nil if current_byte == 120 # "x"
				nil if current_byte == 88 # "X"

				if peek == 39 # "'"
					token_type = :BLOB
					step

					step while xdigit?(peek)

					if peek != 39 || ((@cursor - @anchor) % 2) != 0
						token_type = :ILLEGAL
						step until (b = peek).nil? || b == 39 # "'"
					end

					step if !peek.nil?

					return token_type
				end

				# If it is not a BLOB literal, then it must be an ID, since no
				# SQL keywords start with the letter 'x'.
				step while id?(peek)

				:ID
			when :KYWD, :ID
				step while id?(peek)

				:ID
			when :BOM
				return step(2) && :SPACE if peek == 0xFE && peek(1) == 0xFF

				step while id?(peek)
				:ID
			else
				:ILLEGAL
			end
		end

		def peek(n = 0) = @sql.getbyte(@cursor+n)
		def step(n = 1) = @cursor += n
		def scan(n = 0) = peek(n).tap { step(n+1) }

		def space?(byte) 	= byte && CHARACTER_FLAGS[byte] & 0x01 != 0
		def alnum?(byte) 	= byte && CHARACTER_FLAGS[byte] & 0x06 != 0
		def alpha?(byte) 	= byte && CHARACTER_FLAGS[byte] & 0x02 != 0
		def digit?(byte) 	= byte && CHARACTER_FLAGS[byte] & 0x04 != 0
		def xdigit?(byte) = byte && CHARACTER_FLAGS[byte] & 0x08 != 0
		def quote?(byte) 	= byte && CHARACTER_FLAGS[byte] & 0x80 != 0
		def id?(byte) 		= byte && CHARACTER_FLAGS[byte] & 0x46 != 0
		# If X is a character that can be used in an identifier then
		# IdChar(X) will be true.  Otherwise it is false.
		#
		# For ASCII, any character with the high-order bit set is
		# allowed in an identifier.  For 7-bit characters,
		# sqlite3IsIdChar[X] must be 1.
		#
		# Ticket #1066.  the SQL standard does not allow '$' in the
		# middle of identifiers.  But many SQL implementations do.
		# SQLite will allow '$' in identifiers for compatibility.
		# But the feature is undocumented.
	end
end
