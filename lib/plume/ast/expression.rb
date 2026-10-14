# frozen_string_literal: true

module Plume
	# No plain values (nil, true, symbols) in here, see Node.attribute for why.
	# `_Deferred` keeps its block unfrozen, so a Ractor can only read the type once it is made shareable
	Expression = Ractor.make_shareable(_Union(
		Numeric,
		String,
		Token,
		ColumnName,
		TableName,
		_Deferred {
			_Union(
				UnaryExpression,
				BinaryExpression,
				CastExpression,
				TernaryExpression,
				LikeExpression,
				CaseExpression,
				CollationExpression,
				RaiseExpression,
				FunctionReference,
				LiteralExpression,
				ParentheticalExpression,
				SubqueryExpression,
				ExistsExpression,
				Variable,
			)
		},
	))
end
