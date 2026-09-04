# frozen_string_literal: true

module SpecGen
  module IR
    # An inbound notification endpoint: one path, one payload schema, one
    # signature scheme, several events.
    #
    #   path       path template the provider is told to call
    #   operation  Operation#key of the matching :webhook operation, or nil
    #              when the spec documents webhooks outside `paths`
    #   schema     name of the payload schema in profile.schemas
    #   signature  SignatureProfile, or nil when the spec mentions no
    #              signature at all (which is itself a warning)
    #   events     [WebhookEvent]
    #   json_path  "$.paths['/webhooks/x'].post" or "$.webhooks.x"
    Webhook = Struct.new(:path, :operation, :schema, :signature, :events, :json_path,
                         keyword_init: true)

    # Checks and lookups of Webhook.
    class Webhook
      include Node

      # @param path [String]
      # @param operation [String, nil]
      # @param schema [String, nil]
      # @param signature [SignatureProfile, nil]
      # @param events [Array<WebhookEvent>]
      # @param json_path [String, nil]
      # @raise [ArgumentError]
      def initialize(path:, operation: nil, schema: nil, signature: nil, events: [], json_path: nil)
        Node.assert_text!(path, 'webhook path')
        Node.assert_optional!(signature, SignatureProfile, 'webhook signature')
        super
      end

      # @param name [String] event name
      # @return [WebhookEvent, nil]
      def event(name)
        events.find { |event| event.name == name }
      end

      # @return [Boolean] a signature scheme is known and complete
      def verifiable?
        !signature.nil? && signature.complete?
      end

      # @return [Array<WebhookEvent>] events without an internal status
      def unmapped_events
        events.reject(&:mapped?)
      end
    end
  end
end
