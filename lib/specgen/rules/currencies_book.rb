# frozen_string_literal: true

module SpecGen
  module Rules
    # ISO 4217: экспонента минорной единицы для каждого кода валюты.
    #
    # Экспонента решает, какой множитель сгенерированный сервис применит к
    # `operation.amount`, поэтому она читается из стандарта, а не из слова
    # «копейки» в описании. Провайдера, который от стандарта отклоняется,
    # правит OpenAPI Overlay, а не эта таблица: таблица говорит, что сказано
    # в ISO, overlay — что делает провайдер.
    class CurrenciesBook < Book
      FILE = 'currencies.yml'
      CODE = /\A[A-Z]{3}\z/
      # ISO 4217 использует значения от 0 до 4; всё остальное — опечатка в
      # таблице.
      EXPONENT_RANGE = (0..4)
      # Нужна только тогда, когда сама таблица негодна и загрузка всё равно
      # уже обречена упасть; позволяет доработать остальные проверки.
      FALLBACK_EXPONENT = 2

      # Единицы, о которых может говорить описание поля суммы.
      UNITS = IR::Units::UNITS

      # @return [Integer] экспонента для неизвестного кода; годится только
      #   вместе с предупреждением, никогда молча
      attr_reader :default_exponent

      # @param code [String] буквенный код ISO 4217
      # @return [Integer, nil] экспонента минорной единицы; nil, если код
      #   неизвестен
      def exponent(code)
        entry(code)&.fetch(:exponent)
      end

      # @param code [String]
      # @return [String, nil] название валюты по ISO 4217
      def name_of(code)
        entry(code)&.fetch(:name)
      end

      # @param code [String]
      # @return [Boolean]
      def known?(code)
        !entry(code).nil?
      end

      # @return [Array<String>] все коды таблицы
      def codes
        @currencies.keys
      end

      # О каких единицах говорит описание поля. Только подтверждающий сигнал:
      # источником множителя остаются тип поля и ISO 4217. Слова из обоих
      # списков сразу — подсказки нет.
      # @param description [String, nil]
      # @return [Array(Symbol, String), nil] единица и совпавшие слова
      def unit_hint(description)
        return nil unless description.is_a?(String) && description.valid_encoding?

        hits = @unit_words.filter_map do |unit, patterns|
          found = patterns.lazy.filter_map { |pattern| pattern.match(description) }.first
          [unit, found[0]] if found
        end
        hits.size == 1 ? hits.first : nil
      rescue Encoding::CompatibilityError
        nil
      end

      private

      def entry(code)
        @currencies[code.to_s.strip.upcase]
      end

      def build
        @default_exponent = integer(data['default_exponent'], noun(:default_exponent),
                                    path('default_exponent'),
                                    range: EXPONENT_RANGE) || FALLBACK_EXPONENT
        @currencies = {}
        section('currencies').each { |code, body| add(code, body) }
        fault('currencies.empty', path('currencies')) if @currencies.empty?
        @currencies.freeze
        @unit_words = load_unit_words.freeze
      end

      # @return [Hash{Symbol => Array<Regexp>}]
      def load_unit_words
        listed = section('unit_words', Hash, required: false)
        listed.filter_map do |unit, patterns|
          at = path('unit_words', unit)
          key = symbol_in(unit, UNITS, noun(:amount_unit), at)
          next if key.nil?

          [key, patterns_of(patterns, unit, at)]
        end.to_h
      end

      def patterns_of(listed, unit, at)
        sources = string_list(listed, noun(:list, key: unit), at)
        sources.each_with_index.filter_map do |source, index|
          pattern(source, noun(:pattern), "#{at}[#{index}]")
        end
      end

      def add(code, body)
        at = path('currencies', code)
        unless code.is_a?(String) && code.match?(CODE)
          fault('currencies.bad_code', at, code: code.inspect)
          return
        end
        fields = mapping(body, noun(:currency_body, code: code), at)
        record(code, fields, at)
      end

      def record(code, fields, at)
        exponent = integer(fields['exponent'], noun(:exponent), "#{at}.exponent",
                           range: EXPONENT_RANGE)
        name = text(fields['name'], noun(:currency_name), "#{at}.name")
        return if exponent.nil? || name.nil?

        @currencies[code] = { exponent: exponent, name: name }.freeze
      end
    end
  end
end
