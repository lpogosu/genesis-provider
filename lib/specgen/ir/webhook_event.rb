# frozen_string_literal: true

module SpecGen
  module IR
    # One event a webhook endpoint can deliver, and the internal status the
    # generated `process_callback` moves the operation to.
    #
    #   name             event name verbatim, e.g. "payout.completed"
    #   provider_status  status value carried in the payload, or nil
    #   internal_status  Derived<Symbol> one of Roles::INTERNAL_STATUS
    #   example          payload example verbatim, or nil
    #   json_path        where the event is declared (enum entry or example)
    WebhookEvent = Struct.new(:name, :provider_status, :internal_status, :example, :json_path,
                              keyword_init: true)

    # Checks and predicates of WebhookEvent.
    class WebhookEvent
      include Node

      # @param name [String]
      # @param internal_status [Derived]
      # @param provider_status [String, nil]
      # @param example [Object, nil]
      # @param json_path [String, nil]
      # @raise [ArgumentError]
      def initialize(name:, internal_status:, provider_status: nil, example: nil, json_path: nil)
        Node.assert_text!(name, 'webhook event name')
        Node.assert_derived!(internal_status, 'webhook internal status', allowed: Roles::INTERNAL_STATUS)
        super
      end

      # @return [Boolean]
      def mapped?
        internal_status.known?
      end
    end
  end
end
