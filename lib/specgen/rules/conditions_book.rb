# frozen_string_literal: true

module SpecGen
  module Rules
    # Шаблоны, распознающие условную обязательность, высказанную прозой.
    #
    # Формальные условия — `dependentRequired`, `if/then/else`,
    # зарегистрированные расширения `x-jsonschema-*` — читаются прямо из
    # схемы и справочника не требуют. Этот файл — про другой случай: когда
    # единственное место, где спецификация говорит «обязательно, если у
    # соседа такое значение», это фраза в описании. Такие слова у каждого
    # провайдера и в каждом языке свои, а уверенность такого прочтения —
    # число, которое нужно настраивать, поэтому и то и другое живёт в rules/,
    # а не в lib/.
    #
    # Шаблон обязан захватывать `field` — соседнее поле, от которого зависит
    # обязательность. Если он захватывает ещё и `value`, условие становится
    # условием равенства; без `value` условие про наличие, а это и есть
    # смысл dependentRequired.
    class ConditionsBook < Book
      FILE = 'conditions.yml'
      KINDS = %w[equals presence].freeze
      FIELD_GROUP = 'field'
      VALUE_GROUP = 'value'
      FRACTION = (0.0..1.0)

      # Один шаблон в том виде, в котором его использует анализатор.
      #
      #   name       для строки обоснования
      #   regexp     с именованной группой `field`, необязательно `value`
      #   kind       "equals" или "presence"
      Hint = Struct.new(:name, :regexp, :kind, keyword_init: true)

      # @return [Array<Hint>] в порядке справочника
      attr_reader :hints
      # @return [Float, nil] уверенность условия, прочитанного из прозы
      attr_reader :hint_confidence

      # Текст спецификации приходит в UTF-8, но файл, прочитанный в другой
      # кодировке, заставил бы Regexp#match поднять ошибку вместо простого
      # несовпадения; описание, которое мы не можем прочитать, — это описание
      # без подсказки.
      # @param description [String, nil]
      # @return [Array(Hint, MatchData), nil] первый совпавший шаблон
      def match(description)
        return nil unless description.is_a?(String) && description.valid_encoding?

        hints.each do |hint|
          found = hint.regexp.match(description)
          return [hint, found] unless found.nil?
        end
        nil
      rescue Encoding::CompatibilityError
        nil
      end

      private

      def build
        at = path('required_when')
        section = mapping(data['required_when'], noun(:required_when), at)
        @hint_confidence = confidence_of(section['confidence'])
        @hints = load_hints(section['patterns'])
      end

      def confidence_of(value)
        at = path('required_when', 'confidence')
        return value.to_f if value.is_a?(Numeric) && FRACTION.cover?(value)

        fault('conditions.confidence', at, range: FRACTION, got: describe(value))
      end

      def load_hints(listed)
        at = path('required_when', 'patterns')
        unless listed.is_a?(Array) && !listed.empty?
          fault('checks.list', at, what: noun(:list, key: 'patterns'), got: describe(listed))
          return [].freeze
        end

        listed.each_with_index.filter_map { |body, index| hint(body, "#{at}[#{index}]") }.freeze
      end

      def hint(body, at)
        fields = mapping(body, noun(:pattern_entry), at)
        name = text(fields['name'], noun(:pattern_name), "#{at}.name")
        regexp = pattern(fields['pattern'], noun(:pattern), "#{at}.pattern")
        kind = kind_of(fields['kind'], at)
        return nil if name.nil? || regexp.nil? || kind.nil? || !captures?(regexp, kind, at)

        Hint.new(name: name, regexp: regexp, kind: kind).freeze
      end

      def kind_of(value, at)
        return value if KINDS.include?(value)

        fault('conditions.kind', "#{at}.kind", allowed: KINDS.join(', '), got: describe(value))
      end

      # Без именованных групп анализатору нечего превращать в условие,
      # поэтому шаблон без них — сломанная запись.
      def captures?(regexp, kind, at)
        names = regexp.names
        missing = [FIELD_GROUP] - names
        missing << VALUE_GROUP if kind == 'equals' && !names.include?(VALUE_GROUP)
        return true if missing.empty?

        fault('conditions.captures', "#{at}.pattern", groups: missing.join(', '))
        false
      end
    end
  end
end
