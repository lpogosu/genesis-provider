# frozen_string_literal: true

source 'https://rubygems.org'

ruby '>= 3.2'

# Runtime: CLI, the thin Rack layer and the JSON Schema validator that checks
# generated fixtures against the schemas of the source specification.
gem 'json_schemer', '~> 2.5'
gem 'rack', '~> 3.1'
gem 'thor', '~> 1.3'

group :development, :test do
  gem 'rspec', '~> 3.13'
  gem 'rubocop', '~> 1.60', require: false
  gem 'webmock', '~> 3.20'
end
