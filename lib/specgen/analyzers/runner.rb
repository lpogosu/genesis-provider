# frozen_string_literal: true

module SpecGen
  module Analyzers
    # Runs every analyzer over one document and returns the filled profile.
    #
    # The order is fixed for reproducibility only: analyzers are independent
    # by contract and none reads what another wrote, so the output would be
    # the same in any order. Keeping the list here, in one place, is what
    # lets `integrate analyze` and the generation pipeline share exactly the
    # same analysis stage.
    class Runner
      ORDER = [InfoAnalyzer, AuthAnalyzer, OperationAnalyzer, SchemaAnalyzer].freeze

      # @param document [SpecLoader::Document] spec with every `$ref` resolved
      # @param rules [Rules::Registry] the dictionaries
      # @param options [Hash] CLI options, string or symbol keyed
      # @return [IR::ProviderProfile] filled by every analyzer in ORDER
      def self.call(document:, rules:, options: {})
        profile = IR::ProviderProfile.new
        ORDER.each do |analyzer|
          analyzer.call(document: document, profile: profile, rules: rules, options: options)
        end
        profile
      end
    end
  end
end
