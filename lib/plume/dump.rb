# frozen_string_literal: true

module Plume
	# Trees to and from plain hashes that JSON can carry, and back exactly: positions, keywords as
	# written and the source they point into all come through, so `location`, `source_text` and
	# `to_sql` answer as before. A node is its class under "node" and its props under their names,
	# a token is `[type, beg, fin, kind]`, and the source is kept once, at the root.
	# JSON has no symbols, binary strings or infinity, so those go out tagged: {"symbol" => "EQUALS"},
	# {"bytes" => "9e2e", "encoding" => "BINARY"} and {"float" => "Infinity"}
	module Dump
		extend self

		TOKEN_PROPS = %i[leading trailing].freeze
		SENTINELS = { "LiteralFalse" => LiteralFalse }.freeze
		FLOATS = { "Infinity" => Float::INFINITY, "-Infinity" => -Float::INFINITY, "NaN" => Float::NAN }.freeze

		# Built without recursing, like `walk`, so the deepest tree SQLite takes can be dumped.
		# Generating JSON that deep needs `max_nesting: false`
		def dump(node)
			return node.map { |n| dump(n) } if Array === node

			hashes = {}.compare_by_identity
			parents = {}.compare_by_identity
			node.walk do |n, up|
				hashes[n] = { "node" => n.class.name.delete_prefix("Plume::") }
				parents[n] = up
			end
			hashes.each do |n, hash|
				n.class.literal_properties.each do |property|
					name = property.name
					value = n.instance_variable_get(:"@#{name}")
					next if LiteralNil.equal?(value)
					# A node shares its parent's source unless it was built by hand or brought in from elsewhere
					next if name == :full_source && !n.equal?(node) && value == parents[n].full_source

					hash[name.name] =
						if token?(n.class, name) then dump_token(value)
						elsif Node === value then hashes[value]
						elsif Array === value then value.map { |v| (Node === v) ? hashes[v] : dump_value(v) }
						else
							dump_value(value)
						end
				end
			end
			hashes[node]
		end

		def load(hash)
			return hash.map { |h| load(h) } if Array === hash

			# Parents before children, so building them backwards has every child ready
			order = []
			stack = [[hash, nil]]
			while (h, source = stack.pop)
				source = load_value(h["full_source"]) if h.key?("full_source")
				order << [h, source]
				h.each_value do |v|
					if Hash === v && v.key?("node") then stack << [v, source]
					elsif Array === v then v.each { |e| stack << [e, source] if Hash === e && e.key?("node") }
					end
				end
			end

			built = {}.compare_by_identity
			order.reverse_each { |h, source| built[h] = load_node(h, source, built) }
			built[hash]
		end

		private

		def token?(klass, name) = TOKEN_PROPS.include?(name) || klass.token_names.include?(name)

		def dump_token(tuple)
			return nil if tuple.nil?

			type, beg, fin, kind = tuple
			[(Array === type) ? type.map(&:name) : type.name, beg, fin, kind.name]
		end

		def load_token(array)
			return nil if array.nil?

			type, beg, fin, kind = array
			[(Array === type) ? type.map(&:to_sym) : type.to_sym, beg, fin, kind.to_sym]
		end

		def dump_value(value)
			case value
			when Symbol then { "symbol" => value.name }
			when String
				if value.encoding == Encoding::BINARY || !value.valid_encoding?
					{ "bytes" => value.unpack1("H*"), "encoding" => value.encoding.name }
				else
					value
				end
			when Float then value.finite? ? value : { "float" => value.to_s }
			when Integer, true, false, nil then value
			when Array then value.map { |v| dump_value(v) }
			else
				name = SENTINELS.key(value) or raise ArgumentError, "cannot dump #{value.inspect}"
				{ "sentinel" => name }
			end
		end

		def load_value(value)
			case value
			when Array then value.map { |v| load_value(v) }
			when Hash
				if value.key?("symbol") then value["symbol"].to_sym
				elsif value.key?("bytes") then [value["bytes"]].pack("H*").force_encoding(value["encoding"])
				elsif value.key?("float") then FLOATS.fetch(value["float"])
				elsif value.key?("sentinel") then SENTINELS.fetch(value["sentinel"])
				else
					raise ArgumentError, "cannot load #{value.inspect}"
				end
			else value
			end
		end

		def load_node(hash, source, built)
			name = hash.fetch("node")
			klass = Plume.const_get(name, false) if name.match?(/\A[A-Z]\w*\z/) && Plume.const_defined?(name, false)
			raise ArgumentError, "#{name.inspect} is not a node" unless Class === klass && klass <= Node

			props = { full_source: source }
			hash.each do |key, value|
				next if key == "node" || key == "full_source"

				name = key.to_sym
				props[name] =
					if token?(klass, name) then load_token(value)
					elsif Hash === value && value.key?("node") then built.fetch(value)
					elsif Array === value then value.map { |v| (Hash === v && v.key?("node")) ? built.fetch(v) : load_value(v) }
					else
						load_value(value)
					end
			end
			node = klass.allocate
			node.__send__(:initialize, **props)
			node
		end
	end
end
