# frozen_string_literal: true

module SpecGen
  module Analyzers
    # Все схемы документа под теми именами, которыми их называет остальной
    # IR, — для анализаторов, которые ищут поле по роли, а не читают одну
    # схему целиком.
    #
    # Порядок тот же, что у SchemaAnalyzer, и по той же причине: сначала
    # компоненты в порядке спецификации, затем тела запросов и ответов в
    # порядке операций, затем секция `webhooks` OpenAPI 3.1; вложенные
    # инлайновые объекты регистрируются сразу за родителем. Имена даёт
    # SchemaNaming, поэтому найденное здесь поле суммы указывает на ту же
    # схему, что и `Operation#request_schema`. Каждая схема встречается один
    # раз: компонент, найденный через `$ref` в теле операции, не дублируется.
    #
    # Индекс не пишет в профиль и ничего не выводит: он только отвечает, где
    # что лежит. Выводы делают анализаторы.
    class SchemaIndex
      # Одна схема индекса.
      #
      #   name       имя в profile.schemas
      #   node       объект схемы, `allOf` уже свёрнут
      #   json_path  JSONPath схемы: компонент или место инлайновой схемы
      #   origin     :component | :request | :response | :webhook
      #   operation  Operation#key операции, через тело которой найдена схема;
      #              nil для компонента
      Entry = Struct.new(:name, :node, :json_path, :origin, :operation, keyword_init: true)

      ORIGINS = %i[component request response webhook].freeze
      # Достаточно для любого платёжного тела; глубже — цикл, о котором
      # сообщает SchemaAnalyzer.
      MAX_DEPTH = 8
      ARRAY = 'array'

      # @param data [Object] разрешённый документ
      def initialize(data)
        @data = data.is_a?(Hash) ? data : {}
        @entries = []
        @by_name = {}
        collect
      end

      # @return [Array<Entry>] в порядке спецификации
      attr_reader :entries

      # @param name [String]
      # @return [Entry, nil]
      def entry(name)
        @by_name[name]
      end

      # Поля схемы с их свёрнутыми узлами и JSONPath.
      # @param entry [Entry]
      # @return [Array<Array(String, Hash, String)>] имя, узел, JSONPath
      def fields(entry)
        properties = entry.node['properties']
        return [] unless properties.is_a?(Hash)

        properties.filter_map do |name, body|
          next unless body.is_a?(Hash)

          merged, = SchemaFlattener.call(body)
          [name.to_s, merged, "#{entry.json_path}.properties#{SpecLoader::JsonPath.segment(name)}"]
        end
      end

      # @yieldparam entry [Entry]
      # @yieldparam name [String]
      # @yieldparam node [Hash]
      # @yieldparam json_path [String]
      # @return [Enumerator] если вызван без блока
      def each_field
        return enum_for(:each_field) unless block_given?

        @entries.each do |entry|
          fields(entry).each { |name, node, path| yield(entry, name, node, path) }
        end
      end

      # Схема, на которую смотрит поле-объект или элемент поля-массива.
      # @param entry [Entry] схема, которой принадлежит поле
      # @param name [String] имя поля
      # @param node [Hash] свёрнутый узел поля
      # @return [Entry, nil]
      def nested(entry, name, node)
        child = child_of(entry, name, node, nil)
        child && @by_name[child.first]
      end

      private

      def collect
        components.each { |name, node, path| add(name, node, path, [:component, nil]) }
        Operations.each(@data) { |path, verb, node| bodies(path, verb, node, :request) }
        Operations.each_webhook(@data) { |name, verb, node| bodies(name, verb, node, :webhook) }
      end

      # @return [Array<Array(String, Hash, String)>]
      def components
        section = @data['components']
        listed = section.is_a?(Hash) ? section['schemas'] : nil
        return [] unless listed.is_a?(Hash)

        listed.filter_map do |name, node|
          [name.to_s, node, SchemaNaming.component_path(name.to_s)] if node.is_a?(Hash)
        end
      end

      def bodies(path, verb, node, origin)
        key = SchemaNaming.operation_key(node['operationId'], verb, path)
        section = origin == :webhook ? Operations::WEBHOOKS : Operations::PATHS
        at = SpecLoader::JsonPath.build([section, path, verb])
        body = node['requestBody']
        content(body['content'], [key, 'requestBody'], "#{at}.requestBody", origin, key) if
          body.is_a?(Hash)
        responses(node['responses'], key, at)
      end

      def responses(listed, key, at)
        return unless listed.is_a?(Hash)

        listed.each do |status, response|
          next unless response.is_a?(Hash)

          code = status.to_s
          where = "#{at}.responses#{SpecLoader::JsonPath.segment(code)}"
          content(response['content'], [key, 'responses', code], where, :response, key)
        end
      end

      def content(content, context, at, origin, key)
        media = ContentReader.media_type(content)
        schema = ContentReader.body(content, media)['schema']
        return unless schema.is_a?(Hash)

        component = SchemaNaming.component_of(schema)
        path = component ? SchemaNaming.component_path(component) : inline_path(at, media)
        add(SchemaNaming.name_for(schema, context), schema, path, [origin, key])
      end

      def inline_path(at, media)
        "#{at}.content#{SpecLoader::JsonPath.segment(media)}.schema"
      end

      # Имя записывается раньше, чем читаются поля, поэтому схема, дошедшая
      # до самой себя, находит имя занятым и останавливается.
      # @param source [Array(Symbol, String)] origin и ключ операции
      def add(name, node, path, source, depth = 0)
        return if name.nil? || @by_name.key?(name) || depth > MAX_DEPTH

        merged, = SchemaFlattener.call(node)
        entry = Entry.new(name: name, node: merged, json_path: path, origin: source.first,
                          operation: source.last)
        @by_name[name] = entry
        @entries << entry
        fields(entry).each do |field, body, field_path|
          child = child_of(entry, field, body, field_path)
          add(*child, source, depth + 1) if child
        end
      end

      # Компонентная схема сохраняет имя и путь компонента, через какое бы
      # поле её ни нашли; инлайновый объект называется по месту.
      # @return [Array(String, Hash, String), nil] имя, узел, JSONPath
      def child_of(entry, field, body, field_path)
        target, context, at = target_of(entry, field, body, field_path)
        return nil unless target.is_a?(Hash)

        component = SchemaNaming.component_of(target)
        return [component, target, SchemaNaming.component_path(component)] if component
        return nil unless target['properties'].is_a?(Hash)

        [SchemaNaming.synthetic(context), target, at]
      end

      def target_of(entry, field, body, field_path)
        type, = ConstraintReader.type_of(body)
        if type == ARRAY || body.key?('items')
          [body['items'], [entry.name, 'properties', field, 'items'], "#{field_path}.items"]
        else
          [body, [entry.name, 'properties', field], field_path]
        end
      end
    end
  end
end
