# frozen_string_literal: true

module SpecGen
  module Reporter
    # The operations section of the summary: one line per endpoint with its
    # role, confidence and operationId, then what it sends and receives.
    #
    # Roles outside the contract and operations that declare no security are
    # flagged on the same line, because both change what the generated
    # service will look like and a reader should not have to know the
    # vocabulary to notice them.
    class OperationLines
      INDENT = Format::INDENT

      # @param profile [IR::ProviderProfile]
      # @param explain [Boolean] print the composite-matcher evidence
      def initialize(profile, explain: false)
        @operations = profile.operations
        @explain = explain
      end

      # @return [Array<String>]
      def lines
        return ['Operations: none'] if @operations.empty?

        ['Operations:'] + @operations.flat_map { |operation| operation_lines(operation) }
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
        notes << 'not in contract' if operation.role.known? && !operation.contract?
        notes << 'unsecured' unless operation.secured
        notes.empty? ? '' : "  (#{notes.join(', ')})"
      end

      def request_line(operation)
        parts = []
        parts << "#{operation.request_schema}#{' (optional)' unless operation.request_required}" if
          operation.request_schema
        parts.concat(operation.parameters.map { |parameter| parameter_text(parameter) })
        return [] if parts.empty?

        ["#{INDENT * 3}request:   #{parts.join('; ')}"]
      end

      def parameter_text(parameter)
        need = parameter.required? ? 'required' : 'optional'
        "#{parameter.location} #{parameter.name} (#{need})"
      end

      def responses_line(operation)
        return [] if operation.responses.empty?

        listed = operation.responses.map { |response| response_text(response) }
        ["#{INDENT * 3}responses: #{listed.join(', ')}"]
      end

      def response_text(response)
        text = response.status.dup
        text << " #{response.schema}" if response.schema
        text << " +#{response.headers.join(' +')}" unless response.headers.empty?
        text
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
