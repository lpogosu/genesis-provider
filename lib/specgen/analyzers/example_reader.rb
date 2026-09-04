# frozen_string_literal: true

module SpecGen
  module Analyzers
    # Примеры спецификации как источник фактов, которых нет в схемах.
    #
    # Статус в примере ответа, код ошибки в примере 404, событие в примере
    # тела вебхука — всё это спецификация говорит не ключевыми словами, а
    # данными. Пример не заменяет enum: значение, найденное только здесь,
    # анализаторы записывают вместе с предупреждением о расхождении. Но и
    # выбросить его нельзя: код ошибки, которого нет в enum, всё равно
    # придёт в ответе.
    #
    # Каждое найденное значение несёт JSONPath — предупреждение указывает
    # на сам пример, а не на операцию целиком, — и имена родителей, по
    # которым RoleLookup узнаёт `error.code` среди других `code`.
    module ExampleReader
      # Один пример из документа.
      #
      #   operation  Operation#key
      #   place      :request | :response
      #   status     код ответа для :response, иначе nil
      #   name       имя примера или Response::DEFAULT_EXAMPLE
      #   value      сам пример
      #   json_path  JSONPath значения примера
      #   schema     имя схемы тела, к которому относится пример, или nil
      Example = Struct.new(:operation, :place, :status, :name, :value, :json_path, :schema,
                           keyword_init: true)

      # Примеры конечны, но YAML с якорями может быть глубже здравого смысла.
      MAX_DEPTH = 16

      # Все примеры всех операций и вебхуков документа, в порядке спецификации.
      # @param data [Object] разрешённый документ
      # @yieldparam example [Example]
      # @return [Enumerator] если вызван без блока
      def self.each_in_document(data, &block)
        return enum_for(:each_in_document, data) unless block

        Operations.each(data) do |path, verb, node|
          each_in_operation(node, key_of(node, verb, path), [Operations::PATHS, path, verb], &block)
        end
        Operations.each_webhook(data) do |name, verb, node|
          each_in_operation(node, key_of(node, verb, name), [Operations::WEBHOOKS, name, verb],
                            &block)
        end
      end

      # @param node [Hash] Operation Object
      # @param key [String] Operation#key
      # @param keys [Array<String>] путь ключей операции от корня
      # @yieldparam example [Example]
      # @return [void]
      def self.each_in_operation(node, key, keys, &)
        at = SpecLoader::JsonPath.build(keys)
        body = node['requestBody']
        if body.is_a?(Hash)
          each_example(body['content'], "#{at}.requestBody", [key, 'requestBody']) do |*found|
            yield build(key, :request, nil, found)
          end
        end
        each_response(node['responses'], key, at, &)
      end

      # @return [void]
      def self.each_response(responses, key, at)
        return unless responses.is_a?(Hash)

        responses.each do |status, response|
          next unless response.is_a?(Hash)

          code = status.to_s
          where = "#{at}.responses#{SpecLoader::JsonPath.segment(code)}"
          each_example(response['content'], where, [key, 'responses', code]) do |*found|
            yield build(key, :response, code, found)
          end
        end
      end

      # @param found [Array(String, Object, String, String)] имя, значение,
      #   JSONPath и схема, как их отдаёт .each_example
      # @return [Example]
      def self.build(key, place, status, found)
        name, value, path, schema = found
        Example.new(operation: key, place: place, status: status, name: name, value: value,
                    json_path: path, schema: schema)
      end

      # Примеры одного отображения `content`: именованные `examples` и
      # одиночный `example`, каждый со своим JSONPath.
      # @param content [Object]
      # @param at [String] JSONPath объекта, несущего `content`
      # @param context [Array<String>] для SchemaNaming
      # @yieldparam name [String]
      # @yieldparam value [Object]
      # @yieldparam json_path [String]
      # @yieldparam schema [String, nil]
      # @return [void]
      def self.each_example(content, at, context)
        media = ContentReader.media_type(content)
        return if media.nil?

        body = ContentReader.body(content, media)
        base = "#{at}.content#{SpecLoader::JsonPath.segment(media)}"
        schema = SchemaNaming.name_for(body['schema'], context)
        listed = body['examples']
        if listed.is_a?(Hash)
          listed.each do |name, item|
            yield(name.to_s, ContentReader.value_of(item), named(base, name, item), schema)
          end
        elsif body.key?('example')
          yield(IR::Response::DEFAULT_EXAMPLE, body['example'], "#{base}.example", schema)
        end
      end

      # @return [String] JSONPath значения именованного примера
      def self.named(base, name, item)
        path = "#{base}.examples#{SpecLoader::JsonPath.segment(name.to_s)}"
        item.is_a?(Hash) && item.key?('value') ? "#{path}.value" : path
      end

      # Каждая пара «ключ — значение» внутри примера, на любой глубине.
      # @param value [Object] пример
      # @param path [String] его JSONPath
      # @param parents [Array<String>] имена родителей, ближний первым; на
      #   верхнем уровне — имя схемы, если известно
      # @yieldparam key [String]
      # @yieldparam item [Object]
      # @yieldparam parents [Array<String>]
      # @yieldparam json_path [String]
      # @return [void]
      def self.each_pair(value, path, parents = [], depth = 0, &block)
        return if depth > MAX_DEPTH

        case value
        when Hash then each_hash_pair(value, path, parents, depth, &block)
        when Array
          value.each_with_index do |item, index|
            each_pair(item, "#{path}[#{index}]", parents, depth + 1, &block)
          end
        end
      end

      # @return [void]
      def self.each_hash_pair(hash, path, parents, depth, &block)
        hash.each do |key, item|
          name = key.to_s
          at = path + SpecLoader::JsonPath.segment(name)
          yield(name, item, parents, at)
          each_pair(item, at, [name] + parents, depth + 1, &block)
        end
      end

      def self.key_of(node, verb, path)
        SchemaNaming.operation_key(node['operationId'], verb, path)
      end
      private_class_method :key_of
    end
  end
end
