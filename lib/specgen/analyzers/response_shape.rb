# frozen_string_literal: true

module SpecGen
  module Analyzers
    # Форма успешного ответа операции: одиночный ресурс или список.
    #
    # Это отличие READ_ONE от READ_MULTI в терминах RestTestGen (Corradini,
    # Zampieri, Pasqua, Ceccato, ICSE 2023): CRUD-семантику эндпоинта задаёт
    # не только путь, но и то, что он возвращает. `GET /payouts` и
    # `GET /payouts/{id}` различаются формой ответа, и опрашивать статус
    # конкретной выплаты у листинга нельзя.
    #
    # Списком считается ответ-массив и ответ-объект, у которого после
    # отбрасывания служебных свойств (`meta`, `links`, `page`, `status` —
    # список в rules/operations.yml) осталось ровно одно свойство и оно
    # массив. Правило намеренно узкое: объект с двумя содержательными
    # полями — это ресурс, даже если одно из них массив.
    module ResponseShape
      # @param node [Hash] Operation Object разрешённого документа
      # @param ignore [Array<String>] нормализованные имена служебных свойств
      # @return [Boolean] успешный ответ операции является списком
      def self.list?(node, ignore:)
        schema = success_schema(node)
        return false unless schema.is_a?(Hash)

        list_schema?(schema, ignore)
      end

      # @return [Boolean]
      def self.list_schema?(schema, ignore)
        return true if array?(schema)

        properties = schema['properties']
        return false unless properties.is_a?(Hash)

        payload = properties.reject { |name, _| ignore.include?(Rules::Normalizer.call(name)) }
        payload.size == 1 && array?(payload.values.first)
      end

      # @return [Boolean] схема объявлена массивом (OAS 3.0 и 3.1)
      def self.array?(schema)
        return false unless schema.is_a?(Hash)

        type = schema['type']
        type == 'array' || (type.is_a?(Array) && type.include?('array')) ||
          schema.key?('items')
      end

      # @param node [Hash] Operation Object
      # @return [Hash, nil] схема первого ответа 2xx
      def self.success_schema(node)
        responses = node['responses']
        return nil unless responses.is_a?(Hash)

        _, body = responses.find { |status, node| status.to_s.start_with?('2') && node.is_a?(Hash) }
        content = body&.[]('content')
        ContentReader.body(content, ContentReader.media_type(content))['schema']
      end
    end
  end
end
