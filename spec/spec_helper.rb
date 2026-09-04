# frozen_string_literal: true

require 'webmock/rspec'
require 'specgen'
require 'specgen/cli'

Dir[File.join(__dir__, 'support', '**', '*.rb')].each { |file| require file }

# The generator is a pure function of its input files. No example may reach
# the network, and WebMock turns any attempt into a failure.
WebMock.disable_net_connect!

RSpec.configure do |config|
  config.expect_with(:rspec) { |expectations| expectations.syntax = :expect }
  config.mock_with(:rspec) { |mocks| mocks.verify_partial_doubles = true }
  config.disable_monkey_patching!
  config.example_status_persistence_file_path = '.rspec_status'
  config.filter_run_when_matching :focus
  config.order = :random
  Kernel.srand config.seed
end
