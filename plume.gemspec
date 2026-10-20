# frozen_string_literal: true

require_relative "lib/plume/version"

Gem::Specification.new do |spec|
	spec.name = "plume"
	spec.version = Plume::VERSION
	spec.authors = ["Stephen Margheim", "Joel Drapper"]
	spec.email = ["stephen.margheim@gmail.com", "joel@drapper.me"]

	spec.summary = "Parse, analyze and print SQLite's dialect of SQL"
	spec.description = "Plume parses any statement in SQLite's grammar into a syntax tree you can walk, change and print back to SQL, and tells you which tables and columns a statement reads and writes."
	spec.homepage = "https://github.com/yippee-fun/plume"
	spec.license = "MIT"
	spec.required_ruby_version = ">= 3.2.0"

	spec.metadata["homepage_uri"] = spec.homepage
	spec.metadata["source_code_uri"] = spec.homepage
	spec.metadata["changelog_uri"] = "https://github.com/yippee-fun/plume/blob/main/CHANGELOG.md"
	spec.metadata["funding_uri"] = "https://github.com/sponsors/fractaledmind"

	spec.files = Dir[
		"README.md",
		"LICENSE.txt",
		"lib/**/*.rb"
	]
	spec.require_paths = ["lib"]

	spec.add_dependency "literal", "~> 1.6"

	spec.add_development_dependency "rake"
	spec.add_development_dependency "quickdraw"

	# For more information and examples about making a new gem, check out our
	# guide at: https://bundler.io/guides/creating_gem.html
end
