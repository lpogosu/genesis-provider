# frozen_string_literal: true

module SpecGen
  module Generators
    # Обход полей схемы так же, как его делает Service::Payload: скалярные
    # поля в порядке спецификации, вложенные объекты раскрываются, массивы
    # и циклы — нет. Отчёт обязан считать ровно те поля, которые видел
    # генератор кода, иначе покрытие описывало бы другую схему.
    class SchemaFields
      # Та же глубина, на которой останавливается сборка payload.
      MAX_DEPTH = Service::Payload::MAX_DEPTH
      # Полю-контейнеру роль не положена: её получают вложенные поля. Тот
      # же список, что у Reporter::SchemaLines; повторён здесь, потому что
      # стадия генерации загружается раньше отчёта.
      CONTAINERS = %w[object array].freeze

      # Одно скалярное поле с путём от корня схемы.
      #   field   IR::Field
      #   path    "recipient.phone"
      #   schema  имя схемы, в которой поле объявлено
      Entry = Struct.new(:field, :path, :schema, keyword_init: true)

      # @param ctx [Service::Context]
      def initialize(ctx)
        @ctx = ctx
        @cache = {}
      end

      # @param name [String, nil] имя схемы
      # @return [Array<Entry>] скалярные поля, в порядке схемы
      def of(name)
        return [] if name.nil?

        @cache[name] ||= walk(@ctx.schema(name), [], [name], 0)
      end

      # @param field [IR::Field]
      # @return [Boolean] поле-контейнер, роли у него нет по устройству модели
      def self.container?(field)
        !field.schema.nil? || CONTAINERS.include?(field.type)
      end

      private

      def walk(schema, prefix, visited, depth)
        return [] if schema.nil? || depth >= MAX_DEPTH

        schema.fields.flat_map do |field|
          path = [*prefix, field.name]
          next [entry(schema, field, path)] unless nested?(field, visited)

          walk(@ctx.schema(field.schema), path, visited + [field.schema], depth + 1)
        end
      end

      def entry(schema, field, path)
        Entry.new(field: field, path: path.join('.'), schema: schema.name)
      end

      def nested?(field, visited)
        field.schema && field.type != 'array' && !visited.include?(field.schema)
      end
    end
  end
end
