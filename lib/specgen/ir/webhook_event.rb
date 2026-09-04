# frozen_string_literal: true

module SpecGen
  module IR
    # Одно событие, которое может доставить точка приёма вебхуков, и
    # внутренний статус, в который сгенерированный `process_callback`
    # переводит операцию.
    #
    #   name             имя события дословно, например "payout.completed"
    #   provider_status  значение статуса в теле уведомления или nil
    #   internal_status  Derived<Symbol>, один из Roles::INTERNAL_STATUS
    #   example          пример тела дословно или nil
    #   json_path        где событие объявлено (запись enum или пример)
    WebhookEvent = Struct.new(:name, :provider_status, :internal_status, :example, :json_path,
                              keyword_init: true)

    # Проверки и предикаты WebhookEvent.
    class WebhookEvent
      include Node

      # @param name [String]
      # @param internal_status [Derived]
      # @param provider_status [String, nil]
      # @param example [Object, nil]
      # @param json_path [String, nil]
      # @raise [ArgumentError]
      def initialize(name:, internal_status:, provider_status: nil, example: nil, json_path: nil)
        Node.assert_text!(name, 'имя события вебхука')
        Node.assert_derived!(internal_status, 'внутренний статус вебхука',
                             allowed: Roles::INTERNAL_STATUS)
        super
      end

      # @return [Boolean]
      def mapped?
        internal_status.known?
      end
    end
  end
end
