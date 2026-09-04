# frozen_string_literal: true

module SpecGen
  module Analyzers
    # Минорные или мажорные единицы у поля суммы — по типу и примеру, с
    # описанием только как подтверждением.
    #
    # `type: integer` читается как минорные единицы: целое число копеек —
    # то, как платёжные API передают деньги без плавающей точки. `type:
    # number` (или строка) с дробным примером — мажорные: дробь означает
    # рубли с копейками. Целочисленный `number` без примера не говорит
    # ничего, и единицы остаются невыведенными с предупреждением.
    #
    # Слова описания («в копейках», «in rubles») источником не становятся
    # никогда. Они либо подтверждают вывод — и попадают в обоснование, — либо
    # противоречат ему, и тогда это предупреждение units_inconsistent:
    # догадка по одному слову не заменяет тип, но и молчать о расхождении
    # нельзя. Той же проверке подлежат `minimum`, `maximum` и `example`:
    # дробное значение у минорных единиц — противоречие.
    class UnitReader
      # Выведенная единица и пары [код предупреждения, сообщение], которые
      # анализатор запишет с JSONPath поля.
      Result = Struct.new(:derived, :notes, keyword_init: true)

      EXTENSION = 'x-specgen-amount-unit'
      INTEGER = 'integer'
      FRACTION = /\A-?\d+[.,]\d+\z/
      # Ключевые слова, значения которых у минорных единиц обязаны быть целыми.
      WHOLE = %w[minimum maximum example].freeze

      # @param node [Hash] узел поля суммы
      # @param name [String] имя поля
      # @param book [Rules::CurrenciesBook] слова описания
      # @param exponent [IR::Derived] экспонента, для заметки о minimum
      # @param code [String, nil] код валюты, если известен
      def initialize(node:, name:, book:, exponent:, code:)
        @node = node
        @name = name
        @book = book
        @exponent = exponent
        @code = code
        @notes = []
      end

      # @return [Result]
      def call
        Result.new(derived: overlay || derive, notes: @notes)
      end

      private

      def overlay
        value = @node[EXTENSION]
        return nil if value.nil?

        unit = value.to_s.to_sym
        return IR::Derived.overlay(unit, evidence: t('unit_overlay', value: unit)) if
          IR::Units::UNITS.include?(unit)

        note(:spec_element_unsupported,
             t('unit_overlay_bad', value: value.inspect, allowed: IR::Units::UNITS.join(' | ')))
        nil
      end

      def derive
        type, = ConstraintReader.type_of(@node)
        unit, base = read_type(type)
        return unknown(type) if unit.nil?

        check_whole if unit == :minor
        evidence = [base, confirmation(unit), minimum_note(unit)].join
        IR::Derived.structural(unit, evidence: evidence)
      end

      # @return [Array(Symbol, String), Array(nil, nil)]
      def read_type(type)
        return [:minor, t('unit_integer')] if type == INTEGER

        example = @node['example']
        return [:major, t('unit_fractional', type: type, example: example)] if fractional?(example)

        [nil, nil]
      end

      def unknown(type)
        shown = type || '?'
        note(:units_unknown, t('unknown_message', name: @name, type: shown))
        IR::Derived.unknown(evidence: t('unit_unknown', type: shown))
      end

      # Float — это записанная десятичная дробь, даже если она равна целому:
      # автор примера думал в мажорных единицах.
      def fractional?(value)
        return true if value.is_a?(Float)

        value.is_a?(String) && value.match?(FRACTION)
      end

      # Описание согласно — строка обоснования; описание против — предупреждение.
      # @return [String] суффикс обоснования, пустой без подтверждения
      def confirmation(unit)
        hint = @book.unit_hint(@node['description'])
        return '' if hint.nil?

        said, words = hint
        return t('unit_confirmed', words: words.inspect) if said == unit

        sentence = @node['description'].to_s.strip.inspect
        note(:units_inconsistent,
             t('inconsistent_description', name: @name, unit: unit_name(unit),
                                           said: unit_name(said), sentence: sentence))
        ''
      end

      def check_whole
        WHOLE.each do |keyword|
          value = @node[keyword]
          next unless fractional?(value)

          note(:units_inconsistent,
               t('inconsistent_fraction', name: @name, keyword: keyword, value: value.inspect))
        end
      end

      # «minimum 100000 = 1000.00 RUB» — сверка ограничения с выведенными
      # единицами, которую читатель проверяет глазами.
      def minimum_note(unit)
        minimum = @node['minimum']
        return '' unless unit == :minor && minimum.is_a?(Numeric) && @exponent.known? && @code

        digits = @exponent.value
        major = format("%.#{digits}f", minimum.to_f / (10**digits))
        t('unit_minimum', minimum: minimum, major: major, code: @code)
      end

      def unit_name(unit)
        Texts.t("analyzers.units.unit_name.#{unit}")
      end

      def note(code, message)
        @notes << [code, message]
      end

      def t(key, **params)
        Texts.t("analyzers.units.#{key}", **params)
      end
    end
  end
end
