# frozen_string_literal: true

module Plume
	class ColumnType < Node
		token :text_span

		attribute :text, Stringy

		def self.new(*, text:, **) = super
		def self.concrete(*, text_span:, **) = super

		def text = (@text == LiteralNil) ? text_span_val : @text

		inspectable def affinity
			# rules found at: https://www.sqlite.org/datatype3.html#determination_of_column_affinity
			# Matched as bytes, as SQLite does, so a type name that is not valid UTF-8 has one too
			case text&.b
			when /INT/i							then	:INTEGER
			when /CHAR|CLOB|TEXT/i	then	:TEXT
			when /BLOB/i						then	:BLOB
			when /REAL|FLOA|DOUB/i	then	:REAL
			else													:ANY
			end
		end
	end
end
