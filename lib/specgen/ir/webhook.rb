# frozen_string_literal: true

module SpecGen
  module IR
    # Точка приёма входящих уведомлений: один путь, одна схема тела, одна
    # схема подписи, несколько событий.
    #
    #   path       шаблон пути, который провайдеру велят вызывать
    #   operation  Operation#key соответствующей операции с ролью :webhook или
    #              nil, если спецификация описывает вебхуки вне `paths`
    #   schema     имя схемы тела в profile.schemas
    #   signature  SignatureProfile или nil, если спецификация не упоминает
    #              подпись вообще (что само по себе предупреждение)
    #   events     [WebhookEvent]
    #   json_path  "$.paths['/webhooks/x'].post" или "$.webhooks.x"
    Webhook = Struct.new(:path, :operation, :schema, :signature, :events, :json_path,
                         keyword_init: true)

    # Проверки и выборки Webhook.
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
        Node.assert_text!(path, 'путь вебхука')
        Node.assert_optional!(signature, SignatureProfile, 'подпись вебхука')
        super
      end

      # @param name [String] имя события
      # @return [WebhookEvent, nil]
      def event(name)
        events.find { |event| event.name == name }
      end

      # @return [Boolean] схема подписи выведена и полна
      def verifiable?
        !signature.nil? && signature.complete?
      end

      # @return [Array<WebhookEvent>] события без внутреннего статуса
      def unmapped_events
        events.reject(&:mapped?)
      end
    end
  end
end
