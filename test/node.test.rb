# frozen_string_literal: true

test "Single integer literal expression" do
	node = Plume::LiteralExpression.new(
		value: 2
	)
	assert node.inspect.match?(/#<Plume::LiteralExpression:\d+ value=2>/)
end

test "children of a binary expression are its operands" do
	node = Plume::Parser.new("a + 1").expression

	assert_equal node.children.map(&:class), [Plume::ColumnName, Plume::LiteralExpression]
end

test "walk visits every node of a create table exactly once, parents first" do
	node = parse_stmt("CREATE TABLE t (a INT CHECK (a > 0), b TEXT DEFAULT 'x', PRIMARY KEY (a))")
	visited = node.walk.to_a

	assert_equal visited.first, [node, nil]
	assert_equal visited.map { |n, _| n.object_id }.uniq.size, visited.size
	visited.each do |child, parent|
		assert(parent.nil? || parent.children.any? { |c| c.equal?(child) })
	end

	column_names = node.each_node.grep(Plume::ColumnName).map(&:column)
	assert_equal column_names, ["a"]
	assert_equal node.each_node.grep(Plume::ColumnDefinition).map(&:name), ["a", "b"]
end

test "walk descends into array-valued properties" do
	node = Plume::Parser.new("x IN (1, 2, 3)").expression

	assert_equal node.each_node.grep(Plume::LiteralExpression).map(&:value), [1, 2, 3]
end

test "pattern matching uses the public readers" do
	node = parse_stmt("select * from main.tb0")

	case node.body.source
	in { schema: "main", table: "tb0" }
		success!
	else
		failure! { node.body.source.deconstruct_keys(nil).inspect }
	end
end

test "walking a tree a thousand deep does not run out of stack" do
	statement = Plume.parse("SELECT #{"(" * 1000}a#{")" * 1000}").first

	assert_equal Thread.new { statement.each_node.count }.value, 1004
end

test "walk_with_slots says which prop, and which index of it, each node sits in" do
	node = parse_stmt("SELECT a, b FROM t")
	slots = node.walk_with_slots.map { |n, parent, prop, index| [n.class, parent&.class, prop, index] }

	assert_equal slots.first(4), [
		[Plume::SelectStatement, nil, nil, nil],
		[Plume::SelectCore, Plume::SelectStatement, :body, nil],
		[Plume::ResultColumn, Plume::SelectCore, :columns, 0],
		[Plume::ColumnName, Plume::ResultColumn, :result, nil],
	]
	assert_equal node.walk_with_slots.count { |_, _, prop, index| prop == :columns && index == 1 }, 1
end

test "transform puts replacements in place and leaves the original alone" do
	node = parse_stmt("SELECT a, 1 FROM t WHERE b IN (2, 3) ORDER BY 1")
	replaced = node.transform do |n, parent|
		(Plume::LiteralExpression === n && !(Plume::OrderingTerm === parent)) ? Plume::Variable.new(name: "?") : n
	end

	assert_equal replaced.to_sql, "SELECT a, ? FROM t WHERE b IN (?, ?) ORDER BY 1"
	assert_equal node.to_sql, "SELECT a, 1 FROM t WHERE b IN (2, 3) ORDER BY 1"
	# Only what leads to a replacement is copied
	assert replaced.body.source.equal?(node.body.source)
end

test "transform does not descend into a replacement, and can replace the root" do
	node = parse_stmt("SELECT (SELECT 1) FROM t")
	seen = []
	replaced = node.transform { |n| seen << n.class; (Plume::SubqueryExpression === n) ? Plume::LiteralExpression.new(value: 2) : n }

	assert_equal replaced.to_sql, "SELECT 2 FROM t"
	refute_includes seen, Plume::LiteralExpression
	assert_equal node.transform { parse_stmt("SELECT 3") }.to_sql, "SELECT 3"
end

test "transform refuses a replacement of the wrong type" do
	node = parse_stmt("SELECT a FROM t")

	assert_raises(TypeError) { node.transform { |n| (Plume::ResultColumn === n) ? Plume::TableName.new(table: "x") : n } }
end

test "transform works on a tree too deep to recurse through" do
	node = parse_stmt("SELECT #{(["1"] * 10_000).join(" OR ")}")

	assert_equal node.transform { |n| (Plume::LiteralExpression === n) ? Plume::Variable.new(name: "?") : n }.to_sql.count("?"), 10_000
end
