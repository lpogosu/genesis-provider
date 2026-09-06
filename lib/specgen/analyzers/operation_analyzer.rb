# frozen_string_literal: true

module SpecGen
  module Analyzers
    # Заполняет profile.operations: каждую операцию, объявленную
    # спецификацией, вместе с её ролью, параметрами, телом запроса и
    # ответами.
    #
    # В IR попадает каждая операция, включая те, что не отображаются ни на
    # один метод контракта. Выброшенный здесь эндпоинт — это
    # функциональность, молча исчезающая из интеграции, что читается как баг
    # генератора; сохранённый эндпоинт с ролью :unmapped — строка в
    # report.md, с которой человек может что-то сделать.
    #
    # Роли решает OperationRole, который считает взвешенные голоса из
    # rules/operations.yml. Этот класс лишь превращает то решение и всё
    # остальное содержимое объекта операции в IR — и предупреждает обо всём,
    # что пришлось оставить открытым: нет operationId, роль неоднозначна,
    # роль распознана, но ей нет места в Provider::BaseService.
    class OperationAnalyzer < Base
      # Диапазон, который некоторые спецификации пишут в нижнем регистре;
      # принимается, но не репортится.
      RANGE = /\A[1-5]xx\z/i

      # Заполняет `profile.operations` в порядке спецификации.
      #
      # Два прохода, а не один: слот роли в сервисе занимает не самая
      # уверенная операция поодиночке, а согласованная пара «создание —
      # опрос статуса», и знать о ней можно только когда прочитаны все
      # операции. Предупреждения пишутся после выбора пары, чтобы отчёт
      # объяснял ту роль, которая осталась у операции, а не ту, что была у
      # неё до связывания.
      # @return [IR::ProviderProfile] тот профиль, который был передан
      def call
        @assigner = Matchers::Assigner.new(rules: rules)
        built = []
        each_operation { |path, http_method, node| built << add(path, http_method, node) }
        pair(built)
        built.each { |operation, result, at| report(operation, result, at) }
        profile
      end

      private

      # Предупреждения об одной операции; их состав и порядок решает
      # OperationNotes.
      def report(operation, result, at)
        OperationNotes.new(operation: operation, result: result, at: at)
                      .call.each { |note| record(note) }
      end

      # @return [Array(IR::Operation, OperationRole::Result, String)]
      def add(path, http_method, node)
        at = json_path('paths', path, http_method)
        key = SchemaNaming.operation_key(node['operationId'], http_method, path)
        result = role_of(path, http_method, node)
        operation = build(path, http_method, node, at: at, key: key, role: result.derived)
        profile.operations << operation
        [operation, result, at]
      end

      # Слоты ролей занимает согласованная пара: сервис, который создаёт один
      # ресурс, а статус опрашивает у другого, выглядит рабочим и молча
      # неверен.
      def pair(built)
        choices = OperationPairing.new(operations: profile.operations, book: rules.operations,
                                       links: links).call
        choices.each_value { |choice| occupy(choice, built) }
        PairingNotes.new(choices).notes.each { |note| record(note) }
      end

      # @return [Array<OperationLinks::Link>] формальные связи операций
      def links
        reader = OperationLinks.new(data)
        found = reader.call
        reader.problems.each { |message, at| warn_shape(message, at) }
        found
      end

      # Выбранная операция занимает слот роли; обоснование дописывается
      # только когда было из чего выбирать, иначе отчёт остаётся прежним.
      def occupy(choice, built)
        operation = choice.operation
        operation.primary = true
        text = PairingNotes.evidence(choice)
        return if text.nil?

        operation.role = derived_with(operation.role, choice, text)
        silence(built, operation) if choice.link
      end

      # Формальная ссылка — первый уровень доверия: она заменяет вывод, а не
      # дополняет его.
      def derived_with(role, choice, text)
        return IR::Derived.structural(choice.role, evidence: text) if choice.link

        IR::Derived.heuristic(role.value, confidence: role.confidence,
                                          evidence: [role.evidence, text].compact.join)
      end

      # Роль, названную ссылкой, не о чем предупреждать: сомнение снято
      # спецификацией.
      def silence(built, operation)
        entry = built.find { |candidate, _, _| candidate.equal?(operation) }
        entry[1].reason = nil unless entry.nil?
      end

      # @return [IR::Operation]
      def build(path, http_method, node, at:, key:, role:)
        IR::Operation.new(role: role, http_method: http_method.to_sym, path: path,
                          id: text(node['operationId']), summary: text(node['summary']),
                          tags: tags_of(node, at), parameters: parameters(path, node, at),
                          responses: responses(node, key, at), secured: secured?(node),
                          json_path: at, **request(node, key))
      end

      # @return [OperationRole::Result] решение композитного матчера
      def role_of(path, http_method, node)
        OperationRole.new(book: rules.operations, id: text(node['operationId']),
                          http_method: http_method.to_sym, path: path,
                          tags: node['tags'].is_a?(Array) ? node['tags'].grep(String) : [],
                          body: node['requestBody'].is_a?(Hash),
                          secured: secured?(node), list: list_response?(node)).call
      end

      # Форма успешного ответа отличает чтение одного ресурса от листинга;
      # служебные свойства обёртки перечисляет справочник.
      def list_response?(node)
        ResponseShape.list?(node, ignore: rules.operations.veto(:list_response)[:ignore])
      end

      # Операция отказывается от авторизации пустым списком — так
      # спецификация помечает вызов, который делает нам сам провайдер.
      def secured?(node)
        security = node['security']
        !(security.is_a?(Array) && security.empty?)
      end

      def tags_of(node, at)
        tags = node['tags']
        return [] if tags.nil?
        return tags.grep(String) if tags.is_a?(Array)

        warn_shape(Texts.t('analyzers.operation.tags_shape'), "#{at}.tags")
        []
      end

      # Параметры получают роли тем же матчером, что поля тела: заголовок
      # идемпотентности, подпись и идентификатор в пути — это параметры.
      def parameters(path, node, at)
        item = data['paths'][path]
        reader = ParameterReader.new(shared: item.is_a?(Hash) ? item['parameters'] : nil,
                                     own: node['parameters'], assigner: @assigner,
                                     shared_path: json_path('paths', path, 'parameters'),
                                     own_path: "#{at}.parameters")
        list = reader.call
        reader.problems.each { |message, where| warn_shape(message, where) }
        reader.notes.each { |note| record(note) }
        list
      end

      def record(note)
        profile.warn(note.code, note.message, json_path: note.json_path,
                                              severity: note.severity || :warning,
                                              suggested_overlay: note.suggested_overlay)
      end

      # @return [Hash] члены IR::Operation, описывающие тело запроса
      def request(node, key)
        body = node['requestBody']
        return {} unless body.is_a?(Hash)

        content = body['content']
        media = ContentReader.media_type(content)
        { request_schema: ContentReader.schema_name(content, media, [key, 'requestBody']),
          request_required: body['required'] == true,
          request_media_type: media || IR::Operation::JSON,
          request_examples: ContentReader.examples(content, media) }
      end

      # @return [Array<IR::Response>] в порядке спецификации
      def responses(node, key, at)
        listed = node['responses']
        return [] if listed.nil?

        unless listed.is_a?(Hash)
          warn_shape(Texts.t('analyzers.common.must_be_object', key: 'responses'),
                     "#{at}.responses")
          return []
        end

        listed.filter_map { |status, body| response(status, body, key, "#{at}.responses") }
      end

      # @return [IR::Response, nil]
      def response(status, body, key, base)
        code = status.to_s.strip
        code = code.upcase if code.match?(RANGE)
        at = base + SpecLoader::JsonPath.segment(code)
        return skipped_status(code, at) unless code.match?(IR::Response::STATUS)

        node = body.is_a?(Hash) ? body : {}
        content = node['content']
        media = ContentReader.media_type(content)
        schema = ContentReader.schema_name(content, media, [key, 'responses', code])
        IR::Response.new(status: code, description: text(node['description']), json_path: at,
                         schema: schema, headers: header_names(node['headers']),
                         examples: ContentReader.examples(content, media))
      end

      def header_names(headers)
        headers.is_a?(Hash) ? headers.keys.map(&:to_s) : []
      end

      def skipped_status(code, at)
        warn_shape(Texts.t('analyzers.operation.status_unknown', code: code.inspect), at)
        nil
      end

      def warn_shape(message, at)
        profile.warn(:spec_element_unsupported, message, json_path: at)
        nil
      end

      # @return [String, nil] скаляр как он написан, nil если его нет или он
      #   не текст
      def text(value)
        return nil unless value.is_a?(String)

        stripped = value.strip
        stripped.empty? ? nil : stripped
      end
    end
  end
end
