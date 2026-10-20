# Plume

[![Gem Version](https://badge.fury.io/rb/plume.svg)](https://rubygems.org/gems/plume)
[![Gem Downloads](https://img.shields.io/gem/dt/plume)](https://rubygems.org/gems/plume)
![Tests](https://github.com/yippee-fun/plume/actions/workflows/main.yml/badge.svg)
[![Sponsors](https://img.shields.io/github/sponsors/fractaledmind?color=eb4aaa&logo=GitHub%20Sponsors)](https://github.com/sponsors/fractaledmind)
[![Twitter Follow](https://img.shields.io/twitter/url?label=%40fractaledmind&style=social&url=https%3A%2F%2Ftwitter.com%2Ffractaledmind)](https://twitter.com/fractaledmind)

<img src="/assets/logo.svg" width="100" alt="Plume logo: a blue feather quill pen" align="right" />

Plume is a Ruby library for working with SQLite elegantly. Presently, this means that it provides a pure Ruby implementation of SQLite's lexer/tokenizer as well as a 100% compatible parser. This is useful for introspecting the structure of SQL queries, and for building tools that work with SQL queries - like working out which tables and columns a query is going to read.

## Installation

Install the gem and add to the application's Gemfile by executing:

```bash
bundle add plume
```

If bundler is not being used to manage dependencies, install the gem by executing:

```bash
gem install plume
```

## Usage

Parse a SQL query with the `Plume::Parser` class:

Every statement in SQLite's grammar parses, and the parser is checked against the SQL in SQLite's own test suite: of the 15,836 statements there, the ones it does not parse are those SQLite rejects as well.

```ruby
sql = <<~SQL
  CREATE TEMP TABLE IF NOT EXISTS `schema0`."tb0" (
    c0 INTEGER PRIMARY KEY DESC ON CONFLICT ABORT AUTOINCREMENT,
    c1 INT NOT NULL ON CONFLICT ROLLBACK,
    c2 TEXT UNIQUE ON CONFLICT IGNORE,
    c3 BLOB CHECK (    c3 > 0),
    c4 REAL DEFAULT (1.1 * 2.2),
    c5 ANY COLLATE RTRIM,
    c6 DECIMAL(4, 6) GENERATED ALWAYS AS (1.1 + 2.2) STORED,
    c7 REFERENCES tb1(c1) ON DELETE SET NULL ON UPDATE CASCADE MATCH FULL DEFERRABLE INITIALLY DEFERRED,
    PRIMARY KEY (c0, c1 AUTOINCREMENT) ON CONFLICT ABORT,
    UNIQUE (c0, c1) ON CONFLICT ROLLBACK
    CHECK (c0 > 0)
    FOREIGN KEY (c0) REFERENCES tb1(c1) ON DELETE CASCADE ON UPDATE RESTRICT MATCH FULL DEFERRABLE INITIALLY DEFERRED
  ) WITHOUT ROWID;
SQL
ast = Plume.parse(sql).first # one node per statement
# => Plume::CreateTableStatement(...)
```

<details>
  <summary>(click to see full AST)</summary>

```ruby
Plume::CreateTableStatement(
  temporary = true,
  if_not_exists = true,
  table = Plume::TableName(
    schema = "schema0",
    table = "tb0",
  ),
  columns = [
    Plume::ColumnDefinition(
      name = "c0",
      type = Plume::ColumnType(
        text = "INTEGER",
        affinity = :INTEGER,
      ),
      constraints = [
        Plume::PrimaryKeyColumnConstraint(...),
      ],
    ),
    Plume::ColumnDefinition(
      name = "c1",
      type = Plume::ColumnType(
        text = "INT",
        affinity = :INTEGER,
      ),
      constraints = [
        Plume::NotNullColumnConstraint(...),
      ],
    ),
    Plume::ColumnDefinition(
      name = "c2",
      type = Plume::ColumnType(
        text = "TEXT",
        affinity = :TEXT,
      ),
      constraints = [
        Plume::UniqueColumnConstraint(...),
      ],
    ),
    Plume::ColumnDefinition(
      name = "c3",
      type = Plume::ColumnType(
        text = "BLOB",
        affinity = :BLOB,
      ),
      constraints = [
        Plume::CheckColumnConstraint(...),
      ],
    ),
    Plume::ColumnDefinition(
      name = "c4",
      type = Plume::ColumnType(
        text = "REAL",
        affinity = :REAL,
      ),
      constraints = [
        Plume::DefaultColumnConstraint(...),
      ],
    ),
    Plume::ColumnDefinition(
      name = "c5",
      type = Plume::ColumnType(
        text = "ANY",
        affinity = :ANY,
      ),
      constraints = [
        Plume::CollateColumnConstraint(...),
      ],
    ),
    Plume::ColumnDefinition(
      name = "c6",
      type = Plume::ColumnType(
        text = "DECIMAL(4, 6)",
        affinity = :ANY,
      ),
      constraints = [
        Plume::GeneratedAsColumnConstraint(...),
      ],
    ),
    Plume::ColumnDefinition(
      name = "c7",
      constraints = [
        Plume::ForeignKeyColumnConstraint(...),
      ],
    ),
  ],
  constraints = [
    Plume::PrimaryKeyTableConstraint(
      autoincrement = true,
      columns = [
        Plume::IndexedColumn(...),
        Plume::IndexedColumn(...),
      ],
      conflict_clause = Plume::ConflictClause(resolution = :ABORT),
    ),
    Plume::UniqueTableConstraint(
      columns = [
        Plume::IndexedColumn(...),
        Plume::IndexedColumn(...),
      ],
      conflict_clause = Plume::ConflictClause(resolution = :ROLLBACK),
    ),
    Plume::CheckTableConstraint(
      expression = Plume::BinaryExpression(
        operator = :ABOVE,
        left = Plume::ColumnName(...),
        right = Plume::LiteralExpression(...),
      ),
    ),
    Plume::ForeignKeyTableConstraint(
      columns = [Plume::IndexedColumn(...)],
      foreign_key_clause = Plume::ForeignKeyClause(
        table = "tb1",
        deferred = true,
        columns = [...],
        actions = [...],
        match_clauses = [...],
      ),
    ),
  ],
  options = [
    Plume::WithoutRowidTableOption(),
  ],
  select_statement = Object(),
  strict = false,
  without_row_id = true,
)
```
</details>


Turn a tree back into SQL with `to_sql`. It prints from the nodes' values rather than copying the source, so trees built by hand or changed after parsing print too:

```ruby
stmt = Plume.parse("select a from t where b = 1").first
stmt.body.condition = Plume::BinaryExpression.new(
  operator: :ALL,
  left: stmt.body.condition,
  right: Plume::BinaryExpression.new(operator: :EQUALS, left: Plume::ColumnName.new(column: "tenant_id"), right: Plume::Variable.new(name: "?")),
)
stmt.to_sql
# => "SELECT a FROM t WHERE (b = 1) AND (tenant_id = ?)"
```

Tokenize a SQL query with the `Plume::Lexer` class:

```ruby
tokens = Plume.tokenize("SELECT * FROM users WHERE id = 1")
# => [:SELECT, :STAR, :FROM, :ID, :WHERE, :ID, :EQ, :INTEGER]
```

SQLite works with a grammar of _167_ token types, _136_ of which are keywords. The remaining _31_ are punctuation, operators, and literals.

### What does this query read?

`Plume.reads` works out which tables and columns a statement would read, looking through aliases, joins, subqueries, CTEs and views:

```ruby
catalog = Plume::Catalog.from_sql(<<~SQL)
  CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT, email TEXT);
  CREATE TABLE posts (id INTEGER PRIMARY KEY, user_id INT, title TEXT);
SQL

reads = Plume.reads(<<~SQL, catalog: catalog)
  WITH recent AS (SELECT * FROM posts ORDER BY id DESC LIMIT 10)
  SELECT r.title, u.name FROM recent r JOIN users u ON u.id = r.user_id
  WHERE u.email LIKE '%@example.com'
SQL

reads.tables     # => #<Set: {"posts", "users"}>
reads.columns    # => {"posts" => #<Set: {"id", "user_id", "title"}>, "users" => #<Set: {"id", "name", "email"}>}
reads.projected  # columns whose values can end up in the result rows
reads.referenced # columns only used to filter, join, sort or group
```

`Plume.access` does the same for `INSERT`, `UPDATE` and `DELETE`, and also tells you what they write:

```ruby
access = Plume.access(<<~SQL, catalog: catalog)
  UPDATE posts SET title = upper(u.name) FROM users u WHERE u.id = posts.user_id RETURNING posts.id
SQL

access.writes.updated   # => {"posts" => #<Set: {"title"}>}
access.reads.projected  # => {"users" => #<Set: {"name"}>, "posts" => #<Set: {"id"}>}
access.reads.referenced # => {"users" => #<Set: {"id"}>, "posts" => #<Set: {"user_id"}>}
```

A value copied into a column being written counts as projected, just like one returned in the result rows.

Both also take what you already parsed - a statement node, or the array `Plume.parse` returns - so the SQL is not parsed twice, and a tree you changed after parsing is analyzed as changed.

The catalog can also come from a live database with `Plume::Catalog.from_sqlite(db)`, or be left out - then `SELECT *` is reported as a read of the column `"*"` and unqualified columns only resolve when there is a single table in scope.

Anything that cannot be attributed (an unknown table or column, an ambiguous name) raises `Plume::Analysis::Error` with a pointer into the SQL. Pass `strict: false` to get the partial result and a list in `reads.unresolved` instead. Each entry of `reads.references` carries the AST node it came from, so you can point at it too - see [examples/read_guard.rb](examples/read_guard.rb) for a small column-level access check built on top.

The results are tested against SQLite's own [authorizer callback](https://www.sqlite.org/c3ref/set_authorizer.html), which is also the place to enforce access rules at runtime when you have a connection. `Plume.reads` is for when you want to vet SQL ahead of time, without a database, or with good error messages. It reports one thing the authorizer does not: the right-hand join columns of `USING` and `NATURAL` joins.

### Ractors

Plume loads its parts lazily, and Ractors other than the main one cannot read the class-level state that leaves behind. Call `Plume.eager_load!` once from the main Ractor before starting any, and freeze the catalog with `Ractor.make_shareable` so it can be passed in:

```ruby
Plume.eager_load!
catalog = Ractor.make_shareable(Plume::Catalog.from_sql(schema_sql))

ractors = queries.each_slice(100).map do |batch|
  Ractor.new(batch, catalog) do |sqls, cat|
    sqls.map { |sql| Plume.reads(sql, catalog: cat, strict: false).columns }
  end
end
ractors.flat_map(&:value) # `take` before Ruby 4.0
```

`tokenize`, `parse`, `to_sql`, `walk`, `reads` and `access` all work inside a Ractor. Trees and results come back out like any other object, and a tree passed through `Ractor.make_shareable` can still be read, printed, walked and analyzed - it just can no longer be edited. After `eager_load!` the node classes cannot be given new props.

## Roadmap

- [x] `expression`
- [x] `alter_table_stmt`
- [x] `analyze_stmt`
- [x] `attach_stmt`
- [x] `begin_stmt`
- [x] `commit_stmt`
- [x] `create_table_stmt`
- [x] `create_index_stmt`
- [x] `create_trigger_stmt`
- [x] `create_view_stmt`
- [x] `create_virtual_table_stmt`
- [x] `delete_stmt`
- [x] `detach_stmt`
- [x] `drop_index_stmt`
- [x] `drop_table_stmt`
- [x] `drop_trigger_stmt`
- [x] `drop_view_stmt`
- [x] `insert_stmt`
- [x] `pragma_stmt`
- [x] `reindex_stmt`
- [x] `release_stmt`
- [x] `rollback_stmt`
- [x] `savepoint_stmt`
- [x] `select_stmt`
- [x] `update_stmt`
- [x] `vacuum_stmt`
- [x] `with_stmt`

## Performance

`bin/benchmark` runs the whole fixture corpus (15,817 statements, 4.2 MB of SQL). On an Apple M-series laptop with Ruby 3.4:

| Step | Statements/s | MB/s |
| --- | ---: | ---: |
| `Plume.tokenize` | ~13,500 | 3.7 |
| `Plume.parse` | ~1,400 | 0.38 |
| `Node#to_sql` | ~6,000 | 1.7 |
| `Plume.reads` (no catalog) | ~1,000 | 0.21 |

The corpus leans on very large generated expressions; a typical application query parses in well under a millisecond. About half of the parse time goes to Literal's runtime type checks on every node property.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests. `bin/fixture-report` shows how much of SQLite's own test SQL parses (pass `--write` to record it as the new baseline the tests hold us to), and `bin/benchmark` times the whole pipeline. `bin/trace-fixtures` runs SQLite's Tcl test suite and adds a fixture for each shape of statement it finds that the corpus lacks, and for each one where Plume and SQLite disagree. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/yippee-fun/plume. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/yippee-fun/plume/blob/main/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Plume project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/yippee-fun/plume/blob/main/CODE_OF_CONDUCT.md).
