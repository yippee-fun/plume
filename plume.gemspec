# frozen_string_literal: true

require_relative "lib/plume/version"

Gem::Specification.new do |spec|
	spec.name = "plume"
	spec.version = Plume::VERSION
	spec.authors = ["Stephen Margheim", "Joel Drapper"]
	spec.email = ["stephen.margheim@gmail.com", "joel@drapper.me"]

	spec.summary = "Work with SQLite elegantly"
	spec.description = "Plume is a Ruby library that allows you to write SQLite's dialect of SQL with structured Ruby."
	spec.homepage = "https://github.com/fractaledmind/plume"
	spec.license = "MIT"
	spec.required_ruby_version = ">= 3.2.0"

	spec.metadata["homepage_uri"] = spec.homepage
	spec.metadata["source_code_uri"] = spec.homepage
	spec.metadata["changelog_uri"] = "https://github.com/fractaledmind/plume/releases"
	spec.metadata["funding_uri"] = "https://github.com/sponsors/fractaledmind"

	spec.files = Dir[
		"README.md",
		"LICENSE.txt",
		"lib/**/*.rb"
	]
	spec.require_paths = ["lib"]

	# Uncomment to register a new dependency of your gem
	spec.add_development_dependency "rake"
	spec.add_development_dependency "quickdraw"

	# For more information and examples about making a new gem, check out our
	# guide at: https://bundler.io/guides/creating_gem.html
end
