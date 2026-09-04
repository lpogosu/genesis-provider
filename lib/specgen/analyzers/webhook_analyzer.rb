# frozen_string_literal: true

module SpecGen
  module Analyzers
    # Заполняет profile.webhooks: каждую точку, куда провайдер присылает
    # уведомления, с её событиями, схемой тела и профилем подписи.
    #
    # Входящий вебхук в OpenAPI 3.0 отличает только `security: []` вместе с
    # POST и телом запроса; роль решает тот же OperationRole, что и у
    # OperationAnalyzer, пересчитанный от документа, — общий компонент, а не
    # чтение чужого результата. OpenAPI 3.1 добавляет секцию `webhooks`, её
    # записи попадают сюда с `operation: nil`. События читает WebhookEvents
    # той же логикой статусов, что StatusAnalyzer; подпись — SignatureReader
    # по rules/signatures.yml.
    #
    # Спецификация без вебхуков — справка webhook_missing: статус операции
    # сервис узнает только опросом, и человек должен это знать заранее.
    class WebhookAnalyzer < Base
      ROLE = :webhook

      # Один найденный вебхук до превращения в IR.
      #
      #   path      путь из `paths` или имя из `webhooks`
      #   node      Operation Object
      #   at        JSONPath операции
      #   key       Operation#key
      #   headers   [[имя, JSONPath, описание]] параметров-заголовков
      #   in_paths  объявлен в `paths` (иначе в секции `webhooks`)
      Found = Struct.new(:path, :node, :at, :key, :headers, :in_paths, keyword_init: true)

      # Заполняет `profile.webhooks`.
      # @return [IR::ProviderProfile] тот профиль, который был передан
      def call
        @lookup = RoleLookup.new(rules.roles)
        found = inbound + declared
        return none if found.empty?

        found.each { |entry| add(entry) }
        profile
      end

      private

      # @return [Array<Found>]
      def inbound
        each_operation.filter_map do |path, verb, node|
          next unless webhook?(path, verb, node)

          Found.new(path: path, node: node, at: json_path(Operations::PATHS, path, verb),
                    key: operation_key(path, verb, node), headers: header_names(path, node, verb),
                    in_paths: true)
        end
      end

      def webhook?(path, verb, node)
        security = node['security']
        tags = node['tags'].is_a?(Array) ? node['tags'].grep(String) : []
        OperationRole.new(book: rules.operations, id: node['operationId'], http_method: verb.to_sym,
                          path: path, tags: tags, body: node['requestBody'].is_a?(Hash),
                          secured: !(security.is_a?(Array) && security.empty?)).call.role == ROLE
      end

      # @return [Array<Found>]
      def declared
        Operations.each_webhook(data).map do |name, verb, node|
          at = json_path(Operations::WEBHOOKS, name, verb)
          Found.new(path: name, node: node, at: at,
                    key: SchemaNaming.operation_key(node['operationId'], verb, name),
                    headers: headers_of(node, nil, nil, "#{at}.parameters"), in_paths: false)
        end
      end

      # Заголовки операции вместе с унаследованными от path item.
      # @return [Array<Array(String, String, String)>] имя, JSONPath, описание
      def header_names(path, node, verb)
        item = data[Operations::PATHS][path]
        headers_of(node, item.is_a?(Hash) ? item['parameters'] : nil,
                   json_path(Operations::PATHS, path, 'parameters'),
                   json_path(Operations::PATHS, path, verb, 'parameters'))
      end

      def headers_of(node, shared, shared_path, own_path)
        reader = ParameterReader.new(shared: shared, own: node['parameters'],
                                     shared_path: shared_path, own_path: own_path)
        reader.call.select { |parameter| parameter.location == :header }
              .map { |parameter| [parameter.name, parameter.json_path, parameter.description] }
      end

      def add(found)
        body = found.node['requestBody']
        content = body.is_a?(Hash) ? body['content'] : nil
        media = ContentReader.media_type(content)
        schema_node = ContentReader.body(content, media)['schema']
        events = events_of(found, schema_node, media, content)
        signature = signature_of(found)
        profile.webhooks << build(found, schema_node, events, signature)
        record(events, signature)
      end

      def signature_of(found)
        SignatureReader.new(node: found.node, key: found.key, headers: found.headers,
                            book: rules.signatures, at: found.at).call
      end

      def build(found, schema_node, events, signature)
        IR::Webhook.new(path: found.path, operation: found.in_paths ? found.key : nil,
                        schema: SchemaNaming.name_for(schema_node, [found.key, 'requestBody']),
                        signature: signature.profile, events: events.events, json_path: found.at)
      end

      def events_of(found, schema_node, media, content)
        merged, = SchemaFlattener.call(schema_node)
        examples = []
        ExampleReader.each_example(content, "#{found.at}.requestBody",
                                   [found.key, 'requestBody']) { |*item| examples << item.take(3) }
        WebhookEvents.new(node: merged, schema_path: schema_path(schema_node, found.at, media),
                          examples: examples, lookup: @lookup, book: rules.statuses).call
      end

      def schema_path(schema_node, at, media)
        component = SchemaNaming.component_of(schema_node)
        return SchemaNaming.component_path(component) if component

        "#{at}.requestBody.content#{SpecLoader::JsonPath.segment(media.to_s)}.schema"
      end

      def record(events, signature)
        events.notes.each { |code, message, at| profile.warn(code, message, json_path: at) }
        events.events.reject(&:mapped?).each { |event| unmapped(event, events) }
        signature.notes.each do |code, message, at, fragment|
          profile.warn(code, message, json_path: at, suggested_overlay: fragment)
        end
      end

      def unmapped(event, events)
        fragment = events.field_path && Texts.t('analyzers.status.overlay_fragment',
                                                path: events.field_path, status: event.name)
        message = t('event_unmapped', event: event.name, evidence: event.internal_status.evidence)
        profile.warn(:webhook_event_unmapped, message, json_path: event.json_path,
                                                       suggested_overlay: fragment)
      end

      def none
        at = json_path(Operations::PATHS)
        profile.warn(:webhook_missing, t('missing'), severity: :info, json_path: at)
        profile
      end

      def t(key, **params)
        Texts.t("analyzers.webhook.#{key}", **params)
      end
    end
  end
end
