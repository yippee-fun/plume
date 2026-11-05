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
