# frozen_string_literal: true

module SpecGen
  module Analyzers
    # Одно правило именования схемы, общее для каждого анализатора, который
    # схему упоминает. Операции, ответы и вебхуки ссылаются на схемы по
    # имени, а SchemaAnalyzer раскладывает их под тем же именем, поэтому обе
    # стороны обязаны выводить его одинаково — отсюда отдельный модуль, а не
    # два похожих приватных метода.
    #
    # Схема, пришедшая из `$ref`, сохраняет имя своей компоненты: резолвер
    # заменил ссылку её целью, но оставил исходный указатель в
    # `x-specgen-ref`, поэтому имя переживает разыменование. У инлайновой
    # схемы своего имени нет, и она получает синтетическое, построенное из
    # места, где она стоит: "getBalance.responses.200".
    module SchemaNaming
      # Оставлен SpecLoader::RefResolver на каждом разыменованном объекте.
      MARKER = SpecLoader::RefResolver::MARKER
      SEPARATOR = '.'

      # @param schema [Object] разрешённый объект схемы
      # @param context [Array<String>] где она стоит, например
      #   ["createPayout", "requestBody"]
      # @return [String, nil] nil, если схемы нет вовсе
      def self.name_for(schema, context)
        return nil unless schema.is_a?(Hash)

        component_of(schema) || synthetic(context)
      end

      # @param schema [Object] разрешённый объект схемы; всё, что не объект
      #   (nil у тела без схемы, скаляр в битой спецификации), имени не имеет
      # @return [String, nil] имя компоненты, если схема пришла из `$ref`
      def self.component_of(schema)
        return nil unless schema.is_a?(Hash)

        ref = schema[MARKER]
        return nil unless ref.is_a?(String)

        name = ref.split('/').last.to_s
        name.empty? ? nil : name
      end

      # @param context [Array<String>]
      # @return [String, nil]
      def self.synthetic(context)
        parts = Array(context).compact.map(&:to_s).reject(&:empty?)
        parts.empty? ? nil : parts.join(SEPARATOR)
      end

      # Где живёт компонентная схема, через какое бы место использования её
      # ни нашли. У схемы один JSONPath: предупреждения и target'ы overlay
      # обязаны указывать на саму компоненту, а не на копию, которую
      # резолвер оставил внутри операции.
      # @param name [String] имя компоненты
      # @return [String] "$.components.schemas.Recipient"
      def self.component_path(name)
        SpecLoader::JsonPath.build(['components', 'schemas', name])
      end

      # Как операция называется внутри синтетического имени схемы: по своему
      # operationId, а если в спецификации его нет — по методу и пути, чтобы
      # имя оставалось устойчивым и уникальным и без него.
      # @param id [String, nil] operationId
      # @param http_method [String, Symbol]
      # @param path [String]
      # @return [String] "createPayout" или "post_payouts_payout_id"
      def self.operation_key(id, http_method, path)
        return id.strip if id.is_a?(String) && !id.strip.empty?

        Rules::Normalizer.call("#{http_method}_#{path}")
      end
    end
  end
end
