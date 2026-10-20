# frozen_string_literal: true

module Plume
	class Node < Literal::Struct
		extend Union::Types

		Stringy = _Union(String, Symbol)

		# Literal keeps the props of a class in a Schema guarded by a Mutex, and a Mutex can never be
		# shared - so outside the main Ractor every node constructor raises. Once all props are
		# declared, `Plume.eager_load!` swaps in this frozen stand-in, which has the same readers
		class ShareableSchema
			include Enumerable

			attr_reader :properties_index

			def initialize(schema)
				@properties_index = schema.properties_index.dup
				@sorted_properties = schema.to_a
			end

			def [](key) = @properties_index[key]
			def each(&) = @sorted_properties.each(&)
			def size = @sorted_properties.size
			def empty? = @sorted_properties.empty?
			def <<(property) = raise(FrozenError, "cannot add #{property.name} after Plume.eager_load! has frozen the props")

			# Literal starts the schema of a subclass from a dup of its parent's
			def dup = Literal::Properties::Schema.new(properties_index: @properties_index.dup, sorted_properties: @sorted_properties.dup)
		end

		def self.literal_properties
			@shareable_literal_properties || super
		rescue => error
			raise unless defined?(Ractor::IsolationError) && Ractor::IsolationError === error

			raise Ractor::IsolationError, "#{name} is not shareable yet, call Plume.eager_load! from the main Ractor first " \
				"(or #{name}.make_shareable! for a class defined after it)"
		end

		def self.make_shareable!
			@shareable_literal_properties = Plume.make_shareable(ShareableSchema.new(literal_properties))
			Plume.make_shareable(@inspectable_props)
			Plume.make_shareable(@token_names)
			self
		end

		prop :full_source, _Nilable(String)
		prop :leading, _Nilable(Token)
		prop :trailing, _Nilable(Token)

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
		# along with the parent (nil for the receiver)
		def walk(parent = nil, &block)
			return enum_for(:walk, parent) unless block

			yield self, parent
			children.each { |child| child.walk(self, &block) }
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

		# Absent children read as nil rather than the LiteralNil default. Evaluated from a string
		# because a method defined with a block cannot be called from another Ractor
		def self.define_node_reader(name)
			class_eval <<-RUBY, __FILE__, __LINE__ + 1
				def #{name}
					LiteralNil.equal?(@#{name}) ? nil : @#{name}
				end
			RUBY
		end
	end
end
