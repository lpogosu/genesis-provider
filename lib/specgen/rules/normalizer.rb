# frozen_string_literal: true

module SpecGen
  module Rules
    # Reduces a field or header name to the form the dictionaries are keyed
    # by: lower case, single underscores between words. "X-Payer-Phone",
    # "payerPhone" and "payer phone" all become "payer_phone", so a synonym
    # has to be curated once instead of once per spelling, and a collision
    # between two roles is caught across spellings, not only within one.
    module Normalizer
      ACRONYM_BOUNDARY = /([A-Z]+)([A-Z][a-z])/
      CAMEL_BOUNDARY = /([a-z\d])([A-Z])/
      SEPARATOR = /[^a-z0-9]+/
      EDGES = /\A_+|_+\z/

      # @param name [String, Symbol, nil]
      # @return [String] normalized name; empty when nothing is left of it
      def self.call(name)
        name.to_s
            .gsub(ACRONYM_BOUNDARY, '\1_\2')
            .gsub(CAMEL_BOUNDARY, '\1_\2')
            .downcase
            .gsub(SEPARATOR, '_')
            .gsub(EDGES, '')
      end

      # @param name [String, Symbol, nil]
      # @return [Array<String>] the words of the normalized name
      def self.tokens(name)
        call(name).split('_')
      end
    end
  end
end
