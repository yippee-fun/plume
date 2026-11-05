# frozen_string_literal: true

module Plume
	# Stand-ins for what yippee-fun/literal#391 fixes in Literal itself, so that Plume can run
	# in Ractors before that is released. They apply to Plume's own classes only, and each one
	# stays off when the installed Literal does not need it. Once Plume requires a Literal
	# with that fix, delete this file, its require and extend in plume.rb and its prepend in Node
	module LiteralPatches
		# A Mutex can never be shared between Ractors, and Literal keeps one in every schema
		SCHEMA_HOLDS_MUTEX = Literal::Properties::Schema.new.instance_variable_defined?(:@mutex)

		# Literal 1.9.0 calls the block of a `_Deferred` on every check. Unreleased Literal caches
		# the result instead, but writes to the type on every check while doing so - and a frozen
		# one then raises FrozenError, materialized or not
		DEFERRED_WRITES_ON_CHECK = begin
			probe = Literal::Types::DeferredType.new { Integer }
			probe === 1
			probe.freeze === 1
			false
		rescue FrozenError
			true
		end

		# A frozen schema with the same readers, which `make_shareable!` swaps in once the props
		# of a node class are all declared
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

			# Literal starts the schema of a subclass from a dup of its parent's
			def dup = Literal::Properties::Schema.new(properties_index: @properties_index.dup, sorted_properties: @sorted_properties.dup)
		end

		module NodeSchema
			def literal_properties = @shareable_literal_properties || super

			def make_shareable!
				@shareable_literal_properties = Plume.make_shareable(ShareableSchema.new(literal_properties))
				super
			end
		end

		# Only ever used when DEFERRED_WRITES_ON_CHECK, so this can rely on the caching version's ivars
		class Deferred < Literal::Types::DeferredType
			def materialize = frozen? ? frozen_type : super

			# JRuby takes an endless operator ending in "=" for a setter
			def ===(other)
				frozen? ? frozen_type === other : super
			end

			def >=(other, context: nil)
				frozen? ? Literal.subtype?(other, frozen_type, context:) : super
			end

			private

			def frozen_type = UNMATERIALIZED.equal?(@materialized) ? @block.call : @materialized
		end

		module Types
			def _Deferred(&) = Deferred.new(&)
		end
	end
end
