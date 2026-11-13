# frozen_string_literal: true

require "json"

class Quickdraw::Test
	def through_json(dump) = JSON.parse(JSON.generate(dump))
end

test "a tree comes back from JSON exactly, positions and keywords as written included" do
	sql = "select distinct a as \"x\", x'9e2e', 1e999 from t indexed by i where b is not true limit 2"
	stmt = Plume.parse(sql).first
	back = Plume.load(through_json(stmt.dump))

	assert_equal back, stmt
	assert_equal back.to_sql, stmt.to_sql
	assert_equal back.each_node.map(&:location), stmt.each_node.map(&:location)
	assert_equal back.body.columns.last.source_text, "1e999"
	assert back.body.distinct
end

test "the source is kept once, at the root" do
	dump = Plume.parse("SELECT a FROM t").first.dump

	assert_equal dump["full_source"], "SELECT a FROM t"
	assert_equal dump["body"].key?("full_source"), false
	assert_equal dump["body"]["select_kw"], ["SELECT", 0, 6, "keyword"]
end

test "values JSON cannot hold go out tagged" do
	stmt = Plume.parse((+"SELECT x'ab', 1e999, -1e999, \"\xFF\"").force_encoding(Encoding::UTF_8)).first
	dump = stmt.dump

	assert_equal Plume.load(through_json(dump)).to_sql, stmt.to_sql
	assert_equal dump["full_source"], { "bytes" => (+"SELECT x'ab', 1e999, -1e999, \"\xFF\"").unpack1("H*"), "encoding" => "UTF-8" }
end

test "nodes built by hand, inside a parsed tree, keep having no source" do
	stmt = Plume.parse("SELECT a, 1 FROM t").first
	stmt.body.columns = [stmt.body.columns[0], Plume::ResultColumn.new(result: Plume::Variable.new(name: "?"))]
	back = Plume.load(through_json(stmt.dump))

	assert_equal back.to_sql, "SELECT a, ? FROM t"
	assert_equal back.body.columns[0].source_text, "a"
end

test "a list of statements dumps and loads as a list" do
	stmts = Plume.parse("SELECT 1; DELETE FROM t")

	assert_equal Plume.load(through_json(stmts.map(&:dump))).map(&:to_sql), ["SELECT 1", "DELETE FROM t"]
	assert_equal Plume::Dump.load(Plume::Dump.dump(stmts)), stmts
end

# JSON's own generator and parser recurse, so only the hashes are held to this
test "a tree too deep to recurse through dumps and loads" do
	stmt = Plume.parse("SELECT #{(["a"] * 6000).join(" OR ")}").first

	assert_equal Plume.load(stmt.dump).to_sql, stmt.to_sql
end

test "only node classes are loaded" do
	assert_raises(ArgumentError) { Plume.load({ "node" => "Parser" }) }
	assert_raises(ArgumentError) { Plume.load({ "node" => "::Kernel" }) }
	assert_raises(ArgumentError) { Plume.load({ "node" => "Nope" }) }
end
