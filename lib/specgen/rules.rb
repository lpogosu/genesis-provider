# frozen_string_literal: true

require_relative 'rules/normalizer'
require_relative 'rules/problems'
require_relative 'rules/duplicate_keys'
require_relative 'rules/document'
require_relative 'rules/checks'
require_relative 'rules/book'
require_relative 'rules/roles_book'
require_relative 'rules/statuses_book'
require_relative 'rules/currencies_book'
require_relative 'rules/signatures_book'
require_relative 'rules/idempotency_book'
require_relative 'rules/operations_book'
require_relative 'rules/auth_book'
require_relative 'rules/method_spec'
require_relative 'rules/contract_book'
require_relative 'rules/registry'

module SpecGen
  # The dictionaries under rules/: field-name synonyms for the roles of
  # IR::Roles, status synonyms, ISO 4217 exponents, webhook signature
  # profiles, idempotency header aliases, security schemes, the words and
  # weights that recognise an operation role, and the Provider::BaseService
  # contract itself.
  #
  # Supporting a new provider is meant to be new lines in these files and
  # never a new branch in lib/, which only holds if the data is trustworthy.
  # So the loader is strict: an unknown role, a synonym two roles claim, a
  # currency exponent outside ISO 4217, a contract role no method serves, a
  # key written twice in one file - each stops the run at startup, with
  # every problem in every dictionary listed at once.
  module Rules
    # @param dir [String] directory holding the dictionaries
    # @return [Registry] all eight dictionaries, validated
    # @raise [RulesError] listing every problem found
    def self.load(dir = SpecGen::RULES_DIR)
      Registry.load(dir)
    end
  end
end
