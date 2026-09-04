# frozen_string_literal: true

module SpecGen
  module IR
    # The closed vocabularies the core works with. Field names in payment
    # specs are unlimited; roles are not. Supporting a new provider means new
    # synonyms in rules/, never a new entry here: adding one is a deliberate
    # change to the model, made together with CLAUDE.md and docs/IR.md.
    #
    # The bang methods raise ArgumentError, because a value outside a
    # vocabulary is a programmer error inside the generator, never bad user
    # input; bad user input becomes a Warning or a SpecGen::Error instead.
    module Roles
      # The roles of the payment domain, from CLAUDE.md.
      FIELD = %i[
        amount currency external_id provider_operation_id recipient_type recipient_phone
        bank_code bank_name card_number status error_code error_message created_at
        completed_at idempotency_key signature
      ].freeze

      # What an endpoint does. :unmapped is a result, not a failure: the
      # operation exists and gets reported, it just has no place in the
      # contract, and dropping it silently would look like lost functionality.
      OPERATION = %i[
        create_payout create_deposit fetch_status cancel balance webhook unmapped
      ].freeze

      # Roles that map onto a Provider::BaseService method. Cancel and balance
      # deliberately stay out: CLAUDE.md generates them as extra public
      # methods and lists them in report.md as "not mapped to the contract".
      CONTRACT = %i[create_payout create_deposit fetch_status webhook].freeze

      # Internal operation states of the host platform.
      INTERNAL_STATUS = %i[in_progress approved rejected].freeze

      # What the generated service does with a response. :dedup is the
      # Idempotency-Key case: a conflict that returns the earlier result and
      # is therefore a success path, not an error.
      ERROR_ACTION = %i[reject retry retry_backoff alert escalate dedup].freeze

      # Where a value came from; decides whether a warning is needed.
      SOURCE = %i[structural registry heuristic overlay unknown].freeze

      # Sources that carry no doubt: read from the spec, or stated by a human.
      CERTAIN_SOURCE = %i[structural overlay].freeze

      # @param role [Symbol]
      # @return [Symbol] the role itself
      # @raise [ArgumentError] when it is not a known field role
      def self.field!(role)
        Node.assert_member!(FIELD, role, 'field role')
      end

      # @param role [Symbol]
      # @return [Symbol] the role itself
      # @raise [ArgumentError] when it is not a known operation role
      def self.operation!(role)
        Node.assert_member!(OPERATION, role, 'operation role')
      end

      # @param status [Symbol]
      # @return [Symbol] the status itself
      # @raise [ArgumentError] when it is not an internal status
      def self.internal_status!(status)
        Node.assert_member!(INTERNAL_STATUS, status, 'internal status')
      end

      # @param action [Symbol]
      # @return [Symbol] the action itself
      # @raise [ArgumentError] when it is not a known error action
      def self.error_action!(action)
        Node.assert_member!(ERROR_ACTION, action, 'error action')
      end

      # @param source [Symbol]
      # @return [Symbol] the source itself
      # @raise [ArgumentError] when it is not a known derivation source
      def self.source!(source)
        Node.assert_member!(SOURCE, source, 'derivation source')
      end

      # @param role [Symbol, nil] operation role
      # @return [Boolean] whether it maps onto a Provider::BaseService method
      def self.contract?(role)
        CONTRACT.include?(role)
      end
    end
  end
end
