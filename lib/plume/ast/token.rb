# frozen_string_literal: true

module Plume
	module Token
		extend Literal::Types
		extend self

		Type = _Union(
			:keyword,
			:identifier,
			:punctuation,
			:string,
			:numeric,
			:blob,
			:true,
			:false,
			:null,
			:current,
			:variable,
		)

		Tuple = _Tuple(_Union(Symbol, _Array(Symbol)), Integer, Integer, Type)

		def Keyword(arg)
			[*arg, :keyword] if arg
		end

		def Identifier(arg)
			[*arg, :identifier] if arg
		end

		def Punctuation(arg)
			[*arg, :punctuation] if arg
		end

		def String(arg)
			[*arg, :string] if arg
		end

		def Numeric(arg)
			[*arg, :numeric] if arg
		end

		def Blob(arg)
			[*arg, :blob] if arg
		end

		def True(arg)
			[*arg, :true] if arg
		end

		def False(arg)
			[*arg, :false] if arg
		end

		def Null(arg)
			[*arg, :null] if arg
		end

		def Current(arg)
			[*arg, :current] if arg
		end

		def Variable(arg)
			[*arg, :variable] if arg
		end

		def source(str, tup)
			return unless str && present?(tup)

			_, beg, fin, = tup

			str.byteslice(beg, (fin - beg))
		end

		def value(str, tup)
			return unless str && present?(tup)

			*, type = tup

			case type
			when :null        then LiteralNil
			when :true        then true
			when :false       then LiteralFalse
			when :current     then source(str, tup).to_sym.upcase
			when :numeric     then numeric_literal(str, tup)
			when :string      then string_literal(str, tup)
			when :blob        then blob_literal(str, tup)
			when :keyword     then source(str, tup)
			when :identifier  then identifier(str, tup)
			when :punctuation then source(str, tup)
			when :variable    then source(str, tup)
			end
		end

		def location(tup)
			return unless present?(tup)

			_, beg, fin, = tup

			[beg, fin].freeze
		end

		def token(tup)
			return unless present?(tup)

			tok, * = tup

			tok
		end

		def ===(other)
			Tuple === other
		end

		private

		def present?(tup) = !(tup.nil? || LiteralNil.equal?(tup))

		def numeric_literal(str, tup)
			tok, * = tup
			src = source(str, tup)

			case tok
			when :INTEGER, [:PLUS, :INTEGER], [:MINUS, :INTEGER]
				integer_literal(src)
			when :FLOAT, [:PLUS, :FLOAT], [:MINUS, :FLOAT]
				src.to_f
			when :QNUMBER, [:PLUS, :QNUMBER], [:MINUS, :QNUMBER]
				(src.match?(/[.eE]/) && !src.match?(/0x/i)) ? src.delete("_").to_f : integer_literal(src)
			end
		end

		def integer_literal(src)
			digits = src.delete("_").delete_prefix("+")
			negative = digits.delete_prefix!("-")
			value = digits.match?(/\A0x/i) ? hex_literal(digits) : digits.to_i
			negative ? -value : value
		end

		# SQLite reads a hex literal as a 64-bit two's-complement integer, so 0xFFFFFFFFFFFFFFFF is -1
		def hex_literal(digits)
			value = digits.to_i(16)
			(value >= (2**63)) ? value - (2**64) : value
		end

		def string_literal(str, tup)
			src = source(str, tup)
			bytesize = src.bytesize
			# strip the leading and trailing quotes, a quote inside is written twice
			undoubled(src.byteslice(1, bytesize - 2), "'")
		end

		# Done on the bytes, since TruffleRuby's gsub refuses a string that is not valid UTF-8
		def undoubled(text, quote) = text.b.gsub(quote * 2, quote).force_encoding(text.encoding)

		def blob_literal(str, tup)
			src = source(str, tup)
			bytesize = src.bytesize
			# trim the leading /x'/i and trailing /'/ then decode the hexadecimal string
			[src.byteslice(2, bytesize - 3)].pack("H*")
		end

		def identifier(str, tup)
			tok, * = tup

			return string_literal(str, tup) if tok == :STRING

			src = source(str, tup)

			return src if tok != :ID

			# Inside quotes, the quote character itself is written twice. Brackets have no escape
			case src.getbyte(0)
			when 96 then undoubled(src.byteslice(1, src.bytesize - 2), "`")
			when 39 then undoubled(src.byteslice(1, src.bytesize - 2), "'")
			when 34 then undoubled(src.byteslice(1, src.bytesize - 2), '"')
			when 91 then src.byteslice(1, src.bytesize - 2)
			else src
			end
		end
	end
end
