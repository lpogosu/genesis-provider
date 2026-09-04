# frozen_string_literal: true

module SpecGen
  module Analyzers
    # What every analyzer is given and how it is run.
    #
    # The four inputs are the same everywhere: the resolved `document`, the
    # `profile` being filled, the `rules` dictionaries, and the CLI
    # `options`. Subclasses implement `#call` and nothing else about the
    # plumbing, so adding an analyzer is one file and one line in
    # analyzers.rb.
    #
    # The helpers here are the ones every analyzer needs to keep its
    # warnings actionable: a JSONPath pointing at the exact spec element a
    # decision came from, in the same notation an OpenAPI Overlay uses for
    # its targets, so a warning and its fix address the same place.
    class Base
      # Fixed fields of a Path Item Object that are operations (OpenAPI 3).
      HTTP_METHODS = %w[get put post delete options head patch trace].freeze

      # Builds the analyzer and runs it; takes what #initialize takes.
      # @return [Object] whatever the analyzer's #call returns
      def self.call(**)
        new(**).call
      end

      # @param document [SpecLoader::Document] spec with every `$ref` resolved
      # @param profile [IR::ProviderProfile] the profile to fill
      # @param rules [Rules::Registry, nil] dictionaries; explicitly nil for
      #   an analyzer that reads none
      # @param options [Hash] CLI options, string or symbol keyed
      def initialize(document:, profile:, rules:, options: {})
        @document = document
        @profile = profile
        @rules = rules
        @options = options || {}
      end

      # Reads the document and fills its part of the profile.
      # @return [IR::ProviderProfile]
      # @raise [NotImplementedError] always; subclasses override this
      def call
        raise NotImplementedError, "#{self.class} must implement #call"
      end

      protected

      # @return [SpecLoader::Document]
      attr_reader :document
      # @return [IR::ProviderProfile]
      attr_reader :profile
      # @return [Rules::Registry, nil]
      attr_reader :rules
      # @return [Hash]
      attr_reader :options

      # The resolved document. Empty when the root is not a mapping, so an
      # analyzer never raises on input the loader let through.
      # @return [Hash]
      def data
        document.data.is_a?(Hash) ? document.data : {}
      end

      # @param keys [Array<String, Integer>] key path from the document root
      # @return [String] e.g. "$.servers[0].url"
      def json_path(*keys)
        SpecLoader::JsonPath.build(keys)
      end

      # Every operation of the document, in the order the file declares
      # them. Path items and operations of the wrong shape are skipped: the
      # loader guarantees `paths` exists, not that every corner of it is an
      # object.
      # @yieldparam path [String] template, e.g. "/payouts/{id}"
      # @yieldparam http_method [String] lower case, one of HTTP_METHODS
      # @yieldparam operation [Hash] the Operation Object
      # @return [Enumerator] when called without a block
      def each_operation
        return enum_for(:each_operation) unless block_given?

        paths = data['paths']
        return unless paths.is_a?(Hash)

        paths.each do |path, item|
          next unless item.is_a?(Hash)

          item.each do |http_method, operation|
            next unless HTTP_METHODS.include?(http_method) && operation.is_a?(Hash)

            yield(path, http_method, operation)
          end
        end
      end

      # Options arrive symbol-keyed from tests and string-keyed from Thor;
      # an analyzer should not have to know which.
      # @param name [Symbol]
      # @return [Object, nil]
      def option(name)
        options.key?(name) ? options[name] : options[name.to_s]
      end
    end
  end
end
