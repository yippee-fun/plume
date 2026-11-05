# frozen_string_literal: true

# -- literal values

test "2" do
	parser = Plume::Parser.new("2")
	actual = parser.expression
	expected = Plume::LiteralExpression.new(
		value: 2
	)
	assert_equal actual.value, expected.value
end

test "1.2" do
	parser = Plume::Parser.new("1.2")
	actual = parser.expression
	expected = Plume::LiteralExpression.new(
		value: 1.2
	)
	assert_equal actual.value, expected.value
end

test "'foo'" do
	parser = Plume::Parser.new("'foo'")
	actual = parser.expression
	expected = Plume::LiteralExpression.new(
		value: "foo"
	)
	assert_equal actual.value, expected.value
end

test "X'53514C697465'" do
	parser = Plume::Parser.new("X'53514C697465'")
	actual = parser.expression
	expected = Plume::LiteralExpression.new(
		value: "SQLite"
	)
	assert_equal actual.value, expected.value
end

test "null" do
	parser = Plume::Parser.new("null")
	actual = parser.expression
	expected = Plume::LiteralExpression.new(
		value: nil
	)
	assert_equal actual.value, expected.value
end

test "true" do
	parser = Plume::Parser.new("true")
	actual = parser.expression
	expected = Plume::LiteralExpression.new(
		value: true
	)
	assert_equal actual.value, expected.value
end

test "false" do
	parser = Plume::Parser.new("false")
	actual = parser.expression
	expected = Plume::LiteralExpression.new(
		value: false
	)
	assert_equal actual.value, expected.value
end

test "current_time" do
	parser = Plume::Parser.new("current_time")
	actual = parser.expression
	expected = Plume::LiteralExpression.new(
		value: :CURRENT_TIME
	)
	assert_equal actual.value, expected.value
end

test "current_date" do
	parser = Plume::Parser.new("current_date")
	actual = parser.expression
	expected = Plume::LiteralExpression.new(
		value: :CURRENT_DATE
	)
	assert_equal actual.value, expected.value
end

test "current_timestamp" do
	parser = Plume::Parser.new("current_timestamp")
	actual = parser.expression
	expected = Plume::LiteralExpression.new(
		value: :CURRENT_TIMESTAMP
	)
	assert_equal actual.value, expected.value
end

test "c0" do
	parser = Plume::Parser.new("c0")
	actual = parser.expression
	expected = Plume::ColumnName.new(column: "c0")
	assert_equal actual.column, expected.column
end

test "tb1.c0" do
	parser = Plume::Parser.new("tb1.c0")
	actual = parser.expression
	expected = Plume::ColumnName.new(
		table: "tb1",
		column: "c0",
	)
	assert_equal actual.column, expected.column
	assert_equal actual.table, expected.table
end

test "sc1.tb1.c0" do
	parser = Plume::Parser.new("sc1.tb1.c0")
	actual = parser.expression
	expected = Plume::ColumnName.new(
		schema: "sc1",
		table: "tb1",
		column: "c0",
	)
	assert_equal actual.column, expected.column
	assert_equal actual.table, expected.table
	assert_equal actual.schema, expected.schema
end

test "(2)" do
	parser = Plume::Parser.new("(2)")
	actual = parser.expression
	expected = Plume::ParentheticalExpression.new(
		value: 2
	)
	assert_equal actual.value, expected.value
end

test "(1.2)" do
	parser = Plume::Parser.new("(1.2)")
	actual = parser.expression
	expected = Plume::ParentheticalExpression.new(
		value: 1.2
	)
	assert_equal actual.value, expected.value
end

test "('foo')" do
	parser = Plume::Parser.new("('foo')")
	actual = parser.expression
	expected = Plume::ParentheticalExpression.new(
		value: "foo"
	)
	assert_equal actual.value, expected.value
end

test "(X'53514C697465')" do
	parser = Plume::Parser.new("(X'53514C697465')")
	actual = parser.expression
	expected = Plume::ParentheticalExpression.new(
		value: "SQLite"
	)
	assert_equal actual.value, expected.value
end

test "(null)" do
	parser = Plume::Parser.new("(null)")
	actual = parser.expression
	expected = Plume::ParentheticalExpression.new(
		value: nil
	)
	assert_equal actual.value, expected.value
end

test "(true)" do
	parser = Plume::Parser.new("(true)")
	actual = parser.expression
	expected = Plume::ParentheticalExpression.new(
		value: true
	)
	assert_equal actual.value, expected.value
end

test "(false)" do
	parser = Plume::Parser.new("(false)")
	actual = parser.expression
	expected = Plume::ParentheticalExpression.new(
		value: false
	)
	assert_equal actual.value, expected.value
end

test "(current_time)" do
	parser = Plume::Parser.new("(current_time)")
	actual = parser.expression
	expected = Plume::ParentheticalExpression.new(
		value: :CURRENT_TIME
	)
	assert_equal actual.value, expected.value
end

test "(current_date)" do
	parser = Plume::Parser.new("(current_date)")
	actual = parser.expression
	expected = Plume::ParentheticalExpression.new(
		value: :CURRENT_DATE
	)
	assert_equal actual.value, expected.value
end

test "(current_timestamp)" do
	parser = Plume::Parser.new("(current_timestamp)")
	actual = parser.expression
	expected = Plume::ParentheticalExpression.new(
		value: :CURRENT_TIMESTAMP
	)
	assert_equal actual.value, expected.value
end

test "(c0)" do
	parser = Plume::Parser.new("(c0)")
	actual = parser.expression
	expected = Plume::ParentheticalExpression.new(
		value: Plume::ColumnName.new(column: "c0")
	)
	assert_equal actual.value.column, expected.value.column
end

test "(tb1.c0)" do
	parser = Plume::Parser.new("(tb1.c0)")
	actual = parser.expression
	expected = Plume::ParentheticalExpression.new(
		value: Plume::ColumnName.new(
			table: "tb1",
			column: "c0",
		)
	)
	assert_equal actual.value.column, expected.value.column
	assert_equal actual.value.table, expected.value.table
end

test "(sc1.tb1.c0)" do
	parser = Plume::Parser.new("(sc1.tb1.c0)")
	actual = parser.expression
	expected = Plume::ParentheticalExpression.new(
		value: Plume::ColumnName.new(
			schema: "sc1",
			table: "tb1",
			column: "c0",
		)
	)
	assert_equal actual.value.column, expected.value.column
	assert_equal actual.value.table, expected.value.table
	assert_equal actual.value.schema, expected.value.schema
end

# -- unary operations

test "~c0" do
	parser = Plume::Parser.new("~c0")
	actual = parser.expression
	expected = Plume::UnaryExpression.new(
		operator: :INVERT,
		operand: Plume::ColumnName.new(column: "c0")
	)

	assert_equal actual.operator, expected.operator
	assert_equal actual.operand.column, expected.operand.column
end

test "+c0" do
	parser = Plume::Parser.new("+c0")
	actual = parser.expression
	expected = Plume::UnaryExpression.new(
		operator: :IDENTITY,
		operand: Plume::ColumnName.new(column: "c0")
	)

	assert_equal actual.operator, expected.operator
	assert_equal actual.operand.column, expected.operand.column
end

test "-c0" do
	parser = Plume::Parser.new("-c0")
	actual = parser.expression
	expected = Plume::UnaryExpression.new(
		operator: :NEGATE,
		operand: Plume::ColumnName.new(column: "c0")
	)

	assert_equal actual.operator, expected.operator
	assert_equal actual.operand.column, expected.operand.column
end

test "NOT c0" do
	parser = Plume::Parser.new("NOT c0")
	actual = parser.expression
	expected = Plume::UnaryExpression.new(
		operator: :NOT,
		operand: Plume::ColumnName.new(column: "c0")
	)

	assert_equal actual.operator, expected.operator
	assert_equal actual.operand.column, expected.operand.column
end

test "NOT 0 + 1" do
	parser = Plume::Parser.new("NOT 0 + 1")
	actual = parser.expression
	expected = Plume::UnaryExpression.new(
		operator: :NOT,
		operand: Plume::BinaryExpression.new(
			operator: :ADD,
			left: Plume::LiteralExpression.new(value: 0),
			right: Plume::LiteralExpression.new(value: 1)
		)
	)
	assert_equal actual.operator, expected.operator
	assert_equal actual.operand.operator, expected.operand.operator
	assert_equal actual.operand.left.value, expected.operand.left.value
	assert_equal actual.operand.right.value, expected.operand.right.value
end

test "c0 ISNULL" do
	parser = Plume::Parser.new("c0 ISNULL")
	actual = parser.expression
	expected = Plume::UnaryExpression.new(
		operator: :IS_NULL,
		operand: Plume::ColumnName.new(column: "c0"),
	)

	assert_equal actual.operator, expected.operator
	assert_equal actual.operand.column, expected.operand.column
end

test "c0 NOTNULL" do
	parser = Plume::Parser.new("c0 NOTNULL")
	actual = parser.expression
	expected = Plume::UnaryExpression.new(
		operator: :NOT_NULL,
		operand: Plume::ColumnName.new(column: "c0"),
	)

	assert_equal actual.operator, expected.operator
	assert_equal actual.operand.column, expected.operand.column
end

# -- binary operations

test "c0 || 'suffix'" do
	parser = Plume::Parser.new("c0 || 'suffix'")
	actual = parser.expression
	expected = Plume::BinaryExpression.new(
		operator: :CONCAT,
		left: Plume::ColumnName.new(column: "c0"),
		right: Plume::LiteralExpression.new(value: "suffix"),
	)

	assert_equal actual.operator, expected.operator
	assert_equal actual.left.column, expected.left.column
	assert_equal actual.right.value, expected.right.value
end

test "c0 -> '$.key'" do
	parser = Plume::Parser.new("c0 -> '$.key'")
	actual = parser.expression
	expected = Plume::BinaryExpression.new(
		operator: :EXTRACT,
		left: Plume::ColumnName.new(column: "c0"),
		right: Plume::LiteralExpression.new(value: "$.key"),
	)
	assert_equal actual.operator, expected.operator
	assert_equal actual.left.column, expected.left.column
	assert_equal actual.right.value, expected.right.value
end

test "c0 ->> '$.key'" do
	parser = Plume::Parser.new("c0 ->> '$.key'")
	actual = parser.expression
	expected = Plume::BinaryExpression.new(
		operator: :RETRIEVE,
		left: Plume::ColumnName.new(column: "c0"),
		right: Plume::LiteralExpression.new(value: "$.key"),
	)
	assert_equal actual.operator, expected.operator
	assert_equal actual.left.column, expected.left.column
	assert_equal actual.right.value, expected.right.value
end

test "c0 * 5" do
	parser = Plume::Parser.new("c0 * 5")
	actual = parser.expression
	expected = Plume::BinaryExpression.new(
		operator: :MULTIPLY,
		left: Plume::ColumnName.new(column: "c0"),
		right: Plume::LiteralExpression.new(value: 5),
	)
	assert_equal actual.operator, expected.operator
	assert_equal actual.left.column, expected.left.column
	assert_equal actual.right.value, expected.right.value
end

test "c0 / 2" do
	parser = Plume::Parser.new("c0 / 2")
	actual = parser.expression
	expected = Plume::BinaryExpression.new(
		operator: :DIVIDE,
		left: Plume::ColumnName.new(column: "c0"),
		right: Plume::LiteralExpression.new(value: 2),
	)
	assert_equal actual.operator, expected.operator
	assert_equal actual.left.column, expected.left.column
	assert_equal actual.right.value, expected.right.value
end

test "c0 % 3" do
	parser = Plume::Parser.new("c0 % 3")
	actual = parser.expression
	expected = Plume::BinaryExpression.new(
		operator: :MODULO,
		left: Plume::ColumnName.new(column: "c0"),
		right: Plume::LiteralExpression.new(value: 3),
	)
	assert_equal actual.operator, expected.operator
	assert_equal actual.left.column, expected.left.column
	assert_equal actual.right.value, expected.right.value
end

test "c0 + 10" do
	parser = Plume::Parser.new("c0 + 10")
	actual = parser.expression
	expected = Plume::BinaryExpression.new(
		operator: :ADD,
		left: Plume::ColumnName.new(column: "c0"),
		right: Plume::LiteralExpression.new(value: 10),
	)
	assert_equal actual.operator, expected.operator
	assert_equal actual.left.column, expected.left.column
	assert_equal actual.right.value, expected.right.value
end

test "c0 - 5" do
	parser = Plume::Parser.new("c0 - 5")
	actual = parser.expression
	expected = Plume::BinaryExpression.new(
		operator: :SUB,
		left: Plume::ColumnName.new(column: "c0"),
		right: Plume::LiteralExpression.new(value: 5),
	)
	assert_equal actual.operator, expected.operator
	assert_equal actual.left.column, expected.left.column
	assert_equal actual.right.value, expected.right.value
end

test "c0 & 7" do
	parser = Plume::Parser.new("c0 & 7")
	actual = parser.expression
	expected = Plume::BinaryExpression.new(
		operator: :BIT_AND,
		left: Plume::ColumnName.new(column: "c0"),
		right: Plume::LiteralExpression.new(value: 7),
	)
	assert_equal actual.operator, expected.operator
	assert_equal actual.left.column, expected.left.column
	assert_equal actual.right.value, expected.right.value
end

test "c0 | 8" do
	parser = Plume::Parser.new("c0 | 8")
	actual = parser.expression
	expected = Plume::BinaryExpression.new(
		operator: :BIT_OR,
		left: Plume::ColumnName.new(column: "c0"),
		right: Plume::LiteralExpression.new(value: 8),
	)
	assert_equal actual.operator, expected.operator
	assert_equal actual.left.column, expected.left.column
	assert_equal actual.right.value, expected.right.value
end

test "c0 << 2" do
	parser = Plume::Parser.new("c0 << 2")
	actual = parser.expression
	expected = Plume::BinaryExpression.new(
		operator: :BIT_LSHIFT,
		left: Plume::ColumnName.new(column: "c0"),
		right: Plume::LiteralExpression.new(value: 2),
	)
	assert_equal actual.operator, expected.operator
	assert_equal actual.left.column, expected.left.column
	assert_equal actual.right.value, expected.right.value
end

test "c0 >> 1" do
	parser = Plume::Parser.new("c0 >> 1")
	actual = parser.expression
	expected = Plume::BinaryExpression.new(
		operator: :BIT_RSHIFT,
		left: Plume::ColumnName.new(column: "c0"),
		right: Plume::LiteralExpression.new(value: 1),
	)
	assert_equal actual.operator, expected.operator
	assert_equal actual.left.column, expected.left.column
	assert_equal actual.right.value, expected.right.value
end

test "c0 < 100" do
	parser = Plume::Parser.new("c0 < 100")
	actual = parser.expression
	expected = Plume::BinaryExpression.new(
		operator: :BELOW,
		left: Plume::ColumnName.new(column: "c0"),
		right: Plume::LiteralExpression.new(value: 100),
	)
	assert_equal actual.operator, expected.operator
	assert_equal actual.left.column, expected.left.column
	assert_equal actual.right.value, expected.right.value
end

test "c0 <= 50" do
	parser = Plume::Parser.new("c0 <= 50")
	actual = parser.expression
	expected = Plume::BinaryExpression.new(
		operator: :ATMOST,
		left: Plume::ColumnName.new(column: "c0"),
		right: Plume::LiteralExpression.new(value: 50),
	)
	assert_equal actual.operator, expected.operator
	assert_equal actual.left.column, expected.left.column
	assert_equal actual.right.value, expected.right.value
end

test "c0 >= 20" do
	parser = Plume::Parser.new("c0 >= 20")
	actual = parser.expression
	expected = Plume::BinaryExpression.new(
		operator: :ATLEAST,
		left: Plume::ColumnName.new(column: "c0"),
		right: Plume::LiteralExpression.new(value: 20),
	)
	assert_equal actual.operator, expected.operator
	assert_equal actual.left.column, expected.left.column
	assert_equal actual.right.value, expected.right.value
end

test "c0 = 42" do
	parser = Plume::Parser.new("c0 = 42")
	actual = parser.expression
	expected = Plume::BinaryExpression.new(
		operator: :EQUALS,
		left: Plume::ColumnName.new(column: "c0"),
		right: Plume::LiteralExpression.new(value: 42),
	)
	assert_equal actual.operator, expected.operator
	assert_equal actual.left.column, expected.left.column
	assert_equal actual.right.value, expected.right.value
end

test "c0 != 42" do
	parser = Plume::Parser.new("c0 != 42")
	actual = parser.expression
	expected = Plume::BinaryExpression.new(
		operator: :NOT_EQUALS,
		left: Plume::ColumnName.new(column: "c0"),
		right: Plume::LiteralExpression.new(value: 42),
	)
	assert_equal actual.operator, expected.operator
	assert_equal actual.left.column, expected.left.column
	assert_equal actual.right.value, expected.right.value
end

test "c0 IS TRUE" do
	parser = Plume::Parser.new("c0 IS TRUE")
	actual = parser.expression
	expected = Plume::BinaryExpression.new(
		operator: :IS,
		left: Plume::ColumnName.new(column: "c0"),
		right: Plume::LiteralExpression.new(value: true),
	)
	assert_equal actual.operator, expected.operator
	assert_equal actual.left.column, expected.left.column
	assert_equal actual.right.value, expected.right.value
end

test "c0 IS DISTINCT FROM TRUE" do
	parser = Plume::Parser.new("c0 IS DISTINCT FROM TRUE")
	actual = parser.expression
	expected = Plume::BinaryExpression.new(
		operator: :IS_NOT,
		left: Plume::ColumnName.new(column: "c0"),
		right: Plume::LiteralExpression.new(value: true),
	)
	assert_equal actual.operator, expected.operator
	assert_equal actual.left.column, expected.left.column
	assert_equal actual.right.value, expected.right.value
end

test "c0 IS NOT FALSE" do
	parser = Plume::Parser.new("c0 IS NOT FALSE")
	actual = parser.expression
	expected = Plume::BinaryExpression.new(
		operator: :IS_NOT,
		left: Plume::ColumnName.new(column: "c0"),
		right: Plume::LiteralExpression.new(value: false),
	)
	assert_equal actual.operator, expected.operator
	assert_equal actual.left.column, expected.left.column
	assert_equal actual.right.value, expected.right.value
end

test "c0 IS NOT DISTINCT FROM TRUE" do
	parser = Plume::Parser.new("c0 IS NOT DISTINCT FROM TRUE")
	actual = parser.expression
	expected = Plume::BinaryExpression.new(
		operator: :IS,
		left: Plume::ColumnName.new(column: "c0"),
		right: Plume::LiteralExpression.new(value: true),
	)
	assert_equal actual.operator, expected.operator
	assert_equal actual.left.column, expected.left.column
	assert_equal actual.right.value, expected.right.value
end

test "c0 IS NOT FALSE" do
	parser = Plume::Parser.new("c0 IS NOT FALSE")
	actual = parser.expression
	expected = Plume::BinaryExpression.new(
		operator: :IS_NOT,
		left: Plume::ColumnName.new(column: "c0"),
		right: Plume::LiteralExpression.new(value: false),
	)
	assert_equal actual.operator, expected.operator
	assert_equal actual.left.column, expected.left.column
	assert_equal actual.right.value, expected.right.value
end

test "c0 > 0" do
	parser = Plume::Parser.new("c0 > 0")
	actual = parser.expression
	expected = Plume::BinaryExpression.new(
		operator: :ABOVE,
		left: Plume::ColumnName.new(column: "c0"),
		right: Plume::LiteralExpression.new(value: 0),
	)
	assert_equal actual.operator, expected.operator
	assert_equal actual.left.column, expected.left.column
	assert_equal actual.right.value, expected.right.value
end

test "c0 > -1" do
	parser = Plume::Parser.new("c0 > -1")
	actual = parser.expression
	expected = Plume::BinaryExpression.new(
		operator: :ABOVE,
		left: Plume::ColumnName.new(column: "c0"),
		right: Plume::UnaryExpression.new(
			operator: :NEGATE,
			operand: Plume::LiteralExpression.new(value: 1)
		),
	)
	assert_equal actual.operator, expected.operator
	assert_equal actual.left.column, expected.left.column
	assert_equal actual.right.operator, expected.right.operator
	assert_equal actual.right.operand.value, expected.right.operand.value
end

test "-1 > c0" do
	parser = Plume::Parser.new("-1 > c0")
	actual = parser.expression
	expected = Plume::BinaryExpression.new(
		operator: :ABOVE,
		left: Plume::UnaryExpression.new(
			operator: :NEGATE,
			operand: Plume::LiteralExpression.new(value: 1)
		),
		right: Plume::ColumnName.new(column: "c0"),
	)
	assert_equal actual.operator, expected.operator
	assert_equal actual.left.operator, expected.left.operator
	assert_equal actual.left.operand.value, expected.left.operand.value
	assert_equal actual.right.column, expected.right.column
end

test "c0 IS NOT NULL" do
	parser = Plume::Parser.new("c0 IS NOT NULL")
	actual = parser.expression
	expected = Plume::BinaryExpression.new(
		operator: :IS_NOT,
		left: Plume::ColumnName.new(column: "c0"),
		right: Plume::LiteralExpression.new(value: nil),
	)
	assert_equal actual.operator, expected.operator
	assert_equal actual.left.column, expected.left.column
	assert_equal actual.right.value, expected.right.value
end

test "c0 GLOB '*.txt'" do
	parser = Plume::Parser.new("c0 GLOB '*.txt'")
	actual = parser.expression
	expected = Plume::BinaryExpression.new(
		operator: :GLOB,
		left: Plume::ColumnName.new(column: "c0"),
		right: Plume::LiteralExpression.new(value: "*.txt"),
	)
	assert_equal actual.operator, expected.operator
	assert_equal actual.left.column, expected.left.column
	assert_equal actual.right.value, expected.right.value
end

test "c0 REGEXP '^[A-Z]+'" do
	parser = Plume::Parser.new("c0 REGEXP '^[A-Z]+'")
	actual = parser.expression
	expected = Plume::BinaryExpression.new(
		operator: :REGEXP,
		left: Plume::ColumnName.new(column: "c0"),
		right: Plume::LiteralExpression.new(value: "^[A-Z]+"),
	)
	assert_equal actual.operator, expected.operator
	assert_equal actual.left.column, expected.left.column
	assert_equal actual.right.value, expected.right.value
end

test "c0 MATCH 'patten'" do
	parser = Plume::Parser.new("c0 MATCH 'patten'")
	actual = parser.expression
	expected = Plume::BinaryExpression.new(
		operator: :MATCH,
		left: Plume::ColumnName.new(column: "c0"),
		right: Plume::LiteralExpression.new(value: "patten"),
	)
	assert_equal actual.operator, expected.operator
	assert_equal actual.left.column, expected.left.column
	assert_equal actual.right.value, expected.right.value
end

test "c0 NOT GLOB '*.txt'" do
	parser = Plume::Parser.new("c0 NOT GLOB '*.txt'")
	actual = parser.expression
	expected = Plume::BinaryExpression.new(
		operator: :NOT_GLOB,
		left: Plume::ColumnName.new(column: "c0"),
		right: Plume::LiteralExpression.new(value: "*.txt"),
	)
	assert_equal actual.operator, expected.operator
	assert_equal actual.left.column, expected.left.column
	assert_equal actual.right.value, expected.right.value
end

test "c0 NOT REGEXP '^[A-Z]+'" do
	parser = Plume::Parser.new("c0 NOT REGEXP '^[A-Z]+'")
	actual = parser.expression
	expected = Plume::BinaryExpression.new(
		operator: :NOT_REGEXP,
		left: Plume::ColumnName.new(column: "c0"),
		right: Plume::LiteralExpression.new(value: "^[A-Z]+"),
	)
	assert_equal actual.operator, expected.operator
	assert_equal actual.left.column, expected.left.column
	assert_equal actual.right.value, expected.right.value
end

test "c0 NOT MATCH 'patten'" do
	parser = Plume::Parser.new("c0 NOT MATCH 'patten'")
	actual = parser.expression
	expected = Plume::BinaryExpression.new(
		operator: :NOT_MATCH,
		left: Plume::ColumnName.new(column: "c0"),
		right: Plume::LiteralExpression.new(value: "patten"),
	)
	assert_equal actual.operator, expected.operator
	assert_equal actual.left.column, expected.left.column
	assert_equal actual.right.value, expected.right.value
end

test "c0 > 0 AND c1 < 0" do
	parser = Plume::Parser.new("c0 > 0 AND c1 < 0")
	actual = parser.expression
	expected = Plume::BinaryExpression.new(
		operator: :ALL,
		left: Plume::BinaryExpression.new(
			operator: :ABOVE,
			left: Plume::ColumnName.new(column: "c0"),
			right: Plume::LiteralExpression.new(value: 0)
		),
		right: Plume::BinaryExpression.new(
			operator: :BELOW,
			left: Plume::ColumnName.new(column: "c1"),
			right: Plume::LiteralExpression.new(value: 0)
		)
	)
	assert_equal actual.operator, expected.operator
	assert_equal actual.left.operator, expected.left.operator
	assert_equal actual.left.left.column, expected.left.left.column
	assert_equal actual.left.right.value, expected.left.right.value
	assert_equal actual.right.operator, expected.right.operator
	assert_equal actual.right.left.column, expected.right.left.column
	assert_equal actual.right.right.value, expected.right.right.value
end

test "c0 > 0 OR c1 LIKE 'foo%'" do
	parser = Plume::Parser.new("c0 > 0 OR c1 LIKE 'foo%'")
	actual = parser.expression
	expected = Plume::BinaryExpression.new(
		operator: :ANY,
		left: Plume::BinaryExpression.new(
			operator: :ABOVE,
			left: Plume::ColumnName.new(column: "c0"),
			right: Plume::LiteralExpression.new(value: 0),
		),
		right: Plume::LikeExpression.new(
			left: Plume::ColumnName.new(column: "c1"),
			right: Plume::LiteralExpression.new(value: "foo%"),
		)
	)
	assert_equal actual.left.operator, expected.left.operator
	assert_equal actual.left.left.column, expected.left.left.column
	assert_equal actual.left.right.value, expected.left.right.value
	assert_equal actual.right.left.column, expected.right.left.column
	assert_equal actual.right.right.value, expected.right.right.value
end

# -- comparison operators

test "'str' like 'foo'" do
	parser = Plume::Parser.new("'str' like 'foo'")
	actual = parser.expression
	expected = Plume::LikeExpression.new(
		left: Plume::LiteralExpression.new(value: "str"),
		right: Plume::LiteralExpression.new(value: "foo"),
	)
	assert_equal actual.left.value, expected.left.value
	assert_equal actual.right.value, expected.right.value
end

test "'str' not like 'foo'" do
	parser = Plume::Parser.new("'str' not like 'foo'")
	actual = parser.expression
	expected = Plume::NotLikeExpression.new(
		left: Plume::LiteralExpression.new(value: "str"),
		right: Plume::LiteralExpression.new(value: "foo"),
	)
	assert_equal actual.left.value, expected.left.value
	assert_equal actual.right.value, expected.right.value
end

test "'str' like 'foo' escape '|'" do
	parser = Plume::Parser.new("'str' like 'foo' escape '|'")
	actual = parser.expression
	expected = Plume::LikeExpression.new(
		left: Plume::LiteralExpression.new(value: "str"),
		right: Plume::LiteralExpression.new(value: "foo"),
		escape: Plume::LiteralExpression.new(value: "|"),
	)
	assert_equal actual.left.value, expected.left.value
	assert_equal actual.right.value, expected.right.value
	assert_equal actual.escape.value, expected.escape.value
end

test "'str' not like 'foo' escape '|'" do
	parser = Plume::Parser.new("'str' not like 'foo' escape '|'")
	actual = parser.expression
	expected = Plume::NotLikeExpression.new(
		left: Plume::LiteralExpression.new(value: "str"),
		right: Plume::LiteralExpression.new(value: "foo"),
		escape: Plume::LiteralExpression.new(value: "|"),
	)
	assert_equal actual.left.value, expected.left.value
	assert_equal actual.right.value, expected.right.value
	assert_equal actual.escape.value, expected.escape.value
end

# -- ternary expressions

test "2 between 1 and 10" do
	parser = Plume::Parser.new("2 between 1 and 10")
	actual = parser.expression
	expected = Plume::TernaryExpression.new(
		operator: :BETWEEN,
		left: Plume::LiteralExpression.new(value: 2),
		middle: Plume::LiteralExpression.new(value: 1),
		right: Plume::LiteralExpression.new(value: 10)
	)
	assert_equal actual.left.value, expected.left.value
	assert_equal actual.middle.value, expected.middle.value
	assert_equal actual.right.value, expected.right.value
end

test "2 not between 1 and 10" do
	parser = Plume::Parser.new("2 not between 1 and 10")
	actual = parser.expression
	expected = Plume::TernaryExpression.new(
		operator: :NOT_BETWEEN,
		left: Plume::LiteralExpression.new(value: 2),
		middle: Plume::LiteralExpression.new(value: 1),
		right: Plume::LiteralExpression.new(value: 10)
	)
	assert_equal actual.left.value, expected.left.value
	assert_equal actual.middle.value, expected.middle.value
	assert_equal actual.right.value, expected.right.value
end

test "c0 IN (1, 2, 3)" do
	parser = Plume::Parser.new("c0 IN (1, 2, 3)")
	actual = parser.expression
	expected = Plume::BinaryExpression.new(
		operator: :IN,
		left: Plume::ColumnName.new(column: "c0"),
		right: Plume::ParentheticalExpression.new(
			value: [
				Plume::LiteralExpression.new(value: 1),
				Plume::LiteralExpression.new(value: 2),
				Plume::LiteralExpression.new(value: 3),
			]
		)
	)
	assert_equal actual.operator, expected.operator
	assert_equal actual.left.column, expected.left.column
	assert_equal actual.right.value[0].value, expected.right.value[0].value
	assert_equal actual.right.value[1].value, expected.right.value[1].value
	assert_equal actual.right.value[2].value, expected.right.value[2].value
end

test "c0 IN ()" do
	parser = Plume::Parser.new("c0 IN ()")
	actual = parser.expression
	expected = Plume::BinaryExpression.new(
		operator: :IN,
		left: Plume::ColumnName.new(column: "c0"),
		right: Plume::ParentheticalExpression.new(
			value: nil
		)
	)
	assert_equal actual.operator, expected.operator
	assert_equal actual.left.column, expected.left.column
	assert_equal actual.right.value, expected.right.value
end

test "c0 IN tb0" do
	parser = Plume::Parser.new("c0 IN tb0")
	actual = parser.expression
	expected = Plume::BinaryExpression.new(
		operator: :IN,
		left: Plume::ColumnName.new(column: "c0"),
		right: Plume::TableName.new(
			table: "tb0",
		)
	)
	assert_equal actual.operator, expected.operator
	assert_equal actual.left.column, expected.left.column
	assert_equal actual.right.table, expected.right.table
end

test "c0 IN sc0.tb0" do
	parser = Plume::Parser.new("c0 IN sc0.tb0")
	actual = parser.expression
	expected = Plume::BinaryExpression.new(
		operator: :IN,
		left: Plume::ColumnName.new(column: "c0"),
		right: Plume::TableName.new(
			schema: "sc0",
			table: "tb0",
		)
	)
	assert_equal actual.operator, expected.operator
	assert_equal actual.left.column, expected.left.column
	assert_equal actual.right.schema, expected.right.schema
	assert_equal actual.right.table, expected.right.table
end

test "c0 IN foobar()" do
	parser = Plume::Parser.new("c0 IN foobar()")
	actual = parser.expression
	expected = Plume::BinaryExpression.new(
		operator: :IN,
		left: Plume::ColumnName.new(column: "c0"),
		right: Plume::FunctionReference.new(
			function: "foobar",
			arguments: Plume::FunctionArguments.new(
				expressions: [],
			),
		)
	)
	assert_equal actual.operator, expected.operator
	assert_equal actual.left.column, expected.left.column
	assert_equal actual.right.function, expected.right.function
	assert_equal actual.right.arguments.expressions, expected.right.arguments.expressions
end

test "c0 IN sc0.foobar()" do
	parser = Plume::Parser.new("c0 IN sc0.foobar()")
	actual = parser.expression
	expected = Plume::BinaryExpression.new(
		operator: :IN,
		left: Plume::ColumnName.new(column: "c0"),
		right: Plume::FunctionReference.new(
			schema: "sc0",
			function: "foobar",
			arguments: Plume::FunctionArguments.new(
				expressions: [],
			)
		)
	)
	assert_equal actual.operator, expected.operator
	assert_equal actual.left.column, expected.left.column
	assert_equal actual.right.schema, expected.right.schema
	assert_equal actual.right.function, expected.right.function
	assert_equal actual.right.arguments.expressions, expected.right.arguments.expressions
end

test "c0 IN foobar(1, 2, 3)" do
	parser = Plume::Parser.new("c0 IN foobar(1, 2, 3)")
	actual = parser.expression
	expected = Plume::BinaryExpression.new(
		operator: :IN,
		left: Plume::ColumnName.new(column: "c0"),
		right: Plume::FunctionReference.new(
			function: "foobar",
			arguments: Plume::FunctionArguments.new(
				expressions: [1, 2, 3],
			)
		)
	)
	assert_equal actual.operator, expected.operator
	assert_equal actual.left.column, expected.left.column
	assert_equal actual.right.function, expected.right.function
	assert_equal actual.right.arguments.expressions[0].value, expected.right.arguments.expressions[0]
	assert_equal actual.right.arguments.expressions[1].value, expected.right.arguments.expressions[1]
	assert_equal actual.right.arguments.expressions[2].value, expected.right.arguments.expressions[2]
end

test "c0 IN sc0.foobar(1, 2, 3)" do
	parser = Plume::Parser.new("c0 IN sc0.foobar(1, 2, 3)")
	actual = parser.expression
	expected = Plume::BinaryExpression.new(
		operator: :IN,
		left: Plume::ColumnName.new(column: "c0"),
		right: Plume::FunctionReference.new(
			schema: "sc0",
			function: "foobar",
			arguments: Plume::FunctionArguments.new(
				expressions: [1, 2, 3],
			)
		)
	)
	assert_equal actual.operator, expected.operator
	assert_equal actual.left.column, expected.left.column
	assert_equal actual.right.schema, expected.right.schema
	assert_equal actual.right.function, expected.right.function
	assert_equal actual.right.arguments.expressions[0].value, expected.right.arguments.expressions[0]
	assert_equal actual.right.arguments.expressions[1].value, expected.right.arguments.expressions[1]
	assert_equal actual.right.arguments.expressions[2].value, expected.right.arguments.expressions[2]
end

test "c0 NOT IN (1, 2, 3)" do
	parser = Plume::Parser.new("c0 NOT IN (1, 2, 3)")
	actual = parser.expression
	expected = Plume::BinaryExpression.new(
		operator: :NOT_IN,
		left: Plume::ColumnName.new(column: "c0"),
		right: Plume::ParentheticalExpression.new(
			value: [
				Plume::LiteralExpression.new(value: 1),
				Plume::LiteralExpression.new(value: 2),
				Plume::LiteralExpression.new(value: 3),
			]
		)
	)
	assert_equal actual.operator, expected.operator
	assert_equal actual.left.column, expected.left.column
	assert_equal actual.right.value[0].value, expected.right.value[0].value
	assert_equal actual.right.value[1].value, expected.right.value[1].value
	assert_equal actual.right.value[2].value, expected.right.value[2].value
end

test "c0 NOT IN ()" do
	parser = Plume::Parser.new("c0 NOT IN ()")
	actual = parser.expression
	expected = Plume::BinaryExpression.new(
		operator: :NOT_IN,
		left: Plume::ColumnName.new(column: "c0"),
		right: Plume::ParentheticalExpression.new(
			value: nil
		)
	)
	assert_equal actual.operator, expected.operator
	assert_equal actual.left.column, expected.left.column
	assert_equal actual.right.value, expected.right.value
end

test "c0 NOT IN tb0" do
	parser = Plume::Parser.new("c0 NOT IN tb0")
	actual = parser.expression
	expected = Plume::BinaryExpression.new(
		operator: :NOT_IN,
		left: Plume::ColumnName.new(column: "c0"),
		right: Plume::TableName.new(
			table: "tb0",
		)
	)
	assert_equal actual.operator, expected.operator
	assert_equal actual.left.column, expected.left.column
	assert_equal actual.right.table, expected.right.table
end

test "c0 NOT IN sc0.tb0" do
	parser = Plume::Parser.new("c0 NOT IN sc0.tb0")
	actual = parser.expression
	expected = Plume::BinaryExpression.new(
		operator: :NOT_IN,
		left: Plume::ColumnName.new(column: "c0"),
		right: Plume::TableName.new(
			schema: "sc0",
			table: "tb0",
		)
	)
	assert_equal actual.operator, expected.operator
	assert_equal actual.left.column, expected.left.column
	assert_equal actual.right.schema, expected.right.schema
	assert_equal actual.right.table, expected.right.table
end

test "c0 NOT IN foobar()" do
	parser = Plume::Parser.new("c0 NOT IN foobar()")
	actual = parser.expression
	expected = Plume::BinaryExpression.new(
		operator: :NOT_IN,
		left: Plume::ColumnName.new(column: "c0"),
		right: Plume::FunctionReference.new(
			function: "foobar",
			arguments: Plume::FunctionArguments.new(
				expressions: [],
			),
		)
	)
	assert_equal actual.operator, expected.operator
	assert_equal actual.left.column, expected.left.column
	assert_equal actual.right.function, expected.right.function
	assert_equal actual.right.arguments.expressions, expected.right.arguments.expressions
end

test "c0 NOT IN sc0.foobar()" do
	parser = Plume::Parser.new("c0 NOT IN sc0.foobar()")
	actual = parser.expression
	expected = Plume::BinaryExpression.new(
		operator: :NOT_IN,
		left: Plume::ColumnName.new(column: "c0"),
		right: Plume::FunctionReference.new(
			schema: "sc0",
			function: "foobar",
			arguments: Plume::FunctionArguments.new(
				expressions: [],
			)
		)
	)
	assert_equal actual.operator, expected.operator
	assert_equal actual.left.column, expected.left.column
	assert_equal actual.right.schema, expected.right.schema
	assert_equal actual.right.function, expected.right.function
	assert_equal actual.right.arguments.expressions, expected.right.arguments.expressions
end

test "c0 NOT IN foobar(1, 2, 3)" do
	parser = Plume::Parser.new("c0 NOT IN foobar(1, 2, 3)")
	actual = parser.expression
	expected = Plume::BinaryExpression.new(
		operator: :NOT_IN,
		left: Plume::ColumnName.new(column: "c0"),
		right: Plume::FunctionReference.new(
			function: "foobar",
			arguments: Plume::FunctionArguments.new(
				expressions: [1, 2, 3],
			)
		)
	)
	assert_equal actual.operator, expected.operator
	assert_equal actual.left.column, expected.left.column
	assert_equal actual.right.function, expected.right.function
	assert_equal actual.right.arguments.expressions[0].value, expected.right.arguments.expressions[0]
	assert_equal actual.right.arguments.expressions[1].value, expected.right.arguments.expressions[1]
	assert_equal actual.right.arguments.expressions[2].value, expected.right.arguments.expressions[2]
end

test "c0 NOT IN sc0.foobar(1, 2, 3)" do
	parser = Plume::Parser.new("c0 NOT IN sc0.foobar(1, 2, 3)")
	actual = parser.expression
	expected = Plume::BinaryExpression.new(
		operator: :NOT_IN,
		left: Plume::ColumnName.new(column: "c0"),
		right: Plume::FunctionReference.new(
			schema: "sc0",
			function: "foobar",
			arguments: Plume::FunctionArguments.new(
				expressions: [1, 2, 3],
			)
		)
	)
	assert_equal actual.operator, expected.operator
	assert_equal actual.left.column, expected.left.column
	assert_equal actual.right.schema, expected.right.schema
	assert_equal actual.right.function, expected.right.function
	assert_equal actual.right.arguments.expressions[0].value, expected.right.arguments.expressions[0]
	assert_equal actual.right.arguments.expressions[1].value, expected.right.arguments.expressions[1]
	assert_equal actual.right.arguments.expressions[2].value, expected.right.arguments.expressions[2]
end

# -- CASE expressions

test "CASE WHEN c0 > 0 THEN 'Positive' WHEN c0 < 0 THEN 'Negative' ELSE 'Zero' END" do
	parser = Plume::Parser.new("CASE WHEN c0 > 0 THEN 'Positive' WHEN c0 < 0 THEN 'Negative' ELSE 'Zero' END")
	actual = parser.expression
	expected = Plume::CaseExpression.new(
		conditions: [
			Plume::CaseCondition.new(
				predicate: Plume::BinaryExpression.new(
					operator: :ABOVE,
					left: Plume::ColumnName.new(column: "c0"),
					right: Plume::LiteralExpression.new(value: 0)
				),
				consequence: Plume::LiteralExpression.new(value: "Positive")
			),
			Plume::CaseCondition.new(
				predicate: Plume::BinaryExpression.new(
					operator: :BELOW,
					left: Plume::ColumnName.new(column: "c0"),
					right: Plume::LiteralExpression.new(value: 0)
				),
				consequence: Plume::LiteralExpression.new(value: "Negative")
			),
		],
		else_clause: Plume::LiteralExpression.new(value: "Zero")
	)

	assert_equal actual.predicate, expected.predicate
	assert_equal actual.conditions[0].predicate.operator, expected.conditions[0].predicate.operator
	assert_equal actual.conditions[0].predicate.left.column, expected.conditions[0].predicate.left.column
	assert_equal actual.conditions[0].predicate.right.value, expected.conditions[0].predicate.right.value
	assert_equal actual.conditions[0].consequence.value, expected.conditions[0].consequence.value
	assert_equal actual.conditions[1].predicate.operator, expected.conditions[1].predicate.operator
	assert_equal actual.conditions[1].predicate.left.column, expected.conditions[1].predicate.left.column
	assert_equal actual.conditions[1].predicate.right.value, expected.conditions[1].predicate.right.value
	assert_equal actual.conditions[1].consequence.value, expected.conditions[1].consequence.value
	assert_equal actual.else_clause.value, expected.else_clause.value
end

test "CASE WHEN c0 > 0 THEN 'Positive' WHEN c0 < 0 THEN 'Negative' END" do
	parser = Plume::Parser.new("CASE WHEN c0 > 0 THEN 'Positive' WHEN c0 < 0 THEN 'Negative' END")
	actual = parser.expression
	expected = Plume::CaseExpression.new(
		conditions: [
			Plume::CaseCondition.new(
				predicate: Plume::BinaryExpression.new(
					operator: :ABOVE,
					left: Plume::ColumnName.new(column: "c0"),
					right: Plume::LiteralExpression.new(value: 0)
				),
				consequence: Plume::LiteralExpression.new(value: "Positive")
			),
			Plume::CaseCondition.new(
				predicate: Plume::BinaryExpression.new(
					operator: :BELOW,
					left: Plume::ColumnName.new(column: "c0"),
					right: Plume::LiteralExpression.new(value: 0)
				),
				consequence: Plume::LiteralExpression.new(value: "Negative")
			),
		],
	)

	assert_equal actual.predicate, expected.predicate
	assert_equal actual.conditions[0].predicate.operator, expected.conditions[0].predicate.operator
	assert_equal actual.conditions[0].predicate.left.column, expected.conditions[0].predicate.left.column
	assert_equal actual.conditions[0].predicate.right.value, expected.conditions[0].predicate.right.value
	assert_equal actual.conditions[0].consequence.value, expected.conditions[0].consequence.value
	assert_equal actual.conditions[1].predicate.operator, expected.conditions[1].predicate.operator
	assert_equal actual.conditions[1].predicate.left.column, expected.conditions[1].predicate.left.column
	assert_equal actual.conditions[1].predicate.right.value, expected.conditions[1].predicate.right.value
	assert_equal actual.conditions[1].consequence.value, expected.conditions[1].consequence.value
	assert_equal actual.else_clause, expected.else_clause
end

test "CASE x WHEN w1 THEN r1 WHEN w2 THEN r2 ELSE r3 END" do
	parser = Plume::Parser.new("CASE x WHEN w1 THEN r1 WHEN w2 THEN r2 ELSE r3 END")
	actual = parser.expression
	expected = Plume::CaseExpression.new(
		predicate: Plume::ColumnName.new(column: "x"),
		conditions: [
			Plume::CaseCondition.new(
				predicate: Plume::ColumnName.new(column: "w1"),
				consequence: Plume::ColumnName.new(column: "r1")
			),
			Plume::CaseCondition.new(
				predicate: Plume::ColumnName.new(column: "w2"),
				consequence: Plume::ColumnName.new(column: "r2")
			),
		],
		else_clause: Plume::ColumnName.new(column: "r3")
	)

	assert_equal expected.predicate.column, actual.predicate.column
	assert_equal expected.conditions[0].predicate.column, actual.conditions[0].predicate.column
	assert_equal expected.conditions[0].consequence.column, actual.conditions[0].consequence.column
	assert_equal expected.conditions[1].predicate.column, actual.conditions[1].predicate.column
	assert_equal expected.conditions[1].consequence.column, actual.conditions[1].consequence.column
	assert_equal expected.else_clause.column, actual.else_clause.column
end

test "CASE x WHEN w1 THEN r1 WHEN w2 THEN r2 END" do
	parser = Plume::Parser.new("CASE x WHEN w1 THEN r1 WHEN w2 THEN r2 END")
	actual = parser.expression
	expected = Plume::CaseExpression.new(
		predicate: Plume::ColumnName.new(column: "x"),
		conditions: [
			Plume::CaseCondition.new(
				predicate: Plume::ColumnName.new(column: "w1"),
				consequence: Plume::ColumnName.new(column: "r1")
			),
			Plume::CaseCondition.new(
				predicate: Plume::ColumnName.new(column: "w2"),
				consequence: Plume::ColumnName.new(column: "r2")
			),
		],
		else_clause: nil,
	)

	assert_equal actual.predicate.column, expected.predicate.column
	assert_equal actual.conditions[0].predicate.column, expected.conditions[0].predicate.column
	assert_equal actual.conditions[0].consequence.column, expected.conditions[0].consequence.column
	assert_equal actual.conditions[1].predicate.column, expected.conditions[1].predicate.column
	assert_equal actual.conditions[1].consequence.column, expected.conditions[1].consequence.column
	assert_equal actual.else_clause, expected.else_clause
end

# -- CAST expressions

test "CAST(c0 AS int)" do
	parser = Plume::Parser.new("CAST(c0 AS int)")
	actual = parser.expression
	expected = Plume::CastExpression.new(
		expression: Plume::ColumnName.new(column: "c0"),
		as: Plume::ColumnType.new(text: "int"),
	)
	assert_equal actual.expression.column, expected.expression.column
	assert_equal actual.as.text, "int"
	assert_equal actual.as.affinity, :INTEGER
end

test "CAST(c0 AS char)" do
	parser = Plume::Parser.new("CAST(c0 AS char)")
	actual = parser.expression
	expected = Plume::CastExpression.new(
		expression: Plume::ColumnName.new(column: "c0"),
		as: Plume::ColumnType.new(text: "char"),
	)

	assert_equal actual.expression.column, expected.expression.column
	assert_equal actual.as.text, "char"
	assert_equal actual.as.affinity, :TEXT
end

test "CAST(c0 AS blob)" do
	parser = Plume::Parser.new("CAST(c0 AS blob)")
	actual = parser.expression
	expected = Plume::CastExpression.new(
		expression: Plume::ColumnName.new(column: "c0"),
		as: Plume::ColumnType.new(text: "blob"),
	)

	assert_equal actual.expression.column, expected.expression.column
	assert_equal actual.as.text, "blob"
	assert_equal actual.as.affinity, :BLOB
end

test "CAST(c0 AS real)" do
	parser = Plume::Parser.new("CAST(c0 AS real)")
	actual = parser.expression
	expected = Plume::CastExpression.new(
		expression: Plume::ColumnName.new(column: "c0"),
		as: Plume::ColumnType.new(text: "real"),
	)

	assert_equal actual.expression.column, expected.expression.column
	assert_equal actual.as.text, "real"
	assert_equal actual.as.affinity, :REAL
end

test "CAST(c0 AS any)" do
	parser = Plume::Parser.new("CAST(c0 AS any)")
	actual = parser.expression
	expected = Plume::CastExpression.new(
		expression: Plume::ColumnName.new(column: "c0"),
		as: Plume::ColumnType.new(text: "any"),
	)

	assert_equal actual.expression.column, expected.expression.column
	assert_equal actual.as.text, "any"
	assert_equal actual.as.affinity, :ANY
end

test "CAST(c0 AS decimal(4, 6))" do
	parser = Plume::Parser.new("CAST(c0 AS decimal(4, 6))")
	actual = parser.expression
	expected = Plume::CastExpression.new(
		expression: Plume::ColumnName.new(column: "c0"),
		as: Plume::ColumnType.new(text: "decimal(4, 6)"),
	)

	assert_equal actual.expression.column, expected.expression.column
	assert_equal actual.as.text, "decimal(4, 6)"
	assert_equal actual.as.affinity, :ANY
end

# -- function calls

test "CHANGES()" do
	parser = Plume::Parser.new("CHANGES()")
	actual = parser.expression
	expected = Plume::FunctionReference.new(
		function: "CHANGES",
		arguments: Plume::EmptyFunctionArgument.new
	)
	assert_equal actual.function, expected.function
	assert_equal actual.arguments, expected.arguments
end

test "ABS(-1)" do
	parser = Plume::Parser.new("ABS(-1)")
	actual = parser.expression
	expected = Plume::FunctionReference.new(
		function: "ABS",
		arguments: Plume::FunctionArguments.new(
			expressions: [
				Plume::UnaryExpression.new(
					operator: :NEGATE,
					operand: Plume::LiteralExpression.new(
						value: 1
					)
				),
			]
		)
	)
	assert_equal actual.function, expected.function
	assert_equal actual.arguments.expressions[0].operator, expected.arguments.expressions[0].operator
	assert_equal actual.arguments.expressions[0].operand.value, expected.arguments.expressions[0].operand.value
end

test "COUNT(*)" do
	parser = Plume::Parser.new("COUNT(*)")
	actual = parser.expression
	expected = Plume::FunctionReference.new(
		function: "COUNT",
		arguments: Plume::StarFunctionArgument.new
	)
	assert_equal actual.function, expected.function
	assert_equal actual.arguments, expected.arguments
end

test "COUNT(*) FILTER (WHERE c0 > 0)" do
	parser = Plume::Parser.new("COUNT(*) FILTER (WHERE c0 > 0)")
	actual = parser.expression
	expected = Plume::FunctionReference.new(
		function: "COUNT",
		arguments: Plume::StarFunctionArgument.new,
		filter_clause: Plume::BinaryExpression.new(
			operator: :ABOVE,
			left: Plume::ColumnName.new(column: "c0"),
			right: Plume::LiteralExpression.new(
				value: 0
			)
		)
	)
	assert_equal actual.function, expected.function
	assert_equal actual.arguments, expected.arguments
	assert_equal actual.filter_clause.operator, expected.filter_clause.operator
	assert_equal actual.filter_clause.left.column, expected.filter_clause.left.column
	assert_equal actual.filter_clause.right.value, expected.filter_clause.right.value
end

test "COUNT(DISTINCT c0)" do
	parser = Plume::Parser.new("COUNT(DISTINCT c0)")
	actual = parser.expression
	expected = Plume::FunctionReference.new(
		function: "COUNT",
		arguments: Plume::FunctionArguments.new(
			distinct: true,
			expressions: [
				Plume::ColumnName.new(column: "c0"),
			]
		)
	)
	assert_equal actual.function, expected.function
	assert_equal actual.arguments.distinct, expected.arguments.distinct
	assert_equal actual.arguments.expressions[0].column, expected.arguments.expressions[0].column
end

test "COUNT(DISTINCT c0, c1)" do
	parser = Plume::Parser.new("COUNT(DISTINCT c0, c1)")
	actual = parser.expression
	expected = Plume::FunctionReference.new(
		function: "COUNT",
		arguments: Plume::FunctionArguments.new(
			distinct: true,
			expressions: [
				Plume::ColumnName.new(column: "c0"),
				Plume::ColumnName.new(column: "c1"),
			]
		)
	)
	assert_equal actual.function, expected.function
	assert_equal actual.arguments.distinct, expected.arguments.distinct
	assert_equal actual.arguments.expressions[0].column, expected.arguments.expressions[0].column
	assert_equal actual.arguments.expressions[1].column, expected.arguments.expressions[1].column
end

test "COUNT(DISTINCT c0, c1 ORDER BY c0)" do
	parser = Plume::Parser.new("COUNT(DISTINCT c0, c1 ORDER BY c0)")
	actual = parser.expression
	expected = Plume::FunctionReference.new(
		function: "COUNT",
		arguments: Plume::FunctionArguments.new(
			distinct: true,
			expressions: [
				Plume::ColumnName.new(column: "c0"),
				Plume::ColumnName.new(column: "c1"),
			],
			order_by: [
				Plume::OrderingTerm.new(
					expression: Plume::ColumnName.new(column: "c0")
				),
			]
		)
	)
	assert_equal actual.function, expected.function
	assert_equal actual.arguments.distinct, expected.arguments.distinct
	assert_equal actual.arguments.expressions[0].column, expected.arguments.expressions[0].column
	assert_equal actual.arguments.expressions[1].column, expected.arguments.expressions[1].column
	assert_equal actual.arguments.order_by[0].expression.column, expected.arguments.order_by[0].expression.column
end

test "COUNT(DISTINCT c0, c1 ORDER BY c0 DESC)" do
	parser = Plume::Parser.new("COUNT(DISTINCT c0, c1 ORDER BY c0 DESC)")
	actual = parser.expression
	expected = Plume::FunctionReference.new(
		function: "COUNT",
		arguments: Plume::FunctionArguments.new(
			distinct: true,
			expressions: [
				Plume::ColumnName.new(column: "c0"),
				Plume::ColumnName.new(column: "c1"),
			],
			order_by: [
				Plume::OrderingTerm.new(
					expression: Plume::ColumnName.new(column: "c0"),
					direction: :DESC,
				),
			]
		)
	)
	assert_equal actual.function, expected.function
	assert_equal actual.arguments.distinct, expected.arguments.distinct
	assert_equal actual.arguments.expressions[0].column, expected.arguments.expressions[0].column
	assert_equal actual.arguments.expressions[1].column, expected.arguments.expressions[1].column
	assert_equal actual.arguments.order_by[0].expression.column, expected.arguments.order_by[0].expression.column
	assert_equal actual.arguments.order_by[0].direction, expected.arguments.order_by[0].direction
end

test "COUNT(DISTINCT c0, c1 ORDER BY c0 DESC NULLS LAST)" do
	parser = Plume::Parser.new("COUNT(DISTINCT c0, c1 ORDER BY c0 DESC NULLS LAST)")
	actual = parser.expression
	expected = Plume::FunctionReference.new(
		function: "COUNT",
		arguments: Plume::FunctionArguments.new(
			distinct: true,
			expressions: [
				Plume::ColumnName.new(column: "c0"),
				Plume::ColumnName.new(column: "c1"),
			],
			order_by: [
				Plume::OrderingTerm.new(
					expression: Plume::ColumnName.new(column: "c0"),
					direction: :DESC,
					nulls: :LAST,
				),
			]
		)
	)
	assert_equal actual.function, expected.function
	assert_equal actual.arguments.distinct, expected.arguments.distinct
	assert_equal actual.arguments.expressions[0].column, expected.arguments.expressions[0].column
	assert_equal actual.arguments.expressions[1].column, expected.arguments.expressions[1].column
	assert_equal actual.arguments.order_by[0].expression.column, expected.arguments.order_by[0].expression.column
	assert_equal actual.arguments.order_by[0].direction, expected.arguments.order_by[0].direction
	assert_equal actual.arguments.order_by[0].nulls, expected.arguments.order_by[0].nulls
end

test "COUNT(DISTINCT c0, c1 ORDER BY c0 DESC NULLS FIRST)" do
	parser = Plume::Parser.new("COUNT(DISTINCT c0, c1 ORDER BY c0 DESC NULLS FIRST)")
	actual = parser.expression
	expected = Plume::FunctionReference.new(
		function: "COUNT",
		arguments: Plume::FunctionArguments.new(
			distinct: true,
			expressions: [
				Plume::ColumnName.new(column: "c0"),
				Plume::ColumnName.new(column: "c1"),
			],
			order_by: [
				Plume::OrderingTerm.new(
					expression: Plume::ColumnName.new(column: "c0"),
					direction: :DESC,
					nulls: :FIRST,
				),
			]
		)
	)
	assert_equal actual.function, expected.function
	assert_equal actual.arguments.distinct, expected.arguments.distinct
	assert_equal actual.arguments.expressions[0].column, expected.arguments.expressions[0].column
	assert_equal actual.arguments.expressions[1].column, expected.arguments.expressions[1].column
	assert_equal actual.arguments.order_by[0].expression.column, expected.arguments.order_by[0].expression.column
	assert_equal actual.arguments.order_by[0].direction, expected.arguments.order_by[0].direction
	assert_equal actual.arguments.order_by[0].nulls, expected.arguments.order_by[0].nulls
end

test "COUNT(c0)" do
	parser = Plume::Parser.new("COUNT(c0)")
	actual = parser.expression
	expected = Plume::FunctionReference.new(
		function: "COUNT",
		arguments: Plume::FunctionArguments.new(
			expressions: [
				Plume::ColumnName.new(column: "c0"),
			]
		)
	)
	assert_equal actual.function, expected.function
	assert_equal actual.arguments.distinct, expected.arguments.distinct
	assert_equal actual.arguments.expressions[0].column, expected.arguments.expressions[0].column
end

test "COUNT(c0, c1)" do
	parser = Plume::Parser.new("COUNT(c0, c1)")
	actual = parser.expression
	expected = Plume::FunctionReference.new(
		function: "COUNT",
		arguments: Plume::FunctionArguments.new(
			expressions: [
				Plume::ColumnName.new(column: "c0"),
				Plume::ColumnName.new(column: "c1"),
			]
		)
	)
	assert_equal actual.function, expected.function
	assert_equal actual.arguments.distinct, expected.arguments.distinct
	assert_equal actual.arguments.expressions[0].column, expected.arguments.expressions[0].column
	assert_equal actual.arguments.expressions[1].column, expected.arguments.expressions[1].column
end

test "COUNT(c0, c1 ORDER BY c0)" do
	parser = Plume::Parser.new("COUNT(c0, c1 ORDER BY c0)")
	actual = parser.expression
	expected = Plume::FunctionReference.new(
		function: "COUNT",
		arguments: Plume::FunctionArguments.new(
			expressions: [
				Plume::ColumnName.new(column: "c0"),
				Plume::ColumnName.new(column: "c1"),
			],
			order_by: [
				Plume::OrderingTerm.new(
					expression: Plume::ColumnName.new(column: "c0")
				),
			]
		)
	)
	assert_equal actual.function, expected.function
	assert_equal actual.arguments.distinct, expected.arguments.distinct
	assert_equal actual.arguments.expressions[0].column, expected.arguments.expressions[0].column
	assert_equal actual.arguments.expressions[1].column, expected.arguments.expressions[1].column
	assert_equal actual.arguments.order_by[0].expression.column, expected.arguments.order_by[0].expression.column
end

test "COUNT(c0, c1 ORDER BY c0 DESC)" do
	parser = Plume::Parser.new("COUNT(c0, c1 ORDER BY c0 DESC)")
	actual = parser.expression
	expected = Plume::FunctionReference.new(
		function: "COUNT",
		arguments: Plume::FunctionArguments.new(
			expressions: [
				Plume::ColumnName.new(column: "c0"),
				Plume::ColumnName.new(column: "c1"),
			],
			order_by: [
				Plume::OrderingTerm.new(
					expression: Plume::ColumnName.new(column: "c0"),
					direction: :DESC,
				),
			]
		)
	)
	assert_equal actual.function, expected.function
	assert_equal actual.arguments.distinct, expected.arguments.distinct
	assert_equal actual.arguments.expressions[0].column, expected.arguments.expressions[0].column
	assert_equal actual.arguments.expressions[1].column, expected.arguments.expressions[1].column
	assert_equal actual.arguments.order_by[0].expression.column, expected.arguments.order_by[0].expression.column
	assert_equal actual.arguments.order_by[0].direction, expected.arguments.order_by[0].direction
end

test "COUNT(c0, c1 ORDER BY c0 DESC NULLS LAST)" do
	parser = Plume::Parser.new("COUNT(c0, c1 ORDER BY c0 DESC NULLS LAST)")
	actual = parser.expression
	expected = Plume::FunctionReference.new(
		function: "COUNT",
		arguments: Plume::FunctionArguments.new(
			expressions: [
				Plume::ColumnName.new(column: "c0"),
				Plume::ColumnName.new(column: "c1"),
			],
			order_by: [
				Plume::OrderingTerm.new(
					expression: Plume::ColumnName.new(column: "c0"),
					direction: :DESC,
					nulls: :LAST,
				),
			]
		)
	)
	assert_equal actual.function, expected.function
	assert_equal actual.arguments.distinct, expected.arguments.distinct
	assert_equal actual.arguments.expressions[0].column, expected.arguments.expressions[0].column
	assert_equal actual.arguments.expressions[1].column, expected.arguments.expressions[1].column
	assert_equal actual.arguments.order_by[0].expression.column, expected.arguments.order_by[0].expression.column
	assert_equal actual.arguments.order_by[0].direction, expected.arguments.order_by[0].direction
	assert_equal actual.arguments.order_by[0].nulls, expected.arguments.order_by[0].nulls
end

test "COUNT(c0, c1 ORDER BY c0 DESC NULLS FIRST)" do
	parser = Plume::Parser.new("COUNT(c0, c1 ORDER BY c0 DESC NULLS FIRST)")
	actual = parser.expression
	expected = Plume::FunctionReference.new(
		function: "COUNT",
		arguments: Plume::FunctionArguments.new(
			expressions: [
				Plume::ColumnName.new(column: "c0"),
				Plume::ColumnName.new(column: "c1"),
			],
			order_by: [
				Plume::OrderingTerm.new(
					expression: Plume::ColumnName.new(column: "c0"),
					direction: :DESC,
					nulls: :FIRST,
				),
			]
		)
	)
	assert_equal actual.function, expected.function
	assert_equal actual.arguments.distinct, expected.arguments.distinct
	assert_equal actual.arguments.expressions[0].column, expected.arguments.expressions[0].column
	assert_equal actual.arguments.expressions[1].column, expected.arguments.expressions[1].column
	assert_equal actual.arguments.order_by[0].expression.column, expected.arguments.order_by[0].expression.column
	assert_equal actual.arguments.order_by[0].direction, expected.arguments.order_by[0].direction
	assert_equal actual.arguments.order_by[0].nulls, expected.arguments.order_by[0].nulls
end

test "ROW_NUMBER() OVER ()" do
	parser = Plume::Parser.new("ROW_NUMBER() OVER ()")
	actual = parser.expression
	expected = Plume::FunctionReference.new(
		function: "ROW_NUMBER",
		arguments: Plume::EmptyFunctionArgument.new,
		over_clause: Plume::OverClause.new
	)
	assert_equal actual.function, expected.function
	assert_equal actual.arguments, expected.arguments
	assert_equal actual.over_clause.base_window_name, expected.over_clause.base_window_name
end

test "ROW_NUMBER() OVER win1" do
	parser = Plume::Parser.new("ROW_NUMBER() OVER win1")
	actual = parser.expression
	expected = Plume::FunctionReference.new(
		function: "ROW_NUMBER",
		arguments: Plume::EmptyFunctionArgument.new,
		over_clause: Plume::OverClause.new(
			window_name: "win1"
		)
	)
	assert_equal actual.function, expected.function
	assert_equal actual.arguments, expected.arguments
	assert_equal actual.over_clause.window_name, expected.over_clause.window_name
end

test "ROW_NUMBER() OVER (PARTITION BY y)" do
	parser = Plume::Parser.new("ROW_NUMBER() OVER (PARTITION BY y)")
	actual = parser.expression
	expected = Plume::FunctionReference.new(
		function: "ROW_NUMBER",
		arguments: Plume::EmptyFunctionArgument.new,
		over_clause: Plume::OverClause.new(
			partitions: [
				Plume::ColumnName.new(column: "y"),
			]
		)
	)
	assert_equal actual.function, expected.function
	assert_equal actual.arguments, expected.arguments
	assert_equal actual.over_clause.partitions[0].column, expected.over_clause.partitions[0].column
end

test "ROW_NUMBER() OVER (ORDER BY y)" do
	parser = Plume::Parser.new("ROW_NUMBER() OVER (ORDER BY y)")
	actual = parser.expression
	expected = Plume::FunctionReference.new(
		function: "ROW_NUMBER",
		arguments: Plume::EmptyFunctionArgument.new,
		over_clause: Plume::OverClause.new(
			orderings: [
				Plume::OrderingTerm.new(
					expression: Plume::ColumnName.new(column: "y")
				),
			]
		)
	)
	assert_equal actual.function, expected.function
	assert_equal actual.arguments, expected.arguments
	assert_equal actual.over_clause.orderings[0].expression.column, expected.over_clause.orderings[0].expression.column
end

test "ROW_NUMBER() OVER (RANGE UNBOUNDED PRECEDING)" do
	parser = Plume::Parser.new("ROW_NUMBER() OVER (RANGE UNBOUNDED PRECEDING)")
	actual = parser.expression
	expected = Plume::FunctionReference.new(
		function: "ROW_NUMBER",
		arguments: Plume::EmptyFunctionArgument.new,
		over_clause: Plume::OverClause.new(
			frame: Plume::FrameSpec.new(
				type: :RANGE,
				starting_boundary: Plume::FrameBoundary.new(
					type: :PRECEDING,
					value: :UNBOUNDED
				),
			)
		)
	)
	assert_equal actual.function, expected.function
	assert_equal actual.arguments, expected.arguments
	assert_equal actual.over_clause.frame.type, expected.over_clause.frame.type
	assert_equal actual.over_clause.frame.starting_boundary.type, expected.over_clause.frame.starting_boundary.type
	assert_equal actual.over_clause.frame.starting_boundary.value, expected.over_clause.frame.starting_boundary.value
end

test "ROW_NUMBER() OVER (ROWS UNBOUNDED PRECEDING)" do
	parser = Plume::Parser.new("ROW_NUMBER() OVER (ROWS UNBOUNDED PRECEDING)")
	actual = parser.expression
	expected = Plume::FunctionReference.new(
		function: "ROW_NUMBER",
		arguments: Plume::EmptyFunctionArgument.new,
		over_clause: Plume::OverClause.new(
			frame: Plume::FrameSpec.new(
				type: :ROWS,
				starting_boundary: Plume::FrameBoundary.new(
					type: :PRECEDING,
					value: :UNBOUNDED
				),
			)
		)
	)
	assert_equal actual.function, expected.function
	assert_equal actual.arguments, expected.arguments
	assert_equal actual.over_clause.frame.type, expected.over_clause.frame.type
	assert_equal actual.over_clause.frame.starting_boundary.type, expected.over_clause.frame.starting_boundary.type
	assert_equal actual.over_clause.frame.starting_boundary.value, expected.over_clause.frame.starting_boundary.value
end

test "ROW_NUMBER() OVER (GROUPS UNBOUNDED PRECEDING)" do
	parser = Plume::Parser.new("ROW_NUMBER() OVER (GROUPS UNBOUNDED PRECEDING)")
	actual = parser.expression
	expected = Plume::FunctionReference.new(
		function: "ROW_NUMBER",
		arguments: Plume::EmptyFunctionArgument.new,
		over_clause: Plume::OverClause.new(
			frame: Plume::FrameSpec.new(
				type: :GROUPS,
				starting_boundary: Plume::FrameBoundary.new(
					type: :PRECEDING,
					value: :UNBOUNDED
				),
			)
		)
	)
	assert_equal actual.function, expected.function
	assert_equal actual.arguments, expected.arguments
	assert_equal actual.over_clause.frame.type, expected.over_clause.frame.type
	assert_equal actual.over_clause.frame.starting_boundary.type, expected.over_clause.frame.starting_boundary.type
	assert_equal actual.over_clause.frame.starting_boundary.value, expected.over_clause.frame.starting_boundary.value
end

test "ROW_NUMBER() OVER (ROWS CURRENT ROW)" do
	parser = Plume::Parser.new("ROW_NUMBER() OVER (ROWS CURRENT ROW)")
	actual = parser.expression
	expected = Plume::FunctionReference.new(
		function: "ROW_NUMBER",
		arguments: Plume::EmptyFunctionArgument.new,
		over_clause: Plume::OverClause.new(
			frame: Plume::FrameSpec.new(
				type: :ROWS,
				starting_boundary: Plume::FrameBoundary.new(
					type: :CURRENT_ROW,
				),
			)
		)
	)
	assert_equal actual.function, expected.function
	assert_equal actual.arguments, expected.arguments
	assert_equal actual.over_clause.frame.type, expected.over_clause.frame.type
	assert_equal actual.over_clause.frame.starting_boundary.type, expected.over_clause.frame.starting_boundary.type
end

test "ROW_NUMBER() OVER (ROWS 123 PRECEDING)" do
	parser = Plume::Parser.new("ROW_NUMBER() OVER (ROWS 123 PRECEDING)")
	actual = parser.expression
	expected = Plume::FunctionReference.new(
		function: "ROW_NUMBER",
		arguments: Plume::EmptyFunctionArgument.new,
		over_clause: Plume::OverClause.new(
			frame: Plume::FrameSpec.new(
				type: :ROWS,
				starting_boundary: Plume::FrameBoundary.new(
					type: :PRECEDING,
					value: Plume::LiteralExpression.new(
						value: 123,
					)
				),
			)
		)
	)
	assert_equal actual.function, expected.function
	assert_equal actual.arguments, expected.arguments
	assert_equal actual.over_clause.frame.type, expected.over_clause.frame.type
	assert_equal actual.over_clause.frame.starting_boundary.type, expected.over_clause.frame.starting_boundary.type
	assert_equal actual.over_clause.frame.starting_boundary.value.value, expected.over_clause.frame.starting_boundary.value.value
end

test "ROW_NUMBER() OVER (ROWS BETWEEN UNBOUNDED PRECEDING AND 123 PRECEDING)" do
	parser = Plume::Parser.new("ROW_NUMBER() OVER (ROWS BETWEEN UNBOUNDED PRECEDING AND 123 PRECEDING)")
	actual = parser.expression
	expected = Plume::FunctionReference.new(
		function: "ROW_NUMBER",
		arguments: Plume::EmptyFunctionArgument.new,
		over_clause: Plume::OverClause.new(
			frame: Plume::FrameSpec.new(
				type: :ROWS,
				starting_boundary: Plume::FrameBoundary.new(
					type: :PRECEDING,
					value: :UNBOUNDED
				),
				ending_boundary: Plume::FrameBoundary.new(
					type: :PRECEDING,
					value: Plume::LiteralExpression.new(
						value: 123,
					)
				),
			)
		)
	)
	assert_equal actual.function, expected.function
	assert_equal actual.arguments, expected.arguments
	assert_equal actual.over_clause.frame.type, expected.over_clause.frame.type
	assert_equal actual.over_clause.frame.starting_boundary.type, expected.over_clause.frame.starting_boundary.type
	assert_equal actual.over_clause.frame.starting_boundary.value, expected.over_clause.frame.starting_boundary.value
	assert_equal actual.over_clause.frame.ending_boundary.type, expected.over_clause.frame.ending_boundary.type
	assert_equal actual.over_clause.frame.ending_boundary.value.value, expected.over_clause.frame.ending_boundary.value.value
end

test "ROW_NUMBER() OVER (ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)" do
	parser = Plume::Parser.new("ROW_NUMBER() OVER (ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)")
	actual = parser.expression
	expected = Plume::FunctionReference.new(
		function: "ROW_NUMBER",
		arguments: Plume::EmptyFunctionArgument.new,
		over_clause: Plume::OverClause.new(
			frame: Plume::FrameSpec.new(
				type: :ROWS,
				starting_boundary: Plume::FrameBoundary.new(
					type: :PRECEDING,
					value: :UNBOUNDED
				),
				ending_boundary: Plume::FrameBoundary.new(
					type: :CURRENT_ROW,
				),
			)
		)
	)
	assert_equal actual.function, expected.function
	assert_equal actual.arguments, expected.arguments
	assert_equal actual.over_clause.frame.type, expected.over_clause.frame.type
	assert_equal actual.over_clause.frame.starting_boundary.type, expected.over_clause.frame.starting_boundary.type
	assert_equal actual.over_clause.frame.starting_boundary.value, expected.over_clause.frame.starting_boundary.value
	assert_equal actual.over_clause.frame.ending_boundary.type, expected.over_clause.frame.ending_boundary.type
end

test "ROW_NUMBER() OVER (ROWS BETWEEN UNBOUNDED PRECEDING AND 123 FOLLOWING)" do
	parser = Plume::Parser.new("ROW_NUMBER() OVER (ROWS BETWEEN UNBOUNDED PRECEDING AND 123 FOLLOWING)")
	actual = parser.expression
	expected = Plume::FunctionReference.new(
		function: "ROW_NUMBER",
		arguments: Plume::EmptyFunctionArgument.new,
		over_clause: Plume::OverClause.new(
			frame: Plume::FrameSpec.new(
				type: :ROWS,
				starting_boundary: Plume::FrameBoundary.new(
					type: :PRECEDING,
					value: :UNBOUNDED
				),
				ending_boundary: Plume::FrameBoundary.new(
					type: :FOLLOWING,
					value: Plume::LiteralExpression.new(
						value: 123,
					)
				),
			)
		)
	)
	assert_equal actual.function, expected.function
	assert_equal actual.arguments, expected.arguments
	assert_equal actual.over_clause.frame.type, expected.over_clause.frame.type
	assert_equal actual.over_clause.frame.starting_boundary.type, expected.over_clause.frame.starting_boundary.type
	assert_equal actual.over_clause.frame.starting_boundary.value, expected.over_clause.frame.starting_boundary.value
	assert_equal actual.over_clause.frame.ending_boundary.type, expected.over_clause.frame.ending_boundary.type
	assert_equal actual.over_clause.frame.ending_boundary.value.value, expected.over_clause.frame.ending_boundary.value.value
end

test "ROW_NUMBER() OVER (ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING)" do
	parser = Plume::Parser.new("ROW_NUMBER() OVER (ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING)")
	actual = parser.expression
	expected = Plume::FunctionReference.new(
		function: "ROW_NUMBER",
		arguments: Plume::EmptyFunctionArgument.new,
		over_clause: Plume::OverClause.new(
			frame: Plume::FrameSpec.new(
				type: :ROWS,
				starting_boundary: Plume::FrameBoundary.new(
					type: :PRECEDING,
					value: :UNBOUNDED
				),
				ending_boundary: Plume::FrameBoundary.new(
					type: :FOLLOWING,
					value: :UNBOUNDED
				),
			)
		)
	)
	assert_equal actual.function, expected.function
	assert_equal actual.arguments, expected.arguments
	assert_equal actual.over_clause.frame.type, expected.over_clause.frame.type
	assert_equal actual.over_clause.frame.starting_boundary.type, expected.over_clause.frame.starting_boundary.type
	assert_equal actual.over_clause.frame.starting_boundary.value, expected.over_clause.frame.starting_boundary.value
	assert_equal actual.over_clause.frame.ending_boundary.type, expected.over_clause.frame.ending_boundary.type
	assert_equal actual.over_clause.frame.ending_boundary.value, expected.over_clause.frame.ending_boundary.value
end

test "ROW_NUMBER() OVER (ROWS BETWEEN 123 PRECEDING AND 123 PRECEDING)" do
	parser = Plume::Parser.new("ROW_NUMBER() OVER (ROWS BETWEEN 123 PRECEDING AND 123 PRECEDING)")
	actual = parser.expression
	expected = Plume::FunctionReference.new(
		function: "ROW_NUMBER",
		arguments: Plume::EmptyFunctionArgument.new,
		over_clause: Plume::OverClause.new(
			frame: Plume::FrameSpec.new(
				type: :ROWS,
				starting_boundary: Plume::FrameBoundary.new(
					type: :PRECEDING,
					value: Plume::LiteralExpression.new(
						value: 123,
					)
				),
				ending_boundary: Plume::FrameBoundary.new(
					type: :PRECEDING,
					value: Plume::LiteralExpression.new(
						value: 123,
					)
				),
			)
		)
	)
	assert_equal actual.function, expected.function
	assert_equal actual.arguments, expected.arguments
	assert_equal actual.over_clause.frame.type, expected.over_clause.frame.type
	assert_equal actual.over_clause.frame.starting_boundary.type, expected.over_clause.frame.starting_boundary.type
	assert_equal actual.over_clause.frame.starting_boundary.value.value, expected.over_clause.frame.starting_boundary.value.value
	assert_equal actual.over_clause.frame.ending_boundary.type, expected.over_clause.frame.ending_boundary.type
	assert_equal actual.over_clause.frame.ending_boundary.value.value, expected.over_clause.frame.ending_boundary.value.value
end

test "ROW_NUMBER() OVER (ROWS BETWEEN 123 PRECEDING AND CURRENT ROW)" do
	parser = Plume::Parser.new("ROW_NUMBER() OVER (ROWS BETWEEN 123 PRECEDING AND CURRENT ROW)")
	actual = parser.expression
	expected = Plume::FunctionReference.new(
		function: "ROW_NUMBER",
		arguments: Plume::EmptyFunctionArgument.new,
		over_clause: Plume::OverClause.new(
			frame: Plume::FrameSpec.new(
				type: :ROWS,
				starting_boundary: Plume::FrameBoundary.new(
					type: :PRECEDING,
					value: Plume::LiteralExpression.new(
						value: 123,
					)
				),
				ending_boundary: Plume::FrameBoundary.new(
					type: :CURRENT_ROW,
				),
			)
		)
	)
	assert_equal actual.function, expected.function
	assert_equal actual.arguments, expected.arguments
	assert_equal actual.over_clause.frame.type, expected.over_clause.frame.type
	assert_equal actual.over_clause.frame.starting_boundary.type, expected.over_clause.frame.starting_boundary.type
	assert_equal actual.over_clause.frame.starting_boundary.value.value, expected.over_clause.frame.starting_boundary.value.value
	assert_equal actual.over_clause.frame.ending_boundary.type, expected.over_clause.frame.ending_boundary.type
end

test "ROW_NUMBER() OVER (ROWS BETWEEN 123 PRECEDING AND 123 FOLLOWING)" do
	parser = Plume::Parser.new("ROW_NUMBER() OVER (ROWS BETWEEN 123 PRECEDING AND 123 FOLLOWING)")
	actual = parser.expression
	expected = Plume::FunctionReference.new(
		function: "ROW_NUMBER",
		arguments: Plume::EmptyFunctionArgument.new,
		over_clause: Plume::OverClause.new(
			frame: Plume::FrameSpec.new(
				type: :ROWS,
				starting_boundary: Plume::FrameBoundary.new(
					type: :PRECEDING,
					value: Plume::LiteralExpression.new(
						value: 123,
					)
				),
				ending_boundary: Plume::FrameBoundary.new(
					type: :FOLLOWING,
					value: Plume::LiteralExpression.new(
						value: 123,
					)
				),
			)
		)
	)
	assert_equal actual.function, expected.function
	assert_equal actual.arguments, expected.arguments
	assert_equal actual.over_clause.frame.type, expected.over_clause.frame.type
	assert_equal actual.over_clause.frame.starting_boundary.type, expected.over_clause.frame.starting_boundary.type
	assert_equal actual.over_clause.frame.starting_boundary.value.value, expected.over_clause.frame.starting_boundary.value.value
	assert_equal actual.over_clause.frame.ending_boundary.type, expected.over_clause.frame.ending_boundary.type
	assert_equal actual.over_clause.frame.ending_boundary.value.value, expected.over_clause.frame.ending_boundary.value.value
end

test "ROW_NUMBER() OVER (ROWS BETWEEN 123 PRECEDING AND UNBOUNDED FOLLOWING)" do
	parser = Plume::Parser.new("ROW_NUMBER() OVER (ROWS BETWEEN 123 PRECEDING AND UNBOUNDED FOLLOWING)")
	actual = parser.expression
	expected = Plume::FunctionReference.new(
		function: "ROW_NUMBER",
		arguments: Plume::EmptyFunctionArgument.new,
		over_clause: Plume::OverClause.new(
			frame: Plume::FrameSpec.new(
				type: :ROWS,
				starting_boundary: Plume::FrameBoundary.new(
					type: :PRECEDING,
					value: Plume::LiteralExpression.new(
						value: 123,
					)
				),
				ending_boundary: Plume::FrameBoundary.new(
					type: :FOLLOWING,
					value: :UNBOUNDED
				),
			)
		)
	)
	assert_equal actual.function, expected.function
	assert_equal actual.arguments, expected.arguments
	assert_equal actual.over_clause.frame.type, expected.over_clause.frame.type
	assert_equal actual.over_clause.frame.starting_boundary.type, expected.over_clause.frame.starting_boundary.type
	assert_equal actual.over_clause.frame.starting_boundary.value.value, expected.over_clause.frame.starting_boundary.value.value
	assert_equal actual.over_clause.frame.ending_boundary.type, expected.over_clause.frame.ending_boundary.type
	assert_equal actual.over_clause.frame.ending_boundary.value, expected.over_clause.frame.ending_boundary.value
end

test "ROW_NUMBER() OVER (ROWS BETWEEN CURRENT ROW AND CURRENT ROW)" do
	parser = Plume::Parser.new("ROW_NUMBER() OVER (ROWS BETWEEN CURRENT ROW AND CURRENT ROW)")
	actual = parser.expression
	expected = Plume::FunctionReference.new(
		function: "ROW_NUMBER",
		arguments: Plume::EmptyFunctionArgument.new,
		over_clause: Plume::OverClause.new(
			frame: Plume::FrameSpec.new(
				type: :ROWS,
				starting_boundary: Plume::FrameBoundary.new(
					type: :CURRENT_ROW,
				),
				ending_boundary: Plume::FrameBoundary.new(
					type: :CURRENT_ROW,
				),
			)
		)
	)
	assert_equal actual.function, expected.function
	assert_equal actual.arguments, expected.arguments
	assert_equal actual.over_clause.frame.type, expected.over_clause.frame.type
	assert_equal actual.over_clause.frame.starting_boundary.type, expected.over_clause.frame.starting_boundary.type
	assert_equal actual.over_clause.frame.ending_boundary.type, expected.over_clause.frame.ending_boundary.type
end

test "ROW_NUMBER() OVER (ROWS BETWEEN CURRENT ROW AND 123 FOLLOWING)" do
	parser = Plume::Parser.new("ROW_NUMBER() OVER (ROWS BETWEEN CURRENT ROW AND 123 FOLLOWING)")
	actual = parser.expression
	expected = Plume::FunctionReference.new(
		function: "ROW_NUMBER",
		arguments: Plume::EmptyFunctionArgument.new,
		over_clause: Plume::OverClause.new(
			frame: Plume::FrameSpec.new(
				type: :ROWS,
				starting_boundary: Plume::FrameBoundary.new(
					type: :CURRENT_ROW,
				),
				ending_boundary: Plume::FrameBoundary.new(
					type: :FOLLOWING,
					value: Plume::LiteralExpression.new(
						value: 123,
					)
				),
			)
		)
	)
	assert_equal actual.function, expected.function
	assert_equal actual.arguments, expected.arguments
	assert_equal actual.over_clause.frame.type, expected.over_clause.frame.type
	assert_equal actual.over_clause.frame.starting_boundary.type, expected.over_clause.frame.starting_boundary.type
	assert_equal actual.over_clause.frame.ending_boundary.type, expected.over_clause.frame.ending_boundary.type
	assert_equal actual.over_clause.frame.ending_boundary.value.value, expected.over_clause.frame.ending_boundary.value.value
end

test "ROW_NUMBER() OVER (ROWS BETWEEN CURRENT ROW AND UNBOUNDED FOLLOWING)" do
	parser = Plume::Parser.new("ROW_NUMBER() OVER (ROWS BETWEEN CURRENT ROW AND UNBOUNDED FOLLOWING)")
	actual = parser.expression
	expected = Plume::FunctionReference.new(
		function: "ROW_NUMBER",
		arguments: Plume::EmptyFunctionArgument.new,
		over_clause: Plume::OverClause.new(
			frame: Plume::FrameSpec.new(
				type: :ROWS,
				starting_boundary: Plume::FrameBoundary.new(
					type: :CURRENT_ROW,
				),
				ending_boundary: Plume::FrameBoundary.new(
					type: :FOLLOWING,
					value: :UNBOUNDED
				),
			)
		)
	)
	assert_equal actual.function, expected.function
	assert_equal actual.arguments, expected.arguments
	assert_equal actual.over_clause.frame.type, expected.over_clause.frame.type
	assert_equal actual.over_clause.frame.starting_boundary.type, expected.over_clause.frame.starting_boundary.type
	assert_equal actual.over_clause.frame.ending_boundary.type, expected.over_clause.frame.ending_boundary.type
	assert_equal actual.over_clause.frame.ending_boundary.value, expected.over_clause.frame.ending_boundary.value
end

test "ROW_NUMBER() OVER (ROWS BETWEEN 123 FOLLOWING AND 123 FOLLOWING)" do
	parser = Plume::Parser.new("ROW_NUMBER() OVER (ROWS BETWEEN 123 FOLLOWING AND 123 FOLLOWING)")
	actual = parser.expression
	expected = Plume::FunctionReference.new(
		function: "ROW_NUMBER",
		arguments: Plume::EmptyFunctionArgument.new,
		over_clause: Plume::OverClause.new(
			frame: Plume::FrameSpec.new(
				type: :ROWS,
				starting_boundary: Plume::FrameBoundary.new(
					type: :FOLLOWING,
					value: Plume::LiteralExpression.new(
						value: 123,
					)
				),
				ending_boundary: Plume::FrameBoundary.new(
					type: :FOLLOWING,
					value: Plume::LiteralExpression.new(
						value: 123,
					)
				),
			)
		)
	)
	assert_equal actual.function, expected.function
	assert_equal actual.arguments, expected.arguments
	assert_equal actual.over_clause.frame.type, expected.over_clause.frame.type
	assert_equal actual.over_clause.frame.starting_boundary.type, expected.over_clause.frame.starting_boundary.type
	assert_equal actual.over_clause.frame.starting_boundary.value.value, expected.over_clause.frame.starting_boundary.value.value
	assert_equal actual.over_clause.frame.ending_boundary.type, expected.over_clause.frame.ending_boundary.type
	assert_equal actual.over_clause.frame.ending_boundary.value.value, expected.over_clause.frame.ending_boundary.value.value
end

test "ROW_NUMBER() OVER (ROWS BETWEEN 123 FOLLOWING AND UNBOUNDED FOLLOWING)" do
	parser = Plume::Parser.new("ROW_NUMBER() OVER (ROWS BETWEEN 123 FOLLOWING AND UNBOUNDED FOLLOWING)")
	actual = parser.expression
	expected = Plume::FunctionReference.new(
		function: "ROW_NUMBER",
		arguments: Plume::EmptyFunctionArgument.new,
		over_clause: Plume::OverClause.new(
			frame: Plume::FrameSpec.new(
				type: :ROWS,
				starting_boundary: Plume::FrameBoundary.new(
					type: :FOLLOWING,
					value: Plume::LiteralExpression.new(
						value: 123,
					)
				),
				ending_boundary: Plume::FrameBoundary.new(
					type: :FOLLOWING,
					value: :UNBOUNDED
				),
			)
		)
	)
	assert_equal actual.function, expected.function
	assert_equal actual.arguments, expected.arguments
	assert_equal actual.over_clause.frame.type, expected.over_clause.frame.type
	assert_equal actual.over_clause.frame.starting_boundary.type, expected.over_clause.frame.starting_boundary.type
	assert_equal actual.over_clause.frame.starting_boundary.value.value, expected.over_clause.frame.starting_boundary.value.value
	assert_equal actual.over_clause.frame.ending_boundary.type, expected.over_clause.frame.ending_boundary.type
	assert_equal actual.over_clause.frame.ending_boundary.value, expected.over_clause.frame.ending_boundary.value
end

test "ROW_NUMBER() OVER (win)" do
	parser = Plume::Parser.new("ROW_NUMBER() OVER (win)")
	actual = parser.expression
	expected = Plume::FunctionReference.new(
		function: "ROW_NUMBER",
		arguments: Plume::EmptyFunctionArgument.new,
		over_clause: Plume::OverClause.new(
			base_window_name: "win"
		)
	)
	assert_equal actual.function, expected.function
	assert_equal actual.arguments, expected.arguments
	assert_equal actual.over_clause.base_window_name, expected.over_clause.base_window_name
end

test "ROW_NUMBER() OVER (win ROWS BETWEEN 123 FOLLOWING AND UNBOUNDED FOLLOWING)" do
	parser = Plume::Parser.new("ROW_NUMBER() OVER (win ROWS BETWEEN 123 FOLLOWING AND UNBOUNDED FOLLOWING)")
	actual = parser.expression
	expected = Plume::FunctionReference.new(
		function: "ROW_NUMBER",
		arguments: Plume::EmptyFunctionArgument.new,
		over_clause: Plume::OverClause.new(
			base_window_name: "win",
			frame: Plume::FrameSpec.new(
				type: :ROWS,
				starting_boundary: Plume::FrameBoundary.new(
					type: :FOLLOWING,
					value: Plume::LiteralExpression.new(
						value: 123,
					)
				),
				ending_boundary: Plume::FrameBoundary.new(
					type: :FOLLOWING,
					value: :UNBOUNDED
				),
			)
		)
	)
	assert_equal actual.function, expected.function
	assert_equal actual.arguments, expected.arguments
	assert_equal actual.over_clause.base_window_name, expected.over_clause.base_window_name
	assert_equal actual.over_clause.frame.type, expected.over_clause.frame.type
	assert_equal actual.over_clause.frame.starting_boundary.type, expected.over_clause.frame.starting_boundary.type
	assert_equal actual.over_clause.frame.starting_boundary.value.value, expected.over_clause.frame.starting_boundary.value.value
	assert_equal actual.over_clause.frame.ending_boundary.type, expected.over_clause.frame.ending_boundary.type
	assert_equal actual.over_clause.frame.ending_boundary.value, expected.over_clause.frame.ending_boundary.value
end

test "ROW_NUMBER() OVER (win ORDER BY c0 ROWS BETWEEN 123 FOLLOWING AND UNBOUNDED FOLLOWING)" do
	parser = Plume::Parser.new("ROW_NUMBER() OVER (win ORDER BY c0 ROWS BETWEEN 123 FOLLOWING AND UNBOUNDED FOLLOWING)")
	actual = parser.expression
	expected = Plume::FunctionReference.new(
		function: "ROW_NUMBER",
		arguments: Plume::EmptyFunctionArgument.new,
		over_clause: Plume::OverClause.new(
			base_window_name: "win",
			orderings: [
				Plume::OrderingTerm.new(
					expression: Plume::ColumnName.new(column: "c0")
				),
			],
			frame: Plume::FrameSpec.new(
				type: :ROWS,
				starting_boundary: Plume::FrameBoundary.new(
					type: :FOLLOWING,
					value: Plume::LiteralExpression.new(
						value: 123,
					)
				),
				ending_boundary: Plume::FrameBoundary.new(
					type: :FOLLOWING,
					value: :UNBOUNDED
				),
			)
		)
	)
	assert_equal actual.function, expected.function
	assert_equal actual.arguments, expected.arguments
	assert_equal actual.over_clause.base_window_name, expected.over_clause.base_window_name
	assert_equal actual.over_clause.orderings[0].expression.column, expected.over_clause.orderings[0].expression.column
	assert_equal actual.over_clause.frame.type, expected.over_clause.frame.type
	assert_equal actual.over_clause.frame.starting_boundary.type, expected.over_clause.frame.starting_boundary.type
	assert_equal actual.over_clause.frame.starting_boundary.value.value, expected.over_clause.frame.starting_boundary.value.value
	assert_equal actual.over_clause.frame.ending_boundary.type, expected.over_clause.frame.ending_boundary.type
	assert_equal actual.over_clause.frame.ending_boundary.value, expected.over_clause.frame.ending_boundary.value
end

test "ROW_NUMBER() OVER (RANGE UNBOUNDED PRECEDING EXCLUDE NO OTHERS)" do
	parser = Plume::Parser.new("ROW_NUMBER() OVER (RANGE UNBOUNDED PRECEDING EXCLUDE NO OTHERS)")
	actual = parser.expression
	expected = Plume::FunctionReference.new(
		function: "ROW_NUMBER",
		arguments: Plume::EmptyFunctionArgument.new,
		over_clause: Plume::OverClause.new(
			frame: Plume::FrameSpec.new(
				type: :RANGE,
				starting_boundary: Plume::FrameBoundary.new(
					type: :PRECEDING,
					value: :UNBOUNDED
				),
				exclude: :NO_OTHERS
			)
		)
	)
	assert_equal actual.function, expected.function
	assert_equal actual.arguments, expected.arguments
	assert_equal actual.over_clause.frame.type, expected.over_clause.frame.type
	assert_equal actual.over_clause.frame.starting_boundary.type, expected.over_clause.frame.starting_boundary.type
	assert_equal actual.over_clause.frame.starting_boundary.value, expected.over_clause.frame.starting_boundary.value
	assert_equal actual.over_clause.frame.exclude, expected.over_clause.frame.exclude
end

test "ROW_NUMBER() OVER (RANGE UNBOUNDED PRECEDING EXCLUDE CURRENT ROW)" do
	parser = Plume::Parser.new("ROW_NUMBER() OVER (RANGE UNBOUNDED PRECEDING EXCLUDE CURRENT ROW)")
	actual = parser.expression
	expected = Plume::FunctionReference.new(
		function: "ROW_NUMBER",
		arguments: Plume::EmptyFunctionArgument.new,
		over_clause: Plume::OverClause.new(
			frame: Plume::FrameSpec.new(
				type: :RANGE,
				starting_boundary: Plume::FrameBoundary.new(
					type: :PRECEDING,
					value: :UNBOUNDED
				),
				exclude: :CURRENT_ROW
			)
		)
	)
	assert_equal actual.function, expected.function
	assert_equal actual.arguments, expected.arguments
	assert_equal actual.over_clause.frame.type, expected.over_clause.frame.type
	assert_equal actual.over_clause.frame.starting_boundary.type, expected.over_clause.frame.starting_boundary.type
	assert_equal actual.over_clause.frame.starting_boundary.value, expected.over_clause.frame.starting_boundary.value
	assert_equal actual.over_clause.frame.exclude, expected.over_clause.frame.exclude
end

test "ROW_NUMBER() OVER (RANGE UNBOUNDED PRECEDING EXCLUDE GROUP)" do
	parser = Plume::Parser.new("ROW_NUMBER() OVER (RANGE UNBOUNDED PRECEDING EXCLUDE GROUP)")
	actual = parser.expression
	expected = Plume::FunctionReference.new(
		function: "ROW_NUMBER",
		arguments: Plume::EmptyFunctionArgument.new,
		over_clause: Plume::OverClause.new(
			frame: Plume::FrameSpec.new(
				type: :RANGE,
				starting_boundary: Plume::FrameBoundary.new(
					type: :PRECEDING,
					value: :UNBOUNDED
				),
				exclude: :GROUP
			)
		)
	)
	assert_equal actual.function, expected.function
	assert_equal actual.arguments, expected.arguments
	assert_equal actual.over_clause.frame.type, expected.over_clause.frame.type
	assert_equal actual.over_clause.frame.starting_boundary.type, expected.over_clause.frame.starting_boundary.type
	assert_equal actual.over_clause.frame.starting_boundary.value, expected.over_clause.frame.starting_boundary.value
	assert_equal actual.over_clause.frame.exclude, expected.over_clause.frame.exclude
end

test "ROW_NUMBER() OVER (RANGE UNBOUNDED PRECEDING EXCLUDE TIES)" do
	parser = Plume::Parser.new("ROW_NUMBER() OVER (RANGE UNBOUNDED PRECEDING EXCLUDE TIES)")
	actual = parser.expression
	expected = Plume::FunctionReference.new(
		function: "ROW_NUMBER",
		arguments: Plume::EmptyFunctionArgument.new,
		over_clause: Plume::OverClause.new(
			frame: Plume::FrameSpec.new(
				type: :RANGE,
				starting_boundary: Plume::FrameBoundary.new(
					type: :PRECEDING,
					value: :UNBOUNDED
				),
				exclude: :TIES
			)
		)
	)
	assert_equal actual.function, expected.function
	assert_equal actual.arguments, expected.arguments
	assert_equal actual.over_clause.frame.type, expected.over_clause.frame.type
	assert_equal actual.over_clause.frame.starting_boundary.type, expected.over_clause.frame.starting_boundary.type
	assert_equal actual.over_clause.frame.starting_boundary.value, expected.over_clause.frame.starting_boundary.value
	assert_equal actual.over_clause.frame.exclude, expected.over_clause.frame.exclude
end

# test "c0 = (SELECT MAX(c1) FROM t1)" do
# 	parser = Plume::Parser.new("c0 = (SELECT MAX(c1) FROM t1)")
# 	actual = parser.expression
# 	assert_equal expr, {:EQ=>["c0", {:SELECT=>{:columns=>[{:MAX=>["c1"]}], :from=>"t1"}}]}
# end

# test "(c0 + 5) * 2 > (SELECT AVG(c1) FROM t1) OR c2 IS NOT NULL" do
# 	parser = Plume::Parser.new("(c0 + 5) * 2 > (SELECT AVG(c1) FROM t1) OR c2 IS NOT NULL")
# 	actual = parser.expression
# 	assert_equal expr, {:OR=>[{:GT=>[{:MULTIPLY=>[{:PLUS=>["c0", 5]}, 2]}, {:SELECT=>{:columns=>[{:AVG=>["c1"]}], :from=>"t1"}}]}, {:IS_NOT=>["c2", nil]}]}
# end

test "c0 & 3 | 4" do
	parser = Plume::Parser.new("c0 & 3 | 4")
	actual = parser.expression
	expected = Plume::BinaryExpression.new(
		operator: :BIT_OR,
		left: Plume::BinaryExpression.new(
			operator: :BIT_AND,
			left: Plume::ColumnName.new(column: "c0"),
			right: Plume::LiteralExpression.new(value: 3),
		),
		right: Plume::LiteralExpression.new(value: 4),
	)
	assert_equal actual.operator, expected.operator
	assert_equal actual.left.operator, expected.left.operator
	assert_equal actual.left.left.column, expected.left.left.column
	assert_equal actual.left.right.value, expected.left.right.value
	assert_equal actual.right.value, expected.right.value
end

# Expressions

test "'foo' COLLATE NOCASE" do
	parser = Plume::Parser.new("'foo' COLLATE NOCASE")
	actual = parser.expression
	expected = Plume::CollationExpression.new(
		expression: Plume::LiteralExpression.new(value: "foo"),
		sequence: :NOCASE,
	)
	assert_equal actual.expression.value, expected.expression.value
	assert_equal actual.sequence, expected.sequence
end

test "RAISE (IGNORE)" do
	parser = Plume::Parser.new("RAISE (IGNORE)")
	actual = parser.expression
	expected = Plume::RaiseExpression.new(
		type: :IGNORE
	)
	assert_equal actual.type, expected.type
end

test "RAISE (ROLLBACK, 'error message')" do
	parser = Plume::Parser.new("RAISE (ROLLBACK, 'error message')")
	actual = parser.expression
	expected = Plume::RaiseExpression.new(
		type: :ROLLBACK,
		error_message: Plume::LiteralExpression.new(
			value: "error message"
		),
	)
	assert_equal actual.type, expected.type
	assert_equal actual.error_message.value, expected.error_message.value
end

test "RAISE (ABORT, 'error message')" do
	parser = Plume::Parser.new("RAISE (ABORT, 'error message')")
	actual = parser.expression
	expected = Plume::RaiseExpression.new(
		type: :ABORT,
		error_message: Plume::LiteralExpression.new(
			value: "error message"
		),
	)
	assert_equal actual.type, expected.type
	assert_equal actual.error_message.value, expected.error_message.value
end

test "RAISE (FAIL, 'error message')" do
	parser = Plume::Parser.new("RAISE (FAIL, 'error message')")
	actual = parser.expression
	expected = Plume::RaiseExpression.new(
		type: :FAIL,
		error_message: Plume::LiteralExpression.new(
			value: "error message"
		),
	)
	assert_equal actual.type, expected.type
	assert_equal actual.error_message.value, expected.error_message.value
end
# -- operators after IN, BETWEEN, LIKE and GLOB keep the expression going

test "a IN (1, 2) AND b" do
	actual = Plume::Parser.new("a IN (1, 2) AND b").expression

	assert_equal actual.operator, :ALL
	assert_equal actual.left.operator, :IN
	assert_equal actual.right.column, "b"
end

test "a IN (b OR c)" do
	actual = Plume::Parser.new("a IN (b OR c)").expression

	assert_equal actual.right.value.first.operator, :ANY
end

test "a BETWEEN 1 AND 2 OR b" do
	actual = Plume::Parser.new("a BETWEEN 1 AND 2 OR b").expression

	assert_equal actual.operator, :ANY
	assert_operator Plume::TernaryExpression, :===, actual.left
end

test "a LIKE 'x%' AND b GLOB 'y*' AND c" do
	actual = Plume::Parser.new("a LIKE 'x%' AND b GLOB 'y*' AND c").expression

	assert_equal actual.operator, :ALL
	assert_equal actual.right.column, "c"
end

# -- bind parameters

test "a = ?" do
	actual = Plume::Parser.new("a = ?").expression

	assert_operator Plume::Variable, :===, actual.right
	assert_equal actual.right.name, "?"
end

test "f(:a, ?2, @b, $c)" do
	actual = Plume::Parser.new("f(:a, ?2, @b, $c)").expression

	assert_equal actual.arguments.expressions.map(&:name), [":a", "?2", "@b", "$c"]
end

test "count(x) is not distinct" do
	refute Plume::Parser.new("count(x)").expression.arguments.distinct
	assert Plume::Parser.new("count(distinct x)").expression.arguments.distinct
end

test "'it''s'" do
	assert_equal Plume::Parser.new("'it''s'").expression.value, "it's"
end

test "\"a \"\"b\"\"\".`c``d`" do
	column = Plume::Parser.new("\"a \"\"b\"\"\".`c``d`").expression

	assert_equal [column.table, column.column], ["a \"b\"", "c`d"]
end

# The values SQLite's own test/literal.test expects
test "numeric literals take the values SQLite gives them" do
	{
		"45" => 45, "0xFF" => 255, "0x123FFFFFFFF" => 0x123FFFFFFFF, "0xFFFFFFFFFFFFFFFF" => -1,
		"0x7FFFFFFFFFFFFFFF" => 0x7FFFFFFFFFFFFFFF, "1e12" => 1e12, "1_000" => 1000, "1.1_1" => 1.11,
		"12_3_456.7_8_9" => 123456.789, "9_223_372_036_854_775_807" => 9_223_372_036_854_775_807, "0x1_F" => 31,
	}.each do |sql, value|
		assert_equal parse_stmt("SELECT #{sql}").body.columns.first.result.value, value
	end
end

test "cast to no type, and an aggregate ordered over no arguments" do
	assert_equal parse_stmt("SELECT CAST(x AS)").body.columns.first.result.as, nil
	assert_equal parse_stmt("SELECT count(ORDER BY a)").body.columns.first.result.arguments.order_by.size, 1
	assert_equal parse_stmt("SELECT CAST(x AS), count(ORDER BY a)").to_sql, "SELECT CAST(x AS), count(ORDER BY a)"
end

test "an aggregate's argument list may be empty after DISTINCT or ALL, and ALL is not DISTINCT" do
	assert_equal parse_stmt("SELECT count(ALL), count(ALL x)").to_sql, "SELECT count(ALL), count(ALL x)"
	assert_equal parse_stmt("SELECT count(ALL x)").body.columns.first.result.arguments.distinct, false
	assert_equal parse_stmt("SELECT count(DISTINCT)").body.columns.first.result.arguments.distinct, true
end

test "~ is no binary operator" do
	assert_raises(Plume::SyntaxError) { Plume.parse("SELECT 1 ~ 2") }
	assert_raises(Plume::SyntaxError) { Plume.parse("SELECT n ~(c) + 1 FROM t") }
end

test "a parameter whose name is not valid UTF-8 parses" do
	assert_equal Plume.parse((+"SELECT :a\xFF").force_encoding(Encoding::UTF_8)).first.to_sql, (+"SELECT :a\xFF").force_encoding(Encoding::UTF_8)
end
