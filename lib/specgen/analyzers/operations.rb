# frozen_string_literal: true

module SpecGen
  module Analyzers
    # Обход операций документа — один на всех, кто их читает.
    #
    # Base#each_operation, SchemaIndex и анализаторы, которым нужен документ
    # без профиля, обязаны видеть один и тот же список операций в одном и том
    # же порядке: порядок операций — это порядок спецификации, и от него
    # зависят имена инлайновых схем, порядок предупреждений и golden-тесты.
    # Path item и операции неверной формы пропускаются молча: загрузчик
    # гарантирует, что `paths` есть, а не что каждый его угол — объект.
    module Operations
      # Фиксированные поля Path Item Object, которые являются операциями
      # (OpenAPI 3).
      HTTP_METHODS = %w[get put post delete options head patch trace].freeze
      PATHS = 'paths'
      # Секция OpenAPI 3.1: вебхуки, описанные вне `paths`. Её ключи — имена
      # вебхуков, а не пути, поэтому они и обходятся отдельно.
      WEBHOOKS = 'webhooks'

      # @param data [Object] разрешённый документ
      # @yieldparam path [String] шаблон, например "/payouts/{id}"
      # @yieldparam http_method [String] в нижнем регистре, один из HTTP_METHODS
      # @yieldparam operation [Hash] Operation Object
      # @return [Enumerator] если вызван без блока
      def self.each(data, &)
        return enum_for(:each, data) unless block_given?

        each_in(data, PATHS, &)
      end

      # @param data [Object] разрешённый документ
      # @yieldparam name [String] имя вебхука — ключ секции `webhooks`
      # @yieldparam http_method [String]
      # @yieldparam operation [Hash]
      # @return [Enumerator] если вызван без блока
      def self.each_webhook(data, &)
        return enum_for(:each_webhook, data) unless block_given?

        each_in(data, WEBHOOKS, &)
      end

      # @param data [Object]
      # @param section [String] PATHS или WEBHOOKS
      # @return [void]
      def self.each_in(data, section)
        items = data.is_a?(Hash) ? data[section] : nil
        return unless items.is_a?(Hash)

        items.each do |key, item|
          next unless item.is_a?(Hash)

          item.each do |http_method, operation|
            next unless HTTP_METHODS.include?(http_method) && operation.is_a?(Hash)

            yield(key.to_s, http_method, operation)
          end
        end
      end
    end
  end
end
