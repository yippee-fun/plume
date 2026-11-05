# frozen_string_literal: true

module Plume
	# Turns an AST back into SQL. It works from the nodes' readers rather than from the tokens
	# they were parsed from, so trees built by hand, or changed after parsing, print too. The
	# output is canonical rather than a copy of the input: keywords come out in upper case,
	# identifiers are quoted only when they have to be, and a compound operand gets parentheses
	# unless it is the left operand of an operator at its own precedence, where SQLite's
	# left-associativity already groups it.
	class Printer
		BARE_IDENTIFIER = /\A[A-Za-z_][A-Za-z0-9_]*\z/

		BINARY_OPERATORS = {
			ALL: "AND", ANY: "OR", CONCAT: "||", EXTRACT: "->", RETRIEVE: "->>",
			MULTIPLY: "*", DIVIDE: "/", MODULO: "%", ADD: "+", SUB: "-",
			BIT_AND: "&", BIT_OR: "|", BIT_LSHIFT: "<<", BIT_RSHIFT: ">>",
			BELOW: "<", ABOVE: ">", ATMOST: "<=", ATLEAST: ">=", EQUALS: "=", NOT_EQUALS: "!=",
			IS: "IS", IS_NOT: "IS NOT", GLOB: "GLOB", NOT_GLOB: "NOT GLOB", REGEXP: "REGEXP",
			NOT_REGEXP: "NOT REGEXP", MATCH: "MATCH", NOT_MATCH: "NOT MATCH", IN: "IN", NOT_IN: "NOT IN",
		}.freeze

		# Names that would read back as the start of an expression
		EXPRESSION_KEYWORDS = (Parser::LITERAL_KEYWORDS + [:CAST, :RAISE]).freeze

		# Levels Plume's parser and SQLite agree on: SQLite also puts = and IS with IN, LIKE and the rest
		PRECEDENCE = {
			ANY: 1, ALL: 2,
			IN: 3, NOT_IN: 3, MATCH: 3, NOT_MATCH: 3, GLOB: 3, NOT_GLOB: 3, REGEXP: 3, NOT_REGEXP: 3,
			EQUALS: 4, NOT_EQUALS: 4, IS: 4, IS_NOT: 4,
			BELOW: 5, ABOVE: 5, ATMOST: 5, ATLEAST: 5,
			BIT_AND: 6, BIT_OR: 6, BIT_LSHIFT: 6, BIT_RSHIFT: 6,
			ADD: 7, SUB: 7,
			MULTIPLY: 8, DIVIDE: 8, MODULO: 8,
			CONCAT: 9, EXTRACT: 9, RETRIEVE: 9,
		}.freeze

		COMPOUND_OPERATORS = { UNION: "UNION", UNION_ALL: "UNION ALL", INTERSECT: "INTERSECT", EXCEPT: "EXCEPT" }.freeze
		JOIN_KINDS = { COMMA: ",", INNER: "JOIN", LEFT: "LEFT JOIN", RIGHT: "RIGHT JOIN", FULL: "FULL JOIN", CROSS: "CROSS JOIN" }.freeze
		FOREIGN_KEY_ACTIONS = { CASCADE: "CASCADE", RESTRICT: "RESTRICT", SET_NULL: "SET NULL", SET_DEFAULT: "SET DEFAULT", NO_ACTION: "NO ACTION" }.freeze

		# Operands of these need parentheses to keep their grouping when printed inside another expression
		COMPOUND_EXPRESSIONS = [BinaryExpression, UnaryExpression, TernaryExpression, LikeExpression, CollationExpression].freeze

		Error = Class.new(StandardError)

		def self.print(node)
			new.print(node)
		rescue *STACK_EXHAUSTED
			# As with parsing, how deep is too deep depends on the stack the caller has left
			raise Error, "statement nested too deeply to print"
		end

		def print(node)
			case node
			when nil then nil
			when Array then node.map { |n| print(n) }.join(", ")
			when Node then __send__(:"print_#{underscore(node.class.name.split("::").last)}", node)
			# Expressions built by hand may hold plain values, which stand for the literal they spell
			when LiteralValue then print(LiteralExpression.new(value: node))
			else raise ArgumentError, "cannot print #{node.inspect}"
			end
		end

		def identifier(name)
			name = name.to_s
			return name if name.ascii_only? && name.match?(BARE_IDENTIFIER) && bare_keyword_ok?(name.upcase.to_sym)

			%("#{doubled(name, '"')}")
		end

		# Keywords SQLite falls back to treating as identifiers, like ROWID or KEY, need no quotes -
		# except the ones that would read back as the start of an expression
		def bare_keyword_ok?(word) = !Lexer::KEYWORDS.include?(word) || (Parser::TOKEN_FALLBACKS.include?(word) && !EXPRESSION_KEYWORDS.include?(word))

		def string(value) = "'#{doubled(value.to_s, "'")}'"

		private

		# Done on the bytes, since TruffleRuby's gsub refuses a string that is not valid UTF-8
		def doubled(text, quote) = text.b.gsub(quote, quote * 2).force_encoding(text.encoding)

		def underscore(name) = name.gsub(/([a-z\d])([A-Z])/, '\1_\2').downcase

		def join(*parts) = parts.flatten.reject { |p| !p || (p.respond_to?(:empty?) && p.empty?) }.join(" ")

		def qualified(*names) = names.compact.map { |n| identifier(n) }.join(".")

		def operand(node) = (COMPOUND_EXPRESSIONS.any? { |klass| klass === node }) ? "(#{print(node)})" : print(node)

		def alias_of(node) = node.alias && "AS #{identifier(node.alias)}"

		def list(items) = Array(items).map { |item| print(item) }.join(", ")

		def parenthesized_names(names) = names && "(#{names.map { |n| identifier(n) }.join(", ")})"

		# -- statements

		def print_explain_statement(node) = join(node.query_plan ? "EXPLAIN QUERY PLAN" : "EXPLAIN", print(node.statement))

		def print_select_statement(node)
			join(print(node.with_clause), print(node.body), order_and_limit(node))
		end

		def order_and_limit(node)
			[
				node.orderings && "ORDER BY #{list(node.orderings)}",
				node.limit && "LIMIT #{print(node.limit)}",
				node.offset && "OFFSET #{print(node.offset)}",
			]
		end

		def print_with_clause(node) = join("WITH", node.recursive && "RECURSIVE", list(node.ctes))

		def print_common_table_expression(node)
			materialized = { true => "MATERIALIZED", false => "NOT MATERIALIZED" }[node.materialized]
			join(identifier(node.name) + (node.columns ? "(#{list(node.columns)})" : ""), "AS", materialized, "(#{print(node.select)})")
		end

		def print_compound_select(node)
			join(print(node.left), COMPOUND_OPERATORS.fetch(node.operator), print(node.right))
		end

		def print_select_core(node)
			join(
				"SELECT", node.distinct && "DISTINCT", list(node.columns),
				node.source && "FROM #{print(node.source)}",
				node.condition && "WHERE #{print(node.condition)}",
				node.groupings && "GROUP BY #{list(node.groupings)}",
				node.having && "HAVING #{print(node.having)}",
				node.windows && "WINDOW #{list(node.windows)}",
			)
		end

		def print_values_clause(node) = "VALUES #{list(node.rows)}"
		def print_values_row(node) = "(#{list(node.values)})"

		def print_result_column(node) = join(print(node.result), alias_of(node))
		def print_star_result_column(node) = node.table ? "#{identifier(node.table)}.*" : "*"

		def print_window_definition(node) = "#{identifier(node.name)} AS (#{window_body(node)})"

		def window_body(node)
			join(
				node.base_window_name && identifier(node.base_window_name),
				node.partitions && "PARTITION BY #{list(node.partitions)}",
				node.orderings && "ORDER BY #{list(node.orderings)}",
				print(node.frame),
			)
		end

		def print_insert_statement(node)
			verb = node.or_action ? ((node.insert_kw_tok == :REPLACE) ? "REPLACE" : "INSERT OR #{node.or_action}") : "INSERT"
			join(
				print(node.with_clause), verb, "INTO", print(node.table),
				node.columns && "(#{list(node.columns)})",
				node.default_values ? "DEFAULT VALUES" : print(node.select),
				node.upserts&.map { |u| print(u) },
				print(node.returning),
			)
		end

		def print_upsert_clause(node)
			target = node.targets && "(#{list(node.targets)})"
			action =
				if node.action == :NOTHING
					"DO NOTHING"
				else
					join("DO UPDATE SET", list(node.assignments), node.condition && "WHERE #{print(node.condition)}")
				end
			join("ON CONFLICT", target, node.target_condition && "WHERE #{print(node.target_condition)}", action)
		end

		def print_update_statement(node)
			join(
				print(node.with_clause), node.or_action ? "UPDATE OR #{node.or_action}" : "UPDATE", print(node.table),
				"SET", list(node.assignments),
				node.source && "FROM #{print(node.source)}",
				node.condition && "WHERE #{print(node.condition)}",
				print(node.returning), order_and_limit(node),
			)
		end

		def print_delete_statement(node)
			join(
				print(node.with_clause), "DELETE FROM", print(node.table),
				node.condition && "WHERE #{print(node.condition)}",
				print(node.returning), order_and_limit(node),
			)
		end

		def print_assignment(node)
			target = (node.columns.size == 1 && !node.columns_lp?) ? print(node.columns[0]) : "(#{list(node.columns)})"
			"#{target} = #{print(node.value)}"
		end

		def print_returning_clause(node) = "RETURNING #{list(node.columns)}"

		def print_create_table_statement(node)
			head = join("CREATE", node.temporary && "TEMP", "TABLE", node.if_not_exists && "IF NOT EXISTS", print(node.table))
			return join(head, "AS", print(node.select_statement)) if node.select_statement

			definitions = list([*node.columns, *node.constraints])
			join(head, "(#{definitions})", node.options && list(node.options))
		end

		def print_create_view_statement(node)
			join(
				"CREATE", node.temporary && "TEMP", "VIEW", node.if_not_exists && "IF NOT EXISTS", print(node.view),
				node.columns && "(#{list(node.columns)})", "AS", print(node.select),
			)
		end

		def print_create_index_statement(node)
			join(
				"CREATE", node.unique && "UNIQUE", "INDEX", node.if_not_exists && "IF NOT EXISTS", print(node.index),
				"ON", identifier(node.table), "(#{list(node.columns)})",
				node.condition && "WHERE #{print(node.condition)}",
			)
		end

		def print_create_virtual_table_statement(node)
			arguments = node.arguments_lp? ? "(#{node.arguments.join(", ")})" : nil
			join("CREATE VIRTUAL TABLE", node.if_not_exists && "IF NOT EXISTS", print(node.table), "USING", identifier(node.module_name) + arguments.to_s)
		end

		def print_create_trigger_statement(node)
			event = node.columns ? "UPDATE OF #{list(node.columns)}" : node.event.to_s
			join(
				"CREATE", node.temporary && "TEMP", "TRIGGER", node.if_not_exists && "IF NOT EXISTS", print(node.trigger),
				node.time&.to_s&.tr("_", " "), event, "ON", print(node.table),
				node.for_each_row_kw? && "FOR EACH ROW", node.condition && "WHEN #{print(node.condition)}",
				"BEGIN", node.statements.map { |s| "#{print(s)};" }, "END",
			)
		end

		def print_alter_table_statement(node)
			action =
				case node.action
				when :RENAME_TABLE then "RENAME TO #{identifier(node.new_name)}"
				when :RENAME_COLUMN then "RENAME COLUMN #{identifier(node.column)} TO #{identifier(node.new_name)}"
				when :ADD_COLUMN then "ADD COLUMN #{print(node.column_definition)}"
				when :DROP_COLUMN then "DROP COLUMN #{identifier(node.column)}"
				when :ADD_CONSTRAINT then "ADD #{print(node.constraint)}"
				when :DROP_CONSTRAINT then "DROP CONSTRAINT #{identifier(node.constraint_name)}"
				when :SET_NOT_NULL then join("ALTER COLUMN #{identifier(node.column)} SET NOT NULL", print(node.conflict_clause))
				when :DROP_NOT_NULL then "ALTER COLUMN #{identifier(node.column)} DROP NOT NULL"
				end
			join("ALTER TABLE", print(node.table), action)
		end

		def print_drop_statement(node) = join("DROP", node.type.to_s, node.if_exists && "IF EXISTS", print(node.target))

		def print_begin_statement(node) = join("BEGIN", node.type&.to_s)
		def print_commit_statement(_node) = "COMMIT"
		def print_rollback_statement(node) = join("ROLLBACK", node.savepoint && "TO SAVEPOINT #{identifier(node.savepoint)}")
		def print_savepoint_statement(node) = "SAVEPOINT #{identifier(node.name)}"
		def print_release_statement(node) = "RELEASE SAVEPOINT #{identifier(node.name)}"

		def print_pragma_statement(node)
			name = qualified(node.schema, node.name)
			return "PRAGMA #{name}" if node.value.nil?

			value =
				case node.value
				when Numeric then node.value.to_s
				else (node.value_tk_tok == :STRING) ? string(node.value) : identifier(node.value)
				end
			(node.eq_tk_tok == :LP) ? "PRAGMA #{name}(#{value})" : "PRAGMA #{name} = #{value}"
		end

		def print_attach_statement(node)
			join("ATTACH DATABASE", print(node.file), "AS", print(node.schema), node.key && "KEY #{print(node.key)}")
		end

		def print_detach_statement(node) = "DETACH DATABASE #{print(node.schema)}"
		def print_analyze_statement(node) = join("ANALYZE", print(node.target))
		def print_reindex_statement(node) = join("REINDEX", print(node.target))
		def print_vacuum_statement(node) = join("VACUUM", node.schema && identifier(node.schema), node.into && "INTO #{print(node.into)}")

		# -- FROM

		def print_table_name(node)
			indexed = node.indexed_by ? "INDEXED BY #{identifier(node.indexed_by)}" : (node.not_indexed && "NOT INDEXED")
			join(qualified(node.schema, node.table), alias_of(node), indexed)
		end

		def print_table_function(node)
			join("#{qualified(node.schema, node.function)}(#{list(node.arguments)})", alias_of(node))
		end

		def print_subquery_source(node) = join("(#{print(node.select)})", alias_of(node))
		def print_parenthetical_source(node) = join("(#{print(node.source)})", alias_of(node))

		def print_join_clause(node)
			node.joins.reduce(print(node.left)) do |sql, each|
				operator = print(each.operator)
				right = join(print(each.source), print(each.constraint))
				(operator == ",") ? "#{sql}, #{right}" : "#{sql} #{operator} #{right}"
			end
		end

		def print_join_operator(node) = join(node.natural && "NATURAL", JOIN_KINDS.fetch(node.kind))
		def print_join_on_constraint(node) = "ON #{print(node.expression)}"
		def print_join_using_constraint(node) = "USING (#{list(node.columns)})"

		# -- expressions

		def print_column_name(node) = qualified(node.schema, node.table, node.column)

		def print_literal_expression(node)
			# Numbers keep their spelling, so 0x1F stays hex and 1e3 stays an exponent
			return node.value_tk_src if node.value_tk? && node.value_tk_spn.last == :numeric

			case (value = node.value)
			when nil then "NULL"
			when true then "TRUE"
			when false then "FALSE"
			when Symbol then value.to_s
			when Integer then value.to_s
			when Float
				# SQLite has no literal for NaN or infinity
				value.finite? ? value.to_s : raise(ArgumentError, "cannot print #{value}")
			when String
				(value.encoding == Encoding::BINARY) ? "X'#{value.unpack1("H*").upcase}'" : string(value)
			# A Rational would print as integer division (1/3), a Complex as nothing SQL can read
			else raise ArgumentError, "cannot print #{value.inspect}"
			end
		end

		def print_variable(node) = node.name

		# Every binary operator associates to the left, so a left operand at the same precedence needs no
		# parentheses: `a - b + c`, `a OR b OR c`. A long chain then prints flat rather than nesting a pair
		# per term, and the left spine is walked in a loop, so its length costs no stack
		def print_binary_expression(node)
			chain = [node]
			while BinaryExpression === (left = chain.last.left) && PRECEDENCE[left.operator] == PRECEDENCE[node.operator]
				chain << left
			end

			chain.reverse_each.reduce(+operand(chain.last.left)) do |sql, link|
				sql << " " << BINARY_OPERATORS.fetch(link.operator) << " " << operand(link.right)
			end
		end

		def print_unary_expression(node)
			case node.operator
			when :NOT then "NOT #{operand(node.operand)}"
			when :NEGATE then "-#{unary_operand(node.operand)}"
			when :IDENTITY then "+#{unary_operand(node.operand)}"
			when :INVERT then "~#{unary_operand(node.operand)}"
			when :IS_NULL then "#{operand(node.operand)} ISNULL"
			when :NOT_NULL then "#{operand(node.operand)} NOTNULL"
			end
		end

		# Two minus signs in a row would start a comment
		def unary_operand(node)
			sql = operand(node)
			sql.start_with?("-", "+") ? "(#{sql})" : sql
		end

		def print_ternary_expression(node)
			operator = (node.operator == :NOT_BETWEEN) ? "NOT BETWEEN" : "BETWEEN"
			"#{operand(node.left)} #{operator} #{operand(node.middle)} AND #{operand(node.right)}"
		end

		def print_like_expression(node)
			operator = (node.operator == :NOT_LIKE) ? "NOT LIKE" : "LIKE"
			join("#{operand(node.left)} #{operator} #{operand(node.right)}", node.escape && "ESCAPE #{operand(node.escape)}")
		end
		alias_method :print_not_like_expression, :print_like_expression

		def print_collation_expression(node) = "#{operand(node.expression)} COLLATE #{identifier(node.sequence)}"

		def print_parenthetical_expression(node) = "(#{print(node.contents)})"

		def print_cast_expression(node) = "CAST(#{join(print(node.expression), "AS", print(node.as))})"

		def print_case_expression(node)
			join("CASE", node.predicate && print(node.predicate), list_of(node.conditions), node.else_clause && "ELSE #{print(node.else_clause)}", "END")
		end

		def list_of(items) = items.map { |item| print(item) }

		def print_case_condition(node) = "WHEN #{print(node.predicate)} THEN #{print(node.consequence)}"

		def print_function_reference(node)
			join(
				"#{qualified(node.schema, node.function)}(#{print(node.arguments)})",
				node.within_group && "WITHIN GROUP (ORDER BY #{print(node.within_group)})",
				node.filter_clause && "FILTER (WHERE #{print(node.filter_clause)})",
				print(node.over_clause),
			)
		end

		def print_function_arguments(node)
			quantifier = node.distinct ? "DISTINCT" : (node.distinct_kw_tok == :ALL && "ALL")
			join(quantifier, list(node.expressions), node.order_by && "ORDER BY #{list(node.order_by)}")
		end

		def print_star_function_argument(_node) = "*"
		def print_empty_function_argument(_node) = ""

		def print_over_clause(node)
			return "OVER #{identifier(node.window_name)}" if node.window_name

			"OVER (#{window_body(node)})"
		end

		def print_frame_spec(node)
			type = node.type.to_s.upcase
			exclude = node.exclude && "EXCLUDE #{node.exclude.to_s.upcase.tr("_", " ")}"
			if node.ending_boundary
				join(type, "BETWEEN", print(node.starting_boundary), "AND", print(node.ending_boundary), exclude)
			else
				join(type, print(node.starting_boundary), exclude)
			end
		end

		def print_frame_boundary(node)
			type = node.type.to_s.upcase.tr("_", " ")
			return type if type == "CURRENT ROW"

			value = node.value
			join((Symbol === value || String === value) ? value.to_s.upcase : print(value), type)
		end

		def print_subquery_expression(node) = "(#{print(node.select)})"
		def print_exists_expression(node) = "EXISTS (#{print(node.select)})"

		def print_raise_expression(node)
			return "RAISE(IGNORE)" if node.type == :IGNORE

			"RAISE(#{node.type}, #{print(node.error_message)})"
		end

		def print_ordering_term(node)
			join(
				print(node.expression), node.collation && "COLLATE #{identifier(node.collation)}",
				node.direction&.to_s&.upcase, node.nulls && "NULLS #{node.nulls.to_s.upcase}",
			)
		end

		# -- column and table definitions

		def print_column_definition(node) = join(identifier(node.name), print(node.type), list_of(Array(node.constraints)))
		def print_column_type(node) = node.text

		def constraint_name(node) = node.name && "CONSTRAINT #{identifier(node.name)}"

		def print_primary_key_column_constraint(node)
			join(constraint_name(node), "PRIMARY KEY", node.direction&.to_s, print(node.conflict_clause), node.autoincrement && "AUTOINCREMENT")
		end

		def print_not_null_column_constraint(node) = join(constraint_name(node), "NOT NULL", print(node.conflict_clause))
		def print_null_column_constraint(node) = join(constraint_name(node), "NULL", print(node.conflict_clause))
		def print_unique_column_constraint(node) = join(constraint_name(node), "UNIQUE", print(node.conflict_clause))
		def print_check_column_constraint(node) = join(constraint_name(node), "CHECK (#{print(node.expression)})", print(node.conflict_clause))
		def print_collate_column_constraint(node) = join(constraint_name(node), "COLLATE #{identifier(node.collation)}")
		def print_foreign_key_column_constraint(node) = join(constraint_name(node), print(node.foreign_key_clause))
		def print_no_op_column_constraint(node) = constraint_name(node)

		def print_default_column_constraint(node)
			return join(constraint_name(node), "DEFAULT #{node.value_tk_src}") if node.value_tk?

			value = node.value
			sql =
				case value
				when Node then "(#{print(value)})"
				else print(LiteralExpression.new(value:))
				end
			join(constraint_name(node), "DEFAULT #{sql}")
		end

		def print_generated_as_column_constraint(node)
			join(constraint_name(node), "GENERATED ALWAYS AS (#{print(node.expression)})", node.type&.to_s)
		end

		def print_conflict_clause(node) = "ON CONFLICT #{node.resolution}"

		def print_primary_key_table_constraint(node)
			join(constraint_name(node), "PRIMARY KEY (#{list(node.columns)}#{" AUTOINCREMENT" if node.autoincrement})", print(node.conflict_clause))
		end

		def print_unique_table_constraint(node) = join(constraint_name(node), "UNIQUE (#{list(node.columns)})", print(node.conflict_clause))
		def print_check_table_constraint(node) = join(constraint_name(node), "CHECK (#{print(node.expression)})", print(node.conflict_clause))
		def print_no_op_table_constraint(node) = constraint_name(node)

		def print_deferrable_column_constraint(node) = join(constraint_name(node), deferrable(node) || "DEFERRABLE")

		# The words as written, or else what `deferred` says
		def deferrable(node)
			return Array(node.deferrable_span_tok).join(" ") if node.deferrable_span?

			"DEFERRABLE INITIALLY DEFERRED" if node.deferred
		end

		def print_foreign_key_table_constraint(node)
			join(constraint_name(node), "FOREIGN KEY (#{list(node.columns)})", print(node.foreign_key_clause))
		end

		def print_foreign_key_clause(node)
			join(
				"REFERENCES", identifier(node.table), node.columns && "(#{list(node.columns)})",
				list_of(Array(node.actions)), list_of(Array(node.match_clauses)),
				deferrable(node),
			)
		end

		def print_foreign_key_action(node) = "ON #{node.trigger.to_s.upcase} #{FOREIGN_KEY_ACTIONS.fetch(node.action)}"
		def print_match_clause(node) = "MATCH #{node.type}"

		def print_indexed_column(node)
			join(identifier(node.name), node.collation && "COLLATE #{identifier(node.collation)}", node.direction&.to_s, node.nulls && "NULLS #{node.nulls.to_s.upcase}")
		end

		def print_strict_table_option(_node) = "STRICT"
		def print_without_rowid_table_option(_node) = "WITHOUT ROWID"
	end
end
