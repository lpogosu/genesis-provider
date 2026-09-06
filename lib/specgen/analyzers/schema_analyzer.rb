# frozen_string_literal: true

module SpecGen
  module Analyzers
    # Заполняет profile.schemas: каждую схему, которую сгенерированный сервис
    # обязан собрать или прочитать, под тем именем, которым её называет
    # остальной IR.
    #
    # Три источника в фиксированном порядке, чтобы два прогона давали один и
    # тот же файл: сначала компоненты в порядке спецификации, затем тела
    # запросов и ответов в порядке операций, затем всё, до чего эти два
    # добрались через вложенные объекты и элементы массивов. Компонент, на
    # который никто не ссылается, тоже остаётся: он часть того, что предлагает
    # провайдер, а заметить, что он не используется, — дело отчёта.
    #
    # Имена даёт SchemaNaming, тот же модуль, которым пользуется
    # OperationAnalyzer, поэтому `Operation#request_schema` и
    # `Response#schema` — ключи этого хеша, а не висящие в воздухе строки.
    #
    # Роли полей проставляются здесь же, в момент чтения схемы, через общий
    # компонент Matchers::Assigner — так же, как роль операции даёт общий
    # OperationRole. Отдельной стадии, которая читала бы уже собранные поля
    # профиля, нет намеренно: анализаторы не читают то, что записал другой.
    class SchemaAnalyzer < Base
      # Достаточно глубоко для любого платёжного тела; цикл, который не
      # поймал резолвер, останавливается здесь предупреждением, а не
      # переполнением стека.
      MAX_DEPTH = 8
      # Коды ответов, у которых тела нет по семантике HTTP (RFC 9110):
      # 1xx проверяется отдельно префиксом. `default` — заглушка «на всё
      # остальное», обещанием тела она тоже не является.
      BODILESS = %w[204 205 304 default].freeze
      INFORMATIONAL = '1'
      WEBHOOK = :webhook

      # Заполняет `profile.schemas`.
      # @return [IR::ProviderProfile] тот профиль, который был передан
      def call
        @assigner = Matchers::Assigner.new(rules: rules)
        component_schemas.each { |name, node, at| register(name, node, at) }
        body_schemas.each { |name, node, at| register(name, node, at) }
        check_links
        report_cycles
        profile
      end

      private

      # Рекурсивная схема не отвергает документ: загрузчик размыкает цикл
      # заглушкой без полей. Но заглушка — это поля, которых в коде не
      # будет, поэтому о каждом разомкнутом цикле отчёт говорит отдельно.
      def report_cycles
        document.cycles.each do |chain, at|
          profile.warn(:schema_unresolved,
                       Texts.t('analyzers.schema.ref_cycle', chain: chain), json_path: at)
        end
      end

      # @return [Array<Array(String, Object, String)>] имя, узел, JSONPath
      def component_schemas
        components = data['components']
        listed = components.is_a?(Hash) ? components['schemas'] : nil
        return [] if listed.nil?
        return unusable unless listed.is_a?(Hash)

        listed.map { |name, node| [name.to_s, node, schema_path(name)] }
      end

      def unusable
        profile.warn(:spec_element_unsupported,
                     Texts.t('analyzers.schema.components_not_object'),
                     json_path: json_path('components', 'schemas'))
        []
      end

      # @return [Array<Array(String, Object, String)>] в порядке операций
      def body_schemas
        each_operation.flat_map do |path, http_method, node|
          at = json_path('paths', path, http_method)
          key = SchemaNaming.operation_key(node['operationId'], http_method, path)
          # Ответы входящего вебхука пишем мы: то, что спецификация не
          # описала их тело, пробелом не является.
          incoming = role_of(path, http_method, node) == WEBHOOK
          request_schema(node, key, at) + response_schemas(node, key, at, incoming)
        end
      end

      def request_schema(node, key, at)
        body = node['requestBody']
        return [] unless body.is_a?(Hash)

        [content_schema(body['content'], [key, 'requestBody'], "#{at}.requestBody")].compact
      end

      def response_schemas(node, key, at, incoming)
        listed = node['responses']
        return [] unless listed.is_a?(Hash)

        listed.filter_map do |status, response|
          next unless response.is_a?(Hash)

          code = status.to_s
          where = "#{at}.responses#{SpecLoader::JsonPath.segment(code)}"
          undeclared_body(response, code, key, where) unless incoming
          content_schema(response['content'], [key, 'responses', code], where)
        end
      end

      # Ответ, объявленный одним `description`: `content` нет вовсе или в нём
      # нет ни одного media type. Тела нет по смыслу кода — это норма; у
      # любого другого кода описание обещает ответ, которого никто не описал,
      # и собрать из него нечего — как и из `content` без `schema`.
      def undeclared_body(response, code, key, at)
        return if BODILESS.include?(code) || code.start_with?(INFORMATIONAL)
        return unless ContentReader.media_type(response['content']).nil?

        message = Texts.t('analyzers.schema.response_body_undeclared', operation: key,
                                                                       status: code)
        profile.warn(:schema_unresolved, message, json_path: at)
      end

      # @return [Array(String, Object, String), nil]
      def content_schema(content, context, at)
        media = ContentReader.media_type(content)
        return nil if media.nil?

        body = ContentReader.body(content, media)
        where = "#{at}.content#{SpecLoader::JsonPath.segment(media)}.schema"
        schema = body['schema']
        return unresolved(context, where) unless schema.is_a?(Hash)

        [SchemaNaming.name_for(schema, context), schema, where]
      end

      def unresolved(context, at)
        return nil unless context

        profile.warn(:schema_unresolved,
                     Texts.t('analyzers.schema.body_schema_unreadable', operation: context.first),
                     json_path: at)
        nil
      end

      # Регистрирует схему и всё, что в неё вложено. Имя записывается раньше,
      # чем читаются поля, поэтому схема, которая добралась до самой себя,
      # находит имя занятым и останавливается, а не рекурсирует.
      def register(name, node, at, depth = 0)
        return if name.nil? || profile.schemas.key?(name)
        return too_deep(name, at) if depth > MAX_DEPTH

        result = read(name, node, at)
        profile.schemas[name] = result.schema
        result.notes.each { |note| record(note) }
        result.nested.each { |nested| register(*nested, depth + 1) }
      end

      def read(name, node, at)
        SchemaReader.new(name: name, node: node, at: at, book: rules.conditions,
                         oas31: document.oas31?, assigner: @assigner).call
      end

      def too_deep(name, at)
        profile.warn(:spec_element_unsupported,
                     Texts.t('analyzers.schema.nesting_too_deep', limit: MAX_DEPTH, name: name),
                     json_path: at)
      end

      # Каждое имя, на которое смотрит поле, обязано быть ключом
      # profile.schemas, иначе генератор выдал бы ссылку в никуда.
      def check_links
        profile.schemas.each_value do |schema|
          schema.fields.each do |field|
            next if field.schema.nil? || profile.schemas.key?(field.schema)

            profile.warn(:schema_unresolved,
                         Texts.t('analyzers.schema.field_schema_missing',
                                 field: "#{schema.name}.#{field.name}", schema: field.schema),
                         json_path: field.json_path)
          end
        end
      end

      def record(note)
        profile.warn(note.code, note.message, json_path: note.json_path,
                                              severity: note.severity || :warning,
                                              suggested_overlay: note.suggested_overlay)
      end

      def schema_path(name)
        SchemaNaming.component_path(name)
      end
    end
  end
end
