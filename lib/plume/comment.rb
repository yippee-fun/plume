# frozen_string_literal: true

require "uri"

module Plume
	# A comment in SQL, `-- like this` or `/* like this */`, with the byte range it takes up
	Comment = Data.define(:text, :location) do
		def block? = text.start_with?("/*")

		# What is between the markers
		def body
			block? ? text.delete_prefix("/*").delete_suffix("*/") : text.delete_prefix("--")
		end

		# The tags of a sqlcommenter comment - `/*controller='posts',action='index'*/`, which Rails'
		# query_log_tags writes too - or of its older `key:value` format. Empty for any other comment
		def tags
			parts = body.strip.split(/,(?=[\w.-]+(?:=|:))/)
			return {} if parts.empty?

			if parts.all? { |part| part.match?(/\A[\w.%-]+='.*'\z/m) }
				parts.to_h do |part|
					key, value = part.split("=", 2)
					[URI.decode_www_form_component(key), URI.decode_www_form_component(value[1..-2].gsub("\\'", "'"))]
				end
			elsif parts.all? { |part| part.match?(/\A[\w.-]+:[^,\s]+\z/) }
				parts.to_h { |part| part.split(":", 2) }
			else
				{}
			end
		end
	end

	module Comments
		extend self

		def in(sql)
			lexer = Lexer.new(sql)
			found = []
			while (token = lexer.next_token)
				found << Comment.new(text: lexer.value, location: [lexer.anchor, lexer.cursor].freeze) if token == :COMMENT
			end
			found
		end

		# The comments right before `node` and right after it, with only spaces between them and it
		def around(node)
			source = node.full_source
			loc = node.location
			return [[], []] unless source && loc

			tokens = Plume.tokenize(source, with_values: true, with_positions: true, skip_spaces: false)
			first = tokens.index { |_, _, beg, _| beg >= loc[0] }
			last = tokens.rindex { |_, _, _, fin| fin <= loc[1] }
			[gather(tokens, first - 1, -1), gather(tokens, last + 1, 1)]
		end

		private

		def gather(tokens, from, step)
			found = []
			i = from
			while i >= 0 && (token = tokens[i])
				type, text, beg, fin = token
				break unless type == :SPACE || type == :COMMENT

				found << Comment.new(text:, location: [beg, fin].freeze) if type == :COMMENT
				i += step
			end
			(step.negative? ? found.reverse : found)
		end
	end
end
