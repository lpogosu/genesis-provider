# frozen_string_literal: true

module SpecGen
  module Analyzers
    # Tells the sandbox of a provider from its production host.
    #
    # No spec states this formally: `servers[].description` is a free-text
    # label and a host name is just a name, so the only evidence available
    # is a word. The lexicon below is the vocabulary of the industry, not of
    # any one provider, which is why it lives in lib/ and not in rules/.
    #
    # Sandbox tokens are checked first on purpose: reading a production host
    # as a sandbox costs a failed test call, the opposite costs a real
    # payment.
    module EnvironmentDetector
      TOKENS = {
        sandbox: %w[sandbox test testing staging stage dev develop development demo uat preprod],
        production: %w[production prod live]
      }.freeze

      # A description is written for a human to classify the server; a host
      # name only happens to contain the word.
      DESCRIPTION_CONFIDENCE = 0.8
      HOST_CONFIDENCE = 0.7

      SCHEME = %r{\A[a-z][a-z0-9+.-]*://}i
      WORD_BOUNDARY = /[^a-z0-9]+/

      # Description first, host second.
      # @param url [String] server URL as written in the spec
      # @param description [String, nil] server description as written
      # @return [IR::Derived, nil] nil when no word names an environment and
      #   the caller has to warn
      def self.call(url:, description: nil)
        detect(description, 'description', DESCRIPTION_CONFIDENCE) ||
          detect(host_of(url), 'host', HOST_CONFIDENCE)
      end

      # @param text [String, nil] the text to read words from
      # @param where [String] what that text is, for the evidence line
      # @param confidence [Float] how much that place is worth
      # @return [IR::Derived, nil]
      def self.detect(text, where, confidence)
        found = token_hit(words_of(text))
        return nil if found.nil?

        environment, word = found
        evidence = "server #{where} #{text.inspect} contains #{word.inspect} -> #{environment}"
        IR::Derived.heuristic(environment, confidence: confidence, evidence: evidence)
      end

      # @param words [Array<String>]
      # @return [Array(Symbol, String), nil] environment and the word proving it
      def self.token_hit(words)
        TOKENS.each do |environment, tokens|
          hit = tokens.find { |token| words.include?(token) }
          return [environment, hit] unless hit.nil?
        end
        nil
      end

      # Authority part of the URL. Port, credentials and `{variables}` need
      # no special case: they fall out of the word split.
      # @param url [String, nil]
      # @return [String]
      def self.host_of(url)
        url.to_s.sub(SCHEME, '').split('/').first.to_s
      end

      # @param text [String, nil]
      # @return [Array<String>] lower-case ASCII words
      def self.words_of(text)
        text.to_s.downcase.split(WORD_BOUNDARY).reject(&:empty?)
      end
    end
  end
end
