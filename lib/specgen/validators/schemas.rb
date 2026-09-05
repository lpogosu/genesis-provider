# frozen_string_literal: true

module SpecGen
  module Validators
    # Схемы спецификации, скомпилированные валидатором JSON Schema.
    #
    # Диалект выбирается по версии OpenAPI: у 3.0 это диалект OpenAPI 3.0
    # (`nullable`, булев `exclusiveMinimum`), у 3.1 — JSON Schema 2020-12.
    # Компилируем схему из разрешённого документа (того же, который читали
    # анализаторы), поэтому подсхемы самодостаточны и `$ref` в них не
    # осталось.
    #
    # Одна и та же схема встречается у нескольких фикстур (три примера
    # одного ответа, общая схема ошибки у восьми кодов), поэтому
    # скомпилированное кешируется по пути: на спецификации Adyen это разница
    # между секундами и минутами.
    class Schemas
      # Диалект JSON Schema по семейству версий OpenAPI.
      META = { oas30: JSONSchemer::OpenAPI30::BASE_URI,
               oas31: JSONSchemer::OpenAPI31::BASE_URI }.freeze
      DISCRIMINATOR = 'discriminator'

      # @param document [SpecLoader::Document]
      def initialize(document)
        @data = document.data
        @meta = META.fetch(document.family).to_s
        @cache = {}
      end

      # @param keys [Array<String>, nil] путь до схемы в разрешённом документе
      # @return [JSONSchemer::Schema, nil] nil, если схемы там нет
      def at(keys)
        return nil if keys.nil?

        @cache.fetch(keys) { @cache[keys] = compile(@data.dig(*keys)) }
      end

      private

      def compile(node)
        return nil unless node.is_a?(Hash)

        JSONSchemer.schema(prune(node), meta_schema: @meta)
      end

      # `discriminator` адресует ветку `oneOf` через `$ref`, а в разрешённом
      # документе ссылки уже подставлены — адресовать нечего, и валидатор
      # спотыкается на первой же такой схеме. Ключ снимается, и тело
      # проверяется самим `oneOf`: по тексту OpenAPI дискриминатор только
      # подсказывает ветку, совпасть с ней тело обязано в любом случае.
      def prune(node)
        case node
        when Hash
          node.each_with_object({}) do |(key, value), pruned|
            pruned[key] = prune(value) unless key == DISCRIMINATOR
          end
        when Array then node.map { |item| prune(item) }
        else node
        end
      end
    end
  end
end
