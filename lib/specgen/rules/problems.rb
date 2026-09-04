# frozen_string_literal: true

module SpecGen
  module Rules
    # Collects everything wrong with the dictionaries and raises once, so a
    # run reports every conflict instead of the first one. The dictionaries
    # are our own data: a problem here is a bug to fix before the tool ships,
    # not user input to work around, and the load has to stop rather than
    # quietly keep the first of two synonyms.
    class Problems
      # One thing wrong with one dictionary.
      Issue = Struct.new(:file, :path, :message) do
        # @return [String] "roles.yml at $.roles.amount.names[2]: message"
        def to_s
          where = [file && File.basename(file), path && "at #{path}"].compact.join(' ')
          where.empty? ? message.to_s : "#{where}: #{message}"
        end
      end

      # @return [Array<Issue>] in the order they were found
      attr_reader :issues

      def initialize
        @issues = []
      end

      # @param message [String] what is wrong, in one sentence
      # @param file [String, nil] dictionary the problem is in
      # @param path [String, nil] JSONPath of the offending element
      # @return [void]
      def add(message, file: nil, path: nil)
        @issues << Issue.new(file, path, message)
        nil
      end

      # @return [Boolean]
      def any?
        !@issues.empty?
      end

      # @raise [RulesError] listing every issue, when there is at least one
      # @return [void]
      def raise!
        return unless any?

        raise RulesError, [headline, *@issues.map { |issue| "  #{issue}" }].join("\n")
      end

      private

      def headline
        "#{issues.size} #{issues.size == 1 ? 'problem' : 'problems'} in the rules dictionaries:"
      end
    end
  end
end
