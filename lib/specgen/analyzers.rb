# frozen_string_literal: true

module SpecGen
  # Third pipeline stage. Each analyzer reads the loaded Document and fills
  # one part of the IR::ProviderProfile: identity, auth, operations, fields,
  # amounts, statuses, webhooks.
  #
  # Analyzers are independent by contract (docs/IR.md): none of them reads
  # what another one wrote, so the order they run in can never change the
  # output. Whatever an analyzer cannot derive becomes a `Derived.unknown`
  # plus a `profile.warn`, never a plausible-looking guess: a silent mistake
  # in a payment integration costs more than one manual step.
  module Analyzers
  end
end

require_relative 'analyzers/base'
require_relative 'analyzers/environment_detector'
require_relative 'analyzers/security_requirements'
require_relative 'analyzers/schema_naming'
require_relative 'analyzers/note'
require_relative 'analyzers/constraint_reader'
require_relative 'analyzers/schema_flattener'
require_relative 'analyzers/condition_reader'
require_relative 'analyzers/schema_reader'
require_relative 'analyzers/content_reader'
require_relative 'analyzers/parameter_reader'
require_relative 'analyzers/operation_role'
require_relative 'analyzers/auth_scheme'
require_relative 'analyzers/info_analyzer'
require_relative 'analyzers/auth_analyzer'
require_relative 'analyzers/operation_analyzer'
require_relative 'analyzers/schema_analyzer'
require_relative 'analyzers/runner'
