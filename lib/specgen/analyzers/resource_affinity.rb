# frozen_string_literal: true

module SpecGen
  module Analyzers
    # Связаны ли две операции одним ресурсом — структурно, по спецификации.
    #
    # Правила producer -> consumer взяты у RESTler (Atlidakis, Godefroid,
    # Polishchuk, ICSE 2019), который выводит зависимости между запросами из
    # формы путей и тел, а не из документации:
    #
    #   :container    последний сегмент пути перед параметром у консьюмера
    #                 совпадает с последним статическим сегментом у продюсера
    #                 (`POST /transfers` и `GET /transfers/{id}` — да,
    #                 `GET /transactions/{id}` — нет)
    #   :path_prefix  путь консьюмера начинается с пути продюсера
    #   :schema       схема успешного ответа общая
    #
    # Здесь нет ни весов, ни решения: правила — данные, вес каждого лежит в
    # rules/operations.yml, а выбор пары делает OperationPairing.
    module ResourceAffinity
      TEMPLATE = /\A\{.+\}\z/

      # @param producer [IR::Operation] операция создания
      # @param consumer [IR::Operation] операция, читающая созданное
      # @return [Array<Symbol>] сработавшие правила, сильные первыми
      def self.rules(producer, consumer)
        found = []
        found << :container if same_container?(producer, consumer)
        found << :path_prefix if prefix?(producer.path, consumer.path)
        found << :schema if shared_schema(producer, consumer)
        found
      end

      # @return [Boolean]
      def self.same_container?(producer, consumer)
        into = tail(producer.path)
        !into.nil? && into == container(consumer.path)
      end

      # @return [Boolean]
      def self.prefix?(producer, consumer)
        producer == consumer || consumer.start_with?("#{producer}/")
      end

      # @return [String, nil] имя общей схемы успешного ответа
      def self.shared_schema(producer, consumer)
        (schemas(producer) & schemas(consumer)).first
      end

      # @return [Array<String>] имена схем ответов 2xx
      def self.schemas(operation)
        operation.success_responses.filter_map(&:schema)
      end

      # Контейнер ресурса, у которого читают один экземпляр: сегмент перед
      # последним параметром пути. `/payouts/{id}/cancel` — тоже `payouts`:
      # отмена обращается к тому же ресурсу, что и чтение.
      # @return [String, nil] нормализованное имя
      def self.container(path)
        parts = segments(path)
        last = parts.rindex { |part| TEMPLATE.match?(part) }
        return tail(path) if last.nil?

        before = parts[0...last].grep_v(TEMPLATE).last
        before && Rules::Normalizer.call(before)
      end

      # Контейнер, в который создают: последний статический сегмент.
      # @return [String, nil] нормализованное имя
      def self.tail(path)
        last = segments(path).grep_v(TEMPLATE).last
        last && Rules::Normalizer.call(last)
      end

      # @return [Array<String>] сегменты пути как они написаны
      def self.segments(path)
        path.to_s.split('/').reject(&:empty?)
      end

      # @return [Integer] длина access path — чем короче, тем вероятнее это
      #   основной ресурс, а не его придаток
      def self.depth(path)
        segments(path).size
      end
    end
  end
end
