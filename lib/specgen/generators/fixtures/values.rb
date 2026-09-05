# frozen_string_literal: true

module SpecGen
  module Generators
    module Fixtures
      # Тело примера, когда спецификация не дала готового `example` для
      # операции: собирается из самой схемы IR — `example` свойства, первое
      # значение `enum`, `const`, `default`, — а недостающее заполняется
      # заглушкой по типу.
      #
      # Значение, придуманное здесь, никогда не выдаётся за пример из
      # спецификации: Result#synthesized говорит, была ли хоть одна заглушка,
      # и по нему фикстура получает source schema_example или synthesized.
      class Values
        # Глубина вложенности схем: у чужих спецификаций объекты ссылаются
        # друг на друга десятками уровней, а фикстура должна остаться
        # читаемой.
        MAX_DEPTH = 4
        PLACEHOLDERS = { 'string' => 'string', 'integer' => 0, 'number' => 0, 'boolean' => true,
                         'array' => [], 'object' => {} }.freeze
        DEFAULT_PLACEHOLDER = 'string'
        # Значения, похожие на настоящий секрет: в фикстуры они не попадают
        # даже из чужой спецификации.
        SECRET = /\A(?:[A-Za-z]{2,6}_)?live_[A-Za-z0-9]{8,}\z/

        # Значение вместе с признаком «часть значений — заглушки».
        Result = Struct.new(:value, :synthesized, keyword_init: true)

        # @param ctx [Service::Context]
        def initialize(ctx)
          @ctx = ctx
        end

        # @param name [String, nil] имя схемы тела
        # @return [Result] объект-пример; nil, если схемы нет
        def body(name)
          schema = @ctx.schema(name)
          return Result.new(value: nil, synthesized: true) if schema.nil?

          object(schema, [], 0)
        end

        # Пример значения поля с заданной ролью из любой схемы профиля:
        # параметр пути без своего `example` получает идентификатор из схемы
        # ответа, а не выдуманную строку.
        # @param role [Symbol, nil]
        # @return [Object, nil]
        def role_example(role)
          return nil if role.nil?

          @ctx.profile.schemas.each_value do |schema|
            field = schema.fields.find { |item| item.role.value == role && !item.example.nil? }
            return field.example if field
          end
          nil
        end

        # @param value [Object]
        # @return [Object] глубокая копия: примеры из IR читают несколько
        #   фикстур, подстановка одной не должна менять другие
        def self.dup_value(value)
          case value
          when Hash then value.to_h { |key, item| [key, dup_value(item)] }
          when Array then value.map { |item| dup_value(item) }
          else value
          end
        end

        # @param value [Object]
        # @param path [Array<String>, nil] путь до вложенного ключа
        # @return [Object, nil] значение по пути; nil, если пути нет
        def self.dig_path(value, path)
          return nil if path.nil? || path.empty?

          path.reduce(value) { |item, key| item.is_a?(Hash) ? item[key] : nil }
        end

        # @param value [Object]
        # @param path [Array<String>, nil] путь до вложенного ключа
        # @param replacement [Object]
        # @return [Object, nil] подставленное значение; nil, если ключа нет
        def self.assign(value, path, replacement)
          return if path.nil? || path.empty?

          node = path[0..-2].reduce(value) { |item, key| item.is_a?(Hash) ? item[key] : nil }
          return unless node.is_a?(Hash) && node.key?(path.last)

          node[path.last] = replacement
        end

        # @param value [Object]
        # @param stub [String] чем заменять похожее на секрет
        # @return [Array(Object, Boolean)] значение и признак замены
        def self.redact(value, stub)
          case value
          when Hash then redact_pairs(value.keys, value, stub) { |key| value[key] }
          when Array then redact_pairs((0...value.size).to_a, value, stub) { |i| value[i] }
          when String then value.match?(SECRET) ? [stub, true] : [value, false]
          else [value, false]
          end
        end

        # @return [Array(Object, Boolean)]
        def self.redact_pairs(keys, container, stub)
          changed = false
          keys.each do |key|
            item, hit = redact(yield(key), stub)
            container[key] = item
            changed ||= hit
          end
          [container, changed]
        end
        private_class_method :redact_pairs

        private

        # Объект по полям схемы. Схема, у которой ни одно поле не подсказало
        # значение, собирается целиком: пустое тело в фикстуре бесполезнее
        # заглушки, а source честно скажет synthesized.
        # @return [Result]
        def object(schema, visited, depth)
          return Result.new(value: {}, synthesized: true) if visited.include?(schema.name)

          result = fields(schema, visited, depth, hinted: true)
          return result unless result.value.empty? && !schema.fields.empty?

          fields(schema, visited, depth, hinted: false)
        end

        # @param hinted [Boolean] брать только поля, о которых спецификация
        #   что-то сказала
        # @return [Result]
        def fields(schema, visited, depth, hinted:)
          synthesized = false
          value = {}
          schema.fields.each do |field|
            next if hinted && !include?(field)

            result = field_value(field, visited + [schema.name], depth)
            value[field.name] = result.value
            synthesized ||= result.synthesized
          end
          Result.new(value: value, synthesized: synthesized)
        end

        # Обязательное поле в примере нужно всегда; необязательное — только
        # тогда, когда спецификация сама подсказала значение.
        def include?(field)
          field.required? || !field.example.nil? || !field.enum.nil? ||
            !field.constraints[:const].nil? || !field.constraints[:default].nil?
        end

        def field_value(field, visited, depth)
          declared = declared_value(field)
          return Result.new(value: declared, synthesized: false) unless declared.nil?
          return nested(field, visited, depth) unless field.schema.nil?

          stub(field.type)
        end

        # @return [Object, nil] значение, названное самой спецификацией
        def declared_value(field)
          return field.example unless field.example.nil?
          return field.constraints[:const] unless field.constraints[:const].nil?
          return field.enum.first if field.enum.is_a?(Array) && !field.enum.empty?

          field.constraints[:default]
        end

        def nested(field, visited, depth)
          inner = @ctx.schema(field.schema)
          return stub(field.type) if flat?(inner, depth)

          result = object(inner, visited, depth + 1)
          return result unless field.type == 'array'

          Result.new(value: [result.value], synthesized: result.synthesized)
        end

        # @return [Boolean] дальше раскрывать нечего или незачем
        def flat?(inner, depth)
          inner.nil? || depth >= MAX_DEPTH
        end

        # @return [Result] заглушка по типу: значения спецификация не дала
        def stub(type)
          Result.new(value: PLACEHOLDERS.fetch(type.to_s, DEFAULT_PLACEHOLDER), synthesized: true)
        end
      end
    end
  end
end
