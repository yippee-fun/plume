# frozen_string_literal: true

module Plume
	# SQL shortened to fit a length, for logs and error trackers, by putting `...` where the parts
	# least needed to recognise the query were: result columns, WHERE conditions, VALUES rows, CTE
	# bodies, INSERT column lists and UPDATE assignments - the most deeply nested first, the longest
	# first among those. Everything else stays as written. When that is not enough, the end is cut off
	module Truncate
		extend self

		ELLIPSIS = "..."

		def call(sql, max_length)
			return sql if sql.length <= max_length

			src = sql.b
			chosen = []
			result = sql
			candidates(Parser.new(sql).parse).each do |beg, fin, _depth|
				next if fin - beg <= ELLIPSIS.bytesize || chosen.any? { |b, f| b <= beg && fin <= f }

				chosen.reject! { |b, f| beg <= b && f <= fin }
				chosen << [beg, fin]
				result = render(src, chosen, sql.encoding)
				return result if result.length <= max_length
			end
			"#{result[0, [max_length - ELLIPSIS.length, 0].max]}#{ELLIPSIS}"[0, max_length]
		end

		# Byte ranges that may be cut, with how deeply they are nested, in the order to cut them
		def candidates(statements)
			found = []
			stack = statements.reverse.map { |s| [s, 0] }
			while (node, depth = stack.pop)
				span =
					case node
					when SelectCore then [list_span(node.columns), node.condition&.location]
					when ValuesClause then [list_span(node.rows)]
					when CommonTableExpression then [node.select&.location]
					when InsertStatement then [list_span(node.columns)]
					when UpdateStatement then [list_span(node.assignments)]
					else []
					end
				span.compact.each { |beg, fin| found << [beg, fin, depth] }
				node.children.reverse_each { |child| stack << [child, depth + 1] }
			end
			found.sort_by { |beg, fin, depth| [-depth, beg - fin] }
		end

		private

		def list_span(nodes)
			first, last = nodes&.first&.location, nodes&.last&.location
			[first[0], last[1]] if first && last
		end

		def render(src, spans, encoding)
			out = +""
			at = 0
			spans.sort.each do |beg, fin|
				out << src.byteslice(at, beg - at) << ELLIPSIS
				at = fin
			end
			(out << src.byteslice(at, src.bytesize - at)).force_encoding(encoding)
		end
	end
end
