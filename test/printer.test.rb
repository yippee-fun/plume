# frozen_string_literal: true

test "keywords come out upper case, compound operands parenthesized" do
	assert_equal parse_stmt("select a+b*c, not x or y from t where a between 1 and 2 limit 5, 10").to_sql,
		"SELECT a + (b * c), (NOT x) OR y FROM t WHERE a BETWEEN 1 AND 2 LIMIT 10 OFFSET 5"
end

test "identifiers are quoted only when they have to be" do
	assert_equal parse_stmt(%(select "plain", "two words", "select", [br], "q""uote" from `t`)).to_sql,
		%(SELECT plain, "two words", "select", br, "q""uote" FROM t)
end

test "literals keep their meaning" do
	assert_equal parse_stmt("select 'it''s', x'00ff', 0x1F, 1e3, null, true, current_date, -1, - -1").to_sql,
		"SELECT 'it''s', X'00FF', 0x1F, 1e3, NULL, TRUE, CURRENT_DATE, -1, -(-1)"
end

test "a number SQL cannot spell is refused rather than printed as something else" do
	[Rational(1, 3), Complex(1, 2), Float::NAN, Float::INFINITY].each do |number|
		assert_raises(ArgumentError) { Plume::LiteralExpression.new(value: number).to_sql }
	end
	assert_equal Plume::LiteralExpression.new(value: 2.5).to_sql, "2.5"
end

test "a parenthesized NULL keeps its NULL" do
	assert_equal parse_stmt("select (null), x in (), x in (null)").to_sql, "SELECT (NULL), x IN (), x IN (NULL)"
end

test "aliases always get their AS" do
	assert_equal parse_stmt("select a x from t y").to_sql, "SELECT a AS x FROM t AS y"
end

test "a tree built by hand prints" do
	node = Plume::BinaryExpression.new(
		operator: :EQUALS,
		left: Plume::ColumnName.new(table: "users", column: "e-mail"),
		right: Plume::LiteralExpression.new(value: "o'hara"),
	)

	assert_equal node.to_sql, %(users."e-mail" = 'o''hara')
end

test "a parsed tree changed after the fact prints the change" do
	node = parse_stmt("select a from t where b = 1")
	node.body.condition = Plume::BinaryExpression.new(
		operator: :ALL,
		left: node.body.condition,
		right: Plume::BinaryExpression.new(operator: :EQUALS, left: Plume::ColumnName.new(column: "tenant_id"), right: Plume::Variable.new(name: "?")),
	)

	assert_equal node.to_sql, "SELECT a FROM t WHERE (b = 1) AND (tenant_id = ?)"
end

test "a foreign key action built by hand prints" do
	assert_equal Plume::ForeignKeyAction.new(trigger: :DELETE, action: :SET_NULL).to_sql, "ON DELETE SET NULL"
end

test "plain values in a tree built by hand print as literals" do
	node = Plume::BinaryExpression.new(
		operator: :ALL,
		left: Plume::BinaryExpression.new(operator: :ABOVE, left: Plume::ColumnName.new(column: "age"), right: 21),
		right: Plume::BinaryExpression.new(operator: :EQUALS, left: Plume::ColumnName.new(column: "name"), right: "o'hara"),
	)

	assert_equal node.to_sql, "(age > 21) AND (name = 'o''hara')"
end

test "alter table's constraint and not null forms print back as they parsed" do
	[
		"ALTER TABLE t ADD CONSTRAINT positive CHECK (a > 0) ON CONFLICT IGNORE",
		"ALTER TABLE t ADD CHECK (a > 0)",
		"ALTER TABLE t DROP CONSTRAINT positive",
		"ALTER TABLE t ALTER COLUMN a SET NOT NULL ON CONFLICT ABORT",
		"ALTER TABLE t ALTER COLUMN a DROP NOT NULL",
		"CREATE TABLE t (a INT, CHECK (a != 5) ON CONFLICT IGNORE)",
	].each { |sql| assert_equal parse_stmt(sql).to_sql, sql }
end

test "a chain at one precedence prints flat, and only a right operand keeps its parentheses" do
	assert_equal parse_stmt("SELECT a OR b OR c, a - b + c, a * b / c % d, a = b IS c, a - (b + c), (a OR b) AND c").to_sql,
		"SELECT a OR b OR c, a - b + c, a * b / c % d, a = b IS c, a - (b + c), (a OR b) AND c"
end

# Tests run on a thread, whose stack is far smaller than the main thread's
test "long OR, mixed-operator and UNION ALL chains round trip on a thread" do
	round_trip("SELECT a FROM t WHERE #{(1..6000).map { |i| "a = #{i}" }.join(" OR ")}")
	round_trip("SELECT 0#{(1..6000).map { |i| i.odd? ? " - #{i}" : " + #{i}" }.join}")
	round_trip((1..600).map { |i| "SELECT #{i}" }.join(" UNION ALL "))
end

test "a name that is not valid UTF-8 prints quoted" do
	sql = (+"SELECT \xFFa FROM t").force_encoding(Encoding::UTF_8)

	assert_equal Plume.parse(sql).first.to_sql, (+"SELECT \"\xFFa\" FROM t").force_encoding(Encoding::UTF_8)
	round_trip(sql)
end

test "a collation whose name is not valid UTF-8 prints back" do
	[
		"SELECT a COLLATE n\xFF FROM t",
		"SELECT a FROM t ORDER BY a COLLATE n\xFF",
		"CREATE TABLE t (a COLLATE n\xFF)",
		"CREATE INDEX i ON t (a COLLATE n\xFF)",
	].each do |sql|
		round_trip(sql.dup.force_encoding(Encoding::UTF_8))
	end
end

test "a tree too deep for the printer's stack is a printer error" do
	expression = Plume::ColumnName.new(column: "a")
	100_000.times { expression = Plume::UnaryExpression.new(operator: :NOT, operand: expression) }

	assert_raises(Plume::Printer::Error) { expression.to_sql }
end
