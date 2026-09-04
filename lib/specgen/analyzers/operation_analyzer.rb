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
      # Роли, для которых у контракта нет метода. Они распознаны, а не
      # проигнорированы: генератор даёт каждой отдельный публичный метод, а
      # отчёт говорит «вне контракта».
      OFF_CONTRACT = (IR::Roles::OPERATION - IR::Roles::CONTRACT - [:unmapped]).freeze
      # Диапазон, который некоторые спецификации пишут в нижнем регистре;
      # принимается, но не репортится.
      RANGE = /\A[1-5]xx\z/i

      # Заполняет `profile.operations` в порядке спецификации.
      # @return [IR::ProviderProfile] тот профиль, который был передан
      def call
        each_operation { |path, http_method, node| add(path, http_method, node) }
        profile
      end

      private

      def add(path, http_method, node)
        at = json_path('paths', path, http_method)
        key = SchemaNaming.operation_key(node['operationId'], http_method, path)
        result = role_of(path, http_method, node)
        operation = build(path, http_method, node, at: at, key: key, role: result.derived)
        profile.operations << operation
        report(operation, result, at)
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
                          secured: secured?(node)).call
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

      def parameters(path, node, at)
        item = data['paths'][path]
        reader = ParameterReader.new(shared: item.is_a?(Hash) ? item['parameters'] : nil,
                                     own: node['parameters'],
                                     shared_path: json_path('paths', path, 'parameters'),
                                     own_path: "#{at}.parameters")
        list = reader.call
        reader.problems.each { |message, where| warn_shape(message, where) }
        list
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

      # Два разных молчания — два разных предупреждения: плотная борьба
      # настоящих кандидатов это неоднозначность, которую разрешает человек,
      # а полное отсутствие набранных очков означает, что спецификация не
      # говорит ничего, что мы могли бы прочитать.
      def report(operation, result, at)
        missing_id(operation, at) if operation.id.nil?
        case result.reason
        when :ambiguous then ambiguous(result, at)
        when nil then off_contract(operation, at)
        else no_role(result, at)
        end
      end

      def missing_id(operation, at)
        profile.warn(:operation_id_missing,
                     Texts.t('analyzers.operation.id_missing', key: operation.key.inspect),
                     json_path: at, severity: :info)
      end

      def no_role(result, at)
        profile.warn(:operation_unmapped,
                     Texts.t('analyzers.operation.unmapped', scores: scores_of(result)),
                     json_path: at)
      end

      def ambiguous(result, at)
        profile.warn(:operation_role_ambiguous,
                     Texts.t('analyzers.operation.ambiguous', scores: scores_of(result)),
                     json_path: at)
      end

      # @return [String] "create_payout 8.0, webhook 8.0 из 13.0 поданных голосов"
      def scores_of(result)
        listed = result.scores.take(3).reject { |_, score| score.zero? }
                       .map { |role, score| "#{role} #{format('%.1f', score)}" }
        Texts.t('analyzers.operation.scores', scores: listed.join(', '),
                                              cast: format('%.1f', result.cast))
      end

      def off_contract(operation, at)
        role = operation.role.value
        return unless OFF_CONTRACT.include?(role)

        profile.warn(:operation_unmapped,
                     Texts.t('analyzers.operation.off_contract', role: role),
                     json_path: at, severity: :info)
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
