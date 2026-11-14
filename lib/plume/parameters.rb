# frozen_string_literal: true

module Plume
	# The bind parameters of one statement, numbered the way SQLite numbers them: `?` takes the
	# next number, `?N` takes N, and a name keeps the number it first got. `count` and `names`
	# are what `sqlite3_bind_parameter_count` and `sqlite3_bind_parameter_name` would answer
	class Parameters
		include Enumerable

		# One place a parameter appears. `name` is nil for a bare `?`
		Parameter = Data.define(:number, :name, :node)

		attr_reader :count, :names

		def initialize(statement)
			slots = {}
			@count = 0
			@parameters = variables(statement).map do |variable|
				name = variable.name
				number =
					if name == "?"
						@count += 1
					elsif (n = name[/\A\?(\d+)\z/, 1]&.to_i)
						slots[n] ||= name
						@count = n if n > @count
						n
					elsif (n = slots.key(name))
						n
					else
						slots[@count += 1] = name
						@count
					end
				Parameter.new(number:, name: (name == "?") ? nil : name, node: variable)
			end.freeze
			@names = Array.new(@count) { |i| slots[i + 1] }.freeze
		end

		def each(&) = @parameters.each(&)

		def size = @parameters.size

		# The number a name was given, as `sqlite3_bind_parameter_index` answers it
		def index(name) = @names.index(name)&.+(1)

		private

		# SQLite numbers them as it reads them, which is not always the order of the tree
		def variables(statement)
			statement.each_node.grep(Variable).each_with_index.sort_by { |v, i| [v.location&.first || 0, i] }.map(&:first)
		end
	end
end
