# frozen_string_literal: true

module SpecGen
  # Provider-neutral intermediate representation of a payment provider.
  #
  # Analyzers read the loaded spec and fill their part of a ProviderProfile;
  # generators read the profile and never touch the spec. Every inferred
  # value is wrapped in a Derived that carries its source and confidence, so
  # report.md can explain each decision. The vocabulary (field roles,
  # operation roles, internal statuses, error actions) is closed and lives in
  # IR::Roles; a value outside it is a programmer error, not user input, and
  # raises ArgumentError at construction time.
  #
  # Two conventions hold across all types:
  #
  # * `nil` means "absent in the spec / not applicable"; `Derived.unknown`
  #   means "an analyzer looked and could not derive it". Only the latter is
  #   something the report has to warn about.
  # * `to_h` returns members in definition order with nested objects
  #   converted, so serialised profiles are byte-for-byte stable.
  module IR
  end
end

require_relative 'ir/node'
require_relative 'ir/roles'
require_relative 'ir/derived'
require_relative 'ir/warning'
require_relative 'ir/info'
require_relative 'ir/server'
require_relative 'ir/auth'
require_relative 'ir/required_when'
require_relative 'ir/field'
require_relative 'ir/schema'
require_relative 'ir/parameter'
require_relative 'ir/response'
require_relative 'ir/operation'
require_relative 'ir/status_mapping'
require_relative 'ir/error_rule'
require_relative 'ir/signature_profile'
require_relative 'ir/webhook_event'
require_relative 'ir/webhook'
require_relative 'ir/units'
require_relative 'ir/idempotency'
require_relative 'ir/provider_profile'
