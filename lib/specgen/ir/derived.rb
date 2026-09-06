# frozen_string_literal: true

module SpecGen
  module IR
    # Значение вместе с тем, откуда оно взялось. Каждое выведенное поле IR —
    # это Derived, потому что report.md обязан объяснить каждое решение, а три
    # уровня доверия из docs/PRINCIPLES.md — это ровно этот `source`:
    #
    #   :structural  прочитано из спецификации (required, enum, type)  уверенность 1.0
    #   :overlay     сказано человеком в OpenAPI Overlay               уверенность 1.0
    #   :registry    стандарт или справочник (ISO 4217, роли)          высокая
    #   :heuristic   выведено из структуры или имён                    как измерено
    #   :unknown     опереться не на что; вызывающий обязан ещё и предупредить
    #
    #   value       само значение, nil для :unknown
    #   source      один из Roles::SOURCE
    #   confidence  0.0..1.0, для несомненных источников закреплена на 1.0
    #   evidence    фраза, которую печатает report.md, например «ISO 4217:
    #               экспонента RUB 2» или «матчер имён: amount~sum (0.82)»
    Derived = Struct.new(:value, :source, :confidence, :evidence, keyword_init: true)

    # Фабрики, проверки и предикаты Derived. Экземпляры заморожены:
    # анализаторы заменяют Derived целиком, а не мутируют его, поэтому
    # значение не может потерять обоснование, которое его объясняет.
    class Derived
      include Node

      # Таблица даёт точное значение, но провайдер может отклоняться от
      # стандарта (Adyen и ISK) — именно для этого существует overlay,
      # поэтому здесь не 1.0.
      REGISTRY_CONFIDENCE = 0.9
      HEURISTIC_FALLBACK = 0.5
      RANGE = (0.0..1.0)

      # @param value [Object] прочитано из структуры спецификации
      # @param evidence [String] из какого ключевого слова прочитано
      # @return [Derived]
      def self.structural(value, evidence:)
        new(value: value, source: :structural, confidence: 1.0, evidence: evidence)
      end

      # @param value [Object] сказано человеком в overlay
      # @param evidence [String] какое действие overlay его дало
      # @return [Derived]
      def self.overlay(value, evidence:)
        new(value: value, source: :overlay, confidence: 1.0, evidence: evidence)
      end

      # @param value [Object] взято из стандарта или справочника
      # @param evidence [String] назови стандарт: «ISO 4217: экспонента JPY 0»
      # @param confidence [Float]
      # @return [Derived]
      def self.registry(value, evidence:, confidence: REGISTRY_CONFIDENCE)
        new(value: value, source: :registry, confidence: confidence, evidence: evidence)
      end

      # @param value [Object] выведено из структуры или имён
      # @param confidence [Float] то, что матчеры на самом деле насчитали
      # @param evidence [String] что дал каждый матчер
      # @return [Derived]
      def self.heuristic(value, confidence:, evidence:)
        new(value: value, source: :heuristic, confidence: confidence, evidence: evidence)
      end

      # Вывести не удалось. Вызывающий обязан ещё и добавить Warning:
      # не выведенное значение, о котором никто не сообщил, — это и есть
      # способ, которым молчаливая дыра попадает в сгенерированный код.
      # @param evidence [String] что искали и не нашли
      # @return [Derived]
      def self.unknown(evidence:)
        new(value: nil, source: :unknown, confidence: 0.0, evidence: evidence)
      end

      # @param value [Object, nil]
      # @param source [Symbol] один из Roles::SOURCE
      # @param confidence [Float, nil] игнорируется для несомненных
      #   источников и для :unknown
      # @param evidence [String, nil]
      # @raise [ArgumentError] при неизвестном источнике или уверенности вне
      #   диапазона
      def initialize(value: nil, source: :unknown, confidence: nil, evidence: nil)
        super
        self.source = Roles.source!(source)
        self.confidence = settled_confidence
        self.evidence = evidence&.to_s
        freeze
      end

      # @return [Boolean] есть значение, которым могут пользоваться генераторы
      def known?
        !value.nil? && source != :unknown
      end

      # @return [Boolean] анализатор смотрел и не вывел ничего
      def unknown?
        !known?
      end

      # @return [Boolean] значение не требует проверки человеком
      def certain?
        Roles::CERTAIN_SOURCE.include?(source)
      end

      # @return [String] для report.md: ":minor (registry 0.90: ISO 4217 ...)"
      def to_s
        "#{value.inspect} (#{source} #{format('%.2f', confidence)}: #{evidence})"
      end

      private

      def settled_confidence
        return 1.0 if certain?
        return 0.0 if source == :unknown

        in_range(confidence || HEURISTIC_FALLBACK)
      end

      def in_range(number)
        unless number.is_a?(Numeric)
          raise ArgumentError,
                "уверенность: ожидается число, получено #{number.inspect}"
        end
        return number.to_f if RANGE.cover?(number)

        raise ArgumentError,
              "уверенность: ожидается число в диапазоне #{RANGE}, получено #{number.inspect}"
      end
    end
  end
end
