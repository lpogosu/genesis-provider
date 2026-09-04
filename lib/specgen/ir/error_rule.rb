# frozen_string_literal: true

module SpecGen
  module IR
    # Одна строка сгенерированных таблиц ERROR_MAP / RETRY_POLICY: что делает
    # сервис, увидев заданный HTTP-код и/или код ошибки провайдера. Любой из
    # двух селекторов может быть nil («любой»); правило, ограниченное одной
    # операцией, называет её через Operation#key, потому что один и тот же
    # код может означать разное (409 при создании — это дедупликация, 409 при
    # отмене — отказ).
    #
    #   http_status    Integer или nil
    #   provider_code  строка кода ошибки или nil
    #   operation      Operation#key или nil для любой операции
    #   action         Derived<Symbol>, одно из Roles::ERROR_ACTION
    #   retry_after    true, если ответ объявляет заголовок Retry-After
    #   seen_in        где найден код: подмножество SEEN_IN
    #   json_path      ответ или значение enum, из которого прочитано правило
    ErrorRule = Struct.new(:http_status, :provider_code, :operation, :action, :retry_after,
                           :seen_in, :json_path, keyword_init: true)

    # Словарь значений и проверки ErrorRule.
    class ErrorRule
      include Node

      SEEN_IN = %i[enum example response].freeze
      HTTP_STATUS = (100..599)

      # @param action [Derived] выведенное, одно из Roles::ERROR_ACTION
      # @param http_status [Integer, nil]
      # @param provider_code [String, nil]
      # @param operation [String, nil]
      # @param retry_after [Boolean]
      # @param seen_in [Array<Symbol>] подмножество SEEN_IN
      # @param json_path [String, nil]
      # @raise [ArgumentError]
      def initialize(action:, http_status: nil, provider_code: nil, operation: nil,
                     retry_after: false, seen_in: [], json_path: nil)
        Node.assert_derived!(action, 'действие по ошибке', allowed: Roles::ERROR_ACTION,
                                                           allow_unknown: false)
        check_selectors!(http_status, provider_code)
        seen_in.each { |place| Node.assert_member!(SEEN_IN, place, 'элемент seen_in') }
        super
      end

      # Детерминированный порядок таблицы: правила для конкретной операции
      # после общих, затем по коду ответа, затем по коду ошибки.
      # @return [Array]
      def sort_key
        [operation.to_s, http_status || 0, provider_code.to_s]
      end

      # @return [Boolean] применимо ли правило к любой операции
      def generic?
        operation.nil?
      end

      # @return [Boolean] путь идемпотентности, а не ошибка
      def dedup?
        action.value == :dedup
      end

      # @return [Boolean] найдено в enum, а не только в примерах
      def declared?
        seen_in.include?(:enum)
      end

      private

      def check_selectors!(http_status, provider_code)
        if http_status.nil? && provider_code.nil?
          raise ArgumentError,
                'правилу ошибки нужен HTTP-код или код ошибки провайдера'
        end
        if http_status.nil? || (http_status.is_a?(Integer) && HTTP_STATUS.cover?(http_status))
          return
        end

        raise ArgumentError,
              "http_status: ожидается Integer в диапазоне #{HTTP_STATUS}, " \
              "получено #{http_status.inspect}"
      end
    end
  end
end
