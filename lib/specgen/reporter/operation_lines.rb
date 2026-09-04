# frozen_string_literal: true

module SpecGen
  module Reporter
    # Секция операций в сводке: по строке на эндпоинт — роль, уверенность,
    # operationId, — затем что он отправляет и что получает.
    #
    # Роли вне контракта и операции без авторизации помечаются в той же
    # строке: и то и другое меняет облик сгенерированного сервиса, а читатель
    # не обязан знать словарь ролей, чтобы это заметить.
    class OperationLines
      INDENT = Format::INDENT

      # @param profile [IR::ProviderProfile]
      # @param explain [Boolean] печатать обоснование композитного матчера
      def initialize(profile, explain: false)
        @operations = profile.operations
        @explain = explain
      end

      # @return [Array<String>]
      def lines
        return [Texts.t('summary.operations_none')] if @operations.empty?

        [Texts.t('summary.operations')] +
          @operations.flat_map { |operation| operation_lines(operation) }
      end

      private

      def operation_lines(operation)
        [headline(operation),
         *Format.evidence(operation.role, explain: @explain, depth: 2),
         *request_line(operation),
         *responses_line(operation)]
      end

      def headline(operation)
        role = operation.role
        confidence = role.unknown? ? '  - ' : format('%.2f', role.confidence)
        [INDENT + endpoint(operation).ljust(endpoint_width),
         role_name(role).ljust(role_width), confidence,
         operation.id || '-'].join('  ') + notes(operation)
      end

      def endpoint(operation)
        "#{operation.http_method.to_s.upcase.ljust(4)} #{operation.path}"
      end

      def role_name(role)
        role.unknown? ? 'unmapped' : role.value.to_s
      end

      def notes(operation)
        notes = []
        notes << Texts.t('summary.not_in_contract') if operation.role.known? && !operation.contract?
        notes << Texts.t('summary.unsecured') unless operation.secured
        notes.empty? ? '' : "  (#{notes.join(', ')})"
      end

      def request_line(operation)
        parts = []
        parts << body_text(operation) if operation.request_schema
        parts.concat(operation.parameters.map { |parameter| parameter_text(parameter) })
        return [] if parts.empty?

        ["#{INDENT * 3}#{Texts.t('summary.request').ljust(label_width)} #{parts.join('; ')}"]
      end

      def body_text(operation)
        return operation.request_schema if operation.request_required

        "#{operation.request_schema} #{Texts.t('summary.optional_body')}"
      end

      def parameter_text(parameter)
        need = Texts.t(parameter.required? ? 'summary.param_required' : 'summary.param_optional')
        "#{Texts.t("location.#{parameter.location}")} #{parameter.name} (#{need})"
      end

      def responses_line(operation)
        return [] if operation.responses.empty?

        listed = operation.responses.map { |response| response_text(response) }
        ["#{INDENT * 3}#{Texts.t('summary.responses').ljust(label_width)} #{listed.join(', ')}"]
      end

      def response_text(response)
        text = response.status.dup
        text << " #{response.schema}" if response.schema
        text << " +#{response.headers.join(' +')}" unless response.headers.empty?
        text
      end

      # Метки «запрос:» и «ответы:» выравниваются по длинной, чтобы значения
      # стояли в одной колонке на любом языке.
      def label_width
        @label_width ||= [Texts.t('summary.request'), Texts.t('summary.responses')].map(&:size).max
      end

      def endpoint_width
        @endpoint_width ||= @operations.map { |operation| endpoint(operation).size }.max
      end

      def role_width
        @role_width ||= @operations.map { |operation| role_name(operation.role).size }.max
      end
    end
  end
end
