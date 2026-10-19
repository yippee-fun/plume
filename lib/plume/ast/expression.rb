# frozen_string_literal: true

module Plume
	# No plain values (nil, true, symbols) in here, see Node.attribute for why
	Expression = _Union(
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
	)
end
