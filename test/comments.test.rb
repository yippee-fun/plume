# frozen_string_literal: true

SQL_WITH_COMMENTS = "-- nightly job\n/* v2 */ select a from t /* inside */ where b = 1 " \
	"/*controller='posts',action='index',traceparent='00-abc%2C1'*/; select 2 -- done"

test "comments are their own tokens, which parsing skips like spaces" do
	assert_equal Plume.tokenize("a /* c */ b -- d", skip_spaces: false), [:ID, :SPACE, :COMMENT, :SPACE, :ID, :SPACE, :COMMENT]
	assert_equal Plume.parse(SQL_WITH_COMMENTS).size, 2
end

test "comments come with their text and byte range" do
	assert_equal Plume.comments(SQL_WITH_COMMENTS).map { |c| [c.text, c.location, c.block?] }, [
		["-- nightly job", [0, 14], false],
		["/* v2 */", [15, 23], true],
		["/* inside */", [40, 52], true],
		["/*controller='posts',action='index',traceparent='00-abc%2C1'*/", [65, 127], true],
		["-- done", [138, 145], false],
	]
end

test "sqlcommenter tags are read, URL-encoded and escaped as the spec has it, and Rails' older format too" do
	assert_equal Plume.comments(SQL_WITH_COMMENTS)[3].tags, { "controller" => "posts", "action" => "index", "traceparent" => "00-abc,1" }
	assert_equal Plume.comments("/*name='it\\'s'*/").first.tags, { "name" => "it's" }
	assert_equal Plume.comments("/*application:Shop,controller:posts*/").first.tags, { "application" => "Shop", "controller" => "posts" }
	assert_equal Plume.comments("/* note: something, more */").first.tags, {}
	assert_equal Plume.comments("-- v2").first.tags, {}
end

test "to_sql keeps the comments around a statement when asked, and not those inside it" do
	first, second = Plume.parse(SQL_WITH_COMMENTS)

	assert_equal first.to_sql(comments: true), "-- nightly job\n/* v2 */ SELECT a FROM t WHERE b = 1 /*controller='posts',action='index',traceparent='00-abc%2C1'*/"
	assert_equal second.to_sql(comments: true), "SELECT 2 /* done */"
	assert_equal first.to_sql, "SELECT a FROM t WHERE b = 1"
	assert_equal Plume.parse([first, second].map { |s| s.to_sql(comments: true) }.join(";\n")).map(&:to_sql), [first.to_sql, second.to_sql]
end

test "a node built by hand has no comments to keep" do
	assert_equal Plume::LiteralExpression.new(value: 1).to_sql(comments: true), "1"
end
