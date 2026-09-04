# frozen_string_literal: true

module SpecGen
  module Rules
    # The vocabulary and the weights that turn a path plus a method plus an
    # operationId into an operation role.
    #
    # Nothing about recognising an endpoint lives in lib/: the words, the
    # weight of each signal and the thresholds are all data here, so tuning
    # the matcher is a diff in a YAML file and a test run, not a code
    # change. The loader is strict for the same reason the other books are -
    # a role nobody can ever match, or a weight of zero, would quietly bend
    # every generated integration.
    class OperationsBook < Book
      FILE = 'operations.yml'
      # The independent signals of the composite matcher, in the order the
      # evidence line lists them.
      SIGNALS = %i[operation_id path_tail path_resource http_method tag request_body
                   unsecured].freeze
      # Numbers that shape the decision rather than one signal. All but
      # `floor` are fractions; `floor` is an absolute score in weights.
      FRACTIONS = %i[partial minimum margin ceiling].freeze
      SCORING = (FRACTIONS + [:floor]).freeze
      # Word lists every role may carry.
      LISTS = %i[verbs nouns resources tail tags].freeze
      # :unmapped is the outcome of matching nothing, never an entry.
      ROLES = (IR::Roles::OPERATION - [:unmapped]).freeze
      FRACTION = (0.0..1.0)

      # @return [Array<Symbol>] described roles, in dictionary order
      def roles
        @entries.keys
      end

      # @param role [Symbol] one of ROLES
      # @return [Hash, nil] :verbs, :nouns, :resources, :tail, :tags,
      #   :http_methods, :tail_parameter, :request_body, :unsecured
      def entry(role)
        @entries[role]
      end

      # @param signal [Symbol] one of SIGNALS
      # @return [Integer] its weight
      def weight(signal)
        @weights.fetch(signal, 0)
      end

      # @param key [Symbol] one of SCORING
      # @return [Float]
      def scoring(key)
        @scoring.fetch(key, 0.0)
      end

      private

      def build
        @weights = load_weights
        @scoring = load_scoring
        @entries = load_roles
      end

      def load_weights
        weights = section('weights')
        report_unknown(weights.keys.map(&:to_sym) - SIGNALS, SIGNALS, path('weights'))
        SIGNALS.to_h { |signal| [signal, signal_weight(weights, signal)] }.freeze
      end

      def signal_weight(weights, signal)
        at = path('weights', signal)
        value = integer(weights[signal.to_s], "weight of #{signal}", at)
        return value if value.nil? || value.positive?

        complain("weight of #{signal} must be greater than zero", at)
        nil
      end

      def load_scoring
        scoring = section('scoring')
        report_unknown(scoring.keys.map(&:to_sym) - SCORING, SCORING, path('scoring'))
        values = FRACTIONS.to_h { |key| [key, fraction(scoring[key.to_s], key)] }
        values.merge(floor: above_zero(scoring['floor'], :floor)).freeze
      end

      def above_zero(value, key)
        at = path('scoring', key)
        return value.to_f if value.is_a?(Numeric) && value.positive?

        complain("#{key} must be a number greater than zero, got #{describe(value)}", at)
        nil
      end

      def fraction(value, key)
        at = path('scoring', key)
        return value.to_f if value.is_a?(Numeric) && FRACTION.cover?(value)

        complain("#{key} must be a number within #{FRACTION}, got #{describe(value)}", at)
        nil
      end

      def load_roles
        entries = {}
        section('roles').each do |name, body|
          role = symbol_in(name, ROLES, 'operation role', path('roles', name))
          entries[role] = compile(role, body) unless role.nil?
        end
        report_missing(entries.keys)
        entries.freeze
      end

      def compile(role, body)
        at = path('roles', role)
        fields = mapping(body, "role #{role}", at)
        entry = LISTS.to_h { |key| [key, words(fields[key.to_s], key, at)] }
        entry.merge!(http_methods: methods_of(fields['http_methods'], at),
                     tail_parameter: fields['tail_parameter'] == true,
                     request_body: flag(fields['request_body']),
                     unsecured: fields['unsecured'] == true)
        check_matchable(role, entry, at)
        entry.freeze
      end

      # Dictionary words are stored normalized, so "Pay-Outs", "payOuts" and
      # "pay_outs" in a spec all compare equal to one entry.
      def words(value, key, at)
        listed = string_list(value, "#{key} of the role",
                             "#{at}#{SpecLoader::JsonPath.segment(key)}", required: false)
        listed.map { |word| Normalizer.call(word) }.reject(&:empty?).uniq.freeze
      end

      def methods_of(value, at)
        at = "#{at}.http_methods"
        listed = string_list(value, 'http methods', at, required: false)
        listed.each_with_index.filter_map do |name, index|
          symbol_in(name.to_s.downcase, IR::Operation::METHODS, 'HTTP method', "#{at}[#{index}]")
        end.freeze
      end

      def flag(value)
        [true, false].include?(value) ? value : nil
      end

      # A role whose every list is empty can never win a vote, which is a
      # mistake in the data rather than a curious edge case.
      def check_matchable(role, entry, at)
        return if LISTS.any? { |key| !entry[key].empty? }

        complain("role #{role} lists no word to match on", at)
      end

      def report_missing(described)
        missing = ROLES - described
        return if missing.empty?

        complain("no entry describes #{missing.join(', ')}; every role of " \
                 'IR::Roles::OPERATION but :unmapped must be described', path('roles'))
      end

      def report_unknown(unknown, allowed, at)
        return if unknown.empty?

        complain("unknown keys #{unknown.join(', ')} (allowed: #{allowed.join(', ')})", at)
      end
    end
  end
end
