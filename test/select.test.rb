# frozen_string_literal: true

# -- select core

test "select * from tb0" do
	node = parse_stmt("select * from tb0")

	assert_equal node.body.source.name, "tb0"
	assert_operator Plume::StarResultColumn, :===, node.body.columns[0]
end

test "select 1" do
	node = parse_stmt("select 1")

	assert_equal node.body.columns.size, 1
	assert_equal node.body.columns[0].result.value, 1
	assert_equal node.body.source, nil
end

test "select a, b as c, d e, f 'g' from t" do
	columns = parse_stmt("select a, b as c, d e, f 'g' from t").body.columns

	assert_equal columns.map { |c| c.result.column }, ["a", "b", "d", "f"]
	assert_equal columns.map(&:alias), [nil, "c", "e", "g"]
end

test "select t.*, t.a, s.t.b from s.t" do
	core = parse_stmt("select t.*, t.a, s.t.b from s.t").body

	assert_equal core.columns[0].table, "t"
	assert_operator Plume::StarResultColumn, :===, core.columns[0]
	assert_equal [core.columns[1].result.table, core.columns[1].result.column], ["t", "a"]
	assert_equal [core.columns[2].result.schema, core.columns[2].result.table, core.columns[2].result.column], ["s", "t", "b"]
	assert_equal [core.source.schema, core.source.table], ["s", "t"]
end

test "select distinct a from t" do
	assert parse_stmt("select distinct a from t").body.distinct
	refute parse_stmt("select all a from t").body.distinct
	refute parse_stmt("select a from t").body.distinct
end

test "select ? , :name, @x, $y" do
	columns = parse_stmt("select ?, :name, @x, $y").body.columns

	assert_equal columns.map { |c| c.result.name }, ["?", ":name", "@x", "$y"]
end

test "select a from t where a > 1 and b = ?" do
	core = parse_stmt("select a from t where a > 1 and b = ?").body

	assert_operator Plume::BinaryExpression, :===, core.condition
	assert_equal core.condition.operator, :ALL
	assert_operator Plume::Variable, :===, core.condition.right.right
end

test "select a, count(*) from t group by a, b having count(*) > 1" do
	core = parse_stmt("select a, count(*) from t group by a, b having count(*) > 1").body

	assert_equal core.groupings.map(&:column), ["a", "b"]
	assert_operator Plume::BinaryExpression, :===, core.having
end

test "select count(*) from t having count(*) > 1" do
	core = parse_stmt("select count(*) from t having count(*) > 1").body

	assert_equal core.groupings, nil
	assert_operator Plume::BinaryExpression, :===, core.having
end

test "select sum(a) over w from t window w as (partition by b order by c), v as (w rows unbounded preceding)" do
	core = parse_stmt("select sum(a) over w from t window w as (partition by b order by c), v as (w rows unbounded preceding)").body

	assert_equal core.windows.map(&:name), ["w", "v"]
	assert_equal core.windows[0].partitions.map(&:column), ["b"]
	assert_equal core.windows[0].orderings.map { |o| o.expression.column }, ["c"]
	assert_equal core.windows[1].base_window_name, "w"
	assert_operator Plume::FrameSpec, :===, core.windows[1].frame
end

test "values (1, 2), (3, 4)" do
	node = parse_stmt("values (1, 2), (3, 4)")

	assert_operator Plume::ValuesClause, :===, node.body
	assert_equal node.body.rows.map { |r| r.values.map(&:value) }, [[1, 2], [3, 4]]
end

# -- statement level

test "select a from t order by a desc, b limit 10 offset 5" do
	node = parse_stmt("select a from t order by a desc, b limit 10 offset 5")

	assert_equal node.orderings.map { |o| o.expression.column }, ["a", "b"]
	assert_equal node.orderings.map(&:direction), [:DESC, nil]
	assert_equal node.limit.value, 10
	assert_equal node.offset.value, 5
end

test "select a from t limit 5, 10" do
	node = parse_stmt("select a from t limit 5, 10")

	# The first number is the offset
	assert_equal node.limit.value, 10
	assert_equal node.offset.value, 5
end

test "select a from t limit 3" do
	node = parse_stmt("select a from t limit 3")

	assert_equal node.limit.value, 3
	assert_equal node.offset, nil
end

test "select 1 union select 2 union all select 3 intersect select 4 except select 5 order by 1 limit 2" do
	node = parse_stmt("select 1 union select 2 union all select 3 intersect select 4 except select 5 order by 1 limit 2")

	assert_operator Plume::CompoundSelect, :===, node.body
	assert_equal node.body.operator, :EXCEPT
	assert_equal node.body.left.operator, :INTERSECT
	assert_equal node.body.left.left.operator, :UNION_ALL
	assert_equal node.body.left.left.left.operator, :UNION
	assert_equal node.cores.map { |c| c.columns[0].result.value }, [1, 2, 3, 4, 5]
	assert_equal node.orderings.size, 1
	assert_equal node.limit.value, 2
end

test "select a from t union values (1)" do
	node = parse_stmt("select a from t union values (1)")

	assert_equal node.cores.map(&:class), [Plume::SelectCore, Plume::ValuesClause]
end

# -- FROM sources

test "select * from t as x" do
	source = parse_stmt("select * from t as x").body.source

	assert_equal [source.table, source.alias], ["t", "x"]
end

test "select * from t x" do
	source = parse_stmt("select * from t x").body.source

	assert_equal [source.table, source.alias], ["t", "x"]
end

test "select * from main.t as x indexed by idx" do
	source = parse_stmt("select * from main.t as x indexed by idx").body.source

	assert_equal [source.schema, source.table, source.alias, source.indexed_by], ["main", "t", "x", "idx"]
	refute source.not_indexed
end

test "select * from t not indexed" do
	source = parse_stmt("select * from t not indexed").body.source

	assert_equal source.alias, nil
	assert source.not_indexed
end

test "select * from t indexed by idx" do
	source = parse_stmt("select * from t indexed by idx").body.source

	assert_equal [source.alias, source.indexed_by], [nil, "idx"]
end

test "select * from json_each('[1]')" do
	source = parse_stmt("select * from json_each('[1]')").body.source

	assert_operator Plume::TableFunction, :===, source
	assert_equal source.function, "json_each"
	assert_equal source.arguments.map(&:value), ["[1]"]
end

test "select j.value from main.json_each(t.doc, '$.a') as j" do
	source = parse_stmt("select j.value from main.json_each(t.doc, '$.a') as j").body.source

	assert_equal [source.schema, source.function, source.alias], ["main", "json_each", "j"]
	assert_equal source.arguments.size, 2
end

test "select * from generate_series(1, 10) g" do
	source = parse_stmt("select * from generate_series(1, 10) g").body.source

	assert_equal source.alias, "g"
end

test "select * from (select 1 as a) as s" do
	source = parse_stmt("select * from (select 1 as a) as s").body.source

	assert_operator Plume::SubquerySource, :===, source
	assert_equal source.alias, "s"
	assert_equal source.select.body.columns[0].alias, "a"
end

test "select * from (values (1)) v" do
	source = parse_stmt("select * from (values (1)) v").body.source

	assert_operator Plume::ValuesClause, :===, source.select.body
	assert_equal source.alias, "v"
end

test "select * from (a join b on a.id = b.id) as ab" do
	source = parse_stmt("select * from (a join b on a.id = b.id) as ab").body.source

	assert_operator Plume::ParentheticalSource, :===, source
	assert_equal source.alias, "ab"
	assert_operator Plume::JoinClause, :===, source.source
end

# -- joins

test "select * from t, u" do
	source = parse_stmt("select * from t, u").body.source

	assert_operator Plume::JoinClause, :===, source
	assert_equal source.sources.map(&:table), ["t", "u"]
	assert_equal source.joins[0].operator.kind, :COMMA
end

test "select * from a join b on a.id = b.a_id" do
	join = parse_stmt("select * from a join b on a.id = b.a_id").body.source.joins[0]

	assert_equal join.operator.kind, :INNER
	refute join.operator.natural
	assert_operator Plume::JoinOnConstraint, :===, join.constraint
	assert_equal join.constraint.expression.left.table, "a"
end

test "select * from a left join b using (id, k)" do
	join = parse_stmt("select * from a left join b using (id, k)").body.source.joins[0]

	assert_equal join.operator.kind, :LEFT
	assert join.operator.outer?
	assert_equal join.constraint.column_names, ["id", "k"]
end

test "join operator spellings" do
	{
		"join" => [:INNER, false],
		"inner join" => [:INNER, false],
		"cross join" => [:CROSS, false],
		"left join" => [:LEFT, false],
		"left outer join" => [:LEFT, false],
		"right join" => [:RIGHT, false],
		"right outer join" => [:RIGHT, false],
		"full join" => [:FULL, false],
		"full outer join" => [:FULL, false],
		"natural join" => [:INNER, true],
		"natural inner join" => [:INNER, true],
		"natural left join" => [:LEFT, true],
		"natural left outer join" => [:LEFT, true],
		"natural full outer join" => [:FULL, true],
	}.each do |spelling, (kind, natural)|
		operator = parse_stmt("select * from a #{spelling} b").body.source.joins[0].operator

		assert_equal [operator.kind, operator.natural], [kind, natural]
	end
end

test "select * from a join b on a.x = b.x left join c using (y), d" do
	source = parse_stmt("select * from a join b on a.x = b.x left join c using (y), d").body.source

	assert_equal source.sources.map(&:table), ["a", "b", "c", "d"]
	assert_equal source.joins.map { |j| j.operator.kind }, [:INNER, :LEFT, :COMMA]
end

test "select * from a as x join b y on x.id = y.id where x.z = 1" do
	core = parse_stmt("select * from a as x join b y on x.id = y.id where x.z = 1").body

	assert_equal core.source.sources.map(&:alias), ["x", "y"]
	assert_operator Plume::BinaryExpression, :===, core.condition
end

# -- WITH

test "with x as (select 1) select * from x" do
	node = parse_stmt("with x as (select 1) select * from x")

	refute node.with_clause.recursive
	assert_equal node.with_clause.ctes.map(&:name), ["x"]
	assert_equal node.with_clause.ctes[0].materialized, nil
	assert_equal node.body.source.table, "x"
end

test "with recursive cnt(n) as (select 1 union all select n + 1 from cnt where n < 10) select n from cnt" do
	node = parse_stmt("with recursive cnt(n) as (select 1 union all select n + 1 from cnt where n < 10) select n from cnt")

	assert node.with_clause.recursive
	cte = node.with_clause.ctes[0]
	assert_equal cte.column_names, ["n"]
	assert_operator Plume::CompoundSelect, :===, cte.select.body
end

test "with a as materialized (select 1), b as not materialized (select 2) select * from a, b" do
	ctes = parse_stmt("with a as materialized (select 1), b as not materialized (select 2) select * from a, b").with_clause.ctes

	assert_equal ctes.map(&:materialized), [true, false]
end

test "create table t as with x as (select 1) select * from x" do
	node = parse_stmt("create table t as with x as (select 1) select * from x")

	assert_operator Plume::SelectStatement, :===, node.select_statement
	assert_equal node.select_statement.with_clause.ctes[0].name, "x"
end

# -- subqueries in expressions

test "select * from t where a in (select b from u)" do
	condition = parse_stmt("select * from t where a in (select b from u)").body.condition

	assert_equal condition.operator, :IN
	assert_operator Plume::SubqueryExpression, :===, condition.right
	assert_equal condition.right.select.body.source.table, "u"
end

test "select * from t where a not in (select b from u)" do
	condition = parse_stmt("select * from t where a not in (select b from u)").body.condition

	assert_equal condition.operator, :NOT_IN
	assert_operator Plume::SubqueryExpression, :===, condition.right
end

test "select * from t where a in u" do
	condition = parse_stmt("select * from t where a in u").body.condition

	assert_equal condition.right.table, "u"
end

test "select * from t where exists (select 1 from u where u.t_id = t.id)" do
	condition = parse_stmt("select * from t where exists (select 1 from u where u.t_id = t.id)").body.condition

	assert_operator Plume::ExistsExpression, :===, condition
	assert_equal condition.select.body.source.table, "u"
end

test "select * from t where not exists (select 1 from u)" do
	condition = parse_stmt("select * from t where not exists (select 1 from u)").body.condition

	assert_operator Plume::UnaryExpression, :===, condition
	assert_operator Plume::ExistsExpression, :===, condition.operand
end

test "select (select max(b) from u) as m from t" do
	column = parse_stmt("select (select max(b) from u) as m from t").body.columns[0]

	assert_operator Plume::SubqueryExpression, :===, column.result
	assert_equal column.alias, "m"
end

test "select * from t where (a, b) = (1, 2)" do
	condition = parse_stmt("select * from t where (a, b) = (1, 2)").body.condition

	assert_equal condition.left.value.map(&:column), ["a", "b"]
	assert_equal condition.right.value, [1, 2].map { |v| condition.right.value[v - 1] }
end

# -- traversal

test "every table reference in a nested select is reachable by walking" do
	node = parse_stmt(<<~SQL)
		with c as (select id from cte_src)
		select a.x, (select max(y) from scalar_src)
		from a join (select * from sub_src) s on s.id = a.id
		where a.id in (select id from in_src) and exists (select 1 from exists_src)
		union select 1 from union_src
	SQL

	tables = node.each_node.grep(Plume::TableName).map(&:table).sort
	assert_equal tables, ["a", "cte_src", "exists_src", "in_src", "scalar_src", "sub_src", "union_src"]
end

test "select percentile(x, 50) within group (order by x) filter (where x > 0) from t" do
	column = parse_stmt("select percentile(x, 50) within group (order by x) filter (where x > 0) from t").body.columns[0]

	assert_equal column.result.within_group.column, "x"
	assert_operator Plume::BinaryExpression, :===, column.result.filter_clause
	assert_equal column.alias, nil
end

test "select '@abc'.'!pqr' from '@abc'" do
	core = parse_stmt("select '@abc'.'!pqr' from '@abc'").body

	assert_equal [core.columns[0].result.table, core.columns[0].result.column], ["@abc", "!pqr"]
	assert_equal core.source.table, "@abc"
end

# A list ends where its separator is missing, even before a word that could be a name
test "select sum(b) over (order by c rows 2 preceding) from t" do
	window = parse_stmt("SELECT sum(b) OVER (ORDER BY c ROWS 2 PRECEDING) FROM t").body.columns.first.result.over_clause

	assert_equal window.orderings.size, 1
	assert_equal window.frame.type, :ROWS
end

test "items with no separator between them are a syntax error" do
	[
		"SELECT * + 1 FROM t", "SELECT * FROM json_each(x y)", "CREATE TABLE t(a PRIMARY KEY) STRICT WITHOUT ROWID",
		"SELECT coalesce(a b) FROM t", "SELECT a FROM t WHERE a IN (1 2)"
	].each do |sql|
		assert_raises(Plume::SyntaxError) { Plume.parse(sql) }
	end
end

test "a separator with no item after it is a syntax error" do
	["SELECT a, b, FROM t", "VALUES (1, 2,)", "SELECT a FROM t WHERE a IN (1, 2,)", "WITH x AS (SELECT 1), SELECT 1"].each do |sql|
		assert_raises(Plume::SyntaxError) { Plume.parse(sql) }
	end
end

test "NULLS takes only FIRST or LAST after it" do
	assert_raises(Plume::SyntaxError) { Plume.parse("SELECT a FROM t ORDER BY a NULLS b") }
	assert_raises(Plume::SyntaxError) { Plume.parse("SELECT a FROM t ORDER BY a DESC NULLS") }
end
