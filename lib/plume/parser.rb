# frozen_string_literal: true

module Plume
	class Parser
		# https://www.sqlite.org/syntaxdiagrams.html
		# Thrown on every dead end, most of which `maybe` backtracks out of, so the
		# message is only put together when someone actually reads it
		class ErrorMessage
			def initialize(sql, token, beg, fin, expected)
				@sql, @token, @beg, @fin, @expected = sql, token, beg, fin, expected
			end

			def msg
				src = @sql.b # the SQL can be invalid UTF-8, which String#strip will not take
				line = src.byteslice(0, @beg).count("\n") + 1
				where = src.strip.include?("\n") ? " line #{line}" : ""
				what = @token ? "token #{@token}[#{@sql.byteslice(@beg, @fin - @beg).inspect}]" : "end of input"
				"Unexpected #{what} at#{where}:\n#{Plume.excerpt(@sql, @beg, @fin)}\n  Expected one of: #{@expected.join(", ")}\n"
			end
		end

		# see: https://github.com/sqlite/sqlite/blob/master/src/parse.y#L255-L283
		# Literals in an expression, names anywhere else: SQLite has no TRUE or FALSE keyword, and lets
		# the CURRENT_* ones (CTIME_KW) fall back to names
		LITERAL_KEYWORDS = Set[:TRUE, :FALSE, :CURRENT_DATE, :CURRENT_TIME, :CURRENT_TIMESTAMP].freeze

		TOKEN_FALLBACKS = Set[
			*LITERAL_KEYWORDS,
			:EXPLAIN,
			:QUERY,
			:PLAN,
			:BEGIN,
			:DEFERRED,
			:IMMEDIATE,
			:EXCLUSIVE,
			:END,
			:ROLLBACK,
			:SAVEPOINT,
			:RELEASE,
			:IF,
			:TEMP,
			:TEMPORARY,
			:WITHIN,
			:WITHOUT,
			:ABORT,
			:ACTION,
			:AFTER,
			:ANALYZE,
			:ASC,
			:ATTACH,
			:BEFORE,
			:BY,
			:CASCADE,
			:CAST,
			:CONFLICT,
			:DATABASE,
			:DESC,
			:DETACH,
			:EACH,
			:FAIL,
			:MATCH,
			:REGEXP,
			:GLOB,
			:LIKE,
			:ROWID,
			:STORED,
			:STRICT,
			:COLUMN,
			:DO,
			:FOR,
			:IGNORE,
			:INITIALLY,
			:INSTEAD,
			:NO,
			:KEY,
			:OF,
			:OFFSET,
			:PRAGMA,
			:RAISE,
			:RECURSIVE,
			:REPLACE,
			:RESTRICT,
			:ROW,
			:ROWS,
			:TRIGGER,
			:VACUUM,
			:VIEW,
			:VIRTUAL,
			:WITH,
			:NULLS,
			:FIRST,
			:LAST,
			:CURRENT,
			:FOLLOWING,
			:PARTITION,
			:PRECEDING,
			:RANGE,
			:UNBOUNDED,
			:EXCLUDE,
			:GROUPS,
			:OTHERS,
			:TIES,
			:GENERATED,
			:ALWAYS,
			:MATERIALIZED,
			:REINDEX,
			:RENAME,
			:CTIME_KW,
		].freeze

		OPERATOR_PRECEDENCE = {
			BITNOT:  100,
			UPLUS:   100,
			UMINUS:  100,
			COLLATE:  90,
			CONCAT:   80,
			PTR1:     80,
			PTR2:     80,
			STAR:     70,
			SLASH:    70,
			REM:      70,
			PLUS:     60,
			MINUS:    60,
			BITAND:   55,
			BITOR:    55,
			LSHIFT:   55,
			RSHIFT:   55,
			NOT:      50,
			LT:       40,
			GT:       40,
			LE:       40,
			GE:       40,
			EQ:       30,
			NE:       30,
			IS:       30,
			ISNULL:   30,
			NOTNULL:  30,
			BETWEEN:  20,
			IN:       20,
			MATCH:    20,
			LIKE:     20,
			REGEXP:   20,
			GLOB:     20,
			AND:      10,
			OR:        5,
		}.freeze

		def initialize(sql)
			@lexer = Lexer.new(sql, skip_spaces: true)
			@peek_buffer = []
		end

		def parse
			result = catch(:ERROR) { sql_stmt_list }

			if ErrorMessage === result
				raise SyntaxError.new(result.msg)
			else
				result
			end
		rescue *STACK_EXHAUSTED
			# How deep is too deep depends on the stack the caller has left, so no fixture relies on it
			raise SyntaxError.new("statement nested too deeply")
		end

		def sql_stmt_list
			# Relevant `parse.y` grammar rules:
			#   input ::= cmdlist
			#   cmdlist ::= cmdlist ecmd | ecmd
			#   ecmd ::= SEMI | cmdx SEMI | explain cmdx SEMI
			#
			# Syntax diagram:
			#     ┌──────{ ; }◀─────┐
			#   ◯─┴┬─▶[ sql-stmt ]─┬┴─▶◯
			#      └───────▶───────┘
			#
			# Simplified grammar:
			#   SEMI* [sql_stmt SEMI]*
			#
			# Relevant SQLite documentation:
			#   - https://www.sqlite.org/lang.html
			#
			# A `sql_stmt_list` is zero or more statements,
			# where a `;` is the statement separator,
			# but an empty statement is allowed.
			#
			[].tap do |stmts|
				until current_token.nil?
					maybe :SEMI
					stmts << sql_stmt if current_token
					maybe :SEMI
				end
			end
		end

		def sql_stmt
			#
				# Relevant `parse.y` grammar rules:
				#   ecmd ::= SEMI | cmdx SEMI | explain cmdx SEMI
				#   explain ::= EXPLAIN | EXPLAIN QUERY PLAN
				#   cmdx ::= cmd
				#
				# Syntax diagram:
				#   ◯─┬─────────────┬▶─────────────────────┬─┬─▶[ alter-table-stmt ]──────────▶─┬─▶◯
				#     └─{ EXPLAIN }─┴─▶{ QUERY }─▶{ PLAN }─┘ ├─▶[ analyze-stmt ]──────────────▶─┤
				#                                            ├─▶[ attach-stmt ]───────────────▶─┤
				#                                            ├─▶[ begin-stmt ]────────────────▶─┤
				#                                            ├─▶[ commit-stmt ]───────────────▶─┤
				#                                            ├─▶[ create-index-stmt ]─────────▶─┤
				#                                            ├─▶[ create-table-stmt ]─────────▶─┤
				#                                            ├─▶[ create-trigger-stmt ]───────▶─┤
				#                                            ├─▶[ create-view-stmt ]──────────▶─┤
				#                                            ├─▶[ create-virtual-table-stmt ]─▶─┤
				#                                            ├─▶[ delete-stmt ]───────────────▶─┤
				#                                            ├─▶[ detach-stmt ]───────────────▶─┤
				#                                            ├─▶[ drop-index-stmt ]───────────▶─┤
				#                                            ├─▶[ drop-table-stmt ]───────────▶─┤
				#                                            ├─▶[ drop-trigger-stmt ]─────────▶─┤
				#                                            ├─▶[ drop-view-stmt ]────────────▶─┤
				#                                            ├─▶[ insert-stmt ]───────────────▶─┤
				#                                            ├─▶[ pragma-stmt ]───────────────▶─┤
				#                                            ├─▶[ reindex-stmt ]──────────────▶─┤
				#                                            ├─▶[ release-stmt ]──────────────▶─┤
				#                                            ├─▶[ rollback-stmt ]─────────────▶─┤
				#                                            ├─▶[ savepoint-stmt ]────────────▶─┤
				#                                            ├─▶[ select-stmt ]───────────────▶─┤
				#                                            ├─▶[ update-stmt ]───────────────▶─┤
				#                                            └─▶[ vacuum-stmt ]───────────────▶─┘
				# Simplified grammar:
				#   [EXPLAIN [QUERY PLAN]] stmt
				#
				# Relevant SQLite documentation:
				#   - https://www.sqlite.org/lang_explain.html
				#   - https://www.sqlite.org/eqp.html
				#   - https://www.sqlite.org/opcode.html
				#
				# A `sql_stmt` is a single SQL statement, optionally preceded by one of two different
				# explanation prefixes. A simple `EXPLAIN` prefix requests the bytecode instructions,
				# while `EXPLAIN QUERY PLAN` requests the query plan.
				#
				# This method doesn't consume tokens associated with the statements so that each
				# statement method can independently consume the tokens it needs.
			#
			if (explain_kw = maybe_one_of [:EXPLAIN, :QUERY, :PLAN].freeze, :EXPLAIN)
				return ExplainStatement.concrete(
					full_source: @lexer.sql,
					explain_kw:  Token::Keyword(explain_kw),
					statement:   cmd,
				)
			end

			cmd
		end

		def cmd
			case current_token
			when :ALTER							then alter_table_stmt
			when :ANALYZE						then analyze_stmt
			when :ATTACH						then attach_stmt
			when :BEGIN							then begin_stmt
			when :COMMIT, :END			then commit_stmt
			when :CREATE
				case peek
				when :INDEX		then create_index_stmt
				when :TABLE		then create_table_stmt
				when :TRIGGER	then create_trigger_stmt
				when :VIEW		then create_view_stmt
				when :VIRTUAL	then create_virtual_table_stmt
				when :UNIQUE	then create_index_stmt
				when :TEMP, :TEMPORARY
					case peek(2)
					when [:TEMP, :TABLE]				then create_table_stmt
					when [:TEMP, :TRIGGER]			then create_trigger_stmt
					when [:TEMP, :VIEW]					then create_view_stmt
					when [:TEMPORARY, :TABLE]		then create_table_stmt
					when [:TEMPORARY, :TRIGGER]	then create_trigger_stmt
					when [:TEMPORARY, :VIEW]		then create_view_stmt
					else
						expected! :TABLE, :TRIGGER, :VIEW
					end
				else
					expected! :INDEX, :TABLE, :TRIGGER, :VIEW, :VIRTUAL, :UNIQUE, :TEMP, :TEMPORARY
				end
			when :DELETE						then delete_stmt
			when :DETACH						then detach_stmt
			when :DROP							then drop_stmt
			when :INSERT, :REPLACE	then insert_stmt
			when :PRAGMA						then pragma_stmt
			when :REINDEX						then reindex_stmt
			when :RELEASE						then release_stmt
			when :ROLLBACK					then rollback_stmt
			when :SAVEPOINT					then savepoint_stmt
			when :SELECT, :VALUES		then select_stmt
			when :UPDATE						then update_stmt
			when :VACUUM						then vacuum_stmt
			when :WITH							then with_stmt
			else
				expected!(:ALTER, :ANALYZE, :ATTACH, :BEGIN, :COMMIT, :END, :CREATE, :DELETE, :DETACH, :DROP, :INSERT, :REPLACE, :PRAGMA, :REINDEX, :RELEASE, :ROLLBACK, :SAVEPOINT, :SELECT, :UPDATE, :VACUUM, :WITH)
			end
		end

		# ---------- Statements ----------

		def begin_stmt
			#
				# Relevant `parse.y` grammar rules:
				#   cmd ::= BEGIN transtype trans_opt
				#   transtype ::= . | DEFERRED | IMMEDIATE | EXCLUSIVE
				#   trans_opt ::= . | TRANSACTION | TRANSACTION nm
				#
				# Relevant SQLite documentation:
				#   - https://www.sqlite.org/lang_transaction.html
			#
			begin_kw = require :BEGIN
			type_kw = maybe_one_of :DEFERRED, :IMMEDIATE, :EXCLUSIVE
			transaction_kw, name_tk = transaction_name

			BeginStatement.concrete(
				full_source:    @lexer.sql,
				begin_kw:       Token::Keyword(begin_kw),
				type_kw:        Token::Keyword(type_kw),
				transaction_kw: Token::Keyword(transaction_kw),
				name_tk:        Token::Identifier(name_tk),
			)
		end

		def commit_stmt
			#
				# Relevant `parse.y` grammar rules:
				#   cmd ::= COMMIT|END trans_opt
				#
				# Relevant SQLite documentation:
				#   - https://www.sqlite.org/lang_transaction.html
			#
			commit_kw = require_one_of :COMMIT, :END
			transaction_kw, name_tk = transaction_name

			CommitStatement.concrete(
				full_source:    @lexer.sql,
				commit_kw:      Token::Keyword(commit_kw),
				transaction_kw: Token::Keyword(transaction_kw),
				name_tk:        Token::Identifier(name_tk),
			)
		end

		def rollback_stmt
			#
				# Relevant `parse.y` grammar rules:
				#   cmd ::= ROLLBACK trans_opt
				#   cmd ::= ROLLBACK trans_opt TO savepoint_opt nm
				#   savepoint_opt ::= SAVEPOINT | .
				#
				# Relevant SQLite documentation:
				#   - https://www.sqlite.org/lang_transaction.html
				#   - https://www.sqlite.org/lang_savepoint.html
			#
			rollback_kw = require :ROLLBACK
			transaction_kw, name_tk = transaction_name
			if (to_kw = maybe_one_of [:TO, :SAVEPOINT].freeze, :TO)
				savepoint_tk = name
			end

			RollbackStatement.concrete(
				full_source:    @lexer.sql,
				rollback_kw:    Token::Keyword(rollback_kw),
				transaction_kw: Token::Keyword(transaction_kw),
				name_tk:        Token::Identifier(name_tk),
				to_kw:          Token::Keyword(to_kw),
				savepoint_tk:   Token::Identifier(savepoint_tk),
			)
		end

		# `trans_opt ::= . | TRANSACTION | TRANSACTION nm` - the name is accepted and ignored by SQLite
		def transaction_name
			return [] unless (transaction_kw = maybe :TRANSACTION)

			name_tk = maybe { name(except: [:TO]) } unless statement_end?
			[transaction_kw, name_tk]
		end

		def savepoint_stmt
			#
				# Relevant `parse.y` grammar rules:
				#   cmd ::= SAVEPOINT nm
				#
				# Relevant SQLite documentation:
				#   - https://www.sqlite.org/lang_savepoint.html
			#
			savepoint_kw = require :SAVEPOINT

			SavepointStatement.concrete(
				full_source:  @lexer.sql,
				savepoint_kw: Token::Keyword(savepoint_kw),
				name_tk:      Token::Identifier(name),
			)
		end

		def release_stmt
			#
				# Relevant `parse.y` grammar rules:
				#   cmd ::= RELEASE savepoint_opt nm
				#
				# Relevant SQLite documentation:
				#   - https://www.sqlite.org/lang_savepoint.html
			#
			release_kw = require_one_of [:RELEASE, :SAVEPOINT].freeze, :RELEASE

			ReleaseStatement.concrete(
				full_source: @lexer.sql,
				release_kw:  Token::Keyword(release_kw),
				name_tk:     Token::Identifier(name),
			)
		end

		def drop_stmt
			#
				# Relevant `parse.y` grammar rules:
				#   cmd ::= DROP TABLE ifexists fullname
				#   cmd ::= DROP VIEW ifexists fullname
				#   cmd ::= DROP INDEX ifexists fullname
				#   cmd ::= DROP TRIGGER ifexists fullname
				#   ifexists ::= IF EXISTS | .
				#
				# Relevant SQLite documentation:
				#   - https://www.sqlite.org/lang_droptable.html
				#   - https://www.sqlite.org/lang_dropview.html
				#   - https://www.sqlite.org/lang_dropindex.html
				#   - https://www.sqlite.org/lang_droptrigger.html
			#
			drop_kw = require :DROP
			type_kw = require_one_of :TABLE, :VIEW, :INDEX, :TRIGGER
			if_exists_kw = maybe_all_of :IF, :EXISTS

			DropStatement.concrete(
				full_source:  @lexer.sql,
				drop_kw:      Token::Keyword(drop_kw),
				type_kw:      Token::Keyword(type_kw),
				if_exists_kw: Token::Keyword(if_exists_kw),
				target:       table_name,
			)
		end

		def pragma_stmt
			#
				# Relevant `parse.y` grammar rules:
				#   cmd ::= PRAGMA nm dbnm
				#   cmd ::= PRAGMA nm dbnm EQ nmnum
				#   cmd ::= PRAGMA nm dbnm LP nmnum RP
				#   cmd ::= PRAGMA nm dbnm EQ minus_num
				#   cmd ::= PRAGMA nm dbnm LP minus_num RP
				#   nmnum ::= plus_num | nm | ON | DELETE | DEFAULT
				#
				# Syntax diagram:
				#   ◯─▶{ PRAGMA }┬▶{ schema-name }─▶{ . }┬▶{ pragma-name }┬─────────────────────────────┬─▶◯
				#                └───────────▶───────────┘                ├▶{ = }─▶[ pragma-value ]─────┤
				#                                                         └▶{ ( }─▶[ pragma-value ]─▶{ ) }┘
				#
				# Relevant SQLite documentation:
				#   - https://www.sqlite.org/pragma.html
			#
			pragma_kw = require :PRAGMA
			name_tk = name
			if (dot_tk = maybe :DOT)
				schema_tk = name_tk
				name_tk = name
			end
			if (eq_tk = maybe :EQ)
				value_tk = pragma_value
			elsif (eq_tk = maybe :LP)
				value_tk = pragma_value
				value_rp = require :RP
			end

			PragmaStatement.concrete(
				full_source: @lexer.sql,
				pragma_kw:   Token::Keyword(pragma_kw),
				schema_tk:   Token::Identifier(schema_tk),
				dot_tk:      Token::Punctuation(dot_tk),
				name_tk:     Token::Identifier(name_tk),
				eq_tk:       Token::Punctuation(eq_tk),
				value_tk:    value_tk,
				value_rp:    Token::Punctuation(value_rp),
			)
		end

		def pragma_value
			if current_token in :PLUS | :MINUS | :INTEGER | :FLOAT
				Token::Numeric(signed_number)
			elsif (keyword_tk = maybe_one_of :ON, :DELETE, :DEFAULT, :TRUE, :FALSE)
				Token::Keyword(keyword_tk)
			else
				Token::Identifier(name)
			end
		end

		def attach_stmt
			#
				# Relevant `parse.y` grammar rules:
				#   cmd ::= ATTACH database_kw_opt expr AS expr key_opt
				#   key_opt ::= . | KEY expr
				#   database_kw_opt ::= DATABASE | .
				#
				# Relevant SQLite documentation:
				#   - https://www.sqlite.org/lang_attach.html
			#
			attach_kw = require_one_of [:ATTACH, :DATABASE].freeze, :ATTACH
			file = expression
			as_kw = require :AS
			schema = expression
			if (key_kw = maybe :KEY)
				key = expression
			end

			AttachStatement.concrete(
				full_source: @lexer.sql,
				attach_kw:   Token::Keyword(attach_kw),
				file:        file,
				as_kw:       Token::Keyword(as_kw),
				schema:      schema,
				key_kw:      Token::Keyword(key_kw),
				key:         key,
			)
		end

		def detach_stmt
			#
				# Relevant `parse.y` grammar rules:
				#   cmd ::= DETACH database_kw_opt expr
				#
				# Relevant SQLite documentation:
				#   - https://www.sqlite.org/lang_detach.html
			#
			detach_kw = require_one_of [:DETACH, :DATABASE].freeze, :DETACH

			DetachStatement.concrete(
				full_source: @lexer.sql,
				detach_kw:   Token::Keyword(detach_kw),
				schema:      expression,
			)
		end

		def analyze_stmt
			#
				# Relevant `parse.y` grammar rules:
				#   cmd ::= ANALYZE | ANALYZE nm dbnm
				#
				# Relevant SQLite documentation:
				#   - https://www.sqlite.org/lang_analyze.html
			#
			analyze_kw = require :ANALYZE
			target = table_name unless statement_end?

			AnalyzeStatement.concrete(
				full_source: @lexer.sql,
				analyze_kw:  Token::Keyword(analyze_kw),
				target:      target,
			)
		end

		def reindex_stmt
			#
				# Relevant `parse.y` grammar rules:
				#   cmd ::= REINDEX | REINDEX nm dbnm
				#
				# Relevant SQLite documentation:
				#   - https://www.sqlite.org/lang_reindex.html
			#
			reindex_kw = require :REINDEX
			target = table_name unless statement_end?

			ReindexStatement.concrete(
				full_source: @lexer.sql,
				reindex_kw:  Token::Keyword(reindex_kw),
				target:      target,
			)
		end

		def vacuum_stmt
			#
				# Relevant `parse.y` grammar rules:
				#   cmd ::= VACUUM vinto | VACUUM nm vinto
				#   vinto ::= INTO expr | .
				#
				# Relevant SQLite documentation:
				#   - https://www.sqlite.org/lang_vacuum.html
			#
			vacuum_kw = require :VACUUM
			schema_tk = maybe { name } unless current_token.nil? || current_token in :SEMI | :INTO
			if (into_kw = maybe :INTO)
				into = expression
			end

			VacuumStatement.concrete(
				full_source: @lexer.sql,
				vacuum_kw:   Token::Keyword(vacuum_kw),
				schema_tk:   Token::Identifier(schema_tk),
				into_kw:     Token::Keyword(into_kw),
				into:        into,
			)
		end

		def create_index_stmt
			#
				# Relevant `parse.y` grammar rules:
				#   cmd ::= createkw uniqueflag INDEX ifnotexists nm dbnm ON nm LP sortlist RP where_opt
				#   uniqueflag ::= UNIQUE | .
				#
				# Syntax diagram:
				#   ◯─▶{ CREATE }┬▶{ UNIQUE }┬▶{ INDEX }┬▶{ IF }─▶{ NOT }─▶{ EXISTS }┬┐
				#                └─────▶─────┘          └───────────────▶────────────┘│
				#   ┌──────────────────────────────────◀──────────────────────────────┘
				#   └┬▶{ schema-name }─▶{ . }┬▶{ index-name }─▶{ ON }─▶{ table-name }─▶{ ( }┐
				#    └──────────▶────────────┘                                              │
				#   ┌───────────────────────────────────◀───────────────────────────────────┘
				#   └┬▶[ indexed-column ]┬▶{ ) }┬────────────────────────┬─▶◯
				#    └──────{ , }◀───────┘      └▶{ WHERE }─▶[ expr ]────┘
				#
				# Relevant SQLite documentation:
				#   - https://www.sqlite.org/lang_createindex.html
				#   - https://www.sqlite.org/partialindex.html
				#   - https://www.sqlite.org/expridx.html
			#
			create_kw = require :CREATE
			unique_kw = maybe :UNIQUE
			index_kw = require :INDEX
			if_not_exists_kw = maybe_all_of :IF, :NOT, :EXISTS
			index = table_name
			on_kw = require :ON
			table_tk = name
			columns_lp = require :LP
			columns = require_some(trailing_sep: :COMMA) { ordering_term }
			columns_rp = require :RP
			if (where_kw = maybe :WHERE)
				condition = expression
			end

			CreateIndexStatement.concrete(
				full_source:      @lexer.sql,
				create_kw:        Token::Keyword(create_kw),
				unique_kw:        Token::Keyword(unique_kw),
				index_kw:         Token::Keyword(index_kw),
				if_not_exists_kw: Token::Keyword(if_not_exists_kw),
				index:            index,
				on_kw:            Token::Keyword(on_kw),
				table_tk:         Token::Identifier(table_tk),
				columns_lp:       Token::Punctuation(columns_lp),
				columns:          columns,
				columns_rp:       Token::Punctuation(columns_rp),
				where_kw:         Token::Keyword(where_kw),
				condition:        condition,
			)
		end

		def alter_table_stmt
			#
				# Relevant `parse.y` grammar rules:
				#   cmd ::= ALTER TABLE fullname RENAME TO nm
				#   cmd ::= ALTER TABLE add_column_fullname ADD kwcolumn_opt columnname carglist
				#   cmd ::= ALTER TABLE fullname DROP kwcolumn_opt nm
				#   cmd ::= ALTER TABLE fullname RENAME kwcolumn_opt nm TO nm
				#   cmd ::= ALTER TABLE fullname DROP CONSTRAINT nm
				#   cmd ::= ALTER TABLE fullname ALTER kwcolumn_opt nm DROP NOT NULL
				#   cmd ::= ALTER TABLE fullname ALTER kwcolumn_opt nm SET NOT NULL onconf
				#   cmd ::= ALTER TABLE fullname ADD CONSTRAINT nm CHECK LP expr RP onconf
				#   cmd ::= ALTER TABLE fullname ADD CHECK LP expr RP onconf
				#   kwcolumn_opt ::= . | COLUMNKW
				#
				# Relevant SQLite documentation:
				#   - https://www.sqlite.org/lang_altertable.html
			#
			alter_table_kw = require_all_of :ALTER, :TABLE
			table = table_name

			if current_token == :RENAME && peek == :TO
				action = :RENAME_TABLE
				action_kw = require :RENAME
				to_kw = require :TO
				new_name_tk = name
			elsif (action_kw = maybe_one_of [:RENAME, :COLUMN].freeze, :RENAME)
				action = :RENAME_COLUMN
				column_tk = name
				to_kw = require :TO
				new_name_tk = name
			elsif current_token == :ADD && (peek in :CONSTRAINT | :CHECK)
				action = :ADD_CONSTRAINT
				action_kw = require :ADD
				constraint_name = name if (constraint_kw = maybe :CONSTRAINT)
				constraint = check_table_constraint(constraint_kw, constraint_name)
			elsif (action_kw = maybe_one_of [:ADD, :COLUMN].freeze, :ADD)
				action = :ADD_COLUMN
				column_definition = column_def
			elsif current_token == :DROP && peek == :CONSTRAINT
				action = :DROP_CONSTRAINT
				action_kw = require_all_of :DROP, :CONSTRAINT
				constraint_name_tk = name
			elsif (action_kw = maybe_one_of [:DROP, :COLUMN].freeze, :DROP)
				action = :DROP_COLUMN
				column_tk = name
			elsif (action_kw = maybe_one_of [:ALTER, :COLUMN].freeze, :ALTER)
				column_tk = name
				if current_token == :DROP
					action = :DROP_NOT_NULL
					not_null_kw = require_all_of :DROP, :NOT, :NULL
				else
					action = :SET_NOT_NULL
					not_null_kw = require_all_of :SET, :NOT, :NULL
					on_conflict = maybe { conflict_clause }
				end
			else
				expected!(:RENAME, :ADD, :DROP, :ALTER)
			end

			AlterTableStatement.concrete(
				full_source:        @lexer.sql,
				alter_table_kw:     Token::Keyword(alter_table_kw),
				table:              table,
				action:             action,
				action_kw:          Token::Keyword(action_kw),
				column_tk:          Token::Identifier(column_tk),
				to_kw:              Token::Keyword(to_kw),
				new_name_tk:        Token::Identifier(new_name_tk),
				column_definition:  column_definition,
				constraint:         constraint,
				constraint_name_tk: Token::Identifier(constraint_name_tk),
				not_null_kw:        Token::Keyword(not_null_kw),
				conflict_clause:    on_conflict,
			)
		end

		# tcons ::= CHECK LP expr RP onconf, after the `CONSTRAINT nm` the caller may have read
		def check_table_constraint(constraint_kw = nil, constraint_name = nil)
			check_kw = require :CHECK
			check_lp = require :LP
			check = expression
			check_rp = require :RP
			on_conflict = maybe { conflict_clause }

			CheckTableConstraint.concrete(
				full_source:     @lexer.sql,
				constraint_kw:   Token::Keyword(constraint_kw),
				name_tk:         Token::Identifier(constraint_name),
				check_kw:        Token::Keyword(check_kw),
				check_lp:        Token::Punctuation(check_lp),
				expression:      check,
				check_rp:        Token::Punctuation(check_rp),
				conflict_clause: on_conflict,
			)
		end

		def create_virtual_table_stmt
			#
				# Relevant `parse.y` grammar rules:
				#   create_vtab ::= createkw VIRTUAL TABLE ifnotexists nm dbnm USING nm
				#   cmd ::= create_vtab | create_vtab LP vtabarglist RP
				#   vtabarglist ::= vtabarg | vtabarglist COMMA vtabarg
				#   vtabarg ::= . | vtabarg vtabargtoken
				#   vtabargtoken ::= ANY | lp anylist RP
				#
				# Relevant SQLite documentation:
				#   - https://www.sqlite.org/lang_createvtab.html
			#
			create_virtual_table_kw = require_all_of :CREATE, :VIRTUAL, :TABLE
			if_not_exists_kw = maybe_all_of :IF, :NOT, :EXISTS
			table = table_name
			using_kw = require :USING
			module_tk = name
			if (arguments_lp = maybe :LP)
				arguments, arguments_rp = module_arguments
			end

			CreateVirtualTableStatement.concrete(
				full_source:             @lexer.sql,
				create_virtual_table_kw: Token::Keyword(create_virtual_table_kw),
				if_not_exists_kw:        Token::Keyword(if_not_exists_kw),
				table:                   table,
				using_kw:                Token::Keyword(using_kw),
				module_tk:               Token::Identifier(module_tk),
				arguments_lp:            Token::Punctuation(arguments_lp),
				arguments:               arguments,
				arguments_rp:            Token::Punctuation(arguments_rp),
			)
		end

		# Collects the text of each comma-separated argument up to the closing parenthesis,
		# whatever tokens it is made of
		def module_arguments
			arguments = []
			depth = 0
			first = last = nil

			loop do
				expected!(:RP) if current_token.nil?

				if depth.zero? && current_token in :COMMA | :RP
					arguments << (first ? @lexer.sql.byteslice(first, last - first) : "")
					first = last = nil
					return [arguments, advance] if current_token == :RP

					advance
					next
				end

				depth += 1 if current_token == :LP
				depth -= 1 if current_token == :RP
				_tok, beg, fin = advance
				first ||= beg
				last = fin
			end
		end

		def create_trigger_stmt
			#
				# Relevant `parse.y` grammar rules:
				#   cmd ::= createkw trigger_decl BEGIN trigger_cmd_list END
				#   trigger_decl ::= temp TRIGGER ifnotexists nm dbnm trigger_time trigger_event ON fullname foreach_clause when_clause
				#   trigger_time ::= BEFORE | AFTER | INSTEAD OF | .
				#   trigger_event ::= DELETE | INSERT | UPDATE | UPDATE OF idlist
				#   foreach_clause ::= . | FOR EACH ROW
				#   when_clause ::= . | WHEN expr
				#   trigger_cmd_list ::= trigger_cmd_list trigger_cmd SEMI | trigger_cmd SEMI
				#
				# Relevant SQLite documentation:
				#   - https://www.sqlite.org/lang_createtrigger.html
			#
			create_kw = require :CREATE
			temp_kw = maybe_one_of :TEMP, :TEMPORARY
			trigger_kw = require :TRIGGER
			if_not_exists_kw = maybe_all_of :IF, :NOT, :EXISTS
			trigger = table_name
			time_kw = maybe_one_of :BEFORE, :AFTER, [:INSTEAD, :OF].freeze
			if (event_kw = maybe_all_of :UPDATE, :OF)
				columns = require_some(trailing_sep: :COMMA) { column_reference }
			else
				event_kw = require_one_of :DELETE, :INSERT, :UPDATE
			end
			on_kw = require :ON
			table = table_name
			for_each_row_kw = maybe_all_of :FOR, :EACH, :ROW
			if (when_kw = maybe :WHEN)
				condition = expression
			end
			begin_kw = require :BEGIN
			statements = require_some do
				statement =
					case current_token
					when :UPDATE then update_stmt
					when :INSERT, :REPLACE then insert_stmt
					when :DELETE then delete_stmt
					when :WITH then with_stmt
					else select_stmt
					end
				require :SEMI
				statement
			end
			end_kw = require :END

			CreateTriggerStatement.concrete(
				full_source:      @lexer.sql,
				create_kw:        Token::Keyword(create_kw),
				temp_kw:          Token::Keyword(temp_kw),
				trigger_kw:       Token::Keyword(trigger_kw),
				if_not_exists_kw: Token::Keyword(if_not_exists_kw),
				trigger:          trigger,
				time_kw:          Token::Keyword(time_kw),
				event_kw:         Token::Keyword(event_kw),
				columns:          columns,
				on_kw:            Token::Keyword(on_kw),
				table:            table,
				for_each_row_kw:  Token::Keyword(for_each_row_kw),
				when_kw:          Token::Keyword(when_kw),
				condition:        condition,
				begin_kw:         Token::Keyword(begin_kw),
				statements:       statements,
				end_kw:           Token::Keyword(end_kw),
			)
		end

		def create_table_stmt
			#
				# Relevant `parse.y` grammar rules:
				#   cmd ::= create_table create_table_args
				#   create_table ::= createkw temp TABLE ifnotexists nm dbnm
				#   create_table_args ::= LP columnlist conslist_opt RP table_option_set | AS select
				#   createkw ::= CREATE
				#   temp ::= . | TEMP
				#   ifnotexists ::= . | IF NOT EXISTS
				#   columnlist ::= columnlist COMMA columnname carglist
				#   nm ::= idj | STRING
				#   dbnm ::= . | DOT nm
				#
				# Syntax diagram:
				#   ◯─▶{ CREATE }┬───────▶──────┬▶{ TABLE }┬▶{ IF }─▶{ NOT }─▶{ EXISTS }─┐
				#                ├▶{ TEMP }─────┤          │                             │
				#                └▶{ TEMPORARY }┘          │                             │
				#   ┌─────────────────────◀────────────────┴──────────────────◀──────────┘
				#   ├─▶{ schema-name }─▶{ . }─┬▶{ table-name }┬───────▶{ AS }─▶[ select-stmt ]───▶─────┐
				#   └────────▶────────────────┘               │                                        │
				#   ┌────────────────────◀────────────────────┘                     ┌────────▶─────────┼─▶◯
				#   └▶{ ( }─┬▶[ column-def ]─┬▶┬─────────────────────────────┬▶{ ) }┴▶[ table-options ]┘
				#           └─────{ , }◀─────┘ └[ table-constraint ]◀─{ , }◀─┘
				#
				# Simplified grammar:
				#   CREATE [TEMP] TABLE [IF NOT EXISTS] name [DOT name] (
				#     LP column_def [, column_def]* [table_constraint [, table_constraint]*] RP [table_options]
				#     | AS select_stmt
				#   )
				#
				# Relevant SQLite documentation:
				#   - https://www.sqlite.org/lang_createtable.html
				#
				# A `create_table_stmt` creates a table.
			#
			create_kw         = require      :CREATE
			temp_kw           = maybe_one_of :TEMP, :TEMPORARY
			table_kw          = require      :TABLE
			if_not_exists_kw  = maybe_all_of :IF, :NOT, :EXISTS
			table_name        =              table_name()

			if maybe :AS
				as_select = select_stmt

				CreateTableStatement.concrete(
					full_source:      @lexer.sql,
					create_kw:        Token::Keyword(create_kw),
					temp_kw:          Token::Keyword(temp_kw),
					table_kw:         Token::Keyword(table_kw),
					if_not_exists_kw: Token::Keyword(if_not_exists_kw),
					table:            table_name,
					select_statement: as_select
				)
			elsif (columns_lp = maybe :LP)
				# The comma after the last column leads into the table constraints: `columnlist COMMA conslist`
				columns         = require_some(given: column_def, trailing_sep: :COMMA) do
					column_def unless current_token in :CONSTRAINT | :PRIMARY | :UNIQUE | :CHECK | :FOREIGN
				end
				# inlined `table_constraint`, but for CHECK, which ALTER TABLE shares through check_table_constraint
				constraints     = maybe_some(trailing_sep: [:COMMA, nil].freeze) do
					#
						# Relevant `parse.y` grammar rules:
						#   conslist_opt ::= . | COMMA conslist.
						#   conslist ::= conslist tconscomma tcons | tcons
						#   tconscomma ::= . | COMMA
						#   tcons ::= CONSTRAINT nm |
						#             PRIMARY KEY LP sortlist autoinc RP onconf |
						#             UNIQUE LP sortlist RP onconf |
						#             CHECK LP expr RP onconf |
						#             FOREIGN KEY LP eidlist RP REFERENCES nm eidlist_opt refargs defer_subclause_opt
						#
						# Syntax diagram:
						#   ◯─▶┬▶{ CONSTRAINT }─▶{ name }─┐
						#      ├─────────────◀────────────┘
						#      ├─▶{ PRIMARY }─▶{ KEY }───▶{ ( }┬▶[ indexed-column ]┬┬▶{ AUTOINCREMENT }┬▶{ ) }─▶[ conflict-clause ]───┬─▶◯
						#      │                               └───────{ , }◀──────┘└────────▶─────────┘                              │
						#      ├─▶{ UNIQUE }──▶{ ( }┬▶[ indexed-column ]┬▶{ ) }─▶[ conflict-clause ]────────────────────────────────▶─┤
						#      │                    └───────{ , }◀──────┘                                                             │
						#      ├─▶{ CHECK }─▶{ ( }─▶[ expr ]─▶{ ) }─▶[ conflict-clause ]────────────────────────────────────────────▶─┤
						#      └─▶{ FOREIGN }─▶{ KEY }─▶{ ( }┬▶[ indexed-column ]┬▶{ ) }─▶[ foreign-key-clause ]────────────────────▶─┘
						#                                    └──────{ , }◀───────┘
						#
						# Simplified grammar:
						#
						# Relevant SQLite documentation:
						#   - https://www.sqlite.org/syntax/table-constraint.html
						#
						# A set of SQL constraints for each table.
						# SQLite supports UNIQUE, NOT NULL, CHECK and FOREIGN KEY constraints.
					#
					if (constraint_kw     = maybe :CONSTRAINT)
						constraint_name     = name
					end

					if    (unique_kw      = maybe :UNIQUE)
						unique_lp           = require :LP
						unique_columns      = require_some(trailing_sep: :COMMA) { indexed_column(nulls: true) }
						unique_rp           = require        :RP
						on_conflict         = maybe        { conflict_clause }

						UniqueTableConstraint.concrete(
							full_source:     @lexer.sql,
							constraint_kw:   Token::Keyword(constraint_kw),
							name_tk:         Token::Identifier(constraint_name),
							unique_kw:       Token::Keyword(unique_kw),
							unique_lp:       Token::Punctuation(unique_lp),
							columns:         unique_columns,
							unique_rp:       Token::Punctuation(unique_rp),
							conflict_clause: on_conflict,
						)
					elsif current_token == :CHECK
						check_table_constraint(constraint_kw, constraint_name)
					elsif (primary_key_kw = maybe_all_of   :PRIMARY, :KEY)
						primary_key_lp      = require :LP
						primary_key_columns = require_some(trailing_sep: :COMMA) { indexed_column(nulls: true) }
						autoincrement_kw    = maybe          :AUTOINCREMENT
						primary_key_rp      = require        :RP
						on_conflict         = maybe        { conflict_clause }

						PrimaryKeyTableConstraint.concrete(
							full_source:      @lexer.sql,
							constraint_kw:    Token::Keyword(constraint_kw),
							name_tk:          Token::Identifier(constraint_name),
							primary_key_kw:   Token::Keyword(primary_key_kw),
							primary_key_lp:   Token::Punctuation(primary_key_lp),
							columns:          primary_key_columns,
							autoincrement_kw: Token::Keyword(autoincrement_kw),
							primary_key_rp:   Token::Punctuation(primary_key_rp),
							conflict_clause:  on_conflict,
						)
					elsif (foreign_key_kw = maybe_all_of   :FOREIGN, :KEY)
						foreign_key_lp      = require :LP
						foreign_key_columns = require_some(trailing_sep: :COMMA) { indexed_column }
						foreign_key_rp      = require        :RP
						clause              =                foreign_key_clause

						ForeignKeyTableConstraint.concrete(
							full_source:        @lexer.sql,
							constraint_kw:      Token::Keyword(constraint_kw),
							name_tk:            Token::Identifier(constraint_name),
							foreign_key_kw:     Token::Keyword(foreign_key_kw),
							foreign_key_lp:     Token::Punctuation(foreign_key_lp),
							columns:            foreign_key_columns,
							foreign_key_rp:     Token::Punctuation(foreign_key_rp),
							foreign_key_clause: clause,
						)
					else
						if constraint_name
							NoOpTableConstraint.concrete(
								full_source:   @lexer.sql,
								constraint_kw: Token::Keyword(constraint_kw),
								name_tk:       Token::Identifier(constraint_name),
							)
						else
							expected!(:PRIMARY, :UNIQUE, :CHECK, :FOREIGN)
						end
					end
				end
				columns_rp      = require :RP
				# inlined `table_options`
				options         = maybe_some(trailing_sep: :COMMA) do
					#
						# Relevant `parse.y` grammar rules:
						#   table_option_set ::= . | table_option | table_option_set COMMA table_option
						#   table_option ::= WITHOUT nm  // nm must be "ROWID"
						#   table_option ::= nm          // nm must be "STRICT"
						#
						# Syntax diagram:
						#       ┌─▶{ WITHOUT }─▶{ ROWID }─┐
						#   ◯─┬─┤                         ├─┬─▶◯
						#     │ └─▶{ STRICT }─────────────┘ │
						#     └──────◀───────────────{ , }◀─┘
						#
						# Simplified grammar:
						#   [WITHOUT ROWID | STRICT] [, [WITHOUT ROWID | STRICT]]*
						#
						# Relevant SQLite documentation:
						#   - https://www.sqlite.org/syntax/table-options.html
						#   - https://www.sqlite.org/withoutrowid.html
						#   - https://www.sqlite.org/stricttables.html
						#
						# Whether the table is a WITHOUT ROWID table.
						# Whether the table is subject to STRICT type checking.
					#
					if maybe(:STRICT)
						StrictTableOption.new
					elsif maybe_all_of(:WITHOUT, :ROWID)
						WithoutRowidTableOption.new
					else
						expected!(:STRICT, :WITHOUT)
					end
				end

				CreateTableStatement.concrete(
					full_source:      @lexer.sql,
					create_kw:        Token::Keyword(create_kw),
					temp_kw:          Token::Keyword(temp_kw),
					table_kw:         Token::Keyword(table_kw),
					if_not_exists_kw: Token::Keyword(if_not_exists_kw),
					table:            table_name,
					columns_lp:       Token::Punctuation(columns_lp),
					columns:          columns,
					columns_rp:       Token::Punctuation(columns_rp),
					options:          options,
					constraints:      constraints,
				)
			else
				expected!(:AS, :LP)
			end
		end

		def create_view_stmt
			#
				# Relevant `parse.y` grammar rules:
				#   cmd ::= createkw temp VIEW ifnotexists nm dbnm eidlist_opt AS select
				#
				# Syntax diagram:
				#   ◯─▶{ CREATE }┬───────▶──────┬▶{ VIEW }┬▶{ IF }─▶{ NOT }─▶{ EXISTS }─┐
				#                ├▶{ TEMP }─────┤         │                             │
				#                └▶{ TEMPORARY }┘         │                             │
				#   ┌─────────────────────◀───────────────┴──────────────────◀──────────┘
				#   ├─▶{ schema-name }─▶{ . }─┬▶{ view-name }┬─────────────────────────────────┬▶{ AS }─▶[ select-stmt ]─▶◯
				#   └────────▶────────────────┘              └▶{ ( }┬▶{ column-name }┬▶{ ) }─┘
				#                                                   └──────{ , }◀────┘
				#
				# Simplified grammar:
				#   CREATE [TEMP] VIEW [IF NOT EXISTS] [schema .] name [(column [, column]*)] AS select_stmt
				#
				# Relevant SQLite documentation:
				#   - https://www.sqlite.org/lang_createview.html
				#
				# A view is a named select statement that can be queried like a table.
			#
			create_kw        = require      :CREATE
			temp_kw          = maybe_one_of :TEMP, :TEMPORARY
			view_kw          = require      :VIEW
			if_not_exists_kw = maybe_all_of :IF, :NOT, :EXISTS
			view             = table_name
			if (columns_lp = maybe :LP)
				columns    = require_some(trailing_sep: :COMMA) { indexed_column }
				columns_rp = require :RP
			end
			as_kw            = require :AS
			select           = select_stmt

			CreateViewStatement.concrete(
				full_source:      @lexer.sql,
				create_kw:        Token::Keyword(create_kw),
				temp_kw:          Token::Keyword(temp_kw),
				view_kw:          Token::Keyword(view_kw),
				if_not_exists_kw: Token::Keyword(if_not_exists_kw),
				view:             view,
				columns_lp:       Token::Punctuation(columns_lp),
				columns:          columns,
				columns_rp:       Token::Punctuation(columns_rp),
				as_kw:            Token::Keyword(as_kw),
				select:           select,
			)
		end

		def insert_stmt(with = nil)
			#
				# Relevant `parse.y` grammar rules:
				#   cmd ::= with insert_cmd INTO xfullname idlist_opt select upsert
				#   cmd ::= with insert_cmd INTO xfullname idlist_opt DEFAULT VALUES returning
				#   insert_cmd ::= INSERT orconf | REPLACE
				#   orconf ::= . | OR resolvetype
				#   resolvetype ::= raisetype | IGNORE | REPLACE
				#   idlist_opt ::= . | LP idlist RP
				#   upsert ::= . | RETURNING selcollist |
				#              ON CONFLICT LP sortlist RP where_opt DO UPDATE SET setlist where_opt upsert |
				#              ON CONFLICT LP sortlist RP where_opt DO NOTHING upsert |
				#              ON CONFLICT DO NOTHING returning |
				#              ON CONFLICT DO UPDATE SET setlist where_opt returning
				#
				# Syntax diagram:
				#   ◯─▶┬▶[ with-clause ]─┐
				#      ├───────◀─────────┘
				#      ├─▶{ REPLACE }─────────────────────────┐
				#      └─▶{ INSERT }┬────────────────────────┬┴▶{ INTO }─▶[ qualified-table-name ]┐
				#                   └▶{ OR }─▶{ resolution }─┘                                    │
				#   ┌────────────────────────────────◀────────────────────────────────────────────┘
				#   ├─▶{ ( }┬▶{ column-name }┬▶{ ) }┐
				#   │       └──────{ , }◀────┘      │
				#   ├───────────────◀───────────────┘
				#   ├─▶[ select-stmt ]─┬───────────────────┬───────────┬─▶[ returning-clause ]─▶◯
				#   │                  └▶[ upsert-clause ]─┘           │
				#   └─▶{ DEFAULT }─▶{ VALUES }─────────────────────────┘
				#
				# Simplified grammar:
				#   [with_clause] (INSERT [OR resolution] | REPLACE) INTO table [AS alias] [(column [, column]*)]
				#   (select_stmt [upsert_clause]* | DEFAULT VALUES) [returning_clause]
				#
				# Relevant SQLite documentation:
				#   - https://www.sqlite.org/lang_insert.html
				#   - https://www.sqlite.org/lang_upsert.html
				#
				# Adds rows to a table, from a VALUES list, a select, or the column defaults.
			#
			insert_kw = require_one_of(
				[:INSERT, :OR, :ROLLBACK].freeze, [:INSERT, :OR, :ABORT].freeze, [:INSERT, :OR, :FAIL].freeze,
				[:INSERT, :OR, :IGNORE].freeze, [:INSERT, :OR, :REPLACE].freeze, :INSERT, :REPLACE,
			)
			into_kw = require :INTO
			table = qualified_table_name(indexed: false)
			if (columns_lp = maybe :LP)
				columns = require_some(trailing_sep: :COMMA) { column_reference }
				columns_rp = require :RP
			end

			unless (default_values_kw = maybe_all_of :DEFAULT, :VALUES)
				select = select_stmt
				upserts = maybe_some { upsert_clause }
			end
			returning = returning_clause

			InsertStatement.concrete(
				full_source:       @lexer.sql,
				with_clause:       with,
				insert_kw:         Token::Keyword(insert_kw),
				into_kw:           Token::Keyword(into_kw),
				table:             table,
				columns_lp:        Token::Punctuation(columns_lp),
				columns:           columns,
				columns_rp:        Token::Punctuation(columns_rp),
				default_values_kw: Token::Keyword(default_values_kw),
				select:            select,
				upserts:           upserts,
				returning:         returning,
			)
		end

		def update_stmt(with = nil)
			#
				# Relevant `parse.y` grammar rules:
				#   cmd ::= with UPDATE orconf xfullname indexed_opt SET setlist from where_opt_ret orderby_opt limit_opt
				#   where_opt_ret ::= . | WHERE expr | RETURNING selcollist | WHERE expr RETURNING selcollist
				#
				# Syntax diagram:
				#   ◯─▶┬▶[ with-clause ]─┐
				#      ├───────◀─────────┘
				#      └─▶{ UPDATE }┬────────────────────────┬▶[ qualified-table-name ]─▶{ SET }─┐
				#                   └▶{ OR }─▶{ resolution }─┘                                   │
				#   ┌─────────────────────────────────◀──────────────────────────────────────────┘
				#   └┬▶{ column-name }──────────────────┬▶{ = }─▶[ expr ]┬┬───────────────────────────┬┐
				#    ├▶{ ( }┬▶{ column-name }┬▶{ ) }────┘                │└▶{ FROM }─▶[ join-clause ]─┘│
				#    │      └──────{ , }◀────┘                           │                             │
				#    └───────────────────────{ , }◀──────────────────────┘                             │
				#   ┌──────────────────────────────────────◀───────────────────────────────────────────┘
				#   └┬▶{ WHERE }─▶[ expr ]┬┬─▶[ returning-clause ]┬─▶[ ORDER BY … ]─▶[ LIMIT … ]─▶◯
				#    └──────────▶─────────┘└──────────▶───────────┘
				#
				# Simplified grammar:
				#   [with_clause] UPDATE [OR resolution] table [AS alias] [INDEXED BY index | NOT INDEXED]
				#   SET assignment [, assignment]* [FROM join_clause] [WHERE expr] [returning_clause]
				#   [ORDER BY ordering_term [, ordering_term]*] [LIMIT expr [(OFFSET | COMMA) expr]]
				#
				# Relevant SQLite documentation:
				#   - https://www.sqlite.org/lang_update.html
				#
				# Changes columns of existing rows.
			#
			update_kw = require_one_of(
				[:UPDATE, :OR, :ROLLBACK].freeze, [:UPDATE, :OR, :ABORT].freeze, [:UPDATE, :OR, :FAIL].freeze,
				[:UPDATE, :OR, :IGNORE].freeze, [:UPDATE, :OR, :REPLACE].freeze, :UPDATE,
			)
			table = qualified_table_name(indexed: true)
			set_kw = require :SET
			assignments = set_list
			if (from_kw = maybe :FROM)
				source = join_clause
			end
			if (where_kw = maybe :WHERE)
				condition = expression
			end
			returning = returning_clause
			tail = order_and_limit

			UpdateStatement.concrete(
				full_source: @lexer.sql,
				with_clause: with,
				update_kw:   Token::Keyword(update_kw),
				table:       table,
				set_kw:      Token::Keyword(set_kw),
				assignments: assignments,
				from_kw:     Token::Keyword(from_kw),
				source:      source,
				where_kw:    Token::Keyword(where_kw),
				condition:   condition,
				returning:   returning,
				**tail,
			)
		end

		def delete_stmt(with = nil)
			#
				# Relevant `parse.y` grammar rules:
				#   cmd ::= with DELETE FROM xfullname indexed_opt where_opt_ret orderby_opt limit_opt
				#
				# Syntax diagram:
				#   ◯─▶┬▶[ with-clause ]─┐
				#      ├───────◀─────────┘
				#      └─▶{ DELETE }─▶{ FROM }─▶[ qualified-table-name ]┬▶{ WHERE }─▶[ expr ]┬┐
				#                                                       └──────────▶─────────┘│
				#   ┌──────────────────────────────────────◀──────────────────────────────────┘
				#   └┬─▶[ returning-clause ]┬─▶[ ORDER BY … ]─▶[ LIMIT … ]─▶◯
				#    └──────────▶───────────┘
				#
				# Simplified grammar:
				#   [with_clause] DELETE FROM table [AS alias] [INDEXED BY index | NOT INDEXED]
				#   [WHERE expr] [returning_clause] [ORDER BY …] [LIMIT …]
				#
				# Relevant SQLite documentation:
				#   - https://www.sqlite.org/lang_delete.html
				#
				# Removes rows from a table.
			#
			delete_kw = require :DELETE
			from_kw = require :FROM
			table = qualified_table_name(indexed: true)
			if (where_kw = maybe :WHERE)
				condition = expression
			end
			returning = returning_clause
			tail = order_and_limit

			DeleteStatement.concrete(
				full_source: @lexer.sql,
				with_clause: with,
				delete_kw:   Token::Keyword(delete_kw),
				from_kw:     Token::Keyword(from_kw),
				table:       table,
				where_kw:    Token::Keyword(where_kw),
				condition:   condition,
				returning:   returning,
				**tail,
			)
		end

		# A WITH clause can lead a SELECT, INSERT, UPDATE or DELETE - which one is only
		# known once the clause is behind us
		def with_stmt
			with = with_clause

			case current_token
			when :SELECT, :VALUES   then select_stmt(with)
			when :INSERT, :REPLACE  then insert_stmt(with)
			when :UPDATE            then update_stmt(with)
			when :DELETE            then delete_stmt(with)
			else
				expected!(:SELECT, :VALUES, :INSERT, :REPLACE, :UPDATE, :DELETE)
			end
		end

		def select_stmt(with = nil)
			#
				# Relevant `parse.y` grammar rules:
				#   select ::= WITH wqlist selectnowith |
				#              WITH RECURSIVE wqlist selectnowith |
				#              selectnowith
				#   selectnowith ::= oneselect |
				#                    selectnowith multiselect_op oneselect
				#   multiselect_op ::= UNION | UNION ALL | EXCEPT | INTERSECT
				#   orderby_opt ::= . | ORDER BY sortlist
				#   limit_opt ::= . | LIMIT expr | LIMIT expr OFFSET expr | LIMIT expr COMMA expr
				#
				# Syntax diagram:
				#   ◯─▶┬▶[ with-stmt ]─┐
				#      ├───────◀───────┘
				#   ┌──┴──────────────▶[ select-core ]───────────────────┐
				#   └──────────◀────[ compound-operator ]◀───────────────┤
				#    ┌──────────────────◀────────────────────────────────┘
				#    ├─▶{ ORDER }─▶{ BY }┬▶[ ordering-term ]─┬┐
				#    ▼                   └───────{ , }◀──────┘│
				#    ├────────────────◀───────────────────────┘
				#    ├─▶{ LIMIT }─▶[ expr ]─▶┬───────────────────────▶─┐
				#    │                       ├─▶{ OFFSET }─▶[ expr ]─▶─┤
				#    │                       └─▶{ , }─▶[ expr ]──────▶─┤
				#    └───────────────────────────────────────────────▶─┴───────▶◯
				#
				# Simplified grammar:
				#   [with_clause] select_core [compound_operator select_core]*
				#   [ORDER BY ordering_term [, ordering_term]*]
				#   [LIMIT expr [(OFFSET | COMMA) expr]]
				#
				# Relevant SQLite documentation:
				#   - https://www.sqlite.org/lang_select.html
				#
				# The SELECT statement is used to query the database.
			#
			with ||= with_clause if current_token == :WITH
			body = select_core

			while (operator_tk = maybe_one_of [:UNION, :ALL].freeze, :UNION, :INTERSECT, :EXCEPT)
				body = CompoundSelect.concrete(
					full_source: @lexer.sql,
					operator_tk: Token::Keyword(operator_tk),
					left:        body,
					right:       select_core,
				)
			end

			SelectStatement.concrete(
				full_source: @lexer.sql,
				with_clause: with,
				body:        body,
				**order_and_limit,
			)
		end

		def with_clause
			#
				# Relevant `parse.y` grammar rules:
				#   with ::= WITH wqlist | WITH RECURSIVE wqlist
				#   wqlist ::= wqitem | wqlist COMMA wqitem
				#   wqitem ::= withnm eidlist_opt wqas LP select RP
				#   wqas ::= AS | AS MATERIALIZED | AS NOT MATERIALIZED
				#   eidlist_opt ::= . | LP eidlist RP
				#
				# Syntax diagram:
				#   ◯─▶{ WITH }─┬──────────────────┬▶[ common-table-expression ]┬─▶◯
				#               └─▶{ RECURSIVE }─▶─┘└───────────{ , }◀──────────┘
				#
				#   ◯─▶{ table-name }┬────────────────────────────────────┬▶{ AS }┐
				#                    └▶{ ( }┬▶{ column-name }┬▶{ ) }──────┘       │
				#                           └──────{ , }◀────┘                    │
				#   ┌──────────────────────────────◀──────────────────────────────┘
				#   ├────────────────▶────────────────┬▶{ ( }─▶[ select-stmt ]─▶{ ) }─▶◯
				#   ├─▶{ NOT }─┬─▶{ MATERIALIZED }──▶─┘
				#   └────▶─────┘
				#
				# Simplified grammar:
				#   WITH [RECURSIVE] name [(column [, column]*)] AS [[NOT] MATERIALIZED] (select_stmt)
				#                    [, name [(column [, column]*)] AS [[NOT] MATERIALIZED] (select_stmt)]*
				#
				# Relevant SQLite documentation:
				#   - https://www.sqlite.org/lang_with.html
				#
				# Common table expressions act like temporary views that exist only for a single statement.
			#
			with_kw = require :WITH
			recursive_kw = maybe :RECURSIVE

			ctes = require_some(trailing_sep: :COMMA) do
				name_tk = name
				if (columns_lp = maybe :LP)
					columns = require_some(trailing_sep: :COMMA) { indexed_column }
					columns_rp = require :RP
				end
				as_kw = require :AS
				materialized_tk = maybe_one_of :MATERIALIZED, [:NOT, :MATERIALIZED].freeze
				select_lp = require :LP
				select = select_stmt
				select_rp = require :RP

				CommonTableExpression.concrete(
					full_source:     @lexer.sql,
					name_tk:         Token::Identifier(name_tk),
					columns_lp:      Token::Punctuation(columns_lp),
					columns:         columns,
					columns_rp:      Token::Punctuation(columns_rp),
					as_kw:           Token::Keyword(as_kw),
					materialized_tk: Token::Keyword(materialized_tk),
					select_lp:       Token::Punctuation(select_lp),
					select:          select,
					select_rp:       Token::Punctuation(select_rp),
				)
			end

			WithClause.concrete(
				full_source:  @lexer.sql,
				with_kw:      Token::Keyword(with_kw),
				recursive_kw: Token::Keyword(recursive_kw),
				ctes:         ctes,
			)
		end

		# ---------- Clauses ----------

		def expression(min_precedence = 0)
			#
				# Relevant `parse.y` grammar rules:
				#
				# Syntax diagram:
				#   ◯┬─▶[ literal-value ]───────────────────────────────────────────────────────────────────────────────────┬─▶◯
				#    ├─▶{ bind-parameter }────────────────────────────────────────────────────────────────────────────────▶─┤
				#    ├────────────────────────┬──────────────────────┐                                                      │
				#    ├─▶{ schema-name }─▶{ . }┴▶{ table-name }─▶{ . }┴▶{ column-name }────────────────────────────────────▶─┤
				#    ├─▶{ unary-operator }─▶[ expr ]──────────────────────────────────────────────────────────────────────▶─┤
				#    ├─▶[ expr ]─▶{ binary-operator }─▶[ expr ]───────────────────────────────────────────────────────────▶─┤
				#    ├─▶{ function-name }─▶{ ( }─▶[ function-arguments ]─▶{ ) }┬───────────────────┬┬─────────────────────▶─┤
				#    │       ┌──{ , }◀─┐                                       └▶[ filter-clause ]─┘└▶[ over-clause ]─────▶─┤
				#    ├─▶{ ( }┴▶[ expr ]┴▶{ ) }────────────────────────────────────────────────────────────────────────────▶─┤
				#    ├─▶{ CAST }─▶{ ( }─▶[ expr ]─▶{ AS }─▶[ type-name ]─▶{ ) }───────────────────────────────────────────▶─┤
				#    ├─▶[ expr ]─▶{ COLLATE }─▶{ collation-name }─────────────────────────────────────────────────────────▶─┤
				#    ├─▶[ expr ]┬▶{ NOT }┬┬▶{ LIKE }─────▶[ expr ]─┬────▶────────────────┬▶┬──────────────────────────────▶─┤
				#    │          └────▶───┘├▶{ GLOB }───┐           └▶{ ESCAPE }─▶[ expr ]┘ │                                │
				#    │                    ├▶{ REGEXP }─┼─▶[ expr ]────────────▶────────────┘                                │
				#    │                    └▶{ MATCH }──┘                                                                    │
				#    ├─▶[ expr ]┬▶{ ISNULL }───────┬──────────────────────────────────────────────────────────────────────▶─┤
				#    │          ├▶{ NOTNULL }──────┤                                                                        │
				#    │          └▶{ NOT }─▶{ NULL }┘                                                                        │
				#    ├─▶[ expr ]─▶{ IS }┬▶{ NOT }┬┬▶{ DISTINCT }─▶{ FROM }┬▶[ expr ]──────────────────────────────────────▶─┤
				#    │                  └────▶───┘└────────────▶──────────┘                                                 │
				#    ├─▶[ expr ]┬▶{ NOT }┬▶{ BETWEEN }─▶[ expr ]─▶{ AND }─▶[ expr ]───────────────────────────────────────▶─┤
				#    │          └────▶───┘               ┌─────────────────┐                                                │
				#    ├─▶[ expr ]┬▶{ NOT }┬▶{ IN }┬▶{ ( }─┼▶[ select-stmt ]─┼▶{ ) }────────────────────────────────────────▶─┤
				#    │          └────▶───┘       │       └─┬──▶[ expr ]──┬─┘                                                │
				#    │                           │         └────{ , }◀───┘ ┌▶{ table-name }───────────────────────────────▶─┤
				#    │                           ├────────────────────────┐│                           ┌──{ , }──┐          │
				#    │                           └─▶{ schema-name }─▶{ . }┴┴▶{ table-function }─▶{ ( }┬┴▶[ expr ]┴┬▶{ ) }─▶─┤
				#    ├────▶────┬───────────┐                                                          └─────▶─────┘         │
				#    ├─▶{ NOT }┴▶{ EXISTS }┴▶{ ( }─▶[ select-stmt ]─▶{ ) }────────────────────────────────────────────────▶─┤
				#    ├─▶{ CASE }┬▶[ expr ]┬┬▶{ WHEN }─▶[ expr ]─▶{ THEN }─▶[ expr ]┬┬▶{ ELSE }─▶[ expr ]┬▶{ END }─────────▶─┤
				#    │          └─────▶───┘└────────────────◀──────────────────────┘└─────────▶─────────┘                   │
				#    └─▶[ raise-function ]────────────────────────────────────────────────────────────────────────────────▶─┘
				#
				# Simplified grammar:
				#
				# Relevant SQLite documentation:
				#   -
				#
				# [description]
			#

			left = basic_expression

			while (operator = current_token)
				# ~ has a precedence for its operand's sake, but is no binary operator
				operator_precedence = ((operator != :BITNOT) && OPERATOR_PRECEDENCE[operator]) || -1
				break if operator_precedence < min_precedence
				next_precedence = operator_precedence + 1

				negated = maybe :NOT

				if (in_tk = maybe :IN)
					if (value_lp = maybe :LP)
						if (value_rp = maybe :RP)
							right = ParentheticalExpression.concrete(
								full_source: @lexer.sql,
								value_lp: Token::Punctuation(value_lp),
								value: nil,
								value_rp: Token::Punctuation(value_rp),
							)
						elsif subquery_start?
							select = select_stmt
							value_rp = require :RP

							right = SubqueryExpression.concrete(
								full_source: @lexer.sql,
								select_lp: Token::Punctuation(value_lp),
								select: select,
								select_rp: Token::Punctuation(value_rp),
							)
						elsif (e = maybe { expression })
							exprs = require_some(given: e, trailing_sep: :COMMA) do
								expression
							end
							value_rp = require :RP

							right = ParentheticalExpression.concrete(
								full_source: @lexer.sql,
								value_lp: Token::Punctuation(value_lp),
								value: exprs,
								value_rp: Token::Punctuation(value_rp),
							)
						else
							expected!(:RP, "select-stmt", "expr")
						end
					elsif (first_tk = maybe { name })
						# nm dbnm paren_exprlist: a table, or a table-valued function's call
						dot_tk = maybe :DOT
						schema_tk, object_tk = dot_tk ? [first_tk, name] : [nil, first_tk]

						if (arguments_lp = maybe :LP)
							arguments = maybe_some(trailing_sep: :COMMA) { expression }
							arguments_rp = require :RP

							right = FunctionReference.concrete(
								full_source: @lexer.sql,
								schema_tk: Token::Identifier(schema_tk),
								dot_tk: Token::Punctuation(dot_tk),
								function_tk: Token::Identifier(object_tk),
								arguments_lp: Token::Punctuation(arguments_lp),
								arguments: FunctionArguments.concrete(
									full_source: @lexer.sql,
									expressions: arguments
								),
								arguments_rp: Token::Punctuation(arguments_rp),
							)
						else
							right = TableName.concrete(
								full_source: @lexer.sql,
								schema_tk: Token::Identifier(schema_tk),
								dot_tk: Token::Punctuation(dot_tk),
								table_tk: Token::Identifier(object_tk),
							)
						end
					else
						expected!(:LP, :STRING, "idj")
					end

					left = BinaryExpression.concrete(
						full_source: @lexer.sql,
						operator_tk: Token::Punctuation(token_span_from(negated, in_tk)),
						left: left,
						right: right,
					)
				elsif (between_kw = maybe :BETWEEN)
					middle = expression(next_precedence)
					and_kw = require :AND
					right = expression(next_precedence)
					left = TernaryExpression.concrete(
						full_source: @lexer.sql,
						operator_tk: Token::Keyword(token_span_from(negated, between_kw)),
						left: left,
						middle: middle,
						and_kw: Token::Keyword(and_kw),
						right: right,
					)
				elsif (like_kw = maybe :LIKE)
					expression_node = negated ? NotLikeExpression : LikeExpression
					right = expression(next_precedence)
					if (escape_kw = maybe :ESCAPE)
						escape = expression(next_precedence)
					end
					left = expression_node.concrete(
						full_source: @lexer.sql,
						operator_tk: Token::Keyword(token_span_from(negated, like_kw)),
						left: left,
						right: right,
						escape_kw: Token::Keyword(escape_kw),
						escape: escape,
					)
				elsif (match_tk = maybe_one_of :GLOB, :REGEXP, :MATCH)
					operator_tk = token_span_from(negated, match_tk)
					right = expression(next_precedence)

					left_attr = (Node === left) ? { left: left } : { left_tk: left }
					right_attr = (Node === right) ? { right: right } : { right_tk: right }

					left = BinaryExpression.concrete(
						full_source: @lexer.sql,
						operator_tk: Token::Punctuation(operator_tk),
						**left_attr,
						**right_attr,
					)
				end
				next if in_tk || between_kw || like_kw || match_tk

				if negated && (null_kw = maybe :NULL)
					left = UnaryExpression.concrete(
						full_source: @lexer.sql,
						operator_tk: Token::Punctuation(token_span_from(negated, null_kw)),
						operand: left,
					)
					next
				end

				expected!(:IN, :BETWEEN, :LIKE, :GLOB, :REGEXP, :MATCH, :NULL) if negated

				if (operator_tk = maybe :ISNULL)
					operand_attr = (Node === left) ? { operand: left } : { operand_tk: left }

					left = UnaryExpression.concrete(
						full_source: @lexer.sql,
						operator_tk: Token::Punctuation(operator_tk),
						**operand_attr,
					)
				elsif (operator_tk = maybe :NOTNULL)
					operand_attr = (Node === left) ? { operand: left } : { operand_tk: left }

					left = UnaryExpression.concrete(
						full_source: @lexer.sql,
						operator_tk: Token::Punctuation(operator_tk),
						**operand_attr,
					)
				elsif (is_tk = maybe :IS)
					negated_tk = maybe :NOT
					distinct_from_tk = maybe_all_of :DISTINCT, :FROM

					operator_tk = token_span_from(is_tk, negated_tk, distinct_from_tk)
					right = expression(next_precedence)

					left_attr = (Node === left) ? { left: left } : { left_tk: left }
					right_attr = (Node === right) ? { right: right } : { right_tk: right }

					left = BinaryExpression.concrete(
						full_source: @lexer.sql,
						operator_tk: Token::Punctuation(operator_tk),
						**left_attr,
						**right_attr,
					)
				elsif (collate_kw = maybe :COLLATE)
					expression_attr = (Node === left) ? { expression: left } : { expression_tk: left }
					sequence = identifier_or_string

					left = CollationExpression.concrete(
						full_source: @lexer.sql,
						collate_kw: Token::Keyword(collate_kw),
						**expression_attr,
						sequence_tk: Token::Identifier(sequence),
					)
				else
					operator_tk = require operator
					right = expression(next_precedence)

					left_attr = (Node === left) ? { left: left } : { left_tk: left }
					right_attr = (Node === right) ? { right: right } : { right_tk: right }

					left = BinaryExpression.concrete(
						full_source: @lexer.sql,
						operator_tk: Token::Punctuation(operator_tk),
						**left_attr,
						**right_attr,
					)
				end
			end

			left
		end

		def column_def
			#
				# Used by:
				#   - alter_table_stmt
				#   - create_table_stmt
				#
				# Relevant `parse.y` grammar rules:
				#   columnlist ::= columnname carglist
				#   columnname ::= nm typetoken
				#   carglist ::= . | carglist ccons
				#
				# Syntax diagram:
				#   ◯─▶{ column-name }─┬─▶[ type-name ]─┬▶┬─▶───────────────────▶──┬─▶◯
				#                      └────────▶───────┘ └─[ column-constraint ]◀─┘
				#
				# Simplified grammar:
				#   name [type] [constraint [constraint]*]
				#
				# Relevant SQLite documentation:
				#   - https://www.sqlite.org/lang_createtable.html#column_definitions
				#   - https://www.sqlite.org/syntax/column-def.html
				#
				# Each column definition consists of the name of the column,
				# optionally followed by the declared type of the column,
				# then one or more optional column constraints.
			#
			column_name = name
			column_type = maybe { type_name }
			constraints = maybe_some(trailing_sep: nil) do
				#
					# Relevant `parse.y` grammar rules:
					#   ccons ::= CONSTRAINT nm |
					#             DEFAULT term |
					#             DEFAULT LP expr RP |
					#             DEFAULT PLUS term |
					#             DEFAULT MINUS term |
					#             DEFAULT id |
					#             NULL onconf |
					#             NOT NULL onconf |
					#             PRIMARY KEY sortorder onconf autoinc |
					#             UNIQUE onconf |
					#             CHECK LP expr RP |
					#             REFERENCES nm eidlist_opt refargs |
					#             defer_subclause |
					#             COLLATE ids |
					#             GENERATED ALWAYS AS generated |
					#             AS generated
					#   term ::= NULL | FLOAT | BLOB | STRING | INTEGER | CTIME_KW | QNUMBER
					#   id ::= ID | INDEXED
					#   ids ::= ID | STRING
					#   nm ::= idj | STRING
					#   eidlist_opt ::= . | LP eidlist RP
					#   eidlist ::= eidlist COMMA nm collate sortorder |
					# 	            nm collate sortorder
					#   onconf ::= . | ON CONFLICT resolvetype
					#   sortorder ::= . | ASC | DESC
					#   refargs ::= . | refargs refarg
					#   refarg ::= MATCH nm |
					# 	           ON INSERT refact |
					# 	           ON DELETE refact |
					# 		         ON UPDATE refact
					#   generated ::= LP expr RP |
					#                 LP expr RP ID
					#   autoinc ::= . | AUTOINCR.
					#
					# Syntax diagram:
					#   ◯─▶┬▶{ CONSTRAINT }─▶{ name }─┬───────────────────────────────▶───────────────────────┐
					#      ├─────────────◀────────────┘                                                       │
					#      ├─▶{ PRIMARY }─▶{ KEY }──┬─────▶──────┬─▶[ conflict-clause ]┬──────────▶───────────┼─▶◯
					#      │                        ├─▶{ ASC }──▶┤                     └─▶{ AUTOINCREMENT }─▶─┤
					#      ├─────▶───┐              └─▶{ DESC }─▶┘                                            │
					#      ├─▶{ NOT }┴▶{ NULL }─▶[ conflict-clause ]────────────────────────────────────────▶─┤
					#      ├─▶{ UNIQUE }─▶[ conflict-clause ]───────────────────────────────────────────────▶─┤
					#      ├─▶{ CHECK }─▶{ ( }─▶[ expr ]─▶{ ) }─────────────────────────────────────────────▶─┤
					#      ├─▶{ DEFAULT }─▶┬▶{ ( }─▶[ expr ]─▶{ ) }──┬──────────────────────────────────────▶─┤
					#      │               ├─▶[ literal-value ]────▶─┤                                        │
					#      │               └─▶[ signed-number ]────▶─┘                                        │
					#      ├─▶{ COLLATE }─▶{ collation-name }───────────────────────────────────────────────▶─┤
					#      ├─▶[ foreign-key-clause ]────────────────────────────────────────────────────────▶─┤
					#      ├─▶{ GENERATED }─▶{ ALWAYS }┬▶{ AS }─▶{ ( }─▶[ expr ]─▶{ ) }┬────────────────────▶─┤
					#      └──────────────▶────────────┘                               ├─▶{ STORED }────────▶─┤
					#                                                                  └─▶{ VIRTUAL }───────▶─┘
					#
					# Simplified grammar:
					#   [CONSTRAINT name] (
					#     [PRIMARY KEY [ASC|DESC] [conflict_clause] [AUTOINCREMENT]]
					#     [NOT NULL [conflict_clause]]
					#     [NULL [conflict_clause]]
					#     [UNIQUE [conflict_clause]]
					#     [CHECK LP expression RP [conflict_clause]]
					#     [COLLATE collation-name]
					#     [foreign-key-clause]
					#     [GENERATED ALWAYS AS (expr) STORED | VIRTUAL]
					#   )
					#
					# Relevant SQLite documentation:
					#   - https://www.sqlite.org/lang_createtable.html#column_definitions
					#   - https://www.sqlite.org/syntax/column-constraint.html
					#
					# Included in the definition of "column constraints" for the purposes of the previous statement
					# are the COLLATE and DEFAULT clauses, even though these are not really constraints in the sense
					# that they do not restrict the data that the table may contain. The other constraints -
					# NOT NULL, CHECK, UNIQUE, PRIMARY KEY and FOREIGN KEY constraints - impose restrictions on the table data.
				#
				if (constraint_kw = maybe :CONSTRAINT)
					constraint_name = name
				end

				if    (primary_key_kw = maybe_all_of :PRIMARY, :KEY)
					direction_tk        = maybe_one_of :ASC, :DESC
					on_conflict         = maybe      { conflict_clause }
					autoincrement_kw    = maybe        :AUTOINCREMENT

					PrimaryKeyColumnConstraint.concrete(
						full_source:      @lexer.sql,
						constraint_kw:    Token::Keyword(constraint_kw),
						name_tk:          Token::Identifier(constraint_name),
						primary_key_kw:   Token::Keyword(primary_key_kw),
						direction_tk:     Token::Keyword(direction_tk),
						conflict_clause:  on_conflict,
						autoincrement_kw: Token::Keyword(autoincrement_kw),
					)
				elsif (not_null_kw    = maybe_all_of :NOT, :NULL)
					on_conflict         = maybe      { conflict_clause }

					NotNullColumnConstraint.concrete(
						full_source:     @lexer.sql,
						constraint_kw:   Token::Keyword(constraint_kw),
						name_tk:         Token::Identifier(constraint_name),
						not_null_kw:     Token::Keyword(not_null_kw),
						conflict_clause: on_conflict,
					)
				elsif current_token == :DEFERRABLE || (current_token == :NOT && peek == :DEFERRABLE)
					DeferrableColumnConstraint.concrete(
						full_source:     @lexer.sql,
						constraint_kw:   Token::Keyword(constraint_kw),
						name_tk:         Token::Identifier(constraint_name),
						deferrable_span: Token::Keyword(defer_subclause),
					)
				elsif (null_kw        = maybe        :NULL)
					on_conflict         = maybe      { conflict_clause }

					NullColumnConstraint.concrete(
						full_source:     @lexer.sql,
						constraint_kw:   Token::Keyword(constraint_kw),
						name_tk:         Token::Identifier(constraint_name),
						null_kw:         Token::Keyword(null_kw),
						conflict_clause: on_conflict,
					)
				elsif (unique_kw      = maybe        :UNIQUE)
					on_conflict         = maybe      { conflict_clause }

					UniqueColumnConstraint.concrete(
						full_source:     @lexer.sql,
						constraint_kw:   Token::Keyword(constraint_kw),
						name_tk:         Token::Identifier(constraint_name),
						unique_kw:       Token::Keyword(unique_kw),
						conflict_clause: on_conflict,
					)
				elsif (check_kw       = maybe        :CHECK)
					check_lp            = require      :LP
					check               =              expression
					check_rp            = require      :RP

					CheckColumnConstraint.concrete(
						full_source:   @lexer.sql,
						constraint_kw: Token::Keyword(constraint_kw),
						name_tk:       Token::Identifier(constraint_name),
						check_kw:      Token::Keyword(check_kw),
						check_lp:      Token::Punctuation(check_lp),
						expression:    check,
						check_rp:      Token::Punctuation(check_rp),
					)
				elsif (default_kw     = maybe        :DEFAULT)
					if (default_lp      = maybe        :LP)
						value         = expression
						default_rp    = require :RP

						value_attr = (Node === value) ? { value: value } : { value_tk: value }

						DefaultColumnConstraint.concrete(
							full_source:   @lexer.sql,
							constraint_kw: Token::Keyword(constraint_kw),
							name_tk:       Token::Identifier(constraint_name),
							default_kw:    Token::Keyword(default_kw),
							default_lp:    Token::Punctuation(default_lp),
							default_rp:    Token::Punctuation(default_rp),
							**value_attr,
						)
					elsif (number       = maybe      { signed_number })
						DefaultColumnConstraint.concrete(
							full_source:   @lexer.sql,
							constraint_kw: Token::Keyword(constraint_kw),
							name_tk:       Token::Identifier(constraint_name),
							default_kw:    Token::Keyword(default_kw),
							value_tk:      Token::Numeric(number),
						)
					elsif (value        = maybe      { literal_value })
						DefaultColumnConstraint.concrete(
							full_source:   @lexer.sql,
							constraint_kw: Token::Keyword(constraint_kw),
							name_tk:       Token::Identifier(constraint_name),
							default_kw:    Token::Keyword(default_kw),
							value_tk:      value,
						)
					# A sign on something that is not a number, like `DEFAULT -'hello'`
					elsif (current_token in :PLUS | :MINUS) && (value = maybe { basic_expression })
						DefaultColumnConstraint.concrete(
							full_source:   @lexer.sql,
							constraint_kw: Token::Keyword(constraint_kw),
							name_tk:       Token::Identifier(constraint_name),
							default_kw:    Token::Keyword(default_kw),
							value:         value,
						)
					elsif (id           = maybe      { identifier })
						DefaultColumnConstraint.concrete(
							full_source:   @lexer.sql,
							constraint_kw: Token::Keyword(constraint_kw),
							name_tk:       Token::Identifier(constraint_name),
							default_kw:    Token::Keyword(default_kw),
							value_tk:      Token::Identifier(id),
						)
					else
						expected! :LP, "literal-value", "signed-number"
					end
				elsif (collate_kw     = maybe        :COLLATE)
					collation = name

					CollateColumnConstraint.concrete(
						full_source:   @lexer.sql,
						constraint_kw: Token::Keyword(constraint_kw),
						name_tk:       Token::Identifier(constraint_name),
						collate_kw:    Token::Keyword(collate_kw),
						collation_tk:  Token::Identifier(collation),
					)
				elsif :REFERENCES == current_token
					clause = foreign_key_clause

					ForeignKeyColumnConstraint.concrete(
						full_source:        @lexer.sql,
						constraint_kw:      Token::Keyword(constraint_kw),
						name_tk:            Token::Identifier(constraint_name),
						foreign_key_clause: clause,
					)
				elsif (as_kw = maybe_all_of(:GENERATED, :ALWAYS, :AS) || maybe(:AS))
					as_lp      = require :LP
					default    = expression
					as_rp      = require :RP
					type_tk    = maybe_one_of :STORED, :VIRTUAL

					GeneratedAsColumnConstraint.concrete(
						full_source:        @lexer.sql,
						constraint_kw:      Token::Keyword(constraint_kw),
						name_tk:            Token::Identifier(constraint_name),
						as_kw:              Token::Keyword(as_kw),
						as_lp:              Token::Punctuation(as_lp),
						expression:         default,
						as_rp:              Token::Punctuation(as_rp),
						type_tk:            Token::Keyword(type_tk),
					)
				else
					if constraint_name
						NoOpColumnConstraint.concrete(
							full_source:   @lexer.sql,
							constraint_kw: Token::Keyword(constraint_kw),
							name_tk:       Token::Identifier(constraint_name),
						)
					else
						expected! :PRIMARY, :NOT, :NULL, :UNIQUE, :CHECK, :DEFAULT, :COLLATE, :REFERENCES, :GENERATED
					end
				end
			end

			ColumnDefinition.concrete(
				full_source: @lexer.sql,
				name_tk:     Token::Identifier(column_name),
				type:        column_type,
				constraints: constraints,
			)
		end

		def select_core
			#
				# Relevant `parse.y` grammar rules:
				#   oneselect ::= SELECT distinct selcollist from where_opt groupby_opt having_opt orderby_opt limit_opt |
				#                 SELECT distinct selcollist from where_opt groupby_opt having_opt window_clause orderby_opt limit_opt |
				#                 values
				#   distinct ::= DISTINCT | ALL | .
				#   from ::= . | FROM seltablist
				#   where_opt ::= . | WHERE expr
				#   groupby_opt ::= . | GROUP BY nexprlist
				#   having_opt ::= . | HAVING expr
				#   window_clause ::= WINDOW windowdefn_list
				#   windowdefn_list ::= windowdefn | windowdefn_list COMMA windowdefn
				#   windowdefn ::= nm AS LP window RP
				#   values ::= VALUES LP nexprlist RP | values COMMA LP nexprlist RP
				#
				# Syntax diagram:
				#   ◯─┬───▶{ SELECT }─┬───────▶──────┬─┬▶[ result-column ]─┐
				#     │               ├▶{ DISTINCT }─┤ └─────{ , }◀────────┤
				#     │               └▶{ ALL }─────▶┘                     │
				#     │  ┌──────────────────────────◀──────────────────────┘
				#     │  ├─▶{ FROM }┬─┬▶[ table-or-subquery ]─┬─┬─▶───┐
				#     │  │          │ └────────{ , }◀─────────┘ ▲     ▼
				#     │  │          └──▶[ join-clause ]─────────┘     │
				#     │  ├──────────────────────◀─────────────────────┘
				#     │  ├─▶{ WHERE }─▶[ expr ]─┐
				#     │  ├──────────◀───────────┘
				#     │  ├────────────▶─────────────────┐
				#     │  ├─▶{ GROUP }─▶{ BY }┬▶[ expr ]┬┴▶┬─▶{ HAVING }─▶[ expr ]─┬─┐
				#     │  ▼                   └──{ , }◀─┘  └────────▶──────────────┘ ▼
				#     │  ├─────────────────────────────◀────────────────────────────┘
				#     │  ├─▶{ WINDOW }┬▶{ window-name }─▶{ AS }─▶[ window-defn ]─┐
				#     │  │            └───────────────────{ , }◀─────────────────┤
				#     │  └──────────────────────▶─────────────────────────────▶──┴─┬───▶◯
				#     │                    ┌──{ , }◀─┐                             │
				#     └─▶{ VALUES }┬▶{ ( }─┴▶[ expr ]┴─▶{ ) }─┬─────────────────▶──┘
				#                  └──────────{ , }◀──────────┘
				#
				# Simplified grammar:
				#   SELECT [DISTINCT | ALL] result_column [, result_column]*
				#   [FROM join_clause] [WHERE expr] [GROUP BY expr [, expr]* [HAVING expr]]
				#   [WINDOW name AS window_defn [, name AS window_defn]*]
				#   | VALUES (expr [, expr]*) [, (expr [, expr]*)]*
				#
				# Relevant SQLite documentation:
				#   - https://www.sqlite.org/lang_select.html#select_core
				#
				# A single SELECT or VALUES, which compound operators then glue together.
			#
			if (select_kw = maybe :SELECT)
				type_tk = maybe_one_of :DISTINCT, :ALL
				columns = require_some(trailing_sep: :COMMA) { result_column }
				if (from_kw = maybe :FROM)
					source = join_clause
				end
				if (where_kw = maybe :WHERE)
					condition = expression
				end
				if (group_by_kw = maybe_all_of :GROUP, :BY)
					groupings = require_some(trailing_sep: :COMMA) { expression }
				end
				# SQLite accepts HAVING without GROUP BY, treating the whole result as one group
				if (having_kw = maybe :HAVING)
					having = expression
				end
				if (window_kw = maybe :WINDOW)
					windows = require_some(trailing_sep: :COMMA) { window_definition }
				end

				SelectCore.concrete(
					full_source: @lexer.sql,
					select_kw:   Token::Keyword(select_kw),
					type_tk:     Token::Keyword(type_tk),
					columns:     columns,
					from_kw:     Token::Keyword(from_kw),
					source:      source,
					where_kw:    Token::Keyword(where_kw),
					condition:   condition,
					group_by_kw: Token::Keyword(group_by_kw),
					groupings:   groupings,
					having_kw:   Token::Keyword(having_kw),
					having:      having,
					window_kw:   Token::Keyword(window_kw),
					windows:     windows,
				)
			elsif (values_kw = maybe :VALUES)
				rows = require_some(trailing_sep: :COMMA) do
					row_lp = require :LP
					values = require_some(trailing_sep: :COMMA) { expression }
					row_rp = require :RP

					ValuesRow.concrete(
						full_source: @lexer.sql,
						row_lp:      Token::Punctuation(row_lp),
						values:      values,
						row_rp:      Token::Punctuation(row_rp),
					)
				end

				ValuesClause.concrete(
					full_source: @lexer.sql,
					values_kw:   Token::Keyword(values_kw),
					rows:        rows,
				)
			else
				expected!(:SELECT, :VALUES)
			end
		end

		def window_definition
			#
				# Relevant `parse.y` grammar rules:
				#   windowdefn ::= nm AS LP window RP
				#
				# Syntax diagram:
				#   ◯─▶{ window-name }─▶{ AS }─▶[ window-defn ]─▶◯
				#
				# Relevant SQLite documentation:
				#   - https://www.sqlite.org/windowfunctions.html#window_chaining
				#
				# A named window from the WINDOW clause, which OVER clauses may refer to or extend.
			#
			name_tk = name
			as_kw = require :AS
			window_lp = require :LP
			window = window_body
			window_rp = require :RP

			WindowDefinition.concrete(
				full_source: @lexer.sql,
				name_tk:     Token::Identifier(name_tk),
				as_kw:       Token::Keyword(as_kw),
				window_lp:   Token::Punctuation(window_lp),
				**window,
				window_rp:   Token::Punctuation(window_rp),
			)
		end

		# The inside of a window-defn parenthesis, shared by OVER (…) and WINDOW name AS (…)
		def window_body
			base_window_name_tk = maybe { name(except: [:PARTITION, :ORDER, :RANGE, :ROWS, :GROUPS]) }
			if (partition_by_kw = maybe_all_of(:PARTITION, :BY))
				partitions = require_some(trailing_sep: :COMMA) { expression }
			end
			if (order_by_kw = maybe_all_of(:ORDER, :BY))
				orderings = require_some(trailing_sep: :COMMA) { ordering_term }
			end
			if current_token in :RANGE | :ROWS | :GROUPS
				frame = frame_spec
			end

			{
				base_window_name_tk: Token::Identifier(base_window_name_tk),
				partition_by_kw:     Token::Keyword(partition_by_kw),
				partitions:          partitions,
				order_by_kw:         Token::Keyword(order_by_kw),
				orderings:           orderings,
				frame:               frame,
			}
		end

		def filter_clause
			# Relevant `parse.y` grammar rules:
			#
			# Syntax diagram:
			#   ◯─▶{ FILTER }─▶{ ( }─▶{ WHERE }─▶[ expr ]─▶{ ) }─▶◯
			#
			# Simplified grammar:
			#
			# Relevant SQLite documentation:
			#   -
			#
			# [description]
			#
			require_all_of :FILTER, :LP, :WHERE
			condition = expression
			require :RP

			condition
		end

		def over_clause
			#
				# Relevant `parse.y` grammar rules:
				#   over_clause ::= OVER LP window RP |
				#                   OVER nm
				#   window ::= nm frame_opt |
				#              frame_opt |
				#              nm ORDER BY sortlist frame_opt |
				#              ORDER BY sortlist frame_opt |
				#              nm PARTITION BY nexprlist orderby_opt frame_opt |
				#              PARTITION BY nexprlist orderby_opt frame_opt
				#   frame_opt ::= range_or_rows BETWEEN frame_bound_s AND frame_bound_e frame_exclude_opt |
				#                 range_or_rows frame_bound_s frame_exclude_opt  |
				#                 .
				#   range_or_rows ::= RANGE | ROWS | GROUPS
				#   frame_bound_s ::= frame_bound |
				#                     UNBOUNDED PRECEDING
				#   frame_bound_e ::= frame_bound |
				#                     UNBOUNDED FOLLOWING
				#   frame_exclude_opt ::= . |
				#                         EXCLUDE frame_exclude
				#   frame_bound ::= CURRENT ROW |
				#                   expr PRECEDING | FOLLOWING
				#   frame_exclude ::= NO OTHERS | CURRENT ROW | GROUP | TIES
				#   filter_clause ::= FILTER LP WHERE expr RP
				#
				# Syntax diagram:
				#   ◯─▶{ OVER }┬─▶{ window-name }───────────────────────────────┬─▶◯
				#              └─▶{ ( }┬───────────▶────────────┐               │
				#                      └─▶{ base-window-name }─▶┤               │
				#                   ┌───────────────◀───────────┘               │
				#                   ├─▶{ PARTITION }─▶{ BY }┬[ expr ]┐          │
				#                   │                       └─{ , }◀─┤          │
				#                   ├────────────◀───────────────────┘          │
				#                   ├─▶{ ORDER }─▶{ BY }┬[ ordering-term ]┐     │
				#                   │                   └──────{ , }◀─────┤     │
				#                   ├─────────────◀───────────────────────┘     │
				#                   ├─▶[ frame-spec ]┬─▶──────────────────{ ) }─┘
				#                   └─────────▶──────┘
				#
				# Simplified grammar:
				#
				# Relevant SQLite documentation:
				#   -
				#
				# [description]
			#
			over_kw = require :OVER
			if (window_lp = maybe :LP)
				window = window_body
				window_rp = require :RP

				OverClause.concrete(
					full_source: @lexer.sql,
					over_kw: Token::Keyword(over_kw),
					window_lp: Token::Punctuation(window_lp),
					**window,
					window_rp: Token::Punctuation(window_rp),
				)
			else
				window_name_tk = name

				OverClause.concrete(
					full_source: @lexer.sql,
					over_kw: Token::Keyword(over_kw),
					window_name_tk: Token::Identifier(window_name_tk),
				)
			end
		end

		def foreign_key_clause
			#
				# Relevant `parse.y` grammar rules:
				#   ccons ::= REFERENCES nm eidlist_opt refargs.
				#   eidlist_opt ::= . | LP eidlist RP
				#   eidlist ::= eidlist COMMA nm collate sortorder | nm collate sortorder
				#   refargs ::= . | refargs refarg
				#   refarg ::= MATCH nm |
				#              ON INSERT refact |
				#              ON DELETE refact |
				#              ON UPDATE refact
				#   refact ::= SET NULL |
				#              SET DEFAULT |
				#              CASCADE |
				#              RESTRICT |
				#              NO ACTION
				#   defer_subclause_opt ::= . | defer_subclause
				#   defer_subclause ::= NOT DEFERRABLE init_deferred_pred_opt |
				#                       DEFERRABLE init_deferred_pred_opt
				#   init_deferred_pred_opt ::= . | INITIALLY DEFERRED | INITIALLY IMMEDIATE
				#
				# Syntax diagram:
				#                                                ┌─────{ , }◀─────┐
				#   ◯─▶{ REFERENCES }─▶{ foreign-table }─┬─▶{ ( }┴▶{ column-name }┴▶{ ) }──┐
				#    ┌───────────────────────────────────┴──────────◀──┬───────────────────┘
				#    ├─▶{ ON }┬─▶{ DELETE }─┬┬─▶{ SET }─▶{ NULL }────▶─┤
				#    │        └─▶{ UPDATE }─┘├─▶{ SET }─▶{ DEFAULT }─▶─┤
				#    │                       ├─▶{ CASCADE }──────────▶─┤
				#    │                       ├─▶{ RESTRICT }─────────▶─┤
				#    │                       └─▶{ NO }─▶{ ACTION }───▶─┤
				#    ├─▶{ MATCH }─▶{ name }────────────────────────────┘
				#    ├────────────┬─▶{ DEFERRABLE }┬───────────────────────────────▶─┐
				#    ├─{ NOT }──▶─┘                ├─▶{ INITIALLY }─▶{ DEFERRED }──▶─┤
				#    │                             └─▶{ INITIALLY }─▶{ IMMEDIATE }─▶─┤
				#    └───────────────────────────────────────────────────────────────┴──────▶◯
				#
				# Simplified grammar:
				#
				# Relevant SQLite documentation:
				#   - https://www.sqlite.org/syntax/foreign-key-clause.html
				#   - https://www.sqlite.org/foreignkeys.html
				#
				# [description]
			#
			references_kw = require :REFERENCES
			foreign_table = name(except: [:ON, :MATCH, :DEFERRABLE, :NOT])
			columns = nil
			if (columns_lp = maybe :LP)
				columns = require_some(trailing_sep: :COMMA) { indexed_column }
				columns_rp = require :RP
			end
			# refargs ::= refargs refarg, so ON and MATCH clauses come in any order
			refargs = maybe_some(trailing_sep: nil) do
				next match_clause if current_token == :MATCH

				on_kw      = require        :ON
				trigger_kw = require_one_of :DELETE, :UPDATE, :INSERT
				action_kw  = require_one_of :CASCADE, :RESTRICT, [:SET, :NULL].freeze, [:SET, :DEFAULT].freeze, [:NO, :ACTION].freeze
				ForeignKeyAction.concrete(
					full_source: @lexer.sql,
					on_kw:       Token::Keyword(on_kw),
					trigger_kw:  Token::Keyword(trigger_kw),
					action_kw:   Token::Keyword(action_kw),
				)
			end
			foreign_key_actions = refargs.grep(ForeignKeyAction)
			match_clauses = refargs.grep(MatchClause)
			deferrable_span = defer_subclause

			ForeignKeyClause.concrete(
				full_source: @lexer.sql,
				references_kw: Token::Keyword(references_kw),
				table_tk: Token::Identifier(foreign_table),
				columns_lp: Token::Punctuation(columns_lp),
				columns: columns,
				columns_rp: Token::Punctuation(columns_rp),
				actions: foreign_key_actions,
				match_clauses: match_clauses,
				deferrable_span: Token::Keyword(deferrable_span),
			)
		end

		def match_clause
			match_kw = require :MATCH
			type_tk  = name(except: [:ON, :MATCH, :DEFERRABLE, :NOT])
			MatchClause.concrete(
				full_source: @lexer.sql,
				match_kw:    Token::Keyword(match_kw),
				type_tk:     Token::Identifier(type_tk),
			)
		end

		# defer_subclause ::= NOT DEFERRABLE init_deferred_pred_opt | DEFERRABLE init_deferred_pred_opt
		def defer_subclause
			maybe_one_of(
				[:NOT, :DEFERRABLE, :INITIALLY, :IMMEDIATE].freeze,
				[:NOT, :DEFERRABLE, :INITIALLY, :DEFERRED].freeze,
				[:DEFERRABLE, :INITIALLY, :IMMEDIATE].freeze,
				[:DEFERRABLE, :INITIALLY, :DEFERRED].freeze,
				[:NOT, :DEFERRABLE].freeze,
				:DEFERRABLE,
			)
		end

		def conflict_clause
			#
				# Used by:
				#   - column_def
				#
				# Relevant `parse.y` grammar rules:
				#   onconf ::= . | ON CONFLICT resolvetype.
				#   orconf ::= . | OR resolvetype.
				#   resolvetype ::= raisetype |
				#                   IGNORE |
				#                   REPLACE
				#   raisetype ::= ROLLBACK |
				#                 ABORT |
				#                 FAIL
				#
				# Syntax diagram:
				#   ◯─▶┬────────────────────────────────────────┬─────▶◯
				#      └─▶{ ON }─▶{ CONFLICT }┬─▶{ ROLLBACK }─▶─┤
				#                             ├─▶{ ABORT }────▶─┤
				#                             ├─▶{ FAIL }─────▶─┤
				#                             ├─▶{ IGNORE }───▶─┤
				#                             └─▶{ REPLACE }──▶─┘
				#
				# Simplified grammar:
				#   [ON CONFLICT [ROLLBACK | ABORT | FAIL | IGNORE | REPLACE]]
				#
				# Relevant SQLite documentation:
				#   - https://www.sqlite.org/lang_conflict.html
				#
				# The ON CONFLICT clause is a non-standard extension specific to SQLite
				# that can appear in many other SQL commands. There are five conflict resolution
				# algorithm choices: ROLLBACK, ABORT, FAIL, IGNORE, and REPLACE.
			#
			return unless (on_conflict_kw  = maybe_all_of :ON, :CONFLICT)

			if (resolution_kw = maybe_one_of :ROLLBACK, :ABORT, :FAIL, :IGNORE, :REPLACE)
				ConflictClause.concrete(
					full_source:    @lexer.sql,
					on_conflict_kw: Token::Keyword(on_conflict_kw),
					resolution_kw:  Token::Keyword(resolution_kw),
				)
			else
				expected! :ROLLBACK, :ABORT, :FAIL, :IGNORE, :REPLACE
			end
		end

		def basic_expression
			if (operator_tk = maybe :BITNOT)
				operand = expression(OPERATOR_PRECEDENCE[:BITNOT])
				operand_attr = (Node === operand) ? { operand: operand } : { operand_tk: operand }

				UnaryExpression.concrete(
					full_source: @lexer.sql,
					operator_tk: Token::Punctuation(operator_tk),
					**operand_attr,
				)
			elsif (operator_tk = maybe :PLUS)
				operand = expression(OPERATOR_PRECEDENCE[:UPLUS])
				operand_attr = (Node === operand) ? { operand: operand } : { operand_tk: operand }

				UnaryExpression.concrete(
					full_source: @lexer.sql,
					operator_tk: Token::Punctuation(operator_tk),
					**operand_attr,
				)
			elsif (operator_tk = maybe :MINUS)
				operand = expression(OPERATOR_PRECEDENCE[:UMINUS])
				operand_attr = (Node === operand) ? { operand: operand } : { operand_tk: operand }

				UnaryExpression.concrete(
					full_source: @lexer.sql,
					operator_tk: Token::Punctuation(operator_tk),
					**operand_attr,
				)
			elsif (operator_tk = maybe :NOT)
				operand = expression(OPERATOR_PRECEDENCE[:NOT])
				operand_attr = (Node === operand) ? { operand: operand } : { operand_tk: operand }

				UnaryExpression.concrete(
					full_source: @lexer.sql,
					operator_tk: Token::Punctuation(operator_tk),
					**operand_attr,
				)
			elsif (value_lp = maybe :LP)
				if subquery_start?
					select = select_stmt
					select_rp = require :RP

					return SubqueryExpression.concrete(
						full_source: @lexer.sql,
						select_lp: Token::Punctuation(value_lp),
						select: select,
						select_rp: Token::Punctuation(select_rp),
					)
				end

				value = expression(0)
				# A row value like `(a, b) = (1, 2)`
				if current_token == :COMMA
					value = require_some(given: value, trailing_sep: :COMMA) { expression(0) }
				end
				value_rp = require :RP

				value_attr = (Node === value || Array === value) ? { value: value } : { value_tk: value }

				ParentheticalExpression.concrete(
					full_source: @lexer.sql,
					value_lp: Token::Punctuation(value_lp),
					**value_attr,
					value_rp: Token::Punctuation(value_rp),
				)
			elsif (cast_kw = maybe :CAST)
				expression_lp = require :LP
				e = expression
				as_kw = require :AS
				t = type_name unless current_token == :RP # typetoken ::= .
				expression_rp = require :RP

				CastExpression.concrete(
					full_source: @lexer.sql,
					cast_kw: Token::Keyword(cast_kw),
					expression_lp: Token::Punctuation(expression_lp),
					expression: e,
					as_kw: Token::Keyword(as_kw),
					as: t,
					expression_rp: Token::Punctuation(expression_rp),
				)
			elsif (case_kw = maybe :CASE)
				if current_token == :WHEN
					conditions = require_some(leading_sep: :WHEN) do |when_kw|
						case_predicate = expression
						then_kw = require :THEN
						case_consequence = expression

						predicate_attr = (Node === case_predicate) ? { predicate: case_predicate } : { predicate_tk: case_predicate }
						consequence_attr = (Node === case_consequence) ? { consequence: case_consequence } : { consequence_tk: case_consequence }

						CaseCondition.concrete(
							full_source: @lexer.sql,
							when_kw: Token::Keyword(when_kw),
							**predicate_attr,
							then_kw: Token::Keyword(then_kw),
							**consequence_attr,
						)
					end
					if (else_kw = maybe :ELSE)
						else_clause = expression
					end
					end_kw = require :END

					else_clause_attr = (Node === else_clause) ? { else_clause: else_clause } : { else_clause_tk: else_clause }

					CaseExpression.concrete(
						full_source: @lexer.sql,
						case_kw: Token::Keyword(case_kw),
						conditions: conditions,
						else_kw: Token::Keyword(else_kw),
						**else_clause_attr,
						end_kw: Token::Keyword(end_kw),
					)
				else
					predicate = expression
					conditions = require_some(leading_sep: :WHEN) do |when_kw|
						case_predicate = expression
						then_kw = require :THEN
						case_consequence = expression

						CaseCondition.concrete(
							full_source: @lexer.sql,
							when_kw: Token::Keyword(when_kw),
							predicate: case_predicate,
							then_kw: Token::Keyword(then_kw),
							consequence: case_consequence,
						)
					end
					if (else_kw = maybe :ELSE)
						else_clause = expression
					end
					end_kw = require :END

					CaseExpression.concrete(
						full_source: @lexer.sql,
						case_kw: Token::Keyword(case_kw),
						predicate: predicate,
						conditions: conditions,
						else_kw: Token::Keyword(else_kw),
						else_clause: else_clause,
						end_kw: Token::Keyword(end_kw),
					)
				end
			elsif (exists_kw = maybe :EXISTS)
				select_lp = require :LP
				select = select_stmt
				select_rp = require :RP

				ExistsExpression.concrete(
					full_source: @lexer.sql,
					exists_kw: Token::Keyword(exists_kw),
					select_lp: Token::Punctuation(select_lp),
					select: select,
					select_rp: Token::Punctuation(select_rp),
				)
			# A string followed by a dot is a quoted table name, as in `'t'.col`
			# A string or TRUE/FALSE before a dot names a table: `'t'.x`, `false.false`. SQLite has no TRUE
			# or FALSE keyword at all, while CURRENT_* is always a literal in an expression
			elsif !((current_token in :STRING | :TRUE | :FALSE) && peek == :DOT) &&
					(literal_tk = maybe { literal_value })
				LiteralExpression.concrete(
					full_source: @lexer.sql,
					value_tk: literal_tk,
				)
			elsif (id = maybe { name(except: [:RAISE]) })
				case current_token
				in :IN
					ColumnName.concrete(
						full_source: @lexer.sql,
						column_tk: Token::Identifier(id),
					)
				in :LP
					arguments_lp = require :LP
					arguments = function_arguments
					arguments_rp = require :RP
					if (within_group_kw = maybe_all_of :WITHIN, :GROUP)
						within_lp = require :LP
						require_all_of :ORDER, :BY
						within_group = expression
						within_rp = require :RP
					end
					filter = maybe { filter_clause }
					over = maybe { over_clause }

					FunctionReference.concrete(
						full_source: @lexer.sql,
						function_tk: Token::Identifier(id),
						arguments_lp: Token::Punctuation(arguments_lp),
						arguments: arguments,
						arguments_rp: Token::Punctuation(arguments_rp),
						within_group_kw: Token::Keyword(within_group_kw),
						within_lp: Token::Punctuation(within_lp),
						within_group: within_group,
						within_rp: Token::Punctuation(within_rp),
						filter_clause: filter,
						over_clause: over,
					)
				in :DOT
					schema_or_table_name = id
					dot = require :DOT
					table_or_column_name = name
					if (dot2 = maybe :DOT)
						column_name = name
						ColumnName.concrete(
							full_source: @lexer.sql,
							schema_tk: Token::Identifier(schema_or_table_name),
							dot1: Token::Punctuation(dot),
							table_tk: Token::Identifier(table_or_column_name),
							dot2: Token::Punctuation(dot2),
							column_tk: Token::Identifier(column_name),
						)
					else
						ColumnName.concrete(
							full_source: @lexer.sql,
							table_tk: Token::Identifier(schema_or_table_name),
							dot2: Token::Punctuation(dot),
							column_tk: Token::Identifier(table_or_column_name),
						)
					end
				else
					ColumnName.concrete(
						full_source: @lexer.sql,
						column_tk: Token::Identifier(id),
					)
				end
			elsif :RAISE == current_token
				raise_function
			# SQLite lexes "#9" as a variable too, but "#" and a digit only ever names a register
			# inside its own nested parses, so as a parameter it is a syntax error
			elsif :VARIABLE == current_token && !current_value.b.match?(/\A#\d/)
				Variable.concrete(
					full_source: @lexer.sql,
					name_tk: Token::Variable(require(:VARIABLE)),
				)
			else
				expected!("<basic expression>")
			end
		end

		def raise_function
			#
				# Relevant `parse.y` grammar rules:
				#    expr ::= RAISE LP IGNORE RP | RAISE LP raisetype COMMA expr RP
				#    raisetype ::= ROLLBACK | ABORT | FAIL
				#
				# Syntax diagram:
				#   ◯─▶{ RAISE }─▶{ ( }┬─▶{ IGNORE }────────────────────▶─────────┬▶{ ) }──▶◯
				#                      ├─▶{ ROLLBACK }─┬▶{ , }─▶{ error-message }─┘
				#                      ├─▶{ ABORT }──▶─┤
				#                      └─▶{ FAIL }───▶─┘
				#
				# Simplified grammar:
				#   RAISE LP (IGNORE | (ROLLBACK | ABORT | FAIL) COMMA expr) RP
				#
				# Relevant SQLite documentation:
				#   - https://www.sqlite.org/syntax/raise-function.html
				#   - https://www.sqlite.org/lang_createtrigger.html#the_raise_function
				#
				# The special RAISE expression that may _only_ occur in trigger programs.
			#
			raise_kw = require :RAISE
			raise_lp = require :LP
			if (ignore_kw = maybe :IGNORE)
				raise_rp = require :RP

				RaiseExpression.concrete(
					full_source: @lexer.sql,
					raise_kw: Token::Keyword(raise_kw),
					raise_lp: Token::Punctuation(raise_lp),
					type_kw: Token::Keyword(ignore_kw),
					raise_rp: Token::Punctuation(raise_rp),
				)
			elsif (rollback_kw = maybe :ROLLBACK)
				comma_tk = require :COMMA
				error_message = expression
				error_message.leading = Token::Punctuation(comma_tk)
				raise_rp = require :RP

				RaiseExpression.concrete(
					full_source: @lexer.sql,
					raise_kw: Token::Keyword(raise_kw),
					raise_lp: Token::Punctuation(raise_lp),
					type_kw: Token::Keyword(rollback_kw),
					raise_rp: Token::Punctuation(raise_rp),
					error_message: error_message,
				)
			elsif (abort_kw = maybe :ABORT)
				comma_tk = require :COMMA
				error_message = expression
				error_message.leading = Token::Punctuation(comma_tk)
				raise_rp = require :RP

				RaiseExpression.concrete(
					full_source: @lexer.sql,
					raise_kw: Token::Keyword(raise_kw),
					raise_lp: Token::Punctuation(raise_lp),
					type_kw: Token::Keyword(abort_kw),
					raise_rp: Token::Punctuation(raise_rp),
					error_message: error_message,
				)
			elsif (fail_kw = maybe :FAIL)
				comma_tk = require :COMMA
				error_message = expression
				error_message.leading = Token::Punctuation(comma_tk)
				raise_rp = require :RP

				RaiseExpression.concrete(
					full_source: @lexer.sql,
					raise_kw: Token::Keyword(raise_kw),
					raise_lp: Token::Punctuation(raise_lp),
					type_kw: Token::Keyword(fail_kw),
					raise_rp: Token::Punctuation(raise_rp),
					error_message: error_message,
				)
			else
				expected!(:IGNORE, :ROLLBACK, :ABORT, :FAIL)
			end
		end

		def function_arguments
			#
				# Relevant `parse.y` grammar rules:
				#   expr ::= idj LP distinct exprlist RP
				#            idj LP distinct exprlist ORDER BY sortlist RP
				#            idj LP STAR RP
				#            idj LP distinct exprlist RP filter_over
				#            idj LP distinct exprlist ORDER BY sortlist RP filter_over
				#            idj LP STAR RP filter_over
				#            idj LP distinct exprlist RP WITHIN GROUP LP ORDER BY expr RP filter_over
				#   distinct ::= DISTINCT | ALL | .
				#   exprlist ::= nexprlist | .
				#   nexprlist ::= nexprlist COMMA expr | expr
				#
				# Syntax diagram:
				#       ┌─▶{ DISTINCT }─▶┐ ┌──{ , }◀─┐
				#   ◯─▶─┼────────────────┴▶┴▶[ expr ]┼───────────┬─┬─▶◯
				#       │ ┌──────────────────────────┘           │ │
				#       │ └▶{ ORDER }─▶{ BY }┬▶[ ordering-term ]─┤ │
				#       │                    └───────{ , }◀──────┘ │
				#       └─────────────────┬▶{ * }┬▶────────────────┘
				#                         └───▶──┘
				#
				# Simplified grammar:
				#
				# Relevant SQLite documentation:
				#   -
				#
				# [description]
			#
			return StarFunctionArgument.new if maybe :STAR

			distinct_kw = maybe_one_of :DISTINCT, :ALL
			expressions = maybe_some(trailing_sep: :COMMA) { expression }
			if (order_by_kw = maybe_all_of :ORDER, :BY)
				order_by = require_some(trailing_sep: :COMMA) { ordering_term }
			end
			return EmptyFunctionArgument.new unless distinct_kw || expressions.any? || order_by_kw

			FunctionArguments.concrete(
				full_source: @lexer.sql,
				distinct_kw: Token::Keyword(distinct_kw),
				expressions: expressions,
				order_by_kw: Token::Keyword(order_by_kw),
				order_by: order_by,
			)
		end

		def frame_spec
			# Relevant `parse.y` grammar rules:
			#
			# Syntax diagram:
			#   ◯┬─▶{ RANGE }──┬┬▶{ BETWEEN }┬─▶{ UNBOUNDED }─▶{ PRECEDING }┬▶{ AND }┬─▶[ expr ]─▶{ PRECEDING }────▶─┐
			#    ├─▶{ ROWS }───┤│            ├─▶[ expr ]─▶{ PRECEDING }─────┤        ├─▶{ CURRENT }─▶{ ROW }───────▶─┤
			#    └─▶{ GROUPS }─┘│            ├─▶{ CURRENT }─▶{ ROW }────────┤        ├─▶[ expr ]─▶{ FOLLOWING }────▶─┤
			#                   │            └─▶[ expr ]─▶{ FOLLOWING }─────┘        └─▶{ UNBOUNDED }─▶{ FOLLOWING }─┤
			#                   ├─▶{ UNBOUNDED }─▶{ PRECEDING }────────────────────────────────────────────────────▶─┤
			#                   ├─▶[ expr ]─▶{ PRECEDING }─────────────────────────────────────────────────────────▶─┤
			#                   └─▶{ CURRENT }─▶{ ROW }────────────────────────────────────────────────────────────▶─┤
			#                                           ┌────────────────────────────────────────────────────────────┘
			#                                           ├─▶{ EXCLUDE }─▶{ NO }─▶{ OTHERS }───▶─┐
			#                                           ├─▶{ EXCLUDE }─▶{ CURRENT }─▶{ ROW }─▶─┤
			#                                           ├─▶{ EXCLUDE }─▶{ GROUP }────────────▶─┤
			#                                           ├─▶{ EXCLUDE }─▶{ TIES }─────────────▶─┤
			#                                           └──────────────────────────────────────┴─────────▶◯
			#
			# Simplified grammar:
			#
			# Relevant SQLite documentation:
			#   -
			#
			# [description]
			#
			if current_token in :RANGE | :ROWS | :GROUPS
				type_tk = require current_token
				if (between_kw = maybe :BETWEEN)
					if (unbounded_kw = maybe :UNBOUNDED)
						precedence = 1
						preceding_kw = maybe :PRECEDING
						starting_boundary = FrameBoundary.concrete(
							full_source: @lexer.sql,
							type_tk: Token::Keyword(preceding_kw),
							value_tk: Token::Keyword(unbounded_kw),
						)
					elsif (current_row_kw = maybe_all_of :CURRENT, :ROW)
						precedence = 3
						starting_boundary = FrameBoundary.concrete(
							full_source: @lexer.sql,
							type_tk: Token::Keyword(current_row_kw),
						)
					elsif (e = maybe { expression })
						if (preceding_kw = maybe :PRECEDING)
							precedence = 2
							starting_boundary = FrameBoundary.concrete(
								full_source: @lexer.sql,
								type_tk: Token::Keyword(preceding_kw),
								value: e
							)
						elsif (following_kw = maybe :FOLLOWING)
							precedence = 4
							starting_boundary = FrameBoundary.concrete(
								full_source: @lexer.sql,
								type_tk: Token::Keyword(following_kw),
								value: e
							)
						else
							expected!(:PRECEDING, :FOLLOWING)
						end
					else
						expected!("UNBOUNDED PRECEDING", "CURRENT ROW", "expr")
					end
					and_kw = require :AND
					if (current_row_kw = maybe_all_of :CURRENT, :ROW)
						expected!("UNBOUNDED FOLLOWING", "expr") if 3 < precedence
						ending_boundary = FrameBoundary.concrete(
							full_source: @lexer.sql,
							type_tk: Token::Keyword(current_row_kw),
						)
					elsif (unbounded_kw = maybe :UNBOUNDED)
						following_kw = maybe :FOLLOWING
						ending_boundary = FrameBoundary.concrete(
							full_source: @lexer.sql,
							type_tk: Token::Keyword(following_kw),
							value_tk: Token::Keyword(unbounded_kw),
						)
					elsif (e = maybe { expression })
						if (preceding_kw = maybe :PRECEDING)
							expected!("CURRENT ROW", "UNBOUNDED FOLLOWING", "expr") if 2 < precedence
							ending_boundary = FrameBoundary.concrete(
								full_source: @lexer.sql,
								type_tk: Token::Keyword(preceding_kw),
								value: e
							)
						elsif (following_kw = maybe :FOLLOWING)
							expected!("UNBOUNDED FOLLOWING") if 4 < precedence
							ending_boundary = FrameBoundary.concrete(
								full_source: @lexer.sql,
								type_tk: Token::Keyword(following_kw),
								value: e
							)
						else
							expected!(:PRECEDING, :FOLLOWING)
						end
					else
						expected!("CURRENT ROW", "UNBOUNDED FOLLOWING", "expr")
					end
				elsif (unbounded_kw = maybe :UNBOUNDED)
					preceding_kw = maybe :PRECEDING
					starting_boundary = FrameBoundary.concrete(
						full_source: @lexer.sql,
						type_tk: Token::Keyword(preceding_kw),
						value_tk: Token::Keyword(unbounded_kw),
					)
					ending_boundary = nil
				elsif (current_row_kw = maybe_all_of :CURRENT, :ROW)
					starting_boundary = FrameBoundary.concrete(
						full_source: @lexer.sql,
						type_tk: Token::Keyword(current_row_kw),
					)
					ending_boundary = nil
				elsif (e = maybe { expression })
					preceding_kw = require :PRECEDING
					starting_boundary = FrameBoundary.concrete(
						full_source: @lexer.sql,
						type_tk: Token::Keyword(preceding_kw),
						value: e
					)
					ending_boundary = nil
				else
					expected!(:BETWEEN, :UNBOUNDED, :CURRENT, "expr")
				end

				if (exclude_kw = maybe :EXCLUDE)
					exclude_tk = require_one_of(:GROUP, :TIES, [:NO, :OTHERS].freeze, [:CURRENT, :ROW].freeze)
				end

				FrameSpec.concrete(
					full_source: @lexer.sql,
					type_tk: Token::Keyword(type_tk),
					between_kw: Token::Keyword(between_kw),
					and_kw: Token::Keyword(and_kw),
					starting_boundary: starting_boundary,
					ending_boundary: ending_boundary,
					exclude_kw: Token::Keyword(exclude_kw),
					exclude_tk: Token::Keyword(exclude_tk),
				)
			else
				expected!(:RANGE, :ROWS, :GROUPS)
			end
		end

		# ---------- Objects ----------

		def type_name
			#
				# Used by:
				#   - column_def
				#   - expression
				#
				# Relevant `parse.y` grammar rules:
				#   typetoken ::= . | typename. | typename LP signed RP | typename LP signed COMMA signed RP
				#   typename ::= ids | typename ids
				#   signed ::= plus_num | minus_num
				#   plus_num ::= PLUS number | number
				#   minus_num ::= MINUS number
				#   number ::= INTEGER | FLOAT
				#
				# Syntax diagram:
				#   ◯─┬▶{ name }─┬┬──────────────────────────────▶─────────────────────────────┬─▶◯
				#     └────◀─────┘├─▶{ ( }─▶[ signed-number ]─▶{ ) }─────────────────────────▶─┤
				#                 └─▶{ ( }─▶[ signed-number ]─▶{ , }─▶[ signed-number ]─▶{ ) }─┘
				#
				# Simplified grammar:
				#   name [name]* [LP signed_number [, signed_number] RP]
				#
				# Relevant SQLite documentation:
				#   - https://www.sqlite.org/syntax/type-name.html
				#   - https://www.sqlite.org/datatype3.html
				#   - https://www.sqlite.org/flextypegood.html
				#
				# A typetoken is really zero or more tokens that form a type name such
				# as can be found after the column name in a CREATE TABLE statement.
				# Multiple tokens are concatenated to form the value of the typetoken.
			#
			text = scan do
				require_some(trailing_sep: nil) do
					identifier_or_string(
						# Don't consume tokens that mark the start of a `column_constraint`
						except: Set[:CONSTRAINT, :PRIMARY, :NOT, :NULL, :UNIQUE, :CHECK, :DEFAULT, :COLLATE, :REFERENCES, :GENERATED, :AS]
					)
				end
				if maybe :LP
					signed_number
					signed_number if maybe :COMMA
					require :RP
				end
			end

			ColumnType.concrete(
				full_source: @lexer.sql,
				text_span: Token::Keyword(text),
			)
		end

		def table_name
			#
				# Used by:
				#   - drop table
				#   - delete
				#   - update
				#   - insert
				#   - alter table
				#
				# Relevant `parse.y` grammar rules:
				#   fullname ::= nm | nm DOT nm
				#
				# Syntax diagram:
				#   ◯─▶┬▶{ schema-name }─▶{ . }┬▶{ object-name }─▶◯
				#      └───────────▶───────────┘
				#
				# Simplified grammar:
				#   name [DOT name]
				#
				# Relevant SQLite documentation:
				#   - https://www.sqlite.org/lang_createtable.html
				#   - https://www.sqlite.org/lang_createvtab.html
				#
				# A table or virtual table name, where the schema name is optional.
			#

			if peek == :DOT
				schema_tk = name
				dot_tk    = require :DOT
				table_tk  = name

				TableName.concrete(
					full_source: @lexer.sql,
					schema_tk:   Token::Identifier(schema_tk),
					dot_tk:      Token::Punctuation(dot_tk),
					table_tk:    Token::Identifier(table_tk),
				)
			else
				table_tk = name

				TableName.concrete(
					full_source: @lexer.sql,
					table_tk:    Token::Identifier(table_tk),
				)
			end
		end

		# `xfullname` plus the optional `indexed_opt` - the target table of INSERT, UPDATE and DELETE.
		# Unlike in FROM, an alias here needs the AS
		def qualified_table_name(indexed:)
			#
				# Relevant `parse.y` grammar rules:
				#   xfullname ::= nm | nm DOT nm | nm DOT nm AS nm | nm AS nm
				#   indexed_opt ::= . | indexed_by
				#   indexed_by ::= INDEXED BY nm | NOT INDEXED
				#
				# Relevant SQLite documentation:
				#   - https://www.sqlite.org/syntax/qualified-table-name.html
			#
			table_tk = name
			if (dot_tk = maybe :DOT)
				schema_tk = table_tk
				table_tk = name
			end
			if (as_kw = maybe :AS)
				alias_tk = name
			end
			indexed_kw, index_tk = indexed_by if indexed

			TableName.concrete(
				full_source: @lexer.sql,
				schema_tk:   Token::Identifier(schema_tk),
				dot_tk:      Token::Punctuation(dot_tk),
				table_tk:    Token::Identifier(table_tk),
				as_kw:       Token::Keyword(as_kw),
				alias_tk:    Token::Identifier(alias_tk),
				indexed_kw:  Token::Keyword(indexed_kw),
				index_tk:    Token::Identifier(index_tk),
			)
		end

		def column_reference
			ColumnName.concrete(
				full_source: @lexer.sql,
				column_tk:   Token::Identifier(name),
			)
		end

		def set_list
			#
				# Relevant `parse.y` grammar rules:
				#   setlist ::= setlist COMMA nm EQ expr | setlist COMMA LP idlist RP EQ expr |
				#               nm EQ expr | LP idlist RP EQ expr
			#
			require_some(trailing_sep: :COMMA) do
				if (columns_lp = maybe :LP)
					columns = require_some(trailing_sep: :COMMA) { column_reference }
					columns_rp = require :RP
				else
					columns = [column_reference]
				end
				eq_tk = require :EQ
				value = expression

				Assignment.concrete(
					full_source: @lexer.sql,
					columns_lp:  Token::Punctuation(columns_lp),
					columns:     columns,
					columns_rp:  Token::Punctuation(columns_rp),
					eq_tk:       Token::Punctuation(eq_tk),
					value:       value,
				)
			end
		end

		def upsert_clause
			#
				# Syntax diagram:
				#   ◯─▶{ ON }─▶{ CONFLICT }┬───────────────────────────────────────────────────────────┬┐
				#                          └▶{ ( }┬▶[ indexed-column ]┬▶{ ) }┬────────────────────────┤│
				#                                 └───────{ , }◀──────┘      └▶{ WHERE }─▶[ expr ]─┘  ││
				#   ┌───────────────────────────────────────────◀────────────────────────────────────┘│
				#   └▶{ DO }┬▶{ NOTHING }─────────────────────────────────────────────────────────────┬─▶◯
				#           └▶{ UPDATE }─▶{ SET }─▶[ assignment … ]┬───────────────────────┬──────────┘
				#                                                  └▶{ WHERE }─▶[ expr ]──┘
				#
				# Relevant SQLite documentation:
				#   - https://www.sqlite.org/lang_upsert.html
			#
			on_conflict_kw = require_all_of :ON, :CONFLICT
			if (target_lp = maybe :LP)
				targets = require_some(trailing_sep: :COMMA) { ordering_term }
				target_rp = require :RP
				if (target_where_kw = maybe :WHERE)
					target_condition = expression
				end
			end
			do_kw = require :DO
			action_kw = require_one_of :NOTHING, :UPDATE
			if action_kw[0] == :UPDATE
				set_kw = require :SET
				assignments = set_list
				if (where_kw = maybe :WHERE)
					condition = expression
				end
			end

			UpsertClause.concrete(
				full_source:      @lexer.sql,
				on_conflict_kw:   Token::Keyword(on_conflict_kw),
				target_lp:        Token::Punctuation(target_lp),
				targets:          targets,
				target_rp:        Token::Punctuation(target_rp),
				target_where_kw:  Token::Keyword(target_where_kw),
				target_condition: target_condition,
				do_kw:            Token::Keyword(do_kw),
				action_kw:        Token::Keyword(action_kw),
				set_kw:           Token::Keyword(set_kw),
				assignments:      assignments,
				where_kw:         Token::Keyword(where_kw),
				condition:        condition,
			)
		end

		def returning_clause
			#
				# Relevant SQLite documentation:
				#   - https://www.sqlite.org/lang_returning.html
			#
			return unless (returning_kw = maybe :RETURNING)

			ReturningClause.concrete(
				full_source:  @lexer.sql,
				returning_kw: Token::Keyword(returning_kw),
				columns:      require_some(trailing_sep: :COMMA) { result_column },
			)
		end

		# The statement-level tail of SELECT. UPDATE and DELETE take it too when SQLite is built
		# with SQLITE_ENABLE_UPDATE_DELETE_LIMIT, so we accept it there as well
		def order_and_limit
			if (order_by_kw = maybe_all_of :ORDER, :BY)
				orderings = require_some(trailing_sep: :COMMA) { ordering_term }
			end
			if (limit_kw = maybe :LIMIT)
				limit = expression
				if (offset_tk = maybe :OFFSET)
					offset = expression
				elsif (offset_tk = maybe :COMMA)
					# `LIMIT 5, 10` means skip 5 and take 10, the reverse of what it looks like
					offset = limit
					limit = expression
				end
			end

			{
				order_by_kw: Token::Keyword(order_by_kw),
				orderings:   orderings,
				limit_kw:    Token::Keyword(limit_kw),
				limit:       limit,
				offset_tk:   Token::Keyword(offset_tk),
				offset:      offset,
			}
		end

		def result_column
			#
				# Relevant `parse.y` grammar rules:
				#   selcollist ::= sclp expr as | sclp STAR | sclp nm DOT STAR
				#   sclp ::= selcollist COMMA | .
				#   as ::= AS nm | ids | .
				#   nm ::= idj | STRING
				#
				# Syntax diagram:
				#   ◯┬─▶[ expr ]─┬─────────────▶───────────────┬─▶◯
				#    │           ├─▶{ AS }┬▶{ column-alias }─▶─┤
				#    │           └────▶───┘                    │
				#    ├─▶{ * }────────────────────────────────▶─┤
				#    └─▶{ table-name }─▶{ . }─▶{ * }─────────▶─┘
				#
				# Simplified grammar:
				#   expr [[AS] alias] | * | table.*
				#
				# Relevant SQLite documentation:
				#   - https://www.sqlite.org/syntax/result-column.html
				#
				# One of the columns a select core returns.
			#
			if (star_tk = maybe :STAR)
				StarResultColumn.concrete(
					full_source: @lexer.sql,
					star_tk:     Token::Punctuation(star_tk),
				)
			elsif peek(2) == [:DOT, :STAR]
				table_tk = name
				dot_tk = require :DOT
				star_tk = require :STAR

				StarResultColumn.concrete(
					full_source: @lexer.sql,
					table_tk:    Token::Identifier(table_tk),
					dot_tk:      Token::Punctuation(dot_tk),
					star_tk:     Token::Punctuation(star_tk),
				)
			else
				result = expression
				as_kw, alias_tk = as_alias
				result_attr = (Node === result) ? { result: result } : { result_tk: result }

				ResultColumn.concrete(
					full_source: @lexer.sql,
					**result_attr,
					as_kw:       Token::Keyword(as_kw),
					alias_tk:    Token::Identifier(alias_tk),
				)
			end
		end

		# `as ::= AS nm | ids | .` - without the AS only an identifier or a string will do,
		# so keywords like INDEXED or the join keywords are never mistaken for an alias
		def as_alias
			if (as_kw = maybe :AS)
				[as_kw, name]
			else
				[nil, maybe { identifier_or_string }]
			end
		end

		# indexed_by ::= INDEXED BY nm | NOT INDEXED
		def indexed_by
			if (indexed_kw = maybe_all_of :INDEXED, :BY)
				[indexed_kw, name]
			else
				[maybe_all_of(:NOT, :INDEXED), nil]
			end
		end

		def join_clause
			#
				# Relevant `parse.y` grammar rules:
				#   seltablist ::= stl_prefix nm dbnm as on_using |
				#                  stl_prefix nm dbnm as indexed_by on_using |
				#                  stl_prefix nm dbnm LP exprlist RP as on_using |
				#                  stl_prefix LP select RP as on_using |
				#                  stl_prefix LP seltablist RP as on_using
				#   stl_prefix ::= seltablist joinop | .
				#   joinop ::= COMMA | JOIN | JOIN_KW JOIN | JOIN_KW nm JOIN | JOIN_KW nm nm JOIN
				#   on_using ::= ON expr | USING LP idlist RP | .
				#
				# Syntax diagram:
				#   ◯─▶[ table-or-subquery ]┬───────────────────────────────▶────────────────────────────────┬─▶◯
				#                           └┬▶[ join-operator ]─▶[ table-or-subquery ]─▶[ join-constraint ]┬┘
				#                            └───────────────────────────────◀──────────────────────────────┘
				#
				# Simplified grammar:
				#   table_or_subquery [join_operator table_or_subquery [join_constraint]]*
				#
				# Relevant SQLite documentation:
				#   - https://www.sqlite.org/syntax/join-clause.html
				#
				# Everything after FROM. A comma between sources is a join operator as well.
			#
			left = table_or_subquery
			joins = []

			while (operator = join_operator)
				source = table_or_subquery
				constraint = join_constraint

				joins << Join.concrete(
					full_source: @lexer.sql,
					operator:    operator,
					source:      source,
					constraint:  constraint,
				)
			end

			return left if joins.empty?

			JoinClause.concrete(
				full_source: @lexer.sql,
				left:        left,
				joins:       joins,
			)
		end

		JOIN_KEYWORDS = Set[:NATURAL, :LEFT, :RIGHT, :FULL, :INNER, :OUTER, :CROSS].freeze

		def join_operator
			#
				# Syntax diagram:
				#   ◯┬──────────────▶─────────────────────────────────────────┬─▶◯
				#    ├─▶{ , }──────────────────────────────────────────────▶─┤
				#    ├─▶{ NATURAL }─┬┬─▶{ LEFT }──┬┬────────────┬┬▶{ JOIN }─┘
				#    └──────▶───────┘├─▶{ RIGHT }─┤└▶{ OUTER }─▶┘│
				#                    ├─▶{ FULL }──┘              │
				#                    ├─▶{ INNER }───────────────▶┤
				#                    └─▶{ CROSS }───────────────▶┘
				#
				# Relevant SQLite documentation:
				#   - https://www.sqlite.org/syntax/join-operator.html
			#
			if (comma_tk = maybe :COMMA)
				return JoinOperator.concrete(
					full_source: @lexer.sql,
					operator_tk: Token::Punctuation(comma_tk),
				)
			end

			keywords = []
			keywords << advance while keywords.size < 3 && JOIN_KEYWORDS.include?(current_token)
			join_tk = keywords.any? ? require(:JOIN) : maybe(:JOIN)
			return unless join_tk

			JoinOperator.concrete(
				full_source: @lexer.sql,
				operator_tk: Token::Keyword(token_span_from(*keywords, join_tk)),
			)
		end

		def join_constraint
			#
				# Syntax diagram:
				#   ◯─┬─▶{ ON }─▶[ expr ]─────────────────────────────▶─┬─▶◯
				#     ├─▶{ USING }─▶{ ( }┬▶{ column-name }┬▶{ ) }────▶─┤
				#     │                  └──────{ , }◀────┘             │
				#     └────────────────────────▶────────────────────────┘
				#
				# Relevant SQLite documentation:
				#   - https://www.sqlite.org/syntax/join-constraint.html
			#
			if (on_kw = maybe :ON)
				JoinOnConstraint.concrete(
					full_source: @lexer.sql,
					on_kw:       Token::Keyword(on_kw),
					expression:  expression,
				)
			elsif (using_kw = maybe :USING)
				columns_lp = require :LP
				columns = require_some(trailing_sep: :COMMA) { column_reference }
				columns_rp = require :RP

				JoinUsingConstraint.concrete(
					full_source: @lexer.sql,
					using_kw:    Token::Keyword(using_kw),
					columns_lp:  Token::Punctuation(columns_lp),
					columns:     columns,
					columns_rp:  Token::Punctuation(columns_rp),
				)
			end
		end

		def table_or_subquery
			#
				# Relevant `parse.y` grammar rules:
				#   seltablist ::= stl_prefix nm dbnm as on_using |
				#                  stl_prefix nm dbnm as indexed_by on_using |
				#                  stl_prefix nm dbnm LP exprlist RP as on_using |
				#                  stl_prefix LP select RP as on_using |
				#                  stl_prefix LP seltablist RP as on_using
				#   indexed_by ::= INDEXED BY nm | NOT INDEXED
				#   as ::= AS nm | ids | .
				#   dbnm ::= . | DOT nm
				#
				# Syntax diagram:
				#                                              ┌───────┬────────────────┐
				#   ◯┬─────────────────────────┬─{ table-name }┴▶{ AS }┴▶{ table-alias }┴┬──────────┬─▶◯
				#    ├─▶{ schema-name }─▶{ . }─┤   ┌───────────────────◀─────────────────┘          │
				#    │                         │   ├─▶{ INDEXED }─▶{ BY }─▶{ index-name }─────────▶─┤
				#    │                         │   └─▶{ NOT }─▶{ INDEXED }────────────────────────▶─┤
				#    │                         │                                 ┌──{ , }◀─┐        │
				#    ├─▶───────────────────────┴───{ table-function-name }─▶{ ( }┴▶[ expr ]┴▶{ ) }┬─┤
				#    │                                               ┌────────┬───────◀───────────┘ │
				#    │                                ┌──────────────┴▶{ AS }┬┴▶{ table-alias }───▶─┤
				#    ├─▶{ ( }─▶[ select-stmt ]─▶{ ) }─┴──────────────────────┴────────────────────▶─┤
				#    └─▶{ ( }┬┬▶[ table-or-subquery ]┬┬▶{ ) }─────────────────────────────────────▶─┘
				#            │└─────────{ , }◀───────┘│
				#            └─▶────[ join-clause ]───┘
				#
				# Simplified grammar:
				#   [schema .] table [[AS] alias] [INDEXED BY index | NOT INDEXED]
				#   | [schema .] function (expr [, expr]*) [[AS] alias]
				#   | (select_stmt) [[AS] alias]
				#   | (join_clause) [[AS] alias]
				#
				# Relevant SQLite documentation:
				#   - https://www.sqlite.org/syntax/table-or-subquery.html
				#
				# One source of rows in a FROM clause.
			#
			if (source_lp = maybe :LP)
				if subquery_start?
					select = select_stmt
					source_rp = require :RP
					as_kw, alias_tk = as_alias

					SubquerySource.concrete(
						full_source: @lexer.sql,
						select_lp:   Token::Punctuation(source_lp),
						select:      select,
						select_rp:   Token::Punctuation(source_rp),
						as_kw:       Token::Keyword(as_kw),
						alias_tk:    Token::Identifier(alias_tk),
					)
				else
					source = join_clause
					source_rp = require :RP
					as_kw, alias_tk = as_alias

					ParentheticalSource.concrete(
						full_source: @lexer.sql,
						source_lp:   Token::Punctuation(source_lp),
						source:      source,
						source_rp:   Token::Punctuation(source_rp),
						as_kw:       Token::Keyword(as_kw),
						alias_tk:    Token::Identifier(alias_tk),
					)
				end
			else
				schema_tk = nil
				object_tk = name
				if (dot_tk = maybe :DOT)
					schema_tk = object_tk
					object_tk = name
				end

				if (arguments_lp = maybe :LP)
					arguments = maybe_some(trailing_sep: :COMMA) { expression }
					arguments_rp = require :RP
					as_kw, alias_tk = as_alias

					TableFunction.concrete(
						full_source:  @lexer.sql,
						schema_tk:    Token::Identifier(schema_tk),
						dot_tk:       Token::Punctuation(dot_tk),
						function_tk:  Token::Identifier(object_tk),
						arguments_lp: Token::Punctuation(arguments_lp),
						arguments:    arguments,
						arguments_rp: Token::Punctuation(arguments_rp),
						as_kw:        Token::Keyword(as_kw),
						alias_tk:     Token::Identifier(alias_tk),
					)
				else
					as_kw, alias_tk = as_alias
					indexed_kw, index_tk = indexed_by

					TableName.concrete(
						full_source: @lexer.sql,
						schema_tk:   Token::Identifier(schema_tk),
						dot_tk:      Token::Punctuation(dot_tk),
						table_tk:    Token::Identifier(object_tk),
						as_kw:       Token::Keyword(as_kw),
						alias_tk:    Token::Identifier(alias_tk),
						indexed_kw:  Token::Keyword(indexed_kw),
						index_tk:    Token::Identifier(index_tk),
					)
				end
			end
		end

		def literal_value
			#
				# Relevant `parse.y` grammar rules:
				#   term ::= NULL | FLOAT | BLOB | STRING | INTEGER | CTIME_KW | QNUMBER
				#
				# Syntax diagram:
				#   ◯─┬─▶{ numeric-literal }────▶─┬─▶◯
				#     ├─▶{ string-literal }─────▶─┤
				#     ├─▶{ blob-literal }───────▶─┤
				#     ├─▶{ NULL }───────────────▶─┤
				#     ├─▶{ TRUE }───────────────▶─┤
				#     ├─▶{ FALSE }──────────────▶─┤
				#     ├─▶{ CURRENT_TIME }───────▶─┤
				#     ├─▶{ CURRENT_DATE }───────▶─┤
				#     └─▶{ CURRENT_TIMESTAMP }──▶─┘
				#
				# Simplified grammar:
				#   NULL | CURRENT_TIME | CURRENT_DATE | CURRENT_TIMESTAMP | INTEGER | FLOAT | STRING | BLOB | TRUE | FALSE | QNUMBER
				#
				# Relevant SQLite documentation:
				#   - https://www.sqlite.org/syntax/literal-value.html
				#
				# A value
			#
			case current_token
			when :NULL
				tk = require :NULL
				Token::Null(tk)
			when :CURRENT_TIME
				tk = require :CURRENT_TIME
				Token::Current(tk)
			when :CURRENT_DATE
				tk = require :CURRENT_DATE
				Token::Current(tk)
			when :CURRENT_TIMESTAMP
				tk = require :CURRENT_TIMESTAMP
				Token::Current(tk)
			when :TRUE
				tk = require :TRUE
				Token::True(tk)
			when :FALSE
				tk = require :FALSE
				Token::False(tk)
			when :QNUMBER
				tk = require_qnumber
				Token::Numeric(tk)
			when :INTEGER
				tk = require :INTEGER
				Token::Numeric(tk)
			when :FLOAT
				tk = require :FLOAT
				Token::Numeric(tk)
			when :STRING
				tk = require :STRING
				Token::String(tk)
			when :BLOB
				tk = require :BLOB
				Token::Blob(tk)
			else
				expected!(:INTEGER, :FLOAT, :QNUMBER, :STRING, :BLOB, :NULL, :TRUE, :FALSE, :CURRENT_TIME, :CURRENT_DATE, :CURRENT_TIMESTAMP)
			end
		end

		# `nulls`: whether NULLS FIRST/LAST may follow, as in the sortlist of a PRIMARY KEY or UNIQUE -
		# not in the eidlist of a foreign key, a view or a CTE
		def indexed_column(nulls: false)
			# Used by:
			#   - ccons, tcons, creat-view, cte
			#
			# Relevant `parse.y` grammar rules:
			#   eidlist ::= eidlist COMMA nm collate sortorder | nm collate sortorder
			#   collate ::= . | COLLATE ids.
			#   sortorder ::= . | ASC | DESC
			#   nm ::= idj | STRING
			#   (PRIMARY KEY and UNIQUE take a sortlist, whose items may also end NULLS FIRST or NULLS LAST)
			#
			# Syntax diagram:
			#   ◯──▶{ column-name }─┬─▶───────────────────────────────┬┬────────▶───┬──▶◯
			#                       └─▶{ COLLATE }─▶{ collation-name }┘├─▶{ ASC }─▶─┤
			#                                                          └─▶{ DESC }──┘
			#
			# Simplified grammar:
			#   name [COLLATE identifier] [ASC | DESC] [NULLS FIRST | NULLS LAST]
			#
			# Relevant SQLite documentation:
			#   - https://www.sqlite.org/syntax/indexed-column.html
			#
			# The eidlist non-terminal (Expression Id List) generates an ExprList
			# from a list of identifiers.  The identifier names are in ExprList.a[].zName.
			# This list is stored in an ExprList rather than an IdList so that it
			# can be easily sent to sqlite3ColumnsExprList().
			#
			# IMPORTANT COMPATIBILITY NOTE:  Some prior versions of SQLite accepted
			# COLLATE clauses and ASC or DESC keywords on ID lists in inappropriate
			# places - places that might have been stored in the sqlite_schema table.
			# Those extra features were ignored.  But because they might be in some
			# (busted) old databases, we need to continue parsing them when loading
			# historical schemas.
			#
			column_name  = name(except: [:COLLATE, :ASC, :DESC].freeze)
			if (collate_kw = maybe :COLLATE)
				collation_tk = identifier_or_string(except: [:ASC, :DESC].freeze)
			end
			direction_tk = maybe_one_of :ASC, :DESC
			nulls_tk     = maybe_one_of [:NULLS, :FIRST].freeze, [:NULLS, :LAST].freeze if nulls

			IndexedColumn.concrete(
				full_source: @lexer.sql,
				name_tk:      Token::Identifier(column_name),
				collate_kw:   Token::Keyword(collate_kw),
				collation_tk: Token::Keyword(collation_tk),
				direction_tk: Token::Keyword(direction_tk),
				nulls_tk:     Token::Keyword(nulls_tk),
			)
		end

		def ordering_term
			#
				# Relevant `parse.y` grammar rules:
				#   sortlist ::= sortlist COMMA expr sortorder nulls |
				#                expr sortorder nulls
				#   sortorder ::= ASC | DESC | .
				#   nulls ::= NULLS FIRST | NULLS LAST | .
				#   eidlist ::= eidlist COMMA nm collate sortorder |
				#               nm collate sortorder
				#   collate ::= . |
				#               COLLATE ids.
				#
				# Syntax diagram:
				#   ◯─▶[ expr ]┬───────────────▶────────────────┬▶┬──────▶─────┬▶┬──────────▶─────────────┬─▶◯
				#              └▶{ COLLATE }─▶{ collation-name }┘ ├▶{ ASC }──▶─┤ ├▶{ NULLS }─▶{ FIRST }─▶─┤
				#                                                 └▶{ DESC }─▶─┘ └▶{ NULLS }─▶{ LAST }──▶─┘
				#
				# Simplified grammar:
				#
				# Relevant SQLite documentation:
				#   -
				#
				# [description]
			#
			e = expression
			if (collate_kw = maybe(:COLLATE))
				collation = identifier
			end
			if current_token in :ASC | :DESC
				direction = require current_token
			end
			if (nulls_kw = maybe(:NULLS))
				nulls = require_one_of(:FIRST, :LAST)
			end

			OrderingTerm.concrete(
				full_source: @lexer.sql,
				expression: e,
				collate_kw: Token::Keyword(collate_kw),
				collation_tk: Token::Identifier(collation),
				direction_tk: Token::Keyword(direction),
				nulls_kw: Token::Keyword(nulls_kw),
				nulls_tk: Token::Keyword(nulls),
			)
		end

		def signed_number
			#
				# Used by:
				#   - pragma_value
				#   - type_name
				#
				# Relevant `parse.y` grammar rules:
				#   signed ::= plus_num | minus_num
				#   plus_num ::= PLUS number | number
				#   minus_num ::= MINUS number
				#   number ::= INTEGER | FLOAT
				#
				# Syntax diagram:
				#   ◯─┬───▶────┬─▶{ numeric-literal }─▶◯
				#     ├─▶{ + }─┤
				#     └─▶{ - }─┘
				#
				# Simplified grammar:
				#   [PLUS | MINUS] INTEGER | FLOAT
				#
				# Relevant SQLite documentation:
				#   - https://www.sqlite.org/syntax/signed-number.html
				#
				# A signed number is a numeric literal with an optional sign.
			#
			sign_tk  = maybe_one_of   :PLUS, :MINUS
			value_tk = require_one_of :INTEGER, :FLOAT

			return value_tk unless sign_tk

			sign_tk, beg, _fin = sign_tk
			value_tk, _beg, fin = value_tk

			[[sign_tk, value_tk], beg, fin]
		end

		# ---------- Token Classes ----------

		def name(except: [])
			# Relevant `parse.y` grammar rules:
			#   // The name of a column or table can be any of the following:
			#   nm ::= idj | STRING
			#
			if current_token in :STRING
				require current_token
			elsif (idj = maybe { identifier_or_join_keyword(except: except) })
				idj
			else
				expected!(:STRING, "idj")
			end
		end

		def identifier(except: [])
			# Relevant `parse.y` grammar rules:
			#   // An IDENTIFIER can be a generic identifier, or one of several
			#   // keywords.  Any non-standard keyword can also be an identifier.
			#   %token_class id  ID | INDEXED
			#
			if current_token in :ID | :INDEXED
				require current_token
			elsif !except.include?(current_token) && TOKEN_FALLBACKS.include?(current_token)
				require current_token
			else
				expected!(:ID, :INDEXED, "fallback")
			end
		end

		def identifier_or_string(except: [])
			# Relevant `parse.y` grammar rules:
			#   // And "ids" is an identifer-or-string.
			#   %token_class ids  ID | STRING
			#
			if current_token in :ID | :STRING
				require current_token
			elsif !except.include?(current_token) && TOKEN_FALLBACKS.include?(current_token)
				require current_token
			else
				expected!(:ID, :STRING, "fallback")
			end
		end

		def identifier_or_join_keyword(except: [])
			# Relevant `parse.y` grammar rules:
			#   // An identifier or a join-keyword
			#   %token_class idj  ID | INDEXED | JOIN_KW
			#
			if current_token in :ID | :INDEXED | :CROSS | :FULL | :INNER | :LEFT | :NATURAL | :OUTER | :RIGHT
				require current_token
			elsif !except.include?(current_token) && TOKEN_FALLBACKS.include?(current_token)
				require current_token
			else
				expected!(:ID, :INDEXED, :JOIN_KW, "fallback")
			end
		end

		private

		# ---------- Parsing Helpers ----------

		def require(token)
			if token == current_token
				advance
			else
				expected!(token)
			end
		end

		def maybe(token = nil) # &block
			if block_given?
				start_buffer = @peek_buffer.dup
				start_lexer_cursor = @lexer.cursor
				start_lexer_pos = @lexer.anchor
				start_last_consumed = @last_consumed_token
				start_last_consumed_fin = @last_consumed_fin

				result = catch(:ERROR) { yield }

				if ErrorMessage === result
					@peek_buffer = start_buffer
					@lexer.cursor = start_lexer_cursor
					@lexer.anchor = start_lexer_pos
					@last_consumed_token = start_last_consumed
					@last_consumed_fin = start_last_consumed_fin
					nil
				else
					result
				end
			elsif token == current_token
				advance
			end
		end

		# The span of whatever the block consumes. Positions come from the buffered tokens - the
		# lexer itself may already be several tokens ahead, looking ahead for us
		def scan(&block)
			beg = ensure_buffer[0][1]
			block.call
			[[], beg, @last_consumed_fin]
		end

		def require_all_of(*tokens)
			i, len = 0, tokens.length
			start_pos, end_pos = nil
			while i < len
				if tokens[i] == current_token
					_tok, beg, fin = advance
					start_pos = beg if i == 0 # first iteration
					end_pos = fin if i == (len - 1) # last iteration

					i += 1
				else
					# TODO: only show the tokens from `i` onwards
					expected!(tokens)
				end
			end

			[tokens, start_pos, end_pos].freeze
		end

		def maybe_all_of(*tokens)
			advancing = true
			i, len = 0, tokens.length
			buf = ensure_buffer(len)
			while i < len
				tok, * = buf[i]
				if tokens[i] != tok
					advancing = false
					break
				end
				i += 1
			end

			require_all_of(*tokens) if advancing
		end

		def maybe_one_of(*tokens)
			i, len = 0, tokens.length
			has_nil = false
			while i < len
				check = tokens[i]
				if Symbol === check && (result = maybe check)
					return result
				elsif Array === check && (result = maybe_all_of(*check))
					return result
				elsif check.nil?
					has_nil = true
					i += 1
				else
					i += 1
				end
			end

			has_nil ? false : nil
		end

		def require_one_of(*tokens)
			maybe_one_of(*tokens) || expected!(*tokens)
		end

		def require_some(trailing_sep: nil, leading_sep: nil, given: nil, &)
			a = []

			if leading_sep
				sep_tk = (Array === leading_sep) ? require_one_of(*leading_sep) : require(leading_sep)
				val = yield(sep_tk)
				insert = if Node === val
					val.leading = Token::Punctuation(sep_tk)
					val
				else
					[sep_tk, val]
				end
			elsif trailing_sep
				val = (given || yield)
				sep_tk = (Array === trailing_sep) ? maybe_one_of(*trailing_sep) : maybe(trailing_sep)
				insert = if Node === val
					val.trailing = Token::Punctuation(sep_tk) if sep_tk
					val
				else
					[val, sep_tk]
				end
			else
				val = (given || yield)
				insert = val
			end
			a << insert

			collect(into: a, trailing_sep: trailing_sep, leading_sep: leading_sep, last_sep: sep_tk, &)

			return token_span_from(*a) if a.all?(Array)

			a
		end

		def maybe_some(trailing_sep: nil, leading_sep: nil, &)
			a = []

			if leading_sep
				sep_tk = (Array === leading_sep) ? maybe_one_of(*leading_sep) : maybe(leading_sep)
				return if sep_tk.nil?

				val = yield(sep_tk)
				insert = if Node === val
					val.leading = Token::Punctuation(sep_tk)
					val
				else
					[sep_tk, val]
				end
			elsif trailing_sep
				val = maybe { yield }
				return a if val.nil?

				sep_tk = (Array === trailing_sep) ? maybe_one_of(*trailing_sep) : maybe(trailing_sep)
				insert = if Node === val
					val.trailing = Token::Punctuation(sep_tk) if sep_tk
					val
				else
					[val, sep_tk]
				end
			else
				insert = maybe { yield }
			end

			if insert
				a << insert

				collect(into: a, trailing_sep: trailing_sep, leading_sep: leading_sep, last_sep: sep_tk, &)

				return token_span_from(*a) if a.all?(Array)

				a
			else
				a
			end
		end

		# `last_sep` is what followed the last item in `into`: nil when no separator did, so the list has
		# ended; a separator token, so another item must follow; false when an optional one was left out
		def collect(into: [], trailing_sep: nil, leading_sep: nil, last_sep: false, &block)
			while true
				break if trailing_sep && last_sep.nil?

				if leading_sep
					sep_tk = (Array === leading_sep) ? maybe_one_of(*leading_sep) : maybe(leading_sep)
					break if sep_tk.nil?

					val = yield(sep_tk)

					insert = if Node === val
						val.leading = Token::Punctuation(sep_tk)
						val
					else
						[sep_tk, val]
					end

				elsif trailing_sep
					val = last_sep ? yield : maybe { yield }
					break if val.nil?

					last_sep = sep_tk = (Array === trailing_sep) ? maybe_one_of(*trailing_sep) : maybe(trailing_sep)

					insert = if Node === val
						val.trailing = Token::Punctuation(sep_tk) if sep_tk
						val
					else
						[val, sep_tk]
					end

				else
					val = maybe { yield }
					break if val.nil?

					insert = val
				end

				into << insert
			end

			into
		end

		def token_span_from(*spans)
			spans.compact!
			i, len = 0, spans.length
			start_pos, end_pos = nil
			tokens = []
			while i < len
				tok, beg, fin = spans[i]
				(Array === tok) ? (tokens.concat(tok)) : (tokens << tok)
				start_pos = beg if i == 0 # first iteration
				end_pos = fin if i == (len - 1) # last iteration

				i += 1
			end

			[tokens, start_pos, end_pos]
		end

		# Access the current token type in the lexer stream.
		# Reads but doesn't consume the token at the head of the buffer.
		def current_token
			buf = ensure_buffer
			buf[0][0]
		end

		# SQLite lexes any number holding a "_" as a QNUMBER, and accepts it as a term only if every
		# "_" sits between two digits - hex digits after 0x
		def require_qnumber
			value = current_value
			misplaced = value.match?(/\A0x/i) ? /(?<!\h)_|_(?!\h)/ : /(?<!\d)_|_(?!\d)/
			expected!(:INTEGER, :FLOAT) if value.match?(misplaced)
			require :QNUMBER
		end

		def statement_end?
			current_token.nil? || current_token == :SEMI
		end

		def subquery_start?
			current_token in :SELECT | :VALUES | :WITH
		end

		# Access the string value for the current token.
		# Reads but doesn't consume the start_pos and end_pos values at the head of the buffer.
		def current_value
			buf = ensure_buffer
			sql = @lexer.sql
			_tk, beg, fin = buf[0]

			sql.byteslice(beg, (fin - beg))
		end

		# Peek at the next `n` tokens in the lexer stream.
		# Does not advance the lexer cursor and does not consider the current token.
		def peek(n = 1)
			buf = ensure_buffer(n + 1)
			return buf[1][0] if n == 1 # symbol element of the 2nd token

			[].tap do |a|
				i = 1
				while i <= n
					tok, * = buf[i]
					a << tok
					i += 1
				end
			end
		end

		# Advance the implicit cursor pointing to the first token in the buffer by `n` tokens.
		# Returns the new token at the head of the buffer.
		def advance
			ensure_buffer
			token = @peek_buffer.shift
			@last_consumed_fin = token[2]
			@last_consumed_token = token[0]
			token
		end

		# Ensure that the `@peek_buffer` has at least `size` tokens.
		# Note: the buffer is a nested array of `[token, start_pos, end_pos]` triples
		def ensure_buffer(size = 1)
			lexer = @lexer
			@peek_buffer.tap do |buf|
				while buf.size < size
					token = lexer.next_token
					if token == :WINDOW || token == :OVER || token == :FILTER
						token = contextual_keyword(token, buf.empty? ? @last_consumed_token : buf.last[0])
					end
					buf << [token, lexer.anchor, lexer.cursor].freeze
				end
			end
		end

		# Like SQLite's tokenize.c, decide from the tokens around them whether WINDOW, OVER and FILTER are
		# keywords here or names: WINDOW only before `name AS`, OVER only after `)` and before `(` or a
		# name, FILTER only after `)` and before `(`
		def contextual_keyword(token, previous)
			following, after = lex_ahead
			keyword =
				case token
				when :WINDOW then name_token?(following) && after == :AS
				when :OVER then previous == :RP && (following == :LP || name_token?(following))
				when :FILTER then previous == :RP && following == :LP
				end
			keyword ? token : :ID
		end

		# The types of the two tokens after the one just lexed, leaving the lexer where it was
		def lex_ahead
			cursor, anchor = @lexer.cursor, @lexer.anchor
			[@lexer.next_token, @lexer.next_token]
		ensure
			@lexer.cursor, @lexer.anchor = cursor, anchor
		end

		# What SQLite's tokenize.c counts as a name when looking around WINDOW and OVER
		def name_token?(token)
			(token in :ID | :STRING | :WINDOW | :OVER) || JOIN_KEYWORDS.include?(token) || TOKEN_FALLBACKS.include?(token)
		end

		def expected!(*expected)
			token, beg, fin = ensure_buffer[0]
			throw :ERROR, ErrorMessage.new(@lexer.sql, token, beg, fin, expected)
		end
	end
end
