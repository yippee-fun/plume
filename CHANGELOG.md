## [Unreleased]

- `Plume::SyntaxError` carries `location`, `position`, `token`, `line` and `expected`, so tools can point at the error without reading the message
- Comments lex as `:COMMENT` rather than `:SPACE`; `Plume.comments` lists them with their byte ranges, `Comment#tags` reads sqlcommenter and Rails query_log_tags comments, and `to_sql(comments: true)` keeps the comments before and after a statement
- `Plume.tokenize(sql, with_positions: true)` gives each token's byte range
- `Plume.parameters`: a statement's bind parameters, numbered and named as SQLite numbers and names them
- `Plume.fingerprint`: a stable 16-character hash that is the same for a query whatever its values, parameters, case, spacing and parentheses, and however long its IN lists and VALUES
- `Plume.normalize`: a query with its constants replaced by `?`, everything else as written - or, given a tree, a tree with `Variable`s in their place. Column positions in ORDER BY and GROUP BY are kept
- `Node#walk_with_slots` yields each node's prop and index under its parent, `Node#each_child` the same for direct children, and `Node#transform` returns a copy of the tree with nodes replaced
- `Node#dump` and `Plume.load`: a tree to a plain hash that JSON can carry and back, exactly - positions, keywords as written and source included
- `Plume.truncate(sql, max_length)`: SQL shortened by putting `...` in place of result columns, conditions, VALUES rows, CTE bodies, INSERT columns and UPDATE assignments, the most deeply nested first, and cut off only when that is not enough
- `Plume.split`: the statements in a script, found by their tokens alone so SQL that does not parse splits too, with byte ranges on request
- Fixed: splitting a schema ended a trigger's body at the END of a CASE inside it, and took a table named `trigger` for a trigger, so a later BEGIN swallowed the statements after it
- `to_sql(pretty: true)` lays SQL out over lines - a clause per line, long lists and AND/OR chains an item per line, subqueries indented - with `indent_size:`, `max_line_length:` and `commas_start_of_line:`
- `Plume.summary`: reads and writes of any number of statements, one `Access` per statement and the tables, calls, CTEs and aliases merged, with `statement_types`
- `Reads#ctes` and `#aliases` (shared with `Writes`): the CTE names a statement defines, and what each table alias stands for
- `Reads#calls`: every function a statement calls, including those LIKE, GLOB, REGEXP, MATCH, `->`, `->>` and CURRENT_* call, as SQLite's authorizer reports them
- `Plume.writes`: which tables and columns an INSERT, UPDATE or DELETE would write - the same `Writes` that `Plume.access` returns, without the reads
- `Plume::Catalog::Table#generated_columns`, read from CREATE TABLE and from a live database
- `Plume.eager_load!` makes Plume usable from Ractors: parsing, printing and analysis run in any Ractor, and catalogs and parsed trees can be made shareable
- `ALTER TABLE ... ADD [CONSTRAINT name] CHECK`, `DROP CONSTRAINT`, `ALTER [COLUMN] ... SET NOT NULL` and `DROP NOT NULL` parse, as `AlterTableStatement` actions `:ADD_CONSTRAINT`, `:DROP_CONSTRAINT`, `:SET_NOT_NULL` and `:DROP_NOT_NULL`, with `constraint`, `constraint_name` and `conflict_clause`
- A table CHECK takes `ON CONFLICT`, PRIMARY KEY and UNIQUE columns take `NULLS FIRST`/`LAST`, a column can be `[NOT] DEFERRABLE ...` on its own (as `DeferrableColumnConstraint`), and a foreign key's ON and MATCH clauses come in any order, `ON INSERT` included
- Call arguments follow SQLite's grammar, every part optional, so `count(ORDER BY a)`, `count(ALL)` and `count(DISTINCT)` parse, and CAST may name no type
- Keywords read as names wherever SQLite reads them so: WINDOW, OVER and FILTER by the tokens around them, TRUE, FALSE, CURRENT_* and STORED as names, any name as a window after OVER, and any name (join keywords and strings too) as the table after IN
- The printer quotes a name that would read back as the start of an expression, like `cast`, `raise`, `true` or `current_date`
- Chains at one precedence print flat, the way SQLite associates them (`a - b + c`), and deep trees - a 6000-term OR, 600 UNION ALLs - print and walk without running out of stack
- `LIMIT a, b` prints as written rather than as `LIMIT b OFFSET a`, since SQLite numbers `?` parameters left to right
- Running out of stack while printing or analyzing raises `Plume::Printer::Error` or `Plume::Analysis::Error` instead of `SystemStackError`, and analysis stops at SQLite's limit of 64 tables in a join
- Fixed: a frame boundary of UNBOUNDED with no PRECEDING or FOLLOWING parsed, and then could not be printed
- Fixed: a comma-separated list went on after an item with no separator, or ended on a separator - so `ORDER BY c ROWS 2 PRECEDING` failed to parse, while `SELECT a, b, FROM t`, `SELECT * + 1` and `VALUES (1, 2,)` parsed
- Fixed: `count(ALL x)` read as `count(DISTINCT x)`
- Fixed: `?0` and `?32767` and up parsed; SQLite numbers parameters from 1 to 32766
- Fixed: `.0.` lexed as one number, `1 ~ 2` parsed as a binary expression with no operator, and `ORDER BY a NULLS b` parsed
- Fixed: a byte order mark before a name became part of it, a NUL byte crashed the lexer, and SQL that is not valid UTF-8 raised `ArgumentError` or `EncodingError`
- Fixed: the catalog matched names with Unicode case folding, so `"Σ"` and `"σ"` were one table; SQLite folds A-Z only
- Fixed: `UPDATE t ... FROM` did not count `t` as read unless one of its columns was named
- Fixed: analyzing a join with ON clauses was quadratic in its number of tables
- Fixed: an INSERT without a column list was reported as writing the table's generated columns
- Fixed: `UPDATE t SET rowid = ...` raised "no such column"; it is now a write of `ROWID`, as SQLite's authorizer reports it

## [0.2.0] - 2026-10-20

- Requires Ruby 3.2 or later
- Parse every statement in SQLite's grammar: SELECT (with CTEs, compounds, joins, window definitions and subqueries), INSERT/REPLACE with upserts, UPDATE … FROM, DELETE, RETURNING, CREATE TABLE/VIEW/INDEX/TRIGGER/VIRTUAL TABLE, ALTER TABLE, DROP, transactions and savepoints, PRAGMA, ATTACH/DETACH, ANALYZE, REINDEX, VACUUM and EXPLAIN [QUERY PLAN]
- `Plume.reads` and `Plume.access`: which tables and columns a statement reads and writes, looking through aliases, joins, subqueries, CTEs and views, checked against SQLite's authorizer callback
- `Plume.reads` and `Plume.access` also take an already parsed statement
- `Plume::Catalog`, built from schema SQL or from a live database
- `Node#to_sql` prints any tree, parsed or built by hand, back to SQL
- `Node#children`, `#walk`, `#each_node`, `#location`, `#source_text` and pattern matching with `deconstruct_keys`
- Bind parameters parse as `Plume::Variable`
- Syntax errors point at the offending line
- Fixed: `a IN (…) AND b` and friends stopped after the IN/BETWEEN/LIKE/GLOB; quotes doubled inside strings and identifiers were not unescaped; a column type following a REFERENCES clause came out empty
- A tree built by hand can hold plain numbers and strings, which print as the literals they spell; numbers SQL has no literal for (Rational, Complex, NaN, infinity) raise instead of printing as something else
- Fixed: a `ForeignKeyAction` could not be built by hand
- Fixed: numbers with a misplaced digit separator (`1_`, `12__34`, `0xFFEF_`) parsed, and `#` followed by a digit parsed as a bind parameter; SQLite rejects both
- Fixed: hex literals evaluated to 0, and digit-separated whole numbers lost precision; hex now reads as a 64-bit two's-complement integer, as in SQLite
- A statement nested too deeply to parse raises `Plume::SyntaxError` instead of `SystemStackError`
- Building a tree is no longer quadratic in its size, on Ruby 4 included
- `literal` is now declared as a runtime dependency

## [0.1.0] - 2024-03-22

- Initial release
