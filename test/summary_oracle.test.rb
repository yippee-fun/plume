# frozen_string_literal: true

# Plume.summary over whole scripts, statement by statement, held to what SQLite's authorizer
# reports as it runs them - each statement against the schema the ones before it left

require_relative "support/authorizer_oracle"

SUMMARY_SCHEMA = <<~SQL
	CREATE TABLE posts (id INTEGER PRIMARY KEY, title TEXT UNIQUE, body TEXT);
	CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT);
	CREATE TRIGGER posts_touch AFTER UPDATE ON posts BEGIN SELECT 1; END;
SQL

{
	"archive" => <<~SQL,
		CREATE TABLE archive (id INTEGER PRIMARY KEY, title TEXT);
		ALTER TABLE archive ADD COLUMN moved_at TEXT;
		INSERT INTO archive (id, title, moved_at) SELECT id, title, date('now') FROM posts;
		ALTER TABLE archive RENAME COLUMN title TO heading;
		SELECT heading, moved_at FROM archive;
		CREATE INDEX archive_heading ON archive (heading);
		ALTER TABLE archive RENAME TO old_posts;
		DROP INDEX archive_heading;
		REINDEX old_posts;
		DROP TABLE posts;
		SELECT heading FROM old_posts
	SQL
	"temp tables" => <<~SQL,
		CREATE TEMP TABLE scratch (k PRIMARY KEY, v);
		INSERT INTO scratch SELECT id, name FROM users;
		CREATE INDEX scratch_v ON scratch (v);
		DELETE FROM scratch WHERE v IS NULL;
		CREATE TRIGGER scratch_log AFTER DELETE ON scratch BEGIN DELETE FROM users WHERE id = old.k; END;
		DROP TABLE scratch
	SQL
	"views and columns" => <<~SQL,
		CREATE VIEW titles AS SELECT id, title FROM posts;
		SELECT title FROM titles;
		ALTER TABLE posts DROP COLUMN body;
		CREATE TABLE copies AS SELECT * FROM titles;
		SELECT id, title FROM copies;
		DROP VIEW titles;
		BEGIN;
		UPDATE copies SET title = upper(title);
		COMMIT
	SQL
}.each do |name, script|
	test "summary follows the schema through a script: #{name}" do
		oracle = AuthorizerOracle.new(SUMMARY_SCHEMA)
		summary = Plume.summary(script, catalog: oracle.catalog)

		Plume::Catalog.split_statements(script).zip(summary.accesses) do |sql, access|
			expected = oracle.run(sql)
			actions = access.actions.map { |a| [a.action, a.name, a.detail, a.schema] }

			assert_equal actions.sort_by(&:inspect), expected.actions.reject { |_, n, *| n.start_with?("sqlite_stat") }.sort_by(&:inspect)
			# A trigger's body is read when something fires it, but we say what it does when it is made
			next if sql.lstrip.start_with?("CREATE TRIGGER")

			assert_equal access.reads.references.each_with_object({}) { |r, h| (h[r.table] ||= Set.new) << r.column if r.column }, expected.columns
			assert_equal access.writes.updated, expected.updated
			assert_equal access.writes.references.select { |r| r.usage == :insert }.to_set(&:table), expected.inserted
			assert_equal access.reads.calls, expected.calls unless sql.lstrip.start_with?("ALTER")
		end
	ensure
		oracle&.close
	end
end
