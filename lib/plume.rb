# frozen_string_literal: true

require "plume/version"
require "literal"
require "plume/union"

module Plume
	extend Literal::Types
	extend Union::Types

	# JRuby and TruffleRuby have no Ractors, so there is nothing to make shareable for
	def self.make_shareable(obj) = defined?(Ractor) ? Ractor.make_shareable(obj) : obj

	autoload :Lexer, "plume/lexer"
	autoload :Parser, "plume/parser"
	autoload :Token, "plume/ast/token"
	autoload :SQLiteGrammar, "plume/sqlite_grammar"
	autoload :Catalog, "plume/catalog"
	autoload :Printer, "plume/printer"
	autoload :Analysis, "plume/analysis"

	autoload :BinaryExpression, "plume/ast/binary_expression"
	autoload :ParentheticalExpression, "plume/ast/parenthetical_expression"
	autoload :CaseCondition, "plume/ast/case_condition"
	autoload :CaseExpression, "plume/ast/case_expression"
	autoload :CastExpression, "plume/ast/cast_expression"
	autoload :CheckColumnConstraint, "plume/ast/check_column_constraint"
	autoload :CheckTableConstraint, "plume/ast/check_table_constraint"
	autoload :CollateColumnConstraint, "plume/ast/collate_column_constraint"
	autoload :CollationExpression, "plume/ast/collation_expression"
	autoload :ColumnConstraint, "plume/ast/column_constraint"
	autoload :ColumnDefinition, "plume/ast/column_definition"
	autoload :ColumnName, "plume/ast/column_name"
	autoload :ColumnType, "plume/ast/column_type"
	autoload :ConflictClause, "plume/ast/conflict_clause"
	autoload :CreateTableStatement, "plume/ast/create_table_statement"
	autoload :CreateViewStatement, "plume/ast/create_view_statement"
	autoload :DefaultColumnConstraint, "plume/ast/default_column_constraint"
	autoload :EmptyFunctionArgument, "plume/ast/empty_function_argument"
	autoload :Expression, "plume/ast/expression"
	autoload :ForeignKeyAction, "plume/ast/foreign_key_action"
	autoload :ForeignKeyClause, "plume/ast/foreign_key_clause"
	autoload :ForeignKeyColumnConstraint, "plume/ast/foreign_key_column_constraint"
	autoload :ForeignKeyTableConstraint, "plume/ast/foreign_key_table_constraint"
	autoload :FrameBoundary, "plume/ast/frame_boundary"
	autoload :FrameSpec, "plume/ast/frame_spec"
	autoload :FunctionArguments, "plume/ast/function_arguments"
	autoload :FunctionReference, "plume/ast/function_reference"
	autoload :GeneratedAsColumnConstraint, "plume/ast/generated_as_column_constraint"
	autoload :IndexedColumn, "plume/ast/indexed_column"
	autoload :JoinOnConstraint, "plume/ast/join_on_constraint"
	autoload :JoinUsingConstraint, "plume/ast/join_using_constraint"
	autoload :LikeExpression, "plume/ast/like_expression"
	autoload :LiteralFalse, "plume/ast/literal_false"
	autoload :LiteralNil, "plume/ast/literal_nil"
	autoload :LiteralValue, "plume/ast/literal_value"
	autoload :MatchClause, "plume/ast/match_clause"
	autoload :NoOpColumnConstraint, "plume/ast/noop_column_constraint"
	autoload :NoOpTableConstraint, "plume/ast/noop_table_constraint"
	autoload :Node, "plume/ast/node"
	autoload :NotLikeExpression, "plume/ast/not_like_expression"
	autoload :NotNullColumnConstraint, "plume/ast/not_null_column_constraint"
	autoload :NullColumnConstraint, "plume/ast/null_column_constraint"
	autoload :OrderingTerm, "plume/ast/ordering_term"
	autoload :OverClause, "plume/ast/over_clause"
	autoload :PrimaryKeyColumnConstraint, "plume/ast/primary_key_column_constraint"
	autoload :PrimaryKeyTableConstraint, "plume/ast/primary_key_table_constraint"
	autoload :RaiseExpression, "plume/ast/raise_expression"
	autoload :ResultColumn, "plume/ast/result_column"
	autoload :SelectStatement, "plume/ast/select_statement"
	autoload :StarFunctionArgument, "plume/ast/star_function_argument"
	autoload :StarResultColumn, "plume/ast/star_result_column"
	autoload :StrictTableOption, "plume/ast/strict_table_option"
	autoload :TableConstraint, "plume/ast/table_constraint"
	autoload :TableName, "plume/ast/table_name"
	autoload :TableOption, "plume/ast/table_option"
	autoload :TernaryExpression, "plume/ast/ternary_expression"
	autoload :UnaryExpression, "plume/ast/unary_expression"
	autoload :UniqueColumnConstraint, "plume/ast/unique_column_constraint"
	autoload :UniqueTableConstraint, "plume/ast/unique_table_constraint"
	autoload :LiteralExpression, "plume/ast/literal_expression"
	autoload :Variable, "plume/ast/variable"
	autoload :WithoutRowidTableOption, "plume/ast/without_rowid_table_option"
	autoload :AlterTableStatement, "plume/ast/alter_table_statement"
	autoload :AnalyzeStatement, "plume/ast/analyze_statement"
	autoload :AttachStatement, "plume/ast/attach_statement"
	autoload :BeginStatement, "plume/ast/begin_statement"
	autoload :CommitStatement, "plume/ast/commit_statement"
	autoload :CreateIndexStatement, "plume/ast/create_index_statement"
	autoload :CreateTriggerStatement, "plume/ast/create_trigger_statement"
	autoload :CreateVirtualTableStatement, "plume/ast/create_virtual_table_statement"
	autoload :DetachStatement, "plume/ast/detach_statement"
	autoload :DropStatement, "plume/ast/drop_statement"
	autoload :ExplainStatement, "plume/ast/explain_statement"
	autoload :PragmaStatement, "plume/ast/pragma_statement"
	autoload :ReindexStatement, "plume/ast/reindex_statement"
	autoload :ReleaseStatement, "plume/ast/release_statement"
	autoload :RollbackStatement, "plume/ast/rollback_statement"
	autoload :SavepointStatement, "plume/ast/savepoint_statement"
	autoload :VacuumStatement, "plume/ast/vacuum_statement"
	autoload :Assignment, "plume/ast/assignment"
	autoload :ConflictResolution, "plume/ast/conflict_resolution"
	autoload :DeleteStatement, "plume/ast/delete_statement"
	autoload :InsertStatement, "plume/ast/insert_statement"
	autoload :ReturningClause, "plume/ast/returning_clause"
	autoload :UpdateStatement, "plume/ast/update_statement"
	autoload :UpsertClause, "plume/ast/upsert_clause"
	autoload :CommonTableExpression, "plume/ast/common_table_expression"
	autoload :CompoundSelect, "plume/ast/compound_select"
	autoload :ExistsExpression, "plume/ast/exists_expression"
	autoload :Join, "plume/ast/join"
	autoload :JoinClause, "plume/ast/join_clause"
	autoload :JoinOperator, "plume/ast/join_operator"
	autoload :ParentheticalSource, "plume/ast/parenthetical_source"
	autoload :SelectCore, "plume/ast/select_core"
	autoload :SubqueryExpression, "plume/ast/subquery_expression"
	autoload :SubquerySource, "plume/ast/subquery_source"
	autoload :TableFunction, "plume/ast/table_function"
	autoload :ValuesClause, "plume/ast/values_clause"
	autoload :ValuesRow, "plume/ast/values_row"
	autoload :WindowDefinition, "plume/ast/window_definition"
	autoload :WithClause, "plume/ast/with_clause"

	SyntaxError = Class.new(StandardError)

	def self.tokenize(str, with_values: false, skip_spaces: true)
		lex = Lexer.new(str, skip_spaces: skip_spaces)
		[].tap do |tokens|
			while (token = lex.next_token)
				tokens << (with_values ? [token, lex.value] : token)
			end
		end
	end

	# Loads everything that is otherwise autoloaded and freezes what the node classes know
	# about their props, which is what lets Plume run inside Ractors. Call it from the main
	# Ractor before starting any. Node classes cannot get new props afterwards
	def self.eager_load!
		# SQLiteGrammar is a development tool which pulls in net/http
		(constants - [:SQLiteGrammar]).each { |name| const_get(name) if autoload?(name) }
		Analysis::Resolver
		# Node constructors and type errors reach for these, and Ruby 3.3 cannot autoload outside the main Ractor.
		# Not every Literal version has all of them
		%i[Null TypeError ArgumentError].each { |name| Literal.const_get(name) if Literal.const_defined?(name) }
		# Literal versions that cache a `_Deferred` do so on first use, which a frozen one cannot do.
		# Each node's schema then shares Expression with the rest of its prop types
		Expression === nil
		make_shareable(Token::Tuple)
		constants.each do |name|
			klass = const_get(name)
			klass.make_shareable! if Class === klass && klass <= Node
		end
		true
	end

	def self.parse(sql)
		Parser.new(sql).parse
	end

	# The line of `sql` holding bytes `beg...fin`, with a caret underneath them
	def self.excerpt(sql, beg, fin)
		src = sql.b # positions are byte offsets
		line_start = (beg.zero? ? nil : src.rindex("\n", beg - 1))&.+(1) || 0
		line_end = src.index("\n", beg) || src.bytesize
		line = src.byteslice(line_start, line_end - line_start).force_encoding(Encoding::UTF_8)
		caret = (" " * (beg - line_start)) + ("^" * [fin - beg, 1].max)
		"  #{line}\n  #{caret}"
	end

	def self.reads(...) = Analysis.reads(...)
	def self.access(...) = Analysis.access(...)
end
