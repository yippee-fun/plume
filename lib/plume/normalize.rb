# frozen_string_literal: true

module Plume
	# Constants turned into `?` parameters, so the same query with different values comes out the
	# same - for grouping a log the way pg_stat_statements does, or for keeping values out of it.
	# Numbers, strings and blobs are replaced, a sign in front of a number with them. NULL, TRUE,
	# FALSE and CURRENT_* are not, since `IS ?` would not mean `IS NULL`. Neither is an integer
	# standing alone in ORDER BY or GROUP BY, which SQLite takes for a column's position.
	# Only SELECT, INSERT, UPDATE and DELETE (and EXPLAIN of them) are normalized, other statements
	# are left as they were: their constants are schema, not data
	module Normalize
		extend self

		STATEMENTS = [SelectStatement, InsertStatement, UpdateStatement, DeleteStatement].freeze

		# The SQL with each constant swapped for `?` in place, everything else - spacing, case,
		# comments - kept as written
		def text(sql)
			src = sql.b
			spans = Parser.new(sql).parse.flat_map { |statement| constants(statement).map(&:location) }
			out = +""
			at = 0
			spans.sort_by(&:first).each do |beg, fin|
				out << src.byteslice(at, beg - at) << "?"
				at = fin
			end
			out << src.byteslice(at, src.bytesize - at)
			out.force_encoding(sql.encoding)
		end

		# A copy of the tree with each constant replaced by a `?` Variable
		def tree(node)
			targets = Set.new(constants(node)).compare_by_identity
			node.transform { |n| targets.include?(n) ? Variable.new(name: "?") : n }
		end

		# The nodes to replace: literals, or a sign with the literal under it
		def constants(statement)
			root = (ExplainStatement === statement) ? statement.statement : statement
			return [] unless STATEMENTS.any? { |klass| klass === root }

			found = []
			# By identity: hashing a node hashes its whole subtree
			positional = Set.new.compare_by_identity
			root.walk_with_slots do |node, parent, prop|
				case node
				when OrderingTerm
					positional << node if SelectStatement === parent && prop == :orderings
				when UnaryExpression
					found << node if (node.operator in :NEGATE | :IDENTITY) && value?(node.operand)
				when LiteralExpression
					next if UnaryExpression === parent && (parent.operator in :NEGATE | :IDENTITY)
					next if Integer === node.value && (positional.include?(parent) || (SelectCore === parent && prop == :groupings))

					found << node if value?(node)
				end
			end
			found
		end

		private

		def value?(node) = LiteralExpression === node && (node.value in Numeric | String)
	end
end
