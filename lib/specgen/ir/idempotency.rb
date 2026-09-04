# frozen_string_literal: true

module SpecGen
  module IR
    # Idempotency-Key support of the provider and how the generated service
    # produces the key. The header may be optional in the spec; the service
    # sends it whenever one is known.
    #
    #   header      Derived<String> header name, e.g. "Idempotency-Key"
    #   strategy    Derived<Symbol> one of STRATEGIES
    #   required    whether the spec marks the header as required
    #   operations  Operation#key of every operation that accepts the header
    #   json_path   where the header parameter is declared
    Idempotency = Struct.new(:header, :strategy, :required, :operations, :json_path,
                             keyword_init: true)

    # Vocabulary and defaults of Idempotency.
    class Idempotency
      include Node

      # uuid_v5: deterministic UUID from operation.id, so repeats dedupe;
      # external_id: send the platform's own operation id as the key;
      # none: the provider offers no idempotency.
      STRATEGIES = %i[uuid_v5 external_id none].freeze
      UNDERIVED = 'not derived'

      # @param header [Derived]
      # @param strategy [Derived]
      # @param required [Boolean]
      # @param operations [Array<String>]
      # @param json_path [String, nil]
      # @raise [ArgumentError]
      def initialize(header: Derived.unknown(evidence: UNDERIVED),
                     strategy: Derived.unknown(evidence: UNDERIVED), required: false,
                     operations: [], json_path: nil)
        Node.assert_derived!(header, 'idempotency header')
        Node.assert_derived!(strategy, 'idempotency strategy', allowed: STRATEGIES)
        super
      end

      # @return [Boolean] the service can send a key
      def supported?
        header.known? && strategy.known? && strategy.value != :none
      end
    end
  end
end
