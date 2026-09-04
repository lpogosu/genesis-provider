# frozen_string_literal: true

module SpecGen
  module Analyzers
    # Читает отображение `content` — единственную форму, общую для тел
    # запросов, ответов и payload вебхуков: под какой media type
    # генерировать, какая у тела схема и какие примеры предлагает
    # спецификация.
    #
    # JSON побеждает, если спецификация его предлагает, потому что на нём
    # говорит сгенерированный сервис; спецификация, предлагающая только
    # что-то другое, — не ошибка, тогда берётся первый объявленный тип.
    # Примеры нормализуются к одной форме, {имя => значение}, чтобы
    # fixtures.json не приходилось знать, написала спецификация `examples`
    # или одиночный `example`.
    module ContentReader
      JSON = IR::Operation::JSON
      JSON_HINT = 'json'

      # @param content [Object] отображение `content`
      # @return [String, nil] media type, который надо читать, nil если его нет
      def self.media_type(content)
        return nil unless content.is_a?(Hash)

        types = content.keys.grep(String)
        return nil if types.empty?
        return JSON if types.include?(JSON)

        types.find { |type| type.include?(JSON_HINT) } || types.first
      end

      # @param content [Object]
      # @param media [String, nil]
      # @return [Hash] объект media type; пустой, если его нет или он искажён
      def self.body(content, media)
        value = content.is_a?(Hash) ? content[media] : nil
        value.is_a?(Hash) ? value : {}
      end

      # @param content [Object]
      # @param media [String, nil]
      # @param context [Array<String>] для SchemaNaming
      # @return [String, nil] имя схемы тела
      def self.schema_name(content, media, context)
        SchemaNaming.name_for(body(content, media)['schema'], context)
      end

      # @param content [Object]
      # @param media [String, nil]
      # @return [Hash{String => Object}] одиночный `example` попадает под
      #   ключ Response::DEFAULT_EXAMPLE
      def self.examples(content, media)
        node = body(content, media)
        listed = node['examples']
        return listed.to_h { |name, item| [name.to_s, value_of(item)] } if listed.is_a?(Hash)
        return { IR::Response::DEFAULT_EXAMPLE => node['example'] } if node.key?('example')

        {}
      end

      # Example Object несёт payload под ключом `value`; всё остальное
      # считается самим payload.
      # @param item [Object]
      # @return [Object]
      def self.value_of(item)
        item.is_a?(Hash) && item.key?('value') ? item['value'] : item
      end
    end
  end
end
