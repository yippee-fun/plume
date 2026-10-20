# frozen_string_literal: true

module Plume
	class CollateColumnConstraint < ColumnConstraint
		token :constraint_kw
		token :name_tk
		token :collate_kw
		token :collation_tk

		attribute :name, Stringy
		attribute :collation, Stringy

		def self.new(*, collation:, **) = super
		def self.concrete(*, collate_kw:, collation_tk:, **) = super

		def name = (@name == LiteralNil) ? name_tk_val : @name
		def collation = (@collation == LiteralNil) ? Node.collation_name(collation_tk_val) : @collation
	end
end
