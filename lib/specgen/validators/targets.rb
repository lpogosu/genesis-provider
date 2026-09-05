# frozen_string_literal: true

module SpecGen
  module Validators
    # Где в спецификации лежит схема тела, которое собрал генератор.
    #
    # Фикстура называет операцию ключом IR (`operationId` либо
    # «POST /payouts»), а схему надо искать в документе — по шаблону пути и
    # методу той же операции. Отсюда путь ключей, из которого потом
    # получается и JSONPath для отчёта, и сама схема.
    class Targets
      # Тип содержимого, который читает сгенерированный сервис; если его нет,
      # берём первый объявленный со схемой — проверять что-то лучше, чем
      # молчать.
      JSON_PREFIX = 'application/json'

      # @param document [SpecLoader::Document]
      # @param profile [IR::ProviderProfile]
      def initialize(document:, profile:)
        @data = document.data
        @operations = profile.operations.to_h { |operation| [operation.key, operation] }
      end

      # @param key [String] Operation#key из фикстуры
      # @return [IR::Operation, nil]
      def operation(key)
        @operations[key]
      end

      # @param operation [IR::Operation]
      # @return [Array<String>, nil] путь до схемы тела запроса
      def request(operation)
        body_keys([*base(operation), 'requestBody'])
      end

      # @param operation [IR::Operation]
      # @param response [IR::Response]
      # @return [Array<String>, nil] путь до схемы тела ответа
      def response(operation, response)
        body_keys([*base(operation), 'responses', response.status])
      end

      # Схема входящего уведомления — тело запроса операции вебхука; если
      # спецификация описала вебхук вне `paths` (3.1), остаётся компонентная
      # схема, имя которой знает IR.
      # @param webhook [IR::Webhook]
      # @return [Array<String>, nil]
      def notification(webhook)
        found = webhook.operation && operation(webhook.operation)
        return request(found) if found
        return nil if webhook.schema.nil?

        keys = ['components', 'schemas', webhook.schema]
        @data.dig(*keys) ? keys : nil
      end

      private

      def base(operation)
        ['paths', operation.path, operation.http_method.to_s]
      end

      # @return [Array<String>, nil] nil, если тела нет или схему не объявили
      def body_keys(prefix)
        content = @data.dig(*prefix, 'content')
        return nil unless content.is_a?(Hash)

        media = media_type(content)
        media && [*prefix, 'content', media, 'schema']
      end

      def media_type(content)
        with_schema = content.keys.select { |name| content.dig(name, 'schema').is_a?(Hash) }
        with_schema.find { |name| name.to_s.start_with?(JSON_PREFIX) } || with_schema.first
      end
    end
  end
end
