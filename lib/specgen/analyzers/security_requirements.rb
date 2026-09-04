# frozen_string_literal: true

module SpecGen
  module Analyzers
    # Which security scheme the operations actually require, counted rather
    # than assumed.
    #
    # A spec may declare several schemes in `components.securitySchemes` and
    # use one of them. Counting follows the OpenAPI rule that an operation's
    # own `security` replaces the document-level one, and an empty list is a
    # deliberate "no credentials here" - an inbound webhook is the usual
    # case - so it votes for nothing and never means "the API is open".
    #
    # Ties are broken by the order the schemes are declared in: a stable
    # answer is worth more than a clever one, because the generated service
    # has to come out byte-identical on every run.
    class SecurityRequirements
      # @return [Hash{String => Integer}] operations requiring each scheme,
      #   in first-seen order
      attr_reader :counts
      # @return [Array<String>] JSONPaths of `security` values of a shape
      #   the caller should warn about
      attr_reader :bad_paths

      # @param root [Object] the document's `security`, nil when absent
      # @param root_path [String] JSONPath of it
      # @param operations [Array<Array(Object, String)>] per operation: its
      #   own `security` (nil when it declares none) and the JSONPath of it
      def initialize(root:, root_path:, operations: [])
        @counts = Hash.new(0)
        @scopes = {}
        @bad_paths = []
        count_all(list(root, root_path), operations)
      end

      # The scheme the most operations require.
      # @param names [Array<String>] candidates, in declaration order
      # @return [String, nil] nil when there are no candidates
      def winner(names)
        return nil if names.empty?

        names.each_with_index.min_by { |name, index| [-counts[name], index] }.first
      end

      # @param name [String] scheme name
      # @return [Array<String>] scopes the operations asked of it
      def scopes_for(name)
        @scopes.fetch(name, [])
      end

      # @return [Array<String>] every scheme name some operation requires
      def names
        counts.keys
      end

      private

      # An operation with no `security` of its own inherits the root one.
      def count_all(root, operations)
        required = operations.map { |security, path| security.nil? ? root : list(security, path) }
        required = [root] if required.empty?
        required.each { |entries| count(entries) }
      end

      def count(entries)
        entries.each do |entry|
          entry.each do |name, asked|
            key = name.to_s
            @counts[key] += 1
            @scopes[key] = scopes_for(key) | Array(asked).grep(String)
          end
        end
      end

      def list(value, path)
        return [] if value.nil?
        return bad(path) unless value.is_a?(Array)

        entries = value.grep(Hash)
        @bad_paths << path unless entries.size == value.size
        entries
      end

      def bad(path)
        @bad_paths << path
        []
      end
    end
  end
end
