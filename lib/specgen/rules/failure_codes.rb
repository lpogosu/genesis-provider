# frozen_string_literal: true

module SpecGen
  module Rules
    # Таблица `platform.failure_codes` контракта: чем становится первый
    # аргумент `failure`. Эксперты кейса 5 сентября 2026 (вопрос 20 в
    # docs/QUESTIONS.md, там дословно): это символ в духе HTTP или доменного
    # кода платформы, набор не произвольный, и придумывать свои коды под
    # конкретного провайдера не нужно. Поэтому наше действие (reject,
    # retry_backoff, alert) остаётся политикой обработки в ERROR_MAP и
    # RETRY_POLICY, а платформе уходит её собственный код.
    #
    #   by_http     HTTP-код ответа провайдера → код платформы
    #   by_action   действие ERROR_MAP → код платформы, когда HTTP-кода в
    #               таблице нет
    #   validation  один код на любой отказ предпроверки: набор проверок
    #               открыт, он растёт с каждым ограничением спецификации
    #   internal    отказ самого сервиса (подпись, незнакомое событие) → код
    #               платформы
    #
    # Смысл отказа во всех случаях остаётся вторым аргументом, в ключе
    # локализации: failure(:unauthorized, 'errors.signature_invalid').
    class FailureCodes
      include Checks

      # Код платформы — идентификатор Ruby: он печатается символом.
      CODE = /\A[a-z_][a-z0-9_]*\z/

      # @return [Symbol, nil] код любого отказа предпроверки
      attr_reader :validation
      # @return [Hash{Integer => Symbol}] по HTTP-коду, по возрастанию кода
      attr_reader :by_http
      # @return [Hash{Symbol => Symbol}] по действию ERROR_MAP, в порядке
      #   IR::Roles::ERROR_ACTION
      attr_reader :by_action

      # @param data [Object] значение ключа `failure_codes`
      # @param file [String] файл справочника, для сообщений
      # @param at [String] JSONPath раздела
      # @param problems [Problems] общий сборщик проблем
      def initialize(data, file:, at:, problems:)
        @file = file
        @problems = problems
        @at = at
        section = mapping(data, noun(:platform_map, key: 'failure_codes'), at, required: false)
        @by_http = http_table(section['by_http'])
        @by_action = action_table(section['by_action'])
        @internal = internal_table(section['internal'])
        @validation = validation_of(section)
        freeze
      end

      # @param reason [Symbol] причина отказа самого сервиса
      # @return [Symbol, nil] код платформы
      def internal(reason)
        @internal[reason.to_sym]
      end

      # @return [Array<Symbol>] причины отказов сервиса, которые таблица знает
      def internal_reasons
        @internal.keys
      end

      private

      # Раздел целиком необязателен, как и весь platform: контракт без него
      # просто не даёт выражений. А вот написанный неверно — останавливает
      # загрузку, как везде в справочниках.
      def validation_of(section)
        return nil unless section.key?('validation')

        code(section['validation'], 'validation', "#{@at}.validation")
      end

      def http_table(data)
        at = "#{@at}.by_http"
        table = mapping(data, noun(:platform_map, key: 'by_http'), at, required: false)
        table.filter_map do |status, value|
          number = integer(status, noun(:http_status), "#{at}.#{status}")
          symbol = code(value, status, "#{at}.#{status}")
          number && symbol && [number, symbol]
        end.sort.to_h.freeze
      end

      def action_table(data)
        at = "#{@at}.by_action"
        table = mapping(data, noun(:platform_map, key: 'by_action'), at, required: false)
        pairs = table.filter_map do |action, value|
          symbol = symbol_in(action, IR::Roles::ERROR_ACTION, noun(:error_action),
                             "#{at}.#{action}")
          target = code(value, action, "#{at}.#{action}")
          symbol && target && [symbol, target]
        end
        pairs.sort_by { |action, _| IR::Roles::ERROR_ACTION.index(action) }.to_h.freeze
      end

      def internal_table(data)
        at = "#{@at}.internal"
        table = mapping(data, noun(:platform_map, key: 'internal'), at, required: false)
        table.filter_map do |reason, value|
          symbol = code(value, reason, "#{at}.#{reason}")
          symbol && [reason.to_sym, symbol]
        end.to_h.freeze
      end

      # Код платформы — непустая строка, которая станет символом Ruby.
      def code(value, key, at)
        name = text(value, noun(:failure_code, key: key), at)
        return nil if name.nil?
        return name.to_sym if name.match?(CODE)

        fault('contract.bad_failure_code', at, code: name.inspect)
      end

      def complain(message, at)
        @problems.add(message, file: @file, path: at)
      end
    end
  end
end
