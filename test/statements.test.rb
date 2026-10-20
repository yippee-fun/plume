# frozen_string_literal: true

# -- transactions

test "begin immediate transaction t" do
	node = parse_stmt("begin immediate transaction t")

	assert_operator Plume::BeginStatement, :===, node
	assert_equal node.type, :IMMEDIATE
end

test "begin" do
	assert_equal parse_stmt("begin").type, nil
end

test "commit, end transaction" do
	assert_operator Plume::CommitStatement, :===, parse_stmt("commit")
	assert_operator Plume::CommitStatement, :===, parse_stmt("end transaction")
end

test "rollback transaction to savepoint sp" do
	node = parse_stmt("rollback transaction to savepoint sp")

	assert_equal node.savepoint, "sp"
end

test "savepoint sp; release sp; release savepoint sp" do
	savepoint, release, release_savepoint = Plume.parse("savepoint sp; release sp; release savepoint sp")

	assert_equal [savepoint.name, release.name, release_savepoint.name], ["sp", "sp", "sp"]
end

# -- schema

test "drop table if exists main.t" do
	node = parse_stmt("drop table if exists main.t")

	assert_equal [node.type, node.if_exists, node.target.schema, node.target.name], [:TABLE, true, "main", "t"]
end

test "drop view, index, trigger" do
	assert_equal %w[view index trigger].map { |kind| parse_stmt("drop #{kind} x").type }, [:VIEW, :INDEX, :TRIGGER]
end

test "create unique index if not exists main.i on t (a desc, lower(b) collate nocase) where c > 0" do
	node = parse_stmt("create unique index if not exists main.i on t (a desc, lower(b) collate nocase) where c > 0")

	assert node.unique
	assert node.if_not_exists
	assert_equal [node.index.schema, node.index.name, node.table], ["main", "i", "t"]
	assert_equal node.columns.map(&:direction), [:DESC, nil]
	assert_equal node.columns[1].expression.expression.function, "lower"
	assert_operator Plume::BinaryExpression, :===, node.condition
end

test "alter table forms" do
	rename = parse_stmt("alter table main.t rename to u")
	assert_equal [rename.action, rename.table.schema, rename.new_name], [:RENAME_TABLE, "main", "u"]

	rename_column = parse_stmt("alter table t rename column a to b")
	assert_equal [rename_column.action, rename_column.column, rename_column.new_name], [:RENAME_COLUMN, "a", "b"]
	assert_equal parse_stmt("alter table t rename a to b").action, :RENAME_COLUMN

	add = parse_stmt("alter table t add column c int not null default 0")
	assert_equal [add.action, add.column_definition.name], [:ADD_COLUMN, "c"]
	assert_equal parse_stmt("alter table t add c").column_definition.name, "c"

	drop = parse_stmt("alter table t drop column c")
	assert_equal [drop.action, drop.column], [:DROP_COLUMN, "c"]
end

test "alter table constraint and not null forms" do
	add = parse_stmt("alter table t add constraint positive check (a > 0) on conflict ignore")
	assert_equal [add.action, add.constraint.name, add.constraint.conflict_clause.resolution], [:ADD_CONSTRAINT, "positive", :IGNORE]
	assert_equal [add.constraint_name, parse_stmt("alter table t add check (a > 0)").constraint_name], ["positive", nil]

	drop = parse_stmt("alter table t drop constraint positive")
	assert_equal [drop.action, drop.constraint_name], [:DROP_CONSTRAINT, "positive"]

	set = parse_stmt("alter table t alter column a set not null on conflict abort")
	assert_equal [set.action, set.column, set.conflict_clause.resolution], [:SET_NOT_NULL, "a", :ABORT]
	drop_not_null = parse_stmt("alter table t alter a drop not null")
	assert_equal [drop_not_null.action, drop_not_null.column], [:DROP_NOT_NULL, "a"]

	# Only CHECK can be added
	assert_raises(Plume::SyntaxError) { Plume.parse("alter table t add constraint u unique (a)") }
end

test "create virtual table if not exists v using fts5(a, b, tokenize = 'porter ascii', content = '')" do
	node = parse_stmt("create virtual table if not exists v using fts5(a, b, tokenize = 'porter ascii', content = '')")

	assert node.if_not_exists
	assert_equal node.module_name, "fts5"
	assert_equal node.arguments, ["a", "b", "tokenize = 'porter ascii'", "content = ''"]
end

test "create virtual table v using rtree(id, minx, maxx, +aux(nested, parens))" do
	assert_equal parse_stmt("create virtual table v using rtree(id, minx, maxx, +aux(nested, parens))").arguments,
		["id", "minx", "maxx", "+aux(nested, parens)"]
end

test "create virtual table v using mod" do
	assert_equal parse_stmt("create virtual table v using mod").arguments, []
end

test "create trigger" do
	node = parse_stmt(<<~SQL)
		create temp trigger if not exists tr instead of update of a, b on v for each row when new.a > 0 begin
			update t set x = new.a where id = old.id;
			insert into log values (new.a);
			delete from t where 0;
			select raise(abort, 'nope');
		end
	SQL

	assert node.temporary
	assert_equal [node.time, node.event, node.column_names, node.table.name], [:INSTEAD_OF, :UPDATE, ["a", "b"], "v"]
	assert_operator Plume::BinaryExpression, :===, node.condition
	assert_equal node.statements.map(&:class),
		[Plume::UpdateStatement, Plume::InsertStatement, Plume::DeleteStatement, Plume::SelectStatement]
end

test "create trigger tr after delete on t begin select 1; end" do
	node = parse_stmt("create trigger tr after delete on t begin select 1; end")

	assert_equal [node.time, node.event], [:AFTER, :DELETE]
end

# -- other

test "pragma forms" do
	assert_equal parse_stmt("pragma journal_mode").value, nil
	assert_equal parse_stmt("pragma main.cache_size = -2000").then { |s| [s.schema, s.name, s.value] }, ["main", "cache_size", -2000]
	assert_equal parse_stmt("pragma table_info('t')").value, "t"
	assert_equal parse_stmt("pragma foreign_keys = on").value, "on"
	assert_equal parse_stmt("pragma auto_vacuum = true").value, "true"
end

test "attach database 'x.db' as aux key 'k'" do
	node = parse_stmt("attach database 'x.db' as aux key 'k'")

	assert_equal [node.file.value, node.schema.column, node.key.value], ["x.db", "aux", "k"]
end

test "detach aux" do
	assert_equal parse_stmt("detach database aux").schema.column, "aux"
end

test "analyze, reindex and vacuum" do
	assert_equal parse_stmt("analyze").target, nil
	assert_equal parse_stmt("analyze main.t").target.schema, "main"
	assert_equal parse_stmt("reindex i").target.name, "i"
	assert_equal parse_stmt("vacuum").schema, nil
	assert_equal parse_stmt("vacuum main into 'backup.db'").then { |s| [s.schema, s.into.value] }, ["main", "backup.db"]
end

test "explain query plan select 1" do
	node = parse_stmt("explain query plan select 1")

	assert node.query_plan
	assert_operator Plume::SelectStatement, :===, node.statement
	refute parse_stmt("explain delete from t").query_plan
end

test "a statement with nothing to show inspects briefly" do
	assert parse_stmt("commit").inspect.match?(/\A#<Plume::CommitStatement:\d+>\z/)
end

# -- syntax errors

test "a syntax error points at the offending line" do
	error = assert_raises(Plume::SyntaxError) { Plume.parse("select a,\n  b\nfrom t where and x") }

	assert_equal error.message.split("\n"), [
		'Unexpected token AND["and"] at line 3:',
		"  from t where and x",
		"               ^^^",
		"  Expected one of: <basic expression>",
	]
end

test "running out of SQL is an error too" do
	error = assert_raises(Plume::SyntaxError) { Plume.parse("select * from") }

	assert_equal error.message.split("\n").first, "Unexpected end of input at:"
end

test "a syntax error in SQL that is not valid UTF-8 is still a syntax error" do
	error = assert_raises(Plume::SyntaxError) { Plume.parse((+"select \xFF,\n(").force_encoding(Encoding::UTF_8)) }

	assert_equal error.message.b.split("\n").first, "Unexpected end of input at line 2:"
end
