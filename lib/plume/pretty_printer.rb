# frozen_string_literal: true

module Plume
	# The printer laid out over lines: each clause starts a line, a clause too long for
	# `max_line_length` puts its items one per line, indented by `indent_size`, and a long AND or OR
	# chain in a condition puts each operand on a line of its own. Subqueries are indented inside
	# their parentheses. Expressions otherwise print as `Printer` prints them, so what comes out
	# parses into the same tree
	class PrettyPrinter < Printer
		def self.print(node, indent_size: 4, max_line_length: 80, commas_start_of_line: false)
			new(indent_size:, max_line_length:, commas_start_of_line:).print(node)
		rescue *STACK_EXHAUSTED
			raise Error, "statement nested too deeply to print"
		end

		def initialize(indent_size:, max_line_length:, commas_start_of_line:)
			super()
			@pad = " " * indent_size
			@max = max_line_length
			@leading_commas = commas_start_of_line
		end

		private

		def lines(*parts) = parts.flatten.reject { |p| !p || p.empty? }.join("\n")

		# Only the line breaks between tokens: one inside a string or quoted name is part of its value
		def indent(text)
			src = text.b
			breaks = []
			lexer = Lexer.new(text)
			while (token = lexer.next_token)
				next unless token == :SPACE

				((lexer.anchor)...(lexer.cursor)).each { |i| breaks << i if src.getbyte(i) == 10 && i + 1 < src.bytesize && src.getbyte(i + 1) != 10 }
			end

			out = (src.empty? ? +"" : @pad.b.dup)
			at = 0
			breaks.each do |i|
				out << src.byteslice(at, i + 1 - at) << @pad
				at = i + 1
			end
			(out << src.byteslice(at, src.bytesize - at)).force_encoding(text.encoding)
		end

		# Lines after the first of a multi-line operand line up under the clause it sits in
		def hanging(text) = text.include?("\n") ? indent(text).delete_prefix(@pad) : text

		def fits?(text) = !text.include?("\n") && text.length <= @max

		# `KEYWORD a, b, c` on one line if it fits, otherwise the keyword alone and an item per line
		def clause(keyword, items)
			items = Array(items).map { |item| (String === item) ? item : print(item) }
			one_line = "#{keyword} #{items.join(", ")}"
			return one_line if fits?(one_line)

			body =
				if @leading_commas
					items.each_with_index.map { |item, i| i.zero? ? "  #{item}" : ", #{item}" }.join("\n")
				else
					items.join(",\n")
				end
			"#{keyword}\n#{indent(body)}"
		end

		# A condition on one line if it fits, otherwise its top-level AND or OR chain an operand per line
		def condition(keyword, node)
			one_line = "#{keyword} #{print(node)}"
			return one_line if fits?(one_line) || !(BinaryExpression === node && (node.operator in :ALL | :ANY))

			chain = [node]
			chain << chain.last.left while BinaryExpression === chain.last.left && chain.last.left.operator == node.operator
			word = BINARY_OPERATORS.fetch(node.operator)
			rest = chain.reverse_each.map { |link| "#{word} #{operand(link.right)}" }
			lines("#{keyword} #{hanging(operand(chain.last.left))}", rest.map { |line| indent(line) })
		end

		def parens(inner) = inner.include?("\n") ? "(\n#{indent(inner)}\n)" : "(#{inner})"

		def pretty_order_and_limit(node)
			limit =
				if node.offset && node.offset_tk_tok == :COMMA
					"LIMIT #{print(node.offset)}, #{print(node.limit)}"
				else
					join(node.limit && "LIMIT #{print(node.limit)}", node.offset && "OFFSET #{print(node.offset)}")
				end
			[node.orderings && clause("ORDER BY", node.orderings), limit]
		end

		# -- statements

		def print_select_statement(node) = lines(print(node.with_clause), print(node.body), pretty_order_and_limit(node))

		def print_with_clause(node)
			ctes = node.ctes.map { |cte| print(cte) }
			head = join("WITH", node.recursive && "RECURSIVE")
			"#{head} #{ctes.join(",\n")}"
		end

		def print_common_table_expression(node)
			materialized = { true => "MATERIALIZED", false => "NOT MATERIALIZED" }[node.materialized]
			name = identifier(node.name) + (node.columns ? "(#{list(node.columns)})" : "")
			join(name, "AS", materialized, parens(print(node.select)))
		end

		def print_compound_select(node) = lines(print(node.left), COMPOUND_OPERATORS.fetch(node.operator), print(node.right))

		def print_select_core(node)
			lines(
				clause(node.distinct ? "SELECT DISTINCT" : "SELECT", node.columns),
				node.source && from(node.source),
				node.condition && condition("WHERE", node.condition),
				node.groupings && clause("GROUP BY", node.groupings),
				node.having && condition("HAVING", node.having),
				node.windows && clause("WINDOW", node.windows),
			)
		end

		def from(source) = (JoinClause === source) ? "FROM #{print(source)}" : clause("FROM", [source])

		def print_values_clause(node) = clause("VALUES", node.rows)

		def print_join_clause(node)
			node.joins.reduce(print(node.left)) do |sql, each|
				operator = print(each.operator)
				right = join(print(each.source), print(each.constraint))
				(operator == ",") ? "#{sql},\n#{right}" : "#{sql}\n#{operator} #{right}"
			end
		end

		def print_subquery_source(node) = join(parens(print(node.select)), alias_of(node))
		def print_subquery_expression(node) = parens(print(node.select))
		def print_exists_expression(node) = "EXISTS #{parens(print(node.select))}"

		def print_insert_statement(node)
			verb = node.or_action ? ((node.insert_kw_tok == :REPLACE) ? "REPLACE" : "INSERT OR #{node.or_action}") : "INSERT"
			lines(
				print(node.with_clause),
				join(verb, "INTO", print(node.table), node.columns && "(#{list(node.columns)})"),
				node.default_values ? "DEFAULT VALUES" : print(node.select),
				node.upserts&.map { |u| print(u) },
				print(node.returning),
			)
		end

		def print_upsert_clause(node)
			target = node.targets && "(#{list(node.targets)})"
			head = join("ON CONFLICT", target, node.target_condition && "WHERE #{print(node.target_condition)}")
			return join(head, "DO NOTHING") if node.action == :NOTHING

			lines(head, indent(lines(clause("DO UPDATE SET", node.assignments), node.condition && condition("WHERE", node.condition))))
		end

		def print_update_statement(node)
			lines(
				print(node.with_clause),
				join(node.or_action ? "UPDATE OR #{node.or_action}" : "UPDATE", print(node.table)),
				clause("SET", node.assignments),
				node.source && from(node.source),
				node.condition && condition("WHERE", node.condition),
				print(node.returning), pretty_order_and_limit(node),
			)
		end

		def print_delete_statement(node)
			lines(
				print(node.with_clause), "DELETE FROM #{print(node.table)}",
				node.condition && condition("WHERE", node.condition),
				print(node.returning), pretty_order_and_limit(node),
			)
		end

		def print_returning_clause(node) = clause("RETURNING", node.columns)

		def print_create_table_statement(node)
			head = join("CREATE", node.temporary && "TEMP", "TABLE", node.if_not_exists && "IF NOT EXISTS", print(node.table))
			return lines("#{head} AS", print(node.select_statement)) if node.select_statement

			definitions = [*node.columns, *node.constraints].map { |d| print(d) }
			join("#{head} (\n#{indent(definitions.join(",\n"))}\n)", node.options && list(node.options))
		end

		def print_create_view_statement(node)
			head = join(
				"CREATE", node.temporary && "TEMP", "VIEW", node.if_not_exists && "IF NOT EXISTS", print(node.view),
				node.columns && "(#{list(node.columns)})", "AS",
			)
			lines(head, print(node.select))
		end

		def print_create_trigger_statement(node)
			event = node.columns ? "UPDATE OF #{list(node.columns)}" : node.event.to_s
			head = join(
				"CREATE", node.temporary && "TEMP", "TRIGGER", node.if_not_exists && "IF NOT EXISTS", print(node.trigger),
				node.time&.to_s&.tr("_", " "), event, "ON", print(node.table),
				node.for_each_row_kw? && "FOR EACH ROW", node.condition && "WHEN #{print(node.condition)}",
			)
			lines(head, "BEGIN", node.statements.map { |s| indent("#{print(s)};") }, "END")
		end
	end
end
