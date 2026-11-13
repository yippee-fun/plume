# Plume

[![Gem Version](https://badge.fury.io/rb/plume.svg)](https://rubygems.org/gems/plume)
[![Gem Downloads](https://img.shields.io/gem/dt/plume)](https://rubygems.org/gems/plume)
![Tests](https://github.com/yippee-fun/plume/actions/workflows/main.yml/badge.svg)
[![Sponsors](https://img.shields.io/github/sponsors/fractaledmind?color=eb4aaa&logo=GitHub%20Sponsors)](https://github.com/sponsors/fractaledmind)
[![Twitter Follow](https://img.shields.io/twitter/url?label=%40fractaledmind&style=social&url=https%3A%2F%2Ftwitter.com%2Ffractaledmind)](https://twitter.com/fractaledmind)

<img src="/assets/logo.svg" width="100" alt="Plume logo: a blue feather quill pen" align="right" />

Plume is a Ruby library for working with SQLite elegantly. Presently, this means that it provides a pure Ruby implementation of SQLite's lexer/tokenizer as well as a 100% compatible parser. This is useful for introspecting the structure of SQL queries, and for building tools that work with SQL queries - like working out which tables and columns a query is going to read.

## Installation

Plume needs Ruby 3.2 or later. Install the gem and add to the application's Gemfile by executing:

```bash
bundle add plume
```

If bundler is not being used to manage dependencies, install the gem by executing:

```bash
gem install plume
```

## Usage

Every statement in SQLite's grammar parses, and the parser is checked against the SQL in SQLite's own test suite - both the SQL written in its test files and the SQL they build as they run. Of the 26,977 fixture files in that corpus, Plume parses 26,707 and rejects 266 that SQLite rejects too. The 4 left are deliberate: 3 that Plume parses but SQLite refuses for reasons other than syntax, and 1 expression nested 1,000 deep, past what Plume's stack allows.

Parse SQL with `Plume.parse`, which returns one node per statement:

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

`walk` yields every node with its parent, and `walk_with_slots` also gives the prop the node sits in, plus its index when that prop is a list. `transform` builds a changed copy and leaves the original alone. Return a node from the block to keep it, or another node to put in its place:

```ruby
stmt = Plume.parse("SELECT a FROM t WHERE b IN (1, 2) ORDER BY 1").first
stmt.transform { |node, parent| Plume::LiteralExpression === node && !(Plume::OrderingTerm === parent) ? Plume::Variable.new(name: "?") : node }.to_sql
# => "SELECT a FROM t WHERE b IN (?, ?) ORDER BY 1"
```

Only the nodes on the way to a replacement are copied, and the rest is shared with the original. Neither method recurses, so trees as deep as SQLite allows are fine. This works on shareable trees as well.

`Plume.split` finds the statements in a script by their tokens alone, so it also works on SQL that doesn't parse. A trigger's body stays in one piece:

```ruby
Plume.split("SELECT 1; CREATE TRIGGER t AFTER INSERT ON x BEGIN DELETE FROM y; END; SELEC oops")
# => ["SELECT 1", "CREATE TRIGGER t AFTER INSERT ON x BEGIN DELETE FROM y; END", "SELEC oops"]
```
`to_sql(pretty: true)` lays the SQL out over lines. Each clause starts a line. A clause too long for `max_line_length` (80 by default) puts its items one per line, indented by `indent_size` (4), and a long `AND` or `OR` chain puts each operand on its own line. Subqueries are indented inside their parentheses. `commas_start_of_line: true` puts the commas at the start of the lines:

```ruby
Plume.parse("select id, title from posts p join users u on u.id = p.user_id where u.active and p.draft = 0").first.to_sql(pretty: true)
# => SELECT id, title
#    FROM posts AS p
#    JOIN users AS u ON u.id = p.user_id
#    WHERE u.active AND (p.draft = 0)
```

Pretty SQL parses back into the same tree, which is checked across the whole fixture corpus.

Tokenize SQL with `Plume.tokenize`:

```ruby
tokens = Plume.tokenize("SELECT * FROM users WHERE id = 1")
# => [:SELECT, :STAR, :FROM, :ID, :WHERE, :ID, :EQ, :INTEGER]
```

`with_values: true` adds each token's text, and `with_positions: true` its byte range in the SQL - for highlighting, or for finding a token's place in the original:

```ruby
Plume.tokenize("SELECT a FROM t", with_values: true, with_positions: true)
# => [[:SELECT, "SELECT", 0, 6], [:ID, "a", 7, 8], [:FROM, "FROM", 9, 13], [:ID, "t", 14, 15]]
```

`dump` turns a tree into a plain hash that JSON can carry, and `Plume.load` turns that hash back into the same tree. Positions, keywords as written and the source all come through, so the loaded tree prints, locates and compares as the original did. That makes it possible to cache parsed trees, or to hand them to another process:

```ruby
json = JSON.generate(Plume.parse("SELECT DISTINCT a FROM t").first.dump)
Plume.load(JSON.parse(json)).to_sql
# => "SELECT DISTINCT a FROM t"
```

Neither `dump` nor `load` recurses, but JSON's own generator and parser do, so a very deep tree needs `max_nesting: false` and enough stack.

The lexer knows _183_ token types: _153_ keywords, and _30_ more for punctuation, operators, literals and names. Words like `rowid`, `strict` and `stored`, which SQLite reads as plain names and checks by their text, are keywords here that fall back to names wherever SQLite would take a name.
The lexer knows _184_ token types: _153_ keywords, and _31_ more for punctuation, operators, literals, names and comments. Words like `rowid`, `strict` and `stored`, which SQLite reads as plain names and checks by their text, are keywords here that fall back to names wherever SQLite would take a name.

### Comments

Comments are tokens of their own (`:COMMENT`), which the parser skips the same way SQLite does. `Plume.comments` lists them with their byte ranges. `tags` reads [sqlcommenter](https://google.github.io/sqlcommenter/) comments, including the ones Rails' `query_log_tags` adds, in its current format and the older `key:value` one:

```ruby
sql = "SELECT * FROM posts /*controller='posts',action='index'*/"
Plume.comments(sql).first.tags # => {"controller" => "posts", "action" => "index"}
```

`to_sql(comments: true)` keeps the comments directly before and after a statement, such as a header line or the sqlcommenter tags. Comments inside the statement are left out. A trailing `--` comment is printed as `/* */`, so a semicolon after it doesn't become part of the comment:

```ruby
Plume.parse("-- report
select a from t /*app='shop'*/").first.to_sql(comments: true)
# => "-- report
SELECT a FROM t /*app='shop'*/"
```

`Plume.parameters` numbers a statement's bind parameters the way SQLite does - `?` takes the next number, `?N` takes N, and a name keeps the number it first got - so you know what to bind where before preparing anything:

```ruby
parameters = Plume.parameters("SELECT * FROM posts WHERE user_id = :user AND (title = ? OR body = ?) LIMIT :user")
parameters.count             # => 3
parameters.names             # => [":user", nil, nil]
parameters.index(":user")    # => 1
parameters.map(&:number)     # => [1, 2, 3, 1]
```

`count`, `names` and `index` answer what `sqlite3_bind_parameter_count`, `_name` and `_index` would. Each parameter also carries its `node`, and with it the `location` it was written at.

### Truncating

`Plume.truncate(sql, max_length)` shortens SQL to fit a log line or an error tracker. It replaces the parts you need least to recognise the query with `...`: result columns, `WHERE` conditions, `VALUES` rows, CTE bodies, `INSERT` column lists and `UPDATE` assignments. The most deeply nested parts go first, and the longest first among those. Only if that is still not short enough is the end cut off:

```ruby
sql = "WITH recent AS (SELECT id, title FROM posts WHERE created_at > ?) SELECT r.id, r.title, u.name FROM recent r JOIN users u ON u.id = r.user_id WHERE u.active"
Plume.truncate(sql, 100)
# => "WITH recent AS (...) SELECT ... FROM recent r JOIN users u ON u.id = r.user_id WHERE u.active"
```

### Normalizing

`Plume.normalize` replaces a query's constants with `?` and leaves everything else as written, so the same query with different values comes out the same. That lets you group a log the way `pg_stat_statements` does, or keep values out of it:

```ruby
Plume.normalize("SELECT * FROM posts /* app */ WHERE user_id = 42 AND title LIKE 'Re: %' ORDER BY 1 LIMIT 10")
# => "SELECT * FROM posts /* app */ WHERE user_id = ? AND title LIKE ? ORDER BY 1 LIMIT ?"
```

Numbers (including their sign), strings and blobs are replaced. `NULL`, `TRUE`, `FALSE` and `CURRENT_*` are left alone, and so is an integer on its own in `ORDER BY` or `GROUP BY`, where SQLite reads it as a column position. Only `SELECT`, `INSERT`, `UPDATE` and `DELETE` are normalized. Pass a parsed statement to get a tree back with `Variable`s in place of the constants. The tests bind the constants back into the normalized SQL and check that SQLite returns the same rows.

`Plume.fingerprint` goes one step further and gives the same short hash for every spelling of a query: whatever its values, parameter names, spacing, keyword and name case, or parentheses, and however many constants an `IN` list or `VALUES` holds. It is stable across processes and Ruby versions, so it can be stored:

```ruby
Plume.fingerprint("SELECT a FROM t WHERE b IN (1, 2, 3)") # => "07b540b0c5ed57e1"
Plume.fingerprint("select A from T where b in (?)")       # => "07b540b0c5ed57e1"
```

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
reads.calls      # => #<Set: {"like"}>
```

`reads.calls` lists the functions the statement calls, including the ones inside the views it reads. It also covers what `LIKE`, `GLOB`, `REGEXP`, `MATCH`, `->`, `->>` and `CURRENT_*` call, because SQLite's authorizer counts those as calls too. Table-valued functions in `FROM`, like `json_each`, are listed separately in `reads.functions`.

`Plume.reads` also takes what you already parsed - a statement node, or the array `Plume.parse` returns - so the SQL is not parsed twice, and a tree you changed after parsing is analyzed as changed. So do `Plume.writes` and `Plume.access` below.

The catalog can also come from a live database with `Plume::Catalog.from_sqlite(db)`, or be left out - then `SELECT *` is reported as a read of the column `"*"` and unqualified columns only resolve when there is a single table in scope.

Anything that cannot be attributed (an unknown table or column, an ambiguous name) raises `Plume::Analysis::Error` with a pointer into the SQL. Pass `strict: false` to get the partial result and a list in `reads.unresolved` instead. Each entry of `reads.references` carries the AST node it came from, so you can point at it too - see [examples/read_guard.rb](examples/read_guard.rb) for a small column-level access check built on top.

The results are tested against SQLite's own [authorizer callback](https://www.sqlite.org/c3ref/set_authorizer.html), which is also the place to enforce access rules at runtime when you have a connection. `Plume.reads` is for when you want to vet SQL ahead of time, without a database, or with good error messages. It reports one thing the authorizer does not: the right-hand join columns of `USING` and `NATURAL` joins.

### What does this query write?

`Plume.writes` works out which tables and columns an `INSERT`, `UPDATE` or `DELETE` would change. It takes the same `catalog:` and `strict:` as `Plume.reads`:

```ruby
writes = Plume.writes(<<~SQL, catalog: catalog)
  INSERT INTO posts (user_id, title) VALUES (?, ?)
  ON CONFLICT (id) DO UPDATE SET title = excluded.title
SQL

writes.tables   # => #<Set: {"posts"}>
writes.columns  # => {"posts" => #<Set: {"user_id", "title"}>}
writes.inserted # => {"posts" => #<Set: {"user_id", "title"}>}
writes.updated  # => {"posts" => #<Set: {"title"}>}, from the DO UPDATE
```

A `DELETE` removes whole rows, so it names a table and no columns:

```ruby
writes = Plume.writes("DELETE FROM posts WHERE user_id = ?", catalog: catalog)

writes.deleted # => #<Set: {"posts"}>
writes.tables  # => #<Set: {"posts"}>
writes.columns # => {}
```

Around the edges:

- An `INSERT` without a column list writes every column of the table except generated ones, or `"*"` without a catalog. `DEFAULT VALUES` writes the table but names no columns.
- Setting `rowid`, `oid` or `_rowid_` writes `"ROWID"`, even when an `INTEGER PRIMARY KEY` stands in for it - unless the table has a real column by that name.
- `RETURNING` and CTEs only read. A CTE never stands in for the table being written, even when it has the same name.
- Writing to a view reports the view. Plume does not look into triggers, so what an `INSTEAD OF` trigger or any other trigger writes is not reported, and neither are the rows a `REPLACE` deletes to make room.
- A `SELECT` writes nothing.
- Tables outside `main` are keyed with their schema, as in `"aux.users"`.

With `strict: false`, a column the catalog does not have is left out and listed in `writes.unresolved`:

```ruby
writes = Plume.writes("UPDATE posts SET title = ?, body = ? WHERE id = ?", catalog: catalog, strict: false)

writes.updated                # => {"posts" => #<Set: {"title"}>}
writes.unresolved.map(&:name) # => ["body"]
```

`Plume.access` gives you both the reads and the writes, from one pass over the statement:

```ruby
access = Plume.access(<<~SQL, catalog: catalog)
  UPDATE posts SET title = upper(u.name) FROM users u WHERE u.id = posts.user_id RETURNING posts.id
SQL

access.writes.updated   # => {"posts" => #<Set: {"title"}>}
access.reads.projected  # => {"users" => #<Set: {"name"}>, "posts" => #<Set: {"id"}>}
access.reads.referenced # => {"users" => #<Set: {"id"}>, "posts" => #<Set: {"user_id"}>}
```

A value copied into a column being written counts as projected, just like one returned in the result rows.

Writes are checked against the authorizer as well, and must match it exactly - except for the columns of an `INSERT`, which the authorizer does not name.

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

`tokenize`, `parse`, `to_sql`, `walk`, `reads`, `writes` and `access` all work inside a Ractor. Trees and results come back out like any other object, and a tree passed through `Ractor.make_shareable` can still be read, printed, walked and analyzed - it just can no longer be edited. After `eager_load!` the node classes cannot be given new props.

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

`bin/benchmark` runs every fixture that parses (26,707 files, 5.5 MB of SQL). On an Apple M5 Pro with Ruby 4.0:

| Step | Fixtures/s | MB/s | MB/s with YJIT |
| --- | ---: | ---: | ---: |
| `Plume.tokenize` | ~30,000 | 6.4 | 18.5 |
| `Plume.parse` | ~2,900 | 0.62 | 0.66 |
| `Node#to_sql` | ~12,000 | 2.5 | 2.3 |
| `Plume.reads` (no catalog, `SELECT`s only) | ~2,200 | 0.38 | 0.46 |

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
