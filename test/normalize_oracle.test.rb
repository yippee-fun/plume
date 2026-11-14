# frozen_string_literal: true

# Normalized SQL held to SQLite: with the constants it took out bound back in, by position,
# it must give the same rows and leave the same tables as the original

require "sqlite3"

NORMALIZE_SCHEMA = <<~SQL
	CREATE TABLE t (a INTEGER PRIMARY KEY, b, c TEXT);
	CREATE TABLE u (k, v BLOB);
	INSERT INTO t VALUES (1, 2, 'x'), (2, -3, 'it''s'), (3, 2.5, NULL), (4, 7, 'é');
	INSERT INTO u VALUES (1, x'ab'), (2, x''), (4, NULL);
SQL

class Quickdraw::Test
	def normalized_constant(node)
		case node
		when Plume::UnaryExpression then (node.operator == :NEGATE) ? -node.operand.value : node.operand.value
		else node.value
		end
	end

	def bound_outcome(db, sql, binds = [])
		db.transaction
		statement = db.prepare(sql)
		binds.each_with_index do |value, i|
			statement.bind_param(i + 1, (String === value && value.encoding == Encoding::BINARY) ? SQLite3::Blob.new(value) : value)
		end
		[statement.to_a, db.execute("SELECT * FROM t ORDER BY a"), db.execute("SELECT * FROM u ORDER BY k")]
	ensure
		statement&.close
		db.rollback if db.transaction_active?
	end
end

[
	"SELECT a, b * 2, c || '!' FROM t WHERE b > -1 AND c <> 'x' ORDER BY 1 LIMIT 2 OFFSET 1",
	"SELECT a, sum(b) FROM t GROUP BY 1 HAVING sum(b) > 1.5 ORDER BY 2 DESC",
	"SELECT k, hex(v) FROM u WHERE v = x'ab' OR k IN (2, 4)",
	"SELECT CASE WHEN b > 2 THEN 'big' ELSE 'small' END, coalesce(c, 'none') FROM t ORDER BY a",
	"SELECT a FROM t WHERE c LIKE 'i%' ESCAPE '!' OR b BETWEEN -5 AND +2",
	"WITH r AS (SELECT a, b FROM t WHERE a < 4) SELECT * FROM r ORDER BY 2, 1 LIMIT 3",
	"SELECT a, row_number() OVER (ORDER BY 1, b) FROM t ORDER BY 1",
	"INSERT INTO t (b, c) VALUES (10, 'new'), (-0.5, x'00')",
	"INSERT INTO t (a, b) VALUES (1, 99) ON CONFLICT (a) DO UPDATE SET b = excluded.b + 1, c = 'upserted'",
	"UPDATE t SET b = b + 100, c = 'changed' WHERE a IN (1, 3) RETURNING a, b",
	"DELETE FROM u WHERE k > 1 RETURNING k, 'gone'",
].each do |sql|
	test "with its constants bound back, normalized SQL does what the original does: #{sql}" do
		db = SQLite3::Database.new(":memory:")
		db.execute_batch(NORMALIZE_SCHEMA)
		statement = Plume.parse(sql).first
		values = Plume::Normalize.constants(statement).sort_by { |n| n.location.first }.map { |n| normalized_constant(n) }
		normalized = Plume.normalize(sql)

		prepared = db.prepare(normalized)
		assert_equal prepared.bind_parameter_count, values.size
		prepared.close
		assert_equal bound_outcome(db, normalized, values), bound_outcome(db, sql)
		assert_equal bound_outcome(db, Plume.normalize(statement).to_sql, values), bound_outcome(db, sql)
	ensure
		db&.close
	end
end
