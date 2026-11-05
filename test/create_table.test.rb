# frozen_string_literal: true

test "create table tb0 ()" do
	error = assert_raises(Plume::SyntaxError) do
		parse_stmt(<<~SQL)
			create table tb0 ()
		SQL
	end

	assert_equal error.message.split("\n"), [
		'Unexpected token RP[")"] at:',
		"  create table tb0 ()",
		"                    ^",
		"  Expected one of: STRING, idj",
	]
end

test "create table tb0 (c0)" do
	node = parse_stmt(<<~SQL)
		create table tb0 (c0)
	SQL

	assert_equal node.table.name, "tb0"
	assert_equal node.columns[0].name, "c0"
end

test "create table schema0.tb0 (c0)" do
	node = parse_stmt(<<~SQL)
		create table schema0.tb0 (c0)
	SQL

	assert_equal node.table.schema, "schema0"
	assert_equal node.table.name, "tb0"
	assert_equal node.columns[0].name, "c0"
end

test 'create table "tb0" ("c0")' do
	node = parse_stmt(<<~SQL)
		create table "tb0" ("c0")
	SQL

	assert_equal node.table.name, "tb0"
	assert_equal node.columns[0].name, "c0"
end

test "create table 'tb0' ('c0')" do
	node = parse_stmt(<<~SQL)
		create table 'tb0' ('c0')
	SQL

	assert_equal node.table.name, "tb0"
	assert_equal node.columns[0].name, "c0"
end

test "create table `tb0` (`c0`)" do
	node = parse_stmt(<<~SQL)
		create table `tb0` (`c0`)
	SQL

	assert_equal node.table.name, "tb0"
	assert_equal node.columns[0].name, "c0"
end

test "create table [tb0] ([c0])" do
	node = parse_stmt(<<~SQL)
		create table [tb0] ([c0])
	SQL

	assert_equal node.table.name, "tb0"
	assert_equal node.columns[0].name, "c0"
end

test "create temp table tb0 (c0)" do
	node = parse_stmt(<<~SQL)
		create temp table tb0 (c0)
	SQL

	assert_equal node.table.name, "tb0"
	assert_equal node.columns[0].name, "c0"
	assert_equal node.temporary, true
end

test "create temporary table tb0 (c0)" do
	node = parse_stmt(<<~SQL)
		create temporary table tb0 (c0)
	SQL

	assert_equal node.table.name, "tb0"
	assert_equal node.columns[0].name, "c0"
	assert_equal node.temporary, true
end

test "create table if not exists tb0 (c0)" do
	node = parse_stmt(<<~SQL)
		create table if not exists tb0 (c0)
	SQL

	assert_equal node.table.name, "tb0"
	assert_equal node.columns[0].name, "c0"
	assert_equal node.if_not_exists, true
end

test "create temp table if not exists tb0 (c0)" do
	node = parse_stmt(<<~SQL)
		create temp table if not exists tb0 (c0)
	SQL

	assert_equal node.table.name, "tb0"
	assert_equal node.columns[0].name, "c0"
	assert_equal node.temporary, true
	assert_equal node.if_not_exists, true
end

# column types

test "create table tb0 (c0 int)" do
	node = parse_stmt(<<~SQL)
		create table tb0 (c0 int)
	SQL

	assert_equal node.table.name, "tb0"
	assert_equal node.columns[0].name, "c0"
	assert_equal node.columns[0].type.text, "int"
	assert_equal node.columns[0].type.affinity, :INTEGER
end

test "create table tb0 (c0 char)" do
	node = parse_stmt(<<~SQL)
		create table tb0 (c0 char)
	SQL

	assert_equal node.table.name, "tb0"
	assert_equal node.columns[0].name, "c0"
	assert_equal node.columns[0].type.text, "char"
	assert_equal node.columns[0].type.affinity, :TEXT
end

test "create table tb0 (c0 blob)" do
	node = parse_stmt(<<~SQL)
		create table tb0 (c0 blob)
	SQL

	assert_equal node.table.name, "tb0"
	assert_equal node.columns[0].name, "c0"
	assert_equal node.columns[0].type.text, "blob"
	assert_equal node.columns[0].type.affinity, :BLOB
end

test "create table tb0 (c0 real)" do
	node = parse_stmt(<<~SQL)
		create table tb0 (c0 real)
	SQL

	assert_equal node.table.name, "tb0"
	assert_equal node.columns[0].name, "c0"
	assert_equal node.columns[0].type.text, "real"
	assert_equal node.columns[0].type.affinity, :REAL
end

test "create table tb0 (c0 any)" do
	node = parse_stmt(<<~SQL)
		create table tb0 (c0 any)
	SQL

	assert_equal node.table.name, "tb0"
	assert_equal node.columns[0].name, "c0"
	assert_equal node.columns[0].type.text, "any"
	assert_equal node.columns[0].type.affinity, :ANY
end

test "create table tb0 (c0 decimal(4, 6))" do
	node = parse_stmt(<<~SQL)
		create table tb0 (c0 decimal(4, 6))
	SQL

	assert_equal node.table.name, "tb0"
	assert_equal node.columns[0].name, "c0"
	assert_equal node.columns[0].type.text, "decimal(4, 6)"
	assert_equal node.columns[0].type.affinity, :ANY
end

# column constraints

test "create table tb0 (c0 primary key)" do
	node = parse_stmt(<<~SQL)
		create table tb0 (c0 primary key)
	SQL

	assert_equal node.table.name, "tb0"
	assert_equal node.columns[0].name, "c0"
	assert_operator Plume::PrimaryKeyColumnConstraint, :===, node.columns[0].constraints[0]
end

test "create table tb0 (c0 constraint 'name' primary key)" do
	node = parse_stmt(<<~SQL)
		create table tb0 (c0 constraint 'name' primary key)
	SQL

	assert_equal node.table.name, "tb0"
	assert_equal node.columns[0].name, "c0"
	assert_operator Plume::PrimaryKeyColumnConstraint, :===, node.columns[0].constraints[0]
	assert_equal node.columns[0].constraints[0].name, "name"
end

test "create table tb0 (c0 primary key desc on conflict abort autoincrement)" do
	node = parse_stmt(<<~SQL)
		create table tb0 (c0 primary key desc on conflict abort autoincrement)
	SQL

	assert_equal node.table.name, "tb0"
	assert_equal node.columns[0].name, "c0"
	assert_operator Plume::PrimaryKeyColumnConstraint, :===, node.columns[0].constraints[0]
	assert_equal node.columns[0].constraints[0].direction, :DESC
	assert_equal node.columns[0].constraints[0].conflict_clause.resolution, :ABORT
	assert_equal node.columns[0].constraints[0].autoincrement, true
end

test "create table tb0 (c0 constraint 'name' primary key desc on conflict abort autoincrement)" do
	node = parse_stmt(<<~SQL)
		create table tb0 (c0 constraint 'name' primary key desc on conflict abort autoincrement)
	SQL

	assert_equal node.table.name, "tb0"
	assert_equal node.columns[0].name, "c0"
	assert_operator Plume::PrimaryKeyColumnConstraint, :===, node.columns[0].constraints[0]
	assert_equal node.columns[0].constraints[0].name, "name"
	assert_equal node.columns[0].constraints[0].direction, :DESC
	assert_equal node.columns[0].constraints[0].conflict_clause.resolution, :ABORT
	assert_equal node.columns[0].constraints[0].autoincrement, true
end

test "create table tb0 (c0 not null)" do
	node = parse_stmt(<<~SQL)
		create table tb0 (c0 not null)
	SQL

	assert_equal node.table.name, "tb0"
	assert_equal node.columns[0].name, "c0"
	assert_operator Plume::NotNullColumnConstraint, :===, node.columns[0].constraints[0]
end

test "create table tb0 (c0 constraint 'name' not null)" do
	node = parse_stmt(<<~SQL)
		create table tb0 (c0 constraint 'name' not null)
	SQL

	assert_equal node.table.name, "tb0"
	assert_equal node.columns[0].name, "c0"
	assert_operator Plume::NotNullColumnConstraint, :===, node.columns[0].constraints[0]
	assert_equal node.columns[0].constraints[0].name, "name"
end

test "create table tb0 (c0 not null on conflict abort)" do
	node = parse_stmt(<<~SQL)
		create table tb0 (c0 not null on conflict abort)
	SQL

	assert_equal node.table.name, "tb0"
	assert_equal node.columns[0].name, "c0"
	assert_operator Plume::NotNullColumnConstraint, :===, node.columns[0].constraints[0]
	assert_equal node.columns[0].constraints[0].conflict_clause.resolution, :ABORT
end

test "create table tb0 (c0 constraint 'name' not null on conflict abort)" do
	node = parse_stmt(<<~SQL)
		create table tb0 (c0 constraint 'name' not null on conflict abort)
	SQL

	assert_equal node.table.name, "tb0"
	assert_equal node.columns[0].name, "c0"
	assert_operator Plume::NotNullColumnConstraint, :===, node.columns[0].constraints[0]
	assert_equal node.columns[0].constraints[0].name, "name"
	assert_equal node.columns[0].constraints[0].conflict_clause.resolution, :ABORT
end

test "create table tb0 (c0 unique)" do
	node = parse_stmt(<<~SQL)
		create table tb0 (c0 unique)
	SQL

	assert_equal node.table.name, "tb0"
	assert_equal node.columns[0].name, "c0"
	assert_operator Plume::UniqueColumnConstraint, :===, node.columns[0].constraints[0]
end

test "create table tb0 (c0 constraint 'name' unique)" do
	node = parse_stmt(<<~SQL)
		create table tb0 (c0 constraint 'name' unique)
	SQL

	assert_equal node.table.name, "tb0"
	assert_equal node.columns[0].name, "c0"
	assert_operator Plume::UniqueColumnConstraint, :===, node.columns[0].constraints[0]
	assert_equal node.columns[0].constraints[0].name, "name"
end

test "create table tb0 (c0 unique on conflict abort)" do
	node = parse_stmt(<<~SQL)
		create table tb0 (c0 unique on conflict abort)
	SQL

	assert_equal node.table.name, "tb0"
	assert_equal node.columns[0].name, "c0"
	assert_operator Plume::UniqueColumnConstraint, :===, node.columns[0].constraints[0]
	assert_equal node.columns[0].constraints[0].conflict_clause.resolution, :ABORT
end

test "create table tb0 (c0 constraint 'name' unique on conflict abort)" do
	node = parse_stmt(<<~SQL)
		create table tb0 (c0 constraint 'name' unique on conflict abort)
	SQL

	assert_equal node.table.name, "tb0"
	assert_equal node.columns[0].name, "c0"
	assert_operator Plume::UniqueColumnConstraint, :===, node.columns[0].constraints[0]
	assert_equal node.columns[0].constraints[0].name, "name"
	assert_equal node.columns[0].constraints[0].conflict_clause.resolution, :ABORT
end

test "create table tb0 (c0 check (c0 > 0))" do
	node = parse_stmt(<<~SQL)
		create table tb0 (c0 check (c0 > 0))
	SQL

	assert_equal node.table.name, "tb0"
	assert_equal node.columns[0].name, "c0"
	assert_operator Plume::CheckColumnConstraint, :===, node.columns[0].constraints[0]
	assert_equal node.columns[0].constraints[0].expression.operator, :ABOVE
	assert_operator Plume::ColumnName, :===, node.columns[0].constraints[0].expression.left
	assert_equal node.columns[0].constraints[0].expression.left.column, "c0"
	assert_equal node.columns[0].constraints[0].expression.right.value, 0
end

test "create table tb0 (c0 constraint 'name' check (c0 > 0))" do
	node = parse_stmt(<<~SQL)
		create table tb0 (c0 constraint 'name' check (c0 > 0))
	SQL

	assert_equal node.table.name, "tb0"
	assert_equal node.columns[0].name, "c0"
	assert_operator Plume::CheckColumnConstraint, :===, node.columns[0].constraints[0]
	assert_equal node.columns[0].constraints[0].name, "name"
	assert_equal node.columns[0].constraints[0].expression.operator, :ABOVE
	assert_operator Plume::ColumnName, :===, node.columns[0].constraints[0].expression.left
	assert_equal node.columns[0].constraints[0].expression.left.column, "c0"
	assert_equal node.columns[0].constraints[0].expression.right.value, 0
end

test "create table tb0 (c0 default 123)" do
	node = parse_stmt(<<~SQL)
		create table tb0 (c0 default 123)
	SQL

	assert_equal node.table.name, "tb0"
	assert_equal node.columns[0].name, "c0"
	assert_operator Plume::DefaultColumnConstraint, :===, node.columns[0].constraints[0]
	assert_equal node.columns[0].constraints[0].value, 123
end

test "create table tb0 (c0 constraint 'name' default 123)" do
	node = parse_stmt(<<~SQL)
		create table tb0 (c0 constraint 'name' default 123)
	SQL

	assert_equal node.table.name, "tb0"
	assert_equal node.columns[0].name, "c0"
	assert_operator Plume::DefaultColumnConstraint, :===, node.columns[0].constraints[0]
	assert_equal node.columns[0].constraints[0].value, 123
	assert_equal node.columns[0].constraints[0].name, "name"
end

test "create table tb0 (c0 default 'foo')" do
	node = parse_stmt(<<~SQL)
		create table tb0 (c0 default 'foo')
	SQL

	assert_equal node.table.name, "tb0"
	assert_equal node.columns[0].name, "c0"
	assert_operator Plume::DefaultColumnConstraint, :===, node.columns[0].constraints[0]
	assert_equal node.columns[0].constraints[0].value, "foo"
end

test "create table tb0 (c0 constraint 'name' default 'foo')" do
	node = parse_stmt(<<~SQL)
		create table tb0 (c0 constraint 'name' default 'foo')
	SQL

	assert_equal node.table.name, "tb0"
	assert_equal node.columns[0].name, "c0"
	assert_operator Plume::DefaultColumnConstraint, :===, node.columns[0].constraints[0]
	assert_equal node.columns[0].constraints[0].value, "foo"
	assert_equal node.columns[0].constraints[0].name, "name"
end

test "create table tb0 (c0 default ('a' || 'b'))" do
	node = parse_stmt(<<~SQL)
		create table tb0 (c0 default ('a' || 'b'))
	SQL

	assert_equal node.table.name, "tb0"
	assert_equal node.columns[0].name, "c0"
	assert_operator Plume::DefaultColumnConstraint, :===, node.columns[0].constraints[0]
	assert_operator Plume::BinaryExpression, :===, node.columns[0].constraints[0].value
	assert_equal node.columns[0].constraints[0].value.operator, :CONCAT
	assert_equal node.columns[0].constraints[0].value.left.value, "a"
	assert_equal node.columns[0].constraints[0].value.right.value, "b"
end

test "create table tb0 (c0 constraint 'name' default ('a' || 'b'))" do
	node = parse_stmt(<<~SQL)
		create table tb0 (c0 constraint 'name' default ('a' || 'b'))
	SQL

	assert_equal node.table.name, "tb0"
	assert_equal node.columns[0].name, "c0"
	assert_operator Plume::DefaultColumnConstraint, :===, node.columns[0].constraints[0]
	assert_operator Plume::BinaryExpression, :===, node.columns[0].constraints[0].value
	assert_equal node.columns[0].constraints[0].value.operator, :CONCAT
	assert_equal node.columns[0].constraints[0].value.left.value, "a"
	assert_equal node.columns[0].constraints[0].value.right.value, "b"
	assert_equal node.columns[0].constraints[0].name, "name"
end

test "create table tb0 (c0 collate rtrim)" do
	node = parse_stmt(<<~SQL)
		create table tb0 (c0 collate rtrim)
	SQL

	assert_equal node.table.name, "tb0"
	assert_equal node.columns[0].name, "c0"
	assert_operator Plume::CollateColumnConstraint, :===, node.columns[0].constraints[0]
	assert_equal node.columns[0].constraints[0].collation, :RTRIM
end

test "create table tb0 (c0 constraint 'name' collate rtrim)" do
	node = parse_stmt(<<~SQL)
		create table tb0 (c0 constraint 'name' collate rtrim)
	SQL

	assert_equal node.table.name, "tb0"
	assert_equal node.columns[0].name, "c0"
	assert_operator Plume::CollateColumnConstraint, :===, node.columns[0].constraints[0]
	assert_equal node.columns[0].constraints[0].collation, :RTRIM
	assert_equal node.columns[0].constraints[0].name, "name"
end

test "create table tb0 (c0 generated always as (1 + 2))" do
	node = parse_stmt(<<~SQL)
		create table tb0 (c0 generated always as (1 + 2))
	SQL

	assert_equal node.table.name, "tb0"
	assert_equal node.columns[0].name, "c0"
	assert_operator Plume::GeneratedAsColumnConstraint, :===, node.columns[0].constraints[0]
	assert_equal node.columns[0].constraints[0].expression.operator, :ADD
	assert_equal node.columns[0].constraints[0].expression.left.value, 1
	assert_equal node.columns[0].constraints[0].expression.right.value, 2
end

test "create table tb0 (c0 constraint 'name' generated always as (1 + 2))" do
	node = parse_stmt(<<~SQL)
		create table tb0 (c0 constraint 'name' generated always as (1 + 2))
	SQL

	assert_equal node.table.name, "tb0"
	assert_equal node.columns[0].name, "c0"
	assert_operator Plume::GeneratedAsColumnConstraint, :===, node.columns[0].constraints[0]
	assert_equal node.columns[0].constraints[0].expression.operator, :ADD
	assert_equal node.columns[0].constraints[0].expression.left.value, 1
	assert_equal node.columns[0].constraints[0].expression.right.value, 2
	assert_equal node.columns[0].constraints[0].name, "name"
end

test "create table tb0 (c0 as (1 + 2))" do
	node = parse_stmt(<<~SQL)
		create table tb0 (c0 as (1 + 2))
	SQL

	assert_equal node.table.name, "tb0"
	assert_equal node.columns[0].name, "c0"
	assert_operator Plume::GeneratedAsColumnConstraint, :===, node.columns[0].constraints[0]
	assert_equal node.columns[0].constraints[0].expression.operator, :ADD
	assert_equal node.columns[0].constraints[0].expression.left.value, 1
	assert_equal node.columns[0].constraints[0].expression.right.value, 2
end

test "create table tb0 (c0 constraint 'name' as (1 + 2))" do
	node = parse_stmt(<<~SQL)
		create table tb0 (c0 constraint 'name' as (1 + 2))
	SQL

	assert_equal node.table.name, "tb0"
	assert_equal node.columns[0].name, "c0"
	assert_operator Plume::GeneratedAsColumnConstraint, :===, node.columns[0].constraints[0]
	assert_equal node.columns[0].constraints[0].expression.operator, :ADD
	assert_equal node.columns[0].constraints[0].expression.left.value, 1
	assert_equal node.columns[0].constraints[0].expression.right.value, 2
	assert_equal node.columns[0].constraints[0].name, "name"
end

test "create table tb0 (c0 generated always as (1 + 2) stored)" do
	node = parse_stmt(<<~SQL)
		create table tb0 (c0 generated always as (1 + 2) stored)
	SQL

	assert_equal node.table.name, "tb0"
	assert_equal node.columns[0].name, "c0"
	assert_operator Plume::GeneratedAsColumnConstraint, :===, node.columns[0].constraints[0]
	assert_equal node.columns[0].constraints[0].expression.operator, :ADD
	assert_equal node.columns[0].constraints[0].expression.left.value, 1
	assert_equal node.columns[0].constraints[0].expression.right.value, 2
	assert_equal node.columns[0].constraints[0].type, :STORED
end

test "create table tb0 (c0 constraint 'name' generated always as (1 + 2) stored)" do
	node = parse_stmt(<<~SQL)
		create table tb0 (c0 constraint 'name' generated always as (1 + 2) stored)
	SQL

	assert_equal node.table.name, "tb0"
	assert_equal node.columns[0].name, "c0"
	assert_operator Plume::GeneratedAsColumnConstraint, :===, node.columns[0].constraints[0]
	assert_equal node.columns[0].constraints[0].expression.operator, :ADD
	assert_equal node.columns[0].constraints[0].expression.left.value, 1
	assert_equal node.columns[0].constraints[0].expression.right.value, 2
	assert_equal node.columns[0].constraints[0].type, :STORED
	assert_equal node.columns[0].constraints[0].name, "name"
end

test "create table tb0 (c0 as (1 + 2) stored)" do
	node = parse_stmt(<<~SQL)
		create table tb0 (c0 as (1 + 2) stored)
	SQL

	assert_equal node.table.name, "tb0"
	assert_equal node.columns[0].name, "c0"
	assert_operator Plume::GeneratedAsColumnConstraint, :===, node.columns[0].constraints[0]
	assert_equal node.columns[0].constraints[0].expression.operator, :ADD
	assert_equal node.columns[0].constraints[0].expression.left.value, 1
	assert_equal node.columns[0].constraints[0].expression.right.value, 2
	assert_equal node.columns[0].constraints[0].type, :STORED
end

test "create table tb0 (c0 constraint 'name' as (1 + 2) stored)" do
	node = parse_stmt(<<~SQL)
		create table tb0 (c0 constraint 'name' as (1 + 2) stored)
	SQL

	assert_equal node.table.name, "tb0"
	assert_equal node.columns[0].name, "c0"
	assert_operator Plume::GeneratedAsColumnConstraint, :===, node.columns[0].constraints[0]
	assert_equal node.columns[0].constraints[0].expression.operator, :ADD
	assert_equal node.columns[0].constraints[0].expression.left.value, 1
	assert_equal node.columns[0].constraints[0].expression.right.value, 2
	assert_equal node.columns[0].constraints[0].type, :STORED
	assert_equal node.columns[0].constraints[0].name, "name"
end

test "create table tb0 (c0 generated always as (1 + 2) virtual)" do
	node = parse_stmt(<<~SQL)
		create table tb0 (c0 generated always as (1 + 2) virtual)
	SQL

	assert_equal node.table.name, "tb0"
	assert_equal node.columns[0].name, "c0"
	assert_operator Plume::GeneratedAsColumnConstraint, :===, node.columns[0].constraints[0]
	assert_equal node.columns[0].constraints[0].expression.operator, :ADD
	assert_equal node.columns[0].constraints[0].expression.left.value, 1
	assert_equal node.columns[0].constraints[0].expression.right.value, 2
	assert_equal node.columns[0].constraints[0].type, :VIRTUAL
end

test "create table tb0 (c0 constraint 'name' generated always as (1 + 2) virtual)" do
	node = parse_stmt(<<~SQL)
		create table tb0 (c0 constraint 'name' generated always as (1 + 2) virtual)
	SQL

	assert_equal node.table.name, "tb0"
	assert_equal node.columns[0].name, "c0"
	assert_operator Plume::GeneratedAsColumnConstraint, :===, node.columns[0].constraints[0]
	assert_equal node.columns[0].constraints[0].expression.operator, :ADD
	assert_equal node.columns[0].constraints[0].expression.left.value, 1
	assert_equal node.columns[0].constraints[0].expression.right.value, 2
	assert_equal node.columns[0].constraints[0].type, :VIRTUAL
	assert_equal node.columns[0].constraints[0].name, "name"
end

test "create table tb0 (c0 as (1 + 2) virtual)" do
	node = parse_stmt(<<~SQL)
		create table tb0 (c0 as (1 + 2) virtual)
	SQL

	assert_equal node.table.name, "tb0"
	assert_equal node.columns[0].name, "c0"
	assert_operator Plume::GeneratedAsColumnConstraint, :===, node.columns[0].constraints[0]
	assert_equal node.columns[0].constraints[0].expression.operator, :ADD
	assert_equal node.columns[0].constraints[0].expression.left.value, 1
	assert_equal node.columns[0].constraints[0].expression.right.value, 2
	assert_equal node.columns[0].constraints[0].type, :VIRTUAL
end

test "create table tb0 (c0 constraint 'name' as (1 + 2) virtual)" do
	node = parse_stmt(<<~SQL)
		create table tb0 (c0 constraint 'name' as (1 + 2) virtual)
	SQL

	assert_equal node.table.name, "tb0"
	assert_equal node.columns[0].name, "c0"
	assert_operator Plume::GeneratedAsColumnConstraint, :===, node.columns[0].constraints[0]
	assert_equal node.columns[0].constraints[0].expression.operator, :ADD
	assert_equal node.columns[0].constraints[0].expression.left.value, 1
	assert_equal node.columns[0].constraints[0].expression.right.value, 2
	assert_equal node.columns[0].constraints[0].type, :VIRTUAL
	assert_equal node.columns[0].constraints[0].name, "name"
end

test "create table tb0 (c0 references tb1(c1))" do
	node = parse_stmt(<<~SQL)
		create table tb0 (c0 references tb1(c1))
	SQL

	assert_equal node.table.name, "tb0"
	assert_equal node.columns[0].name, "c0"
	assert_operator Plume::ForeignKeyColumnConstraint, :===, node.columns[0].constraints[0]
	assert_equal node.columns[0].constraints[0].foreign_key_clause.table, "tb1"
	assert_equal node.columns[0].constraints[0].foreign_key_clause.columns[0].name, "c1"
end

test "create table tb0 (c0 constraint 'name' references tb1(c1))" do
	node = parse_stmt(<<~SQL)
		create table tb0 (c0 constraint 'name' references tb1(c1))
	SQL

	assert_equal node.table.name, "tb0"
	assert_equal node.columns[0].name, "c0"
	assert_operator Plume::ForeignKeyColumnConstraint, :===, node.columns[0].constraints[0]
	assert_equal node.columns[0].constraints[0].foreign_key_clause.table, "tb1"
	assert_equal node.columns[0].constraints[0].foreign_key_clause.columns[0].name, "c1"
	assert_equal node.columns[0].constraints[0].name, "name"
end

test "create table tb0 (c0 references tb1(c1) on delete set null)" do
	node = parse_stmt(<<~SQL)
		create table tb0 (c0 references tb1(c1) on delete set null)
	SQL

	assert_equal node.table.name, "tb0"
	assert_equal node.columns[0].name, "c0"
	assert_operator Plume::ForeignKeyColumnConstraint, :===, node.columns[0].constraints[0]
	assert_equal node.columns[0].constraints[0].foreign_key_clause.table, "tb1"
	assert_equal node.columns[0].constraints[0].foreign_key_clause.columns[0].name, "c1"
	assert_equal node.columns[0].constraints[0].foreign_key_clause.on_delete, :SET_NULL
end

test "create table tb0 (c0 references tb1(c1) on delete set default)" do
	node = parse_stmt(<<~SQL)
		create table tb0 (c0 references tb1(c1) on delete set default)
	SQL

	assert_equal node.table.name, "tb0"
	assert_equal node.columns[0].name, "c0"
	assert_operator Plume::ForeignKeyColumnConstraint, :===, node.columns[0].constraints[0]
	assert_equal node.columns[0].constraints[0].foreign_key_clause.table, "tb1"
	assert_equal node.columns[0].constraints[0].foreign_key_clause.columns[0].name, "c1"
	assert_equal node.columns[0].constraints[0].foreign_key_clause.on_delete, :SET_DEFAULT
end

test "create table tb0 (c0 references tb1(c1) on delete cascade)" do
	node = parse_stmt(<<~SQL)
		create table tb0 (c0 references tb1(c1) on delete cascade)
	SQL

	assert_equal node.table.name, "tb0"
	assert_equal node.columns[0].name, "c0"
	assert_operator Plume::ForeignKeyColumnConstraint, :===, node.columns[0].constraints[0]
	assert_equal node.columns[0].constraints[0].foreign_key_clause.table, "tb1"
	assert_equal node.columns[0].constraints[0].foreign_key_clause.columns[0].name, "c1"
	assert_equal node.columns[0].constraints[0].foreign_key_clause.on_delete, :CASCADE
end

test "create table tb0 (c0 references tb1(c1) on delete restrict)" do
	node = parse_stmt(<<~SQL)
		create table tb0 (c0 references tb1(c1) on delete restrict)
	SQL

	assert_equal node.table.name, "tb0"
	assert_equal node.columns[0].name, "c0"
	assert_operator Plume::ForeignKeyColumnConstraint, :===, node.columns[0].constraints[0]
	assert_equal node.columns[0].constraints[0].foreign_key_clause.table, "tb1"
	assert_equal node.columns[0].constraints[0].foreign_key_clause.columns[0].name, "c1"
	assert_equal node.columns[0].constraints[0].foreign_key_clause.on_delete, :RESTRICT
end

test "create table tb0 (c0 references tb1(c1) on delete no action)" do
	node = parse_stmt(<<~SQL)
		create table tb0 (c0 references tb1(c1) on delete no action)
	SQL

	assert_equal node.table.name, "tb0"
	assert_equal node.columns[0].name, "c0"
	assert_operator Plume::ForeignKeyColumnConstraint, :===, node.columns[0].constraints[0]
	assert_equal node.columns[0].constraints[0].foreign_key_clause.table, "tb1"
	assert_equal node.columns[0].constraints[0].foreign_key_clause.columns[0].name, "c1"
	assert_equal node.columns[0].constraints[0].foreign_key_clause.on_delete, :NO_ACTION
end

test "create table tb0 (c0 references tb1(c1) on update set null)" do
	node = parse_stmt(<<~SQL)
		create table tb0 (c0 references tb1(c1) on update set null)
	SQL

	assert_equal node.table.name, "tb0"
	assert_equal node.columns[0].name, "c0"
	assert_operator Plume::ForeignKeyColumnConstraint, :===, node.columns[0].constraints[0]
	assert_equal node.columns[0].constraints[0].foreign_key_clause.table, "tb1"
	assert_equal node.columns[0].constraints[0].foreign_key_clause.columns[0].name, "c1"
	assert_equal node.columns[0].constraints[0].foreign_key_clause.on_update, :SET_NULL
end

test "create table tb0 (c0 references tb1(c1) on update set default)" do
	node = parse_stmt(<<~SQL)
		create table tb0 (c0 references tb1(c1) on update set default)
	SQL

	assert_equal node.table.name, "tb0"
	assert_equal node.columns[0].name, "c0"
	assert_operator Plume::ForeignKeyColumnConstraint, :===, node.columns[0].constraints[0]
	assert_equal node.columns[0].constraints[0].foreign_key_clause.table, "tb1"
	assert_equal node.columns[0].constraints[0].foreign_key_clause.columns[0].name, "c1"
	assert_equal node.columns[0].constraints[0].foreign_key_clause.on_update, :SET_DEFAULT
end

test "create table tb0 (c0 references tb1(c1) on update cascade)" do
	node = parse_stmt(<<~SQL)
		create table tb0 (c0 references tb1(c1) on update cascade)
	SQL

	assert_equal node.table.name, "tb0"
	assert_equal node.columns[0].name, "c0"
	assert_operator Plume::ForeignKeyColumnConstraint, :===, node.columns[0].constraints[0]
	assert_equal node.columns[0].constraints[0].foreign_key_clause.table, "tb1"
	assert_equal node.columns[0].constraints[0].foreign_key_clause.columns[0].name, "c1"
	assert_equal node.columns[0].constraints[0].foreign_key_clause.on_update, :CASCADE
end

test "create table tb0 (c0 references tb1(c1) on update restrict)" do
	node = parse_stmt(<<~SQL)
		create table tb0 (c0 references tb1(c1) on update restrict)
	SQL

	assert_equal node.table.name, "tb0"
	assert_equal node.columns[0].name, "c0"
	assert_operator Plume::ForeignKeyColumnConstraint, :===, node.columns[0].constraints[0]
	assert_equal node.columns[0].constraints[0].foreign_key_clause.table, "tb1"
	assert_equal node.columns[0].constraints[0].foreign_key_clause.columns[0].name, "c1"
	assert_equal node.columns[0].constraints[0].foreign_key_clause.on_update, :RESTRICT
end

test "create table tb0 (c0 references tb1(c1) on update no action)" do
	node = parse_stmt(<<~SQL)
		create table tb0 (c0 references tb1(c1) on update no action)
	SQL

	assert_equal node.table.name, "tb0"
	assert_equal node.columns[0].name, "c0"
	assert_operator Plume::ForeignKeyColumnConstraint, :===, node.columns[0].constraints[0]
	assert_equal node.columns[0].constraints[0].foreign_key_clause.table, "tb1"
	assert_equal node.columns[0].constraints[0].foreign_key_clause.columns[0].name, "c1"
	assert_equal node.columns[0].constraints[0].foreign_key_clause.on_update, :NO_ACTION
end

test "create table tb0 (c0 references tb1(c1) on update no action on delete no action)" do
	node = parse_stmt(<<~SQL)
		create table tb0 (c0 references tb1(c1) on update no action on delete no action)
	SQL

	assert_equal node.table.name, "tb0"
	assert_equal node.columns[0].name, "c0"
	assert_operator Plume::ForeignKeyColumnConstraint, :===, node.columns[0].constraints[0]
	assert_equal node.columns[0].constraints[0].foreign_key_clause.table, "tb1"
	assert_equal node.columns[0].constraints[0].foreign_key_clause.columns[0].name, "c1"
	assert_equal node.columns[0].constraints[0].foreign_key_clause.on_update, :NO_ACTION
	assert_equal node.columns[0].constraints[0].foreign_key_clause.on_delete, :NO_ACTION
end

test "create table tb0 (c0 references tb1(c1) match full)" do
	node = parse_stmt(<<~SQL)
		create table tb0 (c0 references tb1(c1) match full)
	SQL

	assert_equal node.table.name, "tb0"
	assert_equal node.columns[0].name, "c0"
	assert_operator Plume::ForeignKeyColumnConstraint, :===, node.columns[0].constraints[0]
	assert_equal node.columns[0].constraints[0].foreign_key_clause.table, "tb1"
	assert_equal node.columns[0].constraints[0].foreign_key_clause.columns[0].name, "c1"
	assert_equal node.columns[0].constraints[0].foreign_key_clause.match_type, :FULL
end

test "create table tb0 (c0 references tb1(c1) deferrable initially deferred)" do
	node = parse_stmt(<<~SQL)
		create table tb0 (c0 references tb1(c1) deferrable initially deferred)
	SQL

	assert_equal node.table.name, "tb0"
	assert_equal node.columns[0].name, "c0"
	assert_operator Plume::ForeignKeyColumnConstraint, :===, node.columns[0].constraints[0]
	assert_equal node.columns[0].constraints[0].foreign_key_clause.table, "tb1"
	assert_equal node.columns[0].constraints[0].foreign_key_clause.columns[0].name, "c1"
	assert_equal node.columns[0].constraints[0].foreign_key_clause.deferred, true
end

test "create table tb0 (c0 references tb1(c1) deferrable)" do
	node = parse_stmt(<<~SQL)
		create table tb0 (c0 references tb1(c1) deferrable)
	SQL

	assert_equal node.table.name, "tb0"
	assert_equal node.columns[0].name, "c0"
	assert_operator Plume::ForeignKeyColumnConstraint, :===, node.columns[0].constraints[0]
	assert_equal node.columns[0].constraints[0].foreign_key_clause.table, "tb1"
	assert_equal node.columns[0].constraints[0].foreign_key_clause.columns[0].name, "c1"
	assert_equal node.columns[0].constraints[0].foreign_key_clause.deferred, false
end

test "create table tb0 (c0 references tb1(c1) not deferrable)" do
	node = parse_stmt(<<~SQL)
		create table tb0 (c0 references tb1(c1) not deferrable)
	SQL

	assert_equal node.table.name, "tb0"
	assert_equal node.columns[0].name, "c0"
	assert_operator Plume::ForeignKeyColumnConstraint, :===, node.columns[0].constraints[0]
	assert_equal node.columns[0].constraints[0].foreign_key_clause.table, "tb1"
	assert_equal node.columns[0].constraints[0].foreign_key_clause.columns[0].name, "c1"
	assert_equal node.columns[0].constraints[0].foreign_key_clause.deferred, false
end

test "create table tb0 (c0 references tb1(c1) deferrable initially immediate)" do
	node = parse_stmt(<<~SQL)
		create table tb0 (c0 references tb1(c1) deferrable initially immediate)
	SQL

	assert_equal node.table.name, "tb0"
	assert_equal node.columns[0].name, "c0"
	assert_operator Plume::ForeignKeyColumnConstraint, :===, node.columns[0].constraints[0]
	assert_equal node.columns[0].constraints[0].foreign_key_clause.table, "tb1"
	assert_equal node.columns[0].constraints[0].foreign_key_clause.columns[0].name, "c1"
	assert_equal node.columns[0].constraints[0].foreign_key_clause.deferred, false
end

test "create table tb0 (c0 references tb1(c1) not deferrable initially deferred)" do
	node = parse_stmt(<<~SQL)
		create table tb0 (c0 references tb1(c1) not deferrable initially deferred)
	SQL

	assert_equal node.table.name, "tb0"
	assert_equal node.columns[0].name, "c0"
	assert_operator Plume::ForeignKeyColumnConstraint, :===, node.columns[0].constraints[0]
	assert_equal node.columns[0].constraints[0].foreign_key_clause.table, "tb1"
	assert_equal node.columns[0].constraints[0].foreign_key_clause.columns[0].name, "c1"
	assert_equal node.columns[0].constraints[0].foreign_key_clause.deferred, false
end

test "create table tb0 (c0 references tb1(c1) not deferrable initially immediate)" do
	node = parse_stmt(<<~SQL)
		create table tb0 (c0 references tb1(c1) not deferrable initially immediate)
	SQL

	assert_equal node.table.name, "tb0"
	assert_equal node.columns[0].name, "c0"
	assert_operator Plume::ForeignKeyColumnConstraint, :===, node.columns[0].constraints[0]
	assert_equal node.columns[0].constraints[0].foreign_key_clause.table, "tb1"
	assert_equal node.columns[0].constraints[0].foreign_key_clause.columns[0].name, "c1"
	assert_equal node.columns[0].constraints[0].foreign_key_clause.deferred, false
end

# table options

test "create table tb0 (c0) STRICT" do
	node = parse_stmt(<<~SQL)
		create table tb0 (c0) STRICT
	SQL

	assert_equal node.table.name, "tb0"
	assert_equal node.columns[0].name, "c0"
	assert_equal node.strict, true
	assert_operator Plume::StrictTableOption, :===, node.options[0]
end

test "create table tb0 (c0) WITHOUT ROWID" do
	node = parse_stmt(<<~SQL)
		create table tb0 (c0) WITHOUT ROWID
	SQL

	assert_equal node.table.name, "tb0"
	assert_equal node.columns[0].name, "c0"
	assert_equal node.without_row_id, true
	assert_operator Plume::WithoutRowidTableOption, :===, node.options[0]
end

test "create table tb0 (c0) STRICT, WITHOUT ROWID" do
	node = parse_stmt(<<~SQL)
		create table tb0 (c0) STRICT, WITHOUT ROWID
	SQL

	assert_equal node.table.name, "tb0"
	assert_equal node.columns[0].name, "c0"
	assert_equal node.strict, true
	assert_operator Plume::StrictTableOption, :===, node.options[0]
	assert_equal node.without_row_id, true
	assert_operator Plume::WithoutRowidTableOption, :===, node.options[1]
end

# table constraints

test "create table tb0 (c0, primary key (c0))" do
	node = parse_stmt(<<~SQL)
		create table tb0 (c0, primary key (c0))
	SQL

	assert_equal node.table.name, "tb0"
	assert_equal node.columns[0].name, "c0"
	assert_operator Plume::PrimaryKeyTableConstraint, :===, node.constraints[0]
	assert_equal node.constraints[0].columns[0].name, "c0"
end

test "create table tb0 (c0, c1, primary key (c0, c1))" do
	node = parse_stmt(<<~SQL)
		create table tb0 (c0, c1, primary key (c0, c1))
	SQL

	assert_equal node.table.name, "tb0"
	assert_equal node.columns[0].name, "c0"
	assert_equal node.columns[1].name, "c1"
	assert_operator Plume::PrimaryKeyTableConstraint, :===, node.constraints[0]
	assert_equal node.constraints[0].columns[0].name, "c0"
	assert_equal node.constraints[0].columns[1].name, "c1"
end

test "create table tb0 (c0, primary key (c0 autoincrement))" do
	node = parse_stmt(<<~SQL)
		create table tb0 (c0, primary key (c0 autoincrement))
	SQL

	assert_equal node.table.name, "tb0"
	assert_equal node.columns[0].name, "c0"
	assert_operator Plume::PrimaryKeyTableConstraint, :===, node.constraints[0]
	assert_equal node.constraints[0].columns[0].name, "c0"
	assert_equal node.constraints[0].autoincrement, true
end

test "create table tb0 (c0, primary key (c0) on conflict abort)" do
	node = parse_stmt(<<~SQL)
		create table tb0 (c0, primary key (c0) on conflict abort)
	SQL

	assert_equal node.table.name, "tb0"
	assert_equal node.columns[0].name, "c0"
	assert_operator Plume::PrimaryKeyTableConstraint, :===, node.constraints[0]
	assert_equal node.constraints[0].columns[0].name, "c0"
	assert_equal node.constraints[0].conflict_clause.resolution, :ABORT
end

test "create table tb0 (c0, c1, primary key (c0, c1 autoincrement) on conflict abort)" do
	node = parse_stmt(<<~SQL)
		create table tb0 (c0, c1, primary key (c0, c1 autoincrement) on conflict abort)
	SQL

	assert_equal node.table.name, "tb0"
	assert_equal node.columns[0].name, "c0"
	assert_equal node.columns[1].name, "c1"
	assert_operator Plume::PrimaryKeyTableConstraint, :===, node.constraints[0]
	assert_equal node.constraints[0].columns[0].name, "c0"
	assert_equal node.constraints[0].columns[1].name, "c1"
	assert_equal node.constraints[0].autoincrement, true
	assert_equal node.constraints[0].conflict_clause.resolution, :ABORT
end

test "create table tb0 (c0, unique (c0))" do
	node = parse_stmt(<<~SQL)
		create table tb0 (c0, unique (c0))
	SQL

	assert_equal node.table.name, "tb0"
	assert_equal node.columns[0].name, "c0"
	assert_operator Plume::UniqueTableConstraint, :===, node.constraints[0]
	assert_equal node.constraints[0].columns[0].name, "c0"
end

test "create table tb0 (c0, c1, unique (c0, c1))" do
	node = parse_stmt(<<~SQL)
		create table tb0 (c0, c1, unique (c0, c1))
	SQL

	assert_equal node.table.name, "tb0"
	assert_equal node.columns[0].name, "c0"
	assert_equal node.columns[1].name, "c1"
	assert_operator Plume::UniqueTableConstraint, :===, node.constraints[0]
	assert_equal node.constraints[0].columns[0].name, "c0"
	assert_equal node.constraints[0].columns[1].name, "c1"
end

test "create table tb0 (c0, unique (c0) on conflict rollback)" do
	node = parse_stmt(<<~SQL)
		create table tb0 (c0, unique (c0) on conflict rollback)
	SQL

	assert_equal node.table.name, "tb0"
	assert_equal node.columns[0].name, "c0"
	assert_operator Plume::UniqueTableConstraint, :===, node.constraints[0]
	assert_equal node.constraints[0].columns[0].name, "c0"
	assert_equal node.constraints[0].conflict_clause.resolution, :ROLLBACK
end

test "create table tb0 (c0, c1, unique (c0, c1) on conflict rollback)" do
	node = parse_stmt(<<~SQL)
		create table tb0 (c0, c1, unique (c0, c1) on conflict rollback)
	SQL

	assert_equal node.table.name, "tb0"
	assert_equal node.columns[0].name, "c0"
	assert_equal node.columns[1].name, "c1"
	assert_operator Plume::UniqueTableConstraint, :===, node.constraints[0]
	assert_equal node.constraints[0].columns[0].name, "c0"
	assert_equal node.constraints[0].columns[1].name, "c1"
	assert_equal node.constraints[0].conflict_clause.resolution, :ROLLBACK
end

test "create table tb0 (c0, check (c0 > 0))" do
	node = parse_stmt(<<~SQL)
		create table tb0 (c0, check (c0 > 0))
	SQL

	assert_equal node.table.name, "tb0"
	assert_equal node.columns[0].name, "c0"
	assert_operator Plume::CheckTableConstraint, :===, node.constraints[0]
	assert_equal node.constraints[0].expression.operator, :ABOVE
	assert_operator Plume::ColumnName, :===, node.constraints[0].expression.left
	assert_equal node.constraints[0].expression.left.column, "c0"
	assert_equal node.constraints[0].expression.right.value, 0
end

test "create table tb0 (c0, foreign key (c0) references tb1(c1))" do
	node = parse_stmt(<<~SQL)
		create table tb0 (c0, foreign key (c0) references tb1(c1))
	SQL

	assert_equal node.table.name, "tb0"
	assert_equal node.columns[0].name, "c0"
	assert_operator Plume::ForeignKeyTableConstraint, :===, node.constraints[0]
	assert_equal node.constraints[0].columns[0].name, "c0"
	assert_equal node.constraints[0].foreign_key_clause.table, "tb1"
	assert_equal node.constraints[0].foreign_key_clause.columns[0].name, "c1"
end

test "create table tb0 (c0, foreign key (c0) references tb1(c1) on delete no action)" do
	node = parse_stmt(<<~SQL)
		create table tb0 (c0, foreign key (c0) references tb1(c1) on delete no action)
	SQL

	assert_equal node.table.name, "tb0"
	assert_equal node.columns[0].name, "c0"
	assert_operator Plume::ForeignKeyTableConstraint, :===, node.constraints[0]
	assert_equal node.constraints[0].columns[0].name, "c0"
	assert_equal node.constraints[0].foreign_key_clause.table, "tb1"
	assert_equal node.constraints[0].foreign_key_clause.columns[0].name, "c1"
	assert_equal node.constraints[0].foreign_key_clause.on_delete, :NO_ACTION
end

test "create table tb0 (c0, foreign key (c0) references tb1(c1) on update no action)" do
	node = parse_stmt(<<~SQL)
		create table tb0 (c0, foreign key (c0) references tb1(c1) on update no action)
	SQL

	assert_equal node.table.name, "tb0"
	assert_equal node.columns[0].name, "c0"
	assert_operator Plume::ForeignKeyTableConstraint, :===, node.constraints[0]
	assert_equal node.constraints[0].columns[0].name, "c0"
	assert_equal node.constraints[0].foreign_key_clause.table, "tb1"
	assert_equal node.constraints[0].foreign_key_clause.columns[0].name, "c1"
	assert_equal node.constraints[0].foreign_key_clause.on_update, :NO_ACTION
end

test "create table tb0 (c0, foreign key (c0) references tb1(c1) on delete cascade on update set null)" do
	node = parse_stmt(<<~SQL)
		create table tb0 (c0, foreign key (c0) references tb1(c1) on delete cascade on update set null)
	SQL

	assert_equal node.table.name, "tb0"
	assert_equal node.columns[0].name, "c0"
	assert_operator Plume::ForeignKeyTableConstraint, :===, node.constraints[0]
	assert_equal node.constraints[0].columns[0].name, "c0"
	assert_equal node.constraints[0].foreign_key_clause.table, "tb1"
	assert_equal node.constraints[0].foreign_key_clause.columns[0].name, "c1"
	assert_equal node.constraints[0].foreign_key_clause.on_delete, :CASCADE
	assert_equal node.constraints[0].foreign_key_clause.on_update, :SET_NULL
end

test "create table tb0 (c0, foreign key (c0) references tb1(c1) match full)" do
	node = parse_stmt(<<~SQL)
		create table tb0 (c0, foreign key (c0) references tb1(c1) match full)
	SQL

	assert_equal node.table.name, "tb0"
	assert_equal node.columns[0].name, "c0"
	assert_operator Plume::ForeignKeyTableConstraint, :===, node.constraints[0]
	assert_equal node.constraints[0].columns[0].name, "c0"
	assert_equal node.constraints[0].foreign_key_clause.table, "tb1"
	assert_equal node.constraints[0].foreign_key_clause.columns[0].name, "c1"
	assert_equal node.constraints[0].foreign_key_clause.match_type, :FULL
end

test "create table tb0 (c0, foreign key (c0) references tb1(c1) deferrable initially deferred)" do
	node = parse_stmt(<<~SQL)
		create table tb0 (c0, foreign key (c0) references tb1(c1) deferrable initially deferred)
	SQL

	assert_equal node.table.name, "tb0"
	assert_equal node.columns[0].name, "c0"
	assert_operator Plume::ForeignKeyTableConstraint, :===, node.constraints[0]
	assert_equal node.constraints[0].columns[0].name, "c0"
	assert_equal node.constraints[0].foreign_key_clause.table, "tb1"
	assert_equal node.constraints[0].foreign_key_clause.columns[0].name, "c1"
	assert_equal node.constraints[0].foreign_key_clause.deferred, true
end

test "create table tb0 (c0, foreign key (c0) references tb1(c1) on delete cascade on update restrict match full deferrable initially deferred)" do
	node = parse_stmt(<<~SQL)
		create table tb0 (c0, foreign key (c0) references tb1(c1) on delete cascade on update restrict match full deferrable initially deferred)
	SQL

	assert_equal node.table.name, "tb0"
	assert_equal node.columns[0].name, "c0"
	assert_operator Plume::ForeignKeyTableConstraint, :===, node.constraints[0]
	assert_equal node.constraints[0].columns[0].name, "c0"
	assert_equal node.constraints[0].foreign_key_clause.table, "tb1"
	assert_equal node.constraints[0].foreign_key_clause.columns[0].name, "c1"
	assert_equal node.constraints[0].foreign_key_clause.on_delete, :CASCADE
	assert_equal node.constraints[0].foreign_key_clause.on_update, :RESTRICT
	assert_equal node.constraints[0].foreign_key_clause.match_type, :FULL
	assert_equal node.constraints[0].foreign_key_clause.deferred, true
end

# complex statement

test "parse fully complex statement" do
	node = parse_stmt(<<~SQL)
		create temp table if not exists `schema0`."tb0" (
			[c],
			c0 integer constraint 'pk0' primary key desc on conflict abort autoincrement,
			c1 int constraint 'nonnull' not null on conflict rollback,
			c2 text constraint 'uniqued' unique on conflict ignore,
			c3 blob constraint 'checked' check (c3 > 0),
			c4 real constraint 'defaulted' default (1.1 * 2.2),
			c5 any constraint 'collated' collate rtrim,
			c6 decimal(4, 6) constraint 'generated' generated always as (1.1 + 2.2) stored,
			c7 constraint 'fk0' references tb1(c1) on delete set null on update cascade match full deferrable initially deferred,
			primary key (c0, c1 autoincrement) on conflict abort,
			unique (c0, c1) on conflict rollback
			check (c0 > 0)
			foreign key (c0) references tb1(c1) on delete cascade on update restrict match full deferrable initially deferred
		) STRICT, WITHOUT ROWID;
	SQL

	assert_equal node.table.schema, "schema0"
	assert_equal node.table.name, "tb0"
	assert_equal node.temporary, true
	assert_equal node.if_not_exists, true

	assert_equal node.columns[0].name, "c"
	assert_operator nil, :===, node.columns[0].type

	assert_equal node.columns[1].name, "c0"
	assert_equal node.columns[1].type.text, "integer"
	assert_equal node.columns[1].type.affinity, :INTEGER
	assert_operator Plume::PrimaryKeyColumnConstraint, :===, node.columns[1].constraints[0]
	assert_equal node.columns[1].constraints[0].name, "pk0"
	assert_equal node.columns[1].constraints[0].direction, :DESC
	assert_equal node.columns[1].constraints[0].conflict_clause.resolution, :ABORT
	assert_equal node.columns[1].constraints[0].autoincrement, true

	assert_equal node.columns[2].name, "c1"
	assert_equal node.columns[2].type.text, "int"
	assert_equal node.columns[2].type.affinity, :INTEGER
	assert_operator Plume::NotNullColumnConstraint, :===, node.columns[2].constraints[0]
	assert_equal node.columns[2].constraints[0].name, "nonnull"
	assert_equal node.columns[2].constraints[0].conflict_clause.resolution, :ROLLBACK

	assert_equal node.columns[3].name, "c2"
	assert_equal node.columns[3].type.text, "text"
	assert_equal node.columns[3].type.affinity, :TEXT
	assert_operator Plume::UniqueColumnConstraint, :===, node.columns[3].constraints[0]
	assert_equal node.columns[3].constraints[0].name, "uniqued"
	assert_equal node.columns[3].constraints[0].conflict_clause.resolution, :IGNORE

	assert_equal node.columns[4].name, "c3"
	assert_equal node.columns[4].type.text, "blob"
	assert_equal node.columns[4].type.affinity, :BLOB
	assert_operator Plume::CheckColumnConstraint, :===, node.columns[4].constraints[0]
	assert_equal node.columns[4].constraints[0].name, "checked"
	assert_equal node.columns[4].constraints[0].expression.operator, :ABOVE
	assert_operator Plume::ColumnName, :===, node.columns[4].constraints[0].expression.left
	assert_equal node.columns[4].constraints[0].expression.left.column, "c3"
	assert_equal node.columns[4].constraints[0].expression.right.value, 0

	assert_equal node.columns[5].name, "c4"
	assert_equal node.columns[5].type.text, "real"
	assert_equal node.columns[5].type.affinity, :REAL
	assert_operator Plume::DefaultColumnConstraint, :===, node.columns[5].constraints[0]
	assert_equal node.columns[5].constraints[0].name, "defaulted"
	assert_operator Plume::BinaryExpression, :===, node.columns[5].constraints[0].value
	assert_equal node.columns[5].constraints[0].value.operator, :MULTIPLY
	assert_equal node.columns[5].constraints[0].value.left.value, 1.1
	assert_equal node.columns[5].constraints[0].value.right.value, 2.2

	assert_equal node.columns[6].name, "c5"
	assert_equal node.columns[6].type.text, "any"
	assert_equal node.columns[6].type.affinity, :ANY
	assert_operator Plume::CollateColumnConstraint, :===, node.columns[6].constraints[0]
	assert_equal node.columns[6].constraints[0].name, "collated"
	assert_equal node.columns[6].constraints[0].collation, :RTRIM

	assert_equal node.columns[7].name, "c6"
	assert_equal node.columns[7].type.text, "decimal(4, 6)"
	assert_equal node.columns[7].type.affinity, :ANY
	assert_operator Plume::GeneratedAsColumnConstraint, :===, node.columns[7].constraints[0]
	assert_equal node.columns[7].constraints[0].name, "generated"
	assert_equal node.columns[7].constraints[0].expression.operator, :ADD
	assert_equal node.columns[7].constraints[0].expression.left.value, 1.1
	assert_equal node.columns[7].constraints[0].expression.right.value, 2.2
	assert_equal node.columns[7].constraints[0].type, :STORED

	assert_equal node.columns[8].name, "c7"
	assert_equal node.columns[8].type, nil
	assert_operator Plume::ForeignKeyColumnConstraint, :===, node.columns[8].constraints[0]
	assert_equal node.columns[8].constraints[0].name, "fk0"
	assert_equal node.columns[8].constraints[0].foreign_key_clause.table, "tb1"
	assert_equal node.columns[8].constraints[0].foreign_key_clause.columns[0].name, "c1"
	assert_equal node.columns[8].constraints[0].foreign_key_clause.deferred, true
	assert_equal node.columns[8].constraints[0].foreign_key_clause.match_type, :FULL
	assert_equal node.columns[8].constraints[0].foreign_key_clause.on_update, :CASCADE
	assert_equal node.columns[8].constraints[0].foreign_key_clause.on_delete, :SET_NULL

	assert_operator Plume::PrimaryKeyTableConstraint, :===, node.constraints[0]
	assert_equal node.constraints[0].columns[0].name, "c0"
	assert_equal node.constraints[0].columns[1].name, "c1"
	assert_equal node.constraints[0].autoincrement, true
	assert_equal node.constraints[0].conflict_clause.resolution, :ABORT

	assert_operator Plume::UniqueTableConstraint, :===, node.constraints[1]
	assert_equal node.constraints[1].columns[0].name, "c0"
	assert_equal node.constraints[1].columns[1].name, "c1"
	assert_equal node.constraints[1].conflict_clause.resolution, :ROLLBACK

	assert_operator Plume::CheckTableConstraint, :===, node.constraints[2]
	assert_equal node.constraints[2].expression.operator, :ABOVE
	assert_operator Plume::ColumnName, :===, node.constraints[2].expression.left
	assert_equal node.constraints[2].expression.left.column, "c0"
	assert_equal node.constraints[2].expression.right.value, 0

	assert_operator Plume::ForeignKeyTableConstraint, :===, node.constraints[3]
	assert_equal node.constraints[3].columns[0].name, "c0"
	assert_equal node.constraints[3].foreign_key_clause.table, "tb1"
	assert_equal node.constraints[3].foreign_key_clause.columns[0].name, "c1"
	assert_equal node.constraints[3].foreign_key_clause.on_delete, :CASCADE
	assert_equal node.constraints[3].foreign_key_clause.on_update, :RESTRICT
	assert_equal node.constraints[3].foreign_key_clause.match_type, :FULL
	assert_equal node.constraints[3].foreign_key_clause.deferred, true

	assert_equal node.strict, true
	assert_operator Plume::StrictTableOption, :===, node.options[0]
	assert_equal node.without_row_id, true
	assert_operator Plume::WithoutRowidTableOption, :===, node.options[1]
end

test "CREATE TABLE t (a REFERENCES t2 ON DELETE CASCADE, c DECIMAL(4, 6))" do
	# The REFERENCES clause looks ahead for DEFERRABLE, which used to throw off the span of the next type
	node = parse_stmt("CREATE TABLE t (a REFERENCES t2 ON DELETE CASCADE, c DECIMAL(4, 6))")

	assert_equal node.columns[1].type.text, "DECIMAL(4, 6)"
end

test "a foreign key clause can be built by hand" do
	clause = Plume::ForeignKeyClause.new(table: "users", deferred: true)

	assert_equal [clause.table, clause.deferred], ["users", true]
	assert_equal clause.to_sql, "REFERENCES users DEFERRABLE INITIALLY DEFERRED"
end

# The comma after the last column leads into the constraints, and the comma between constraints is optional
test "create table z(a, b, primary key(a) unique(b))" do
	["CREATE TABLE z(a, b, PRIMARY KEY(a) UNIQUE(b))", "CREATE TABLE z(a, b, PRIMARY KEY(a), UNIQUE(b))"].each do |sql|
		statement = parse_stmt(sql)

		assert_equal statement.columns.size, 2
		assert_equal statement.constraints.size, 2
	end
end

test "create table t(a, b, primary key(a desc, b nulls first), unique(a nulls last))" do
	statement = parse_stmt("CREATE TABLE t(a, b, PRIMARY KEY(a DESC, b NULLS FIRST), UNIQUE(a NULLS LAST))")

	assert_equal statement.constraints.first.columns.map(&:nulls), [nil, :FIRST]
	assert_equal statement.constraints.last.columns.first.nulls, :LAST
end

test "a column may be deferrable on its own, as SQLite's grammar allows" do
	constraints = parse_stmt("CREATE TABLE t(a NOT NULL DEFERRABLE INITIALLY DEFERRED, b NOT DEFERRABLE)").columns.map { |c| c.constraints.last }

	assert_equal constraints.map(&:class), [Plume::DeferrableColumnConstraint, Plume::DeferrableColumnConstraint]
	assert_equal constraints.map(&:deferred), [true, false]
end

test "a foreign key's on and match clauses come in any order" do
	clause = parse_stmt("CREATE TABLE t(a REFERENCES u MATCH FULL ON DELETE CASCADE MATCH SIMPLE ON UPDATE SET NULL)").columns.first.constraints.first.foreign_key_clause

	assert_equal [clause.on_delete, clause.on_update, clause.match_type], [:CASCADE, :SET_NULL, :SIMPLE]
end

test "nulls first or last only follows the columns of a primary key or unique" do
	["CREATE TABLE t(a REFERENCES u(b NULLS FIRST))", "CREATE TABLE t(a, FOREIGN KEY(a NULLS FIRST) REFERENCES u)", "WITH c(a NULLS FIRST) AS (SELECT 1) SELECT * FROM c"].each do |sql|
		assert_raises(Plume::SyntaxError) { Plume.parse(sql) }
	end
end

test "create table t(a references u on insert cascade)" do
	assert_equal parse_stmt("CREATE TABLE t(a REFERENCES u ON INSERT CASCADE)").columns.first.constraints.first.foreign_key_clause.actions.first.trigger, :INSERT
end

test "a type name that is not valid UTF-8 has an affinity" do
	node = parse_stmt((+"CREATE TABLE t (c \xFFREAL)").force_encoding(Encoding::UTF_8))

	assert_equal node.columns[0].type.affinity, :REAL
end
