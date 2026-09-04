# frozen_string_literal: true

module SpecGen
  module IR
    # One row of the generated ERROR_MAP / RETRY_POLICY tables: what the
    # service does when it sees a given HTTP status and/or provider error
    # code. Either selector may be nil ("any"); a rule scoped to one
    # operation names it by Operation#key, because the same status can mean
    # different things (409 on create is dedup, 409 on cancel is reject).
    #
    #   http_status    Integer or nil
    #   provider_code  error code string or nil
    #   operation      Operation#key or nil for every operation
    #   action         Derived<Symbol> one of Roles::ERROR_ACTION
    #   retry_after    true when the response declares a Retry-After header
    #   seen_in        where the code was found: subset of SEEN_IN
    #   json_path      the response or enum value the rule was read from
    ErrorRule = Struct.new(:http_status, :provider_code, :operation, :action, :retry_after,
                           :seen_in, :json_path, keyword_init: true)

    # Vocabulary and checks of ErrorRule.
    class ErrorRule
      include Node

      SEEN_IN = %i[enum example response].freeze
      HTTP_STATUS = (100..599)

      # @param action [Derived] known, one of Roles::ERROR_ACTION
      # @param http_status [Integer, nil]
      # @param provider_code [String, nil]
      # @param operation [String, nil]
      # @param retry_after [Boolean]
      # @param seen_in [Array<Symbol>] subset of SEEN_IN
      # @param json_path [String, nil]
      # @raise [ArgumentError]
      def initialize(action:, http_status: nil, provider_code: nil, operation: nil,
                     retry_after: false, seen_in: [], json_path: nil)
        Node.assert_derived!(action, 'error action', allowed: Roles::ERROR_ACTION,
                                                     allow_unknown: false)
        check_selectors!(http_status, provider_code)
        seen_in.each { |place| Node.assert_member!(SEEN_IN, place, 'seen_in entry') }
        super
      end

      # Deterministic table order: operation-specific rules after generic
      # ones, then by status, then by code.
      # @return [Array]
      def sort_key
        [operation.to_s, http_status || 0, provider_code.to_s]
      end

      # @return [Boolean] whether the rule applies to every operation
      def generic?
        operation.nil?
      end

      # @return [Boolean] the idempotency path, not an error
      def dedup?
        action.value == :dedup
      end

      # @return [Boolean] found in an enum, not only in examples
      def declared?
        seen_in.include?(:enum)
      end

      private

      def check_selectors!(http_status, provider_code)
        if http_status.nil? && provider_code.nil?
          raise ArgumentError,
                'an error rule needs an HTTP status or a provider code'
        end
        if http_status.nil? || (http_status.is_a?(Integer) && HTTP_STATUS.cover?(http_status))
          return
        end

        raise ArgumentError,
              "http_status must be an Integer in #{HTTP_STATUS}, got #{http_status.inspect}"
      end
    end
  end
end
