# frozen_string_literal: true

module SpecGen
  module IR
    # Условная обязательность поля: «обязательно, когда соседнее `field`
    # равно `equals`» или, при `equals` равном nil, «обязательно, когда
    # соседнее `field` присутствует» (семантика dependentRequired).
    #
    #   field       имя соседнего поля, на которое смотрит условие
    #   equals      значение или Array значений; nil для условия о наличии
    #   origin      один из ORIGINS; откуда прочитано условие
    #   evidence    одна строка для отчёта
    #   confidence  1.0 для формальных источников, задаётся явно для намёка
    #               в описании
    RequiredWhen = Struct.new(:field, :equals, :origin, :evidence, :confidence, keyword_init: true)

    # Словарь значений и проверки RequiredWhen.
    class RequiredWhen
      include Node

      ORIGINS = %i[
        dependent_required if_then x_jsonschema_if discriminator overlay description_hint
      ].freeze
      # Какому источнику Derived соответствует каждый origin.
      SOURCE_BY_ORIGIN = {
        dependent_required: :structural, if_then: :structural, x_jsonschema_if: :structural,
        discriminator: :structural, overlay: :overlay, description_hint: :heuristic
      }.freeze

      # @param field [String] имя соседнего поля
      # @param origin [Symbol] один из ORIGINS
      # @param evidence [String]
      # @param equals [Object, Array, nil]
      # @param confidence [Float, nil] нужна только для :description_hint
      # @raise [ArgumentError]
      def initialize(field:, origin:, evidence:, equals: nil, confidence: nil)
        Node.assert_text!(field, 'поле условия')
        Node.assert_member!(ORIGINS, origin, 'источник условия')
        Node.assert_text!(evidence, 'обоснование условия')
        confidence = resolve_confidence(origin, confidence)
        super
      end

      # @return [Symbol] источник Derived, который подразумевает origin
      def source
        SOURCE_BY_ORIGIN.fetch(origin)
      end

      # @return [Boolean] прочитано из ключевых слов схемы или из overlay, а
      #   не из прозы
      def formal?
        source != :heuristic
      end

      # @return [Boolean] «обязательно при наличии `field`», а не при
      #   равенстве
      def presence?
        equals.nil?
      end

      # @return [Array] допустимые значения соседа; пусто для условия о
      #   наличии
      def values
        Array(equals)
      end

      private

      def resolve_confidence(origin, given)
        return formal_confidence(origin, given) if SOURCE_BY_ORIGIN.fetch(origin) != :heuristic

        raise ArgumentError, "для источника #{origin.inspect} уверенность обязательна" if given.nil?
        unless given.is_a?(Numeric) && given.between?(0.0, 1.0)
          raise ArgumentError,
                "уверенность: ожидается число в диапазоне 0.0..1.0, получено #{given.inspect}"
        end

        given.to_f
      end

      # Условие, прочитанное из ключевых слов схемы или высказанное в
      # overlay, — не догадка, поэтому его уверенность закреплена, а не
      # принимается на веру.
      def formal_confidence(origin, given)
        return 1.0 if given.nil? || full?(given)

        raise ArgumentError,
              "уверенность для #{origin.inspect} закреплена на 1.0, получено #{given.inspect}"
      end

      def full?(given)
        number = Float(given, exception: false)
        !number.nil? && (number - 1.0).abs < Float::EPSILON
      end
    end
  end
end
