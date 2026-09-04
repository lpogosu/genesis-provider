# frozen_string_literal: true

source 'https://rubygems.org'

ruby '>= 3.2'

# Runtime: CLI and the thin Rack layer. The OpenAPI parser is added later,
# once the loader stage is implemented.
gem 'rack', '~> 3.1'
gem 'thor', '~> 1.3'

group :development, :test do
  gem 'rspec', '~> 3.13'
  gem 'rubocop', '~> 1.60', require: false
  gem 'webmock', '~> 3.20'
end
