# frozen_string_literal: true

module SpecGen
  module Rules
    # Шаблоны, распознающие условия, высказанные прозой.
    #
    # Две секции одной природы. `required_when` — условная обязательность
    # поля: формальные условия (`dependentRequired`, `if/then/else`,
    # зарегистрированные расширения `x-jsonschema-*`) читаются прямо из
    # схемы, а этот файл — про случай, когда единственное место, где
    # спецификация говорит «обязательно, если у соседа такое значение», это
    # фраза в описании. `status_restriction` — ограничение операции по
    # статусу («отмена возможна только в статусах pending и processing»),
    # другое условие взаимодействия (IR::Condition). Такие слова у каждого
    # провайдера и в каждом языке свои, а уверенность такого прочтения —
    # число, которое нужно настраивать, поэтому и то и другое живёт в
    # rules/, а не в lib/.
    #
    # Шаблон required_when обязан захватывать `field` — соседнее поле, от
    # которого зависит обязательность; с группой `value` условие становится
    # условием равенства, без неё — про наличие. Шаблон status_restriction
    # обязан захватывать `statuses` — хвост фразы со статусами.
    class ConditionsBook < Book
      FILE = 'conditions.yml'
      KINDS = %w[equals presence].freeze
      FIELD_GROUP = 'field'
      VALUE_GROUP = 'value'
      STATUSES_GROUP = 'statuses'
      # Вид шаблона status_restriction: у него один смысл, kind не пишут.
      STATUSES_KIND = 'statuses'
      REQUIRED_WHEN = 'required_when'
      STATUS_RESTRICTION = 'status_restriction'
      FRACTION = (0.0..1.0)

      # Один шаблон в том виде, в котором его использует анализатор.
      #
      #   name       для строки обоснования
      #   regexp     с именованными группами
      #   kind       "equals", "presence" или "statuses"
      Hint = Struct.new(:name, :regexp, :kind, keyword_init: true)

      # @return [Array<Hint>] шаблоны условной обязательности, в порядке справочника
      attr_reader :hints
      # @return [Float, nil] уверенность условия, прочитанного из прозы
      attr_reader :hint_confidence
      # @return [Array<Hint>] шаблоны ограничения по статусу
      attr_reader :restrictions
      # @return [Float, nil] уверенность ограничения, прочитанного из прозы
      attr_reader :restriction_confidence

      # Текст спецификации приходит в UTF-8, но файл, прочитанный в другой
      # кодировке, заставил бы Regexp#match поднять ошибку вместо простого
      # несовпадения; описание, которое мы не можем прочитать, — это описание
      # без подсказки.
      # @param description [String, nil]
      # @return [Array(Hint, MatchData), nil] первый совпавший шаблон
      def match(description)
        first_match(hints, description)
      end

      # @param description [String, nil]
      # @return [Array(Hint, MatchData), nil] первый совпавший шаблон
      #   ограничения по статусу
      def match_restriction(description)
        first_match(restrictions, description)
      end

      private

      def first_match(listed, description)
        return nil unless description.is_a?(String) && description.valid_encoding?

        listed.each do |hint|
          found = hint.regexp.match(description)
          return [hint, found] unless found.nil?
        end
        nil
      rescue Encoding::CompatibilityError
        nil
      end

      def build
        @hint_confidence, @hints = load_section(REQUIRED_WHEN, required: true) do |body, at|
          hint(body, at)
        end
        @restriction_confidence, @restrictions = load_section(STATUS_RESTRICTION,
                                                              required: false) do |body, at|
          restriction(body, at)
        end
      end

      # @return [Array(Float, Array<Hint>)]
      def load_section(key, required:, &)
        section = mapping(data[key], noun(key.to_sym), path(key), required: required)
        return [nil, [].freeze] if section.empty? && !required

        [confidence_of(section['confidence'], key), load_hints(section['patterns'], key, &)]
      end

      def confidence_of(value, key)
        at = path(key, 'confidence')
        return value.to_f if value.is_a?(Numeric) && FRACTION.cover?(value)

        fault('conditions.confidence', at, range: FRACTION, got: describe(value))
      end

      def load_hints(listed, key)
        at = path(key, 'patterns')
        unless listed.is_a?(Array) && !listed.empty?
          fault('checks.list', at, what: noun(:list, key: 'patterns'), got: describe(listed))
          return [].freeze
        end

        listed.each_with_index.filter_map { |body, index| yield(body, "#{at}[#{index}]") }.freeze
      end

      def hint(body, at)
        fields = mapping(body, noun(:pattern_entry), at)
        name = text(fields['name'], noun(:pattern_name), "#{at}.name")
        regexp = pattern(fields['pattern'], noun(:pattern), "#{at}.pattern")
        kind = kind_of(fields['kind'], at)
        return nil if name.nil? || regexp.nil? || kind.nil?

        groups = kind == 'equals' ? [FIELD_GROUP, VALUE_GROUP] : [FIELD_GROUP]
        return nil unless captures?(regexp, groups, at)

        Hint.new(name: name, regexp: regexp, kind: kind).freeze
      end

      def restriction(body, at)
        fields = mapping(body, noun(:pattern_entry), at)
        name = text(fields['name'], noun(:pattern_name), "#{at}.name")
        regexp = pattern(fields['pattern'], noun(:pattern), "#{at}.pattern")
        return nil if name.nil? || regexp.nil? || !captures?(regexp, [STATUSES_GROUP], at)

        Hint.new(name: name, regexp: regexp, kind: STATUSES_KIND).freeze
      end

      def kind_of(value, at)
        return value if KINDS.include?(value)

        fault('conditions.kind', "#{at}.kind", allowed: KINDS.join(', '), got: describe(value))
      end

      # Без именованных групп анализатору нечего превращать в условие,
      # поэтому шаблон без них — сломанная запись.
      def captures?(regexp, groups, at)
        missing = groups - regexp.names
        return true if missing.empty?

        fault('conditions.captures', "#{at}.pattern", groups: missing.join(', '))
        false
      end
    end
  end
end
