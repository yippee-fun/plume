# frozen_string_literal: true

module Plume
	class Node < Literal::Struct
		extend Union::Types

		Stringy = _Union(String, Symbol)

		prop :full_source, _Nilable(String)
		prop :leading, _Nilable(Token)
		prop :trailing, _Nilable(Token)

		# A collation's name, upcased as a symbol. A symbol cannot hold bytes that
		# are not valid UTF-8, so a name with those stays the string it was
		def self.collation_name(name) = name&.valid_encoding? ? name.to_sym.upcase : name

		def self.inspectable(*props)
			@inspectable_props ||= Set.new
			@inspectable_props.merge(props)
		end

		def self.all_inspectable_props
			ancestors.reduce(Set.new) do |all_props, ancestor|
				if (props = ancestor.instance_variable_get(:@inspectable_props))
					all_props.merge(props)
				else
					all_props
				end
			end
		end

		def inspectable_props
			all_inspectable_props = self.class.all_inspectable_props
			all_inspectable_props.map do |prop|
				val = __send__(prop)
				next if val.nil? || (val.respond_to?(:empty?) && val.empty?)

				[prop, val]
			end.tap(&:compact!)
		end

		alias_method :full_inspect, :inspect
		def inspect
			return "#<#{self.class.name}:#{object_id}>" if inspectable_props.empty?

			prop_values = inspectable_props.map do |prop, val|
				"#{prop}=#{val.inspect}"
			end

			"#<#{self.class.name}:#{object_id} #{prop_values&.join(", ")}>"
		end

		def pretty_please(pp)
			pp.push "#{self.class.name}("
			pp.map(inspectable_props) do |prop, val|
				"#{prop} = #{pp.capture { pp.prettify(val) }}"
			end
			pp.push ")"
		end

		# Direct child nodes in property declaration order. Arrays of nodes are flattened in
		def children
			self.class.literal_properties.each_with_object([]) do |property, kids|
				value = instance_variable_get(:"@#{property.name}")
				case value
				when Node then kids << value
				when Array then value.each { |v| kids << v if Node === v }
				end
			end
		end

		# Yields every node in the subtree depth-first, parents before their children,
		# along with the parent (nil for the receiver). Without recursing, so a tree as
		# deep as SQLite allows does not run out of stack
		def walk(parent = nil)
			return enum_for(:walk, parent) unless block_given?

			stack = [[self, parent]]
			while (node, up = stack.pop)
				yield node, up
				node.children.reverse_each { |child| stack << [child, node] }
			end
			self
		end

		def each_node(&block)
			return enum_for(:each_node) unless block

			walk { |node, _parent| yield node }
		end

		# Byte range `[beg, fin]` of the source this node was parsed from, spanning every token
		# in its subtree. Separators the node merely carries (`leading`/`trailing`) are left out.
		# Nil for nodes built by hand with `.new`
		def location
			beg = fin = nil
			each_token_span do |_tok, b, f|
				beg = b if beg.nil? || b < beg
				fin = f if fin.nil? || f > fin
			end
			[beg, fin].freeze if beg
		end

		def to_sql = Printer.print(self)

		def source_text
			return unless @full_source && (loc = location)

			@full_source.byteslice(loc[0], loc[1] - loc[0])
		end

		def each_token_span(&block)
			instance_variables.each do |ivar|
				next if ivar == :@leading || ivar == :@trailing

				case (value = instance_variable_get(ivar))
				when Node then value.each_token_span(&block)
				when Array
					if Token === value
						yield value
					else
						value.each do |v|
							if Node === v then v.each_token_span(&block)
							elsif Token === v then yield v
							end
						end
					end
				end
			end
		end

		# Uses the public readers, so token-backed values like `TableName#table` come out
		# as their parsed values rather than raw token spans
		def deconstruct_keys(keys)
			names = keys || self.class.literal_properties.map(&:name)
			names.each_with_object({}) do |name, h|
				h[name] = public_send(name) if respond_to?(name)
			end
		end

		def self.concrete(*a, full_source:, **kw)
			object = allocate
			object.__send__(:initialize, *a, full_source: full_source, **kw)
			object
		end

		# Every prop is type checked as a tree is built, so the check must never hash a node,
		# see Plume::Union
		def self.attribute(name, type, **kw)
			prop name, _Nilable(_Union(type, LiteralNil)), reader: kw.fetch(:reader, false), default: LiteralNil, **kw
			inspectable name
		end

		def self.token_names
			ancestors.each_with_object(Set.new) do |ancestor, names|
				names.merge(ancestor.instance_variable_get(:@token_names) || [])
			end
		end

		def self.token(name, **kw)
			(@token_names ||= Set.new) << name
			prop name, _Nilable(_Union(Token, LiteralNil)), reader: false, default: LiteralNil, **kw

			# Define methods for accessing token properties, like the original source text, parsed value, and location.
			# The token reader method is simply the parsed value of the token.
			class_eval <<-RUBY, __FILE__, __LINE__ + 1
				# frozen_string_literal: true

				def #{name}_src
					Token.source(@full_source, @#{name})
				end

				def #{name}_val
					Token.value(@full_source, @#{name})
				end
				alias_method :#{name}, :#{name}_val

				def #{name}_loc
					Token.location(@#{name})
				end

				def #{name}_tok
					Token.token(@#{name})
				end

				def #{name}_spn
					@#{name}
				end

				def #{name}?
					!(@#{name}.nil? || LiteralNil.equal?(@#{name}))
				end
			RUBY
		end

		def self.node(name, type, **kw)
			attribute name, _Nilable(type), **kw
			define_node_reader(name)
		end

		def self.nodes(name, type, **kw)
			attribute name, _Nilable(_Array(type)), **kw
			define_node_reader(name)
		end

		# Absent children read as nil rather than the LiteralNil default
		def self.define_node_reader(name)
			ivar = :"@#{name}"
			define_method(name) do
				value = instance_variable_get(ivar)
				LiteralNil.equal?(value) ? nil : value
			end
		end
	end
end
