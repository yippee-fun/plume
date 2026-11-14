# frozen_string_literal: true

require "digest"

module Plume
	# A short, stable hash of what statements mean, which stays the same across the values in them
	# and how they are spelled: constants (as `Normalize` finds them) and parameters all count as one
	# `?`, an IN list or VALUES of nothing but those counts as one item or row, and token positions,
	# keyword and name case and redundant parentheses do not count at all. It is the same in every
	# process and Ruby, unlike `Object#hash`
	module Fingerprint
		extend self

		SKIPPED = %i[full_source leading trailing].freeze
		Field = Data.define(:name)

		def of(statements)
			Digest::SHA256.hexdigest(stream(Array(statements)).join)[0, 16]
		end

		private

		# The tree walked in order without recursing, each item length-prefixed so none runs into the next
		def stream(statements)
			constants = Set.new.compare_by_identity
			statements.each { |s| constants.merge(Normalize.constants(s)) }
			fields = Hash.new { |h, klass| h[klass] = (klass.literal_properties.map(&:name) - klass.token_names.to_a - SKIPPED) | klass.all_inspectable_props.to_a }

			out = []
			emit = -> (tag, text) { out << "#{tag}#{text.bytesize}:#{text}" }
			pending = statements.reverse.map { |s| [s, nil] }
			while (item, field = pending.pop)
				case item
				when Variable then emit.("?", "")
				when Node
					next emit.("?", "") if constants.include?(item)

					if ParentheticalExpression === item && Node === item.contents
						pending << [item.contents, field]
						next
					end
					emit.("n", item.class.name)
					fields[item.class].reverse_each do |name|
						value = node_field(item, name)
						value = collapse(value, item, name, constants)
						pending << [value, name] << [Field.new(name), nil]
					end
				when Array
					emit.("l", item.size.to_s)
					item.reverse_each { |element| pending << [element, field] }
				when Field then emit.("f", item.name.name)
				when String
					# Names are matched without regard to ASCII case, the values a statement keeps (a DEFAULT) are not
					emit.("s", (field == :value) ? item.b : item.b.downcase(:ascii))
				when Symbol then emit.("y", item.name.upcase)
				when LiteralNil, nil then emit.("0", "")
				else emit.("v", item.inspect)
				end
			end
			out
		end

		def node_field(node, name)
			if ParentheticalExpression === node && name == :value
				node.contents
			else
				node.respond_to?(name) ? node.public_send(name) : node.instance_variable_get(:"@#{name}")
			end
		end

		# Only the shape of a list of values counts, not how many values it has
		def collapse(value, node, name, constants)
			return value unless Array === value && value.size > 1

			if ParentheticalExpression === node && name == :value && value.all? { |v| placeholder?(v, constants) }
				value.first(1)
			elsif ValuesClause === node && name == :rows && value.all? { |row| row.values.all? { |v| placeholder?(v, constants) } }
				value.uniq { |row| row.values.size }
			else
				value
			end
		end

		def placeholder?(node, constants) = Variable === node || constants.include?(node)
	end
end
