# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in plume.gemspec
gemspec

gem "quickdraw", git: "https://github.com/joeldrapper/quickdraw.git", ref: "2c5929f79d1e529db2c32953a78eba063736b72a"

group :development do
	gem "rubocop", "1.70.0", platform: :ruby
	gem "simplecov", platform: :ruby
	gem "sqlite3", platforms: :ruby # a C extension, JRuby skips the tests that need it
	gem "debug", ">= 1.0.0", platforms: :ruby
end

# Editor tooling, which CI leaves out with BUNDLE_WITHOUT
group :editor do
	gem "solargraph", platform: :ruby
	gem "ruby-lsp", platform: :ruby
end
