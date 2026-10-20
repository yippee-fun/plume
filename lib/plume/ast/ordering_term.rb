# frozen_string_literal: true

module Plume
	class OrderingTerm < Node
		Direction = _Union(
			:ASC, "ASC", :asc, "asc", :ASCENDING, "ASCENDING", :ascending, "ascending",
			:DESC, "DESC", :desc, "desc", :DESCENDING, "DESCENDING", :descending, "descending",
		)
		Nulls = _Union(
			:FIRST, "FIRST", :first, "first",
			:LAST, "LAST", :last, "last",
		)

		token :collate_kw
		token :collation_tk
		token :direction_tk
		token :nulls_kw
		token :nulls_tk

		node :expression, Expression
		attribute :collation, Stringy
		attribute :direction, Direction
		attribute :nulls, Nulls

		def self.new(*, **) = super
		def self.concrete(*, **) = super

		def collation = (@collation == LiteralNil) ? Node.collation_name(collation_tk_val) : @collation
		def direction = (@direction == LiteralNil) ? direction_tk_val&.to_sym&.upcase : @direction
		def nulls = (@nulls == LiteralNil) ? nulls_tk_val&.to_sym&.upcase : @nulls
	end
end
