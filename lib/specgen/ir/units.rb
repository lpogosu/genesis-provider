# frozen_string_literal: true

module SpecGen
  module IR
    # В каких единицах провайдер ждёт сумму и какой множитель
    # сгенерированный сервис применяет к `operation.amount` (мажорные
    # единицы). Каждое поле — Derived, потому что каждое приходит из своего
    # места: валюта из enum или примера, единица из типа и примера,
    # экспонента из ISO 4217.
    #
    #   currency   Derived<String> — код ISO 4217
    #   unit       Derived<Symbol> :minor | :major
    #   exponent   Derived<Integer> — экспонента минорной единицы ISO 4217
    #   json_path  поле суммы, для которого выведены единицы
    Units = Struct.new(:currency, :unit, :exponent, :json_path, keyword_init: true)

    # Словарь значений и арифметика Units. Значений по умолчанию нет:
    # каждый член приходит от анализатора вместе с обоснованием, и
    # невыведенное значение обязано объяснить, что искали и не нашли.
    class Units
      include Node

      UNITS = %i[minor major].freeze

      # @param currency [Derived]
      # @param unit [Derived]
      # @param exponent [Derived]
      # @param json_path [String, nil]
      # @raise [ArgumentError]
      def initialize(currency:, unit:, exponent:, json_path: nil)
        Node.assert_derived!(currency, 'валюта')
        Node.assert_derived!(unit, 'единица суммы', allowed: UNITS)
        Node.assert_derived!(exponent, 'экспонента валюты')
        super
      end

      # @return [Integer, nil] множитель от мажорных единиц к единицам
      #   провайдера; nil, если посчитать его пока нельзя
      def multiplier
        return 1 if unit.value == :major
        return nil unless unit.value == :minor && exponent.known?

        10**exponent.value
      end

      # @return [Boolean]
      def known?
        !multiplier.nil?
      end

      # Член, из-за которого множитель не посчитан.
      #
      # Нужен для сообщения человеку. Единица и экспонента выводятся из
      # разных мест, и выведенная единица при невыведенной экспоненте — не
      # редкость: у мультивалютного провайдера `type: integer` прямо говорит
      # «минорные», а какой валюты — станет известно только в рантайме.
      # Показать в таком случае обоснование единицы значит написать
      # «не выведено, потому что выведено»; показывать надо то, чего не
      # хватило.
      #
      # @return [Derived, nil] nil, когда множитель посчитан
      def blocker
        return nil if known?
        return unit unless unit.known?

        exponent
      end

      # @return [Float] наименьшая уверенность среди полей, от которых
      #   зависит множитель; 0.0, если множитель не выведен
      def confidence
        return 0.0 unless known?

        members = unit.value == :major ? [unit] : [unit, exponent]
        members.map(&:confidence).min
      end
    end
  end
end
