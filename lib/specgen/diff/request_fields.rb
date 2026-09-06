# frozen_string_literal: true

module SpecGen
  module Diff
    # Поля тела запроса одной операции, включая вложенные схемы, ключом
    # «путь от корня тела» (`recipient.phone`).
    #
    # Спускаться во вложенные схемы обязательно: условная обязательность
    # реквизитов живёт не в схеме тела, а в схеме получателя, и сравнение,
    # видящее только первый уровень, не заметило бы ни смены роли реквизита,
    # ни появления нового способа выплаты.
    module RequestFields
      # Та же граница, что у сборщика фикстур: глубже спецификации платёжных
      # провайдеров не описывают тело запроса, а рекурсия по чужой схеме
      # обязана иметь предел.
      MAX_DEPTH = 4

      # @param profile [IR::ProviderProfile] откуда брать вложенные схемы
      # @param operation [IR::Operation, nil]
      # @return [Hash{String => IR::Field}] поля по пути от корня тела
      def self.call(profile, operation)
        schema = operation && profile.schema(operation.request_schema)
        return {} if schema.nil?

        collect(profile, schema, nil, [schema.name], {})
      end

      # Цикл схем размыкается списком уже пройденных имён: схема, ссылающаяся
      # на себя, законна, а бесконечный обход — нет.
      def self.collect(profile, schema, prefix, seen, found)
        schema.fields.each do |field|
          name = [prefix, field.name].compact.join('.')
          found[name] = field
          nested = field.schema && profile.schema(field.schema)
          next if nested.nil? || seen.include?(nested.name) || seen.size >= MAX_DEPTH

          collect(profile, nested, name, seen + [nested.name], found)
        end
        found
      end
      private_class_method :collect
    end
  end
end
