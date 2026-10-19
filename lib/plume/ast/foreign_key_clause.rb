# frozen_string_literal: true

module Plume
	class ForeignKeyClause < Node
		TOKEN_TO_DEFERRABLE = {
			:DEFERRABLE                                        => false,
			[:DEFERRABLE].freeze                               => false,
			[:NOT, :DEFERRABLE].freeze                         => false,
			[:DEFERRABLE, :INITIALLY, :DEFERRED].freeze        => true,
			[:DEFERRABLE, :INITIALLY, :IMMEDIATE].freeze       => false,
			[:NOT, :DEFERRABLE, :INITIALLY, :DEFERRED].freeze  => false,
			[:NOT, :DEFERRABLE, :INITIALLY, :IMMEDIATE].freeze => false,
		}.freeze
		Deferrable = _Union(*TOKEN_TO_DEFERRABLE.values.uniq)

		token :references_kw
		token :table_tk
		token :columns_lp
		token :columns_rp
		token :deferrable_span

		attribute :table, Stringy
		attribute :deferred, Deferrable
		nodes :columns, IndexedColumn
		nodes :actions, ForeignKeyAction
		nodes :match_clauses, MatchClause

		def self.new(*, table:, **) = super
		def self.concrete(*, references_kw:, table_tk:, **) = super

		def table = (@table == LiteralNil) ? table_tk_val : @table
		def deferred = (@deferred == LiteralNil) ? TOKEN_TO_DEFERRABLE[deferrable_span_tok] : @deferred

		def on_delete
			actions.reverse_each do |it|
				return it.action if it.trigger == :DELETE
			end
		end

		def on_update
			actions.reverse_each do |it|
				return it.action if it.trigger == :UPDATE
			end
		end

		def match_type
			match_clauses.last.type
		end
	end
end
