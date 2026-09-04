# frozen_string_literal: true

module SpecGen
  module Analyzers
    # Fills profile.operations: every operation the spec declares, with the
    # role it plays, its parameters, its request body and its responses.
    #
    # Every operation ends up in the IR, including the ones that map to no
    # contract method. An endpoint dropped here is functionality that
    # silently disappears from the integration, which reads as a bug in the
    # generator; an endpoint kept with the role :unmapped is a line in
    # report.md that a human can act on.
    #
    # Roles are decided by OperationRole, which counts weighted votes from
    # rules/operations.yml. This class only turns that decision, and the
    # rest of the operation object, into IR - and warns about everything it
    # had to leave open: no operationId, an ambiguous role, a role that is
    # recognised but has no place in Provider::BaseService.
    class OperationAnalyzer < Base
      # Roles the contract has no method for. They are recognised, not
      # ignored: the generator gives each one a separate public method and
      # the report says "not mapped to the contract".
      OFF_CONTRACT = (IR::Roles::OPERATION - IR::Roles::CONTRACT - [:unmapped]).freeze
      # A range some specs spell in lower case; accepted, not reported.
      RANGE = /\A[1-5]xx\z/i

      # Fills `profile.operations`, in spec order.
      # @return [IR::ProviderProfile] the profile it was given
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

      # @return [OperationRole::Result]
      def role_of(path, http_method, node)
        OperationRole.new(book: rules.operations, id: text(node['operationId']),
                          http_method: http_method.to_sym, path: path,
                          tags: node['tags'].is_a?(Array) ? node['tags'].grep(String) : [],
                          body: node['requestBody'].is_a?(Hash),
                          secured: secured?(node)).call
      end

      # An operation opts out of authentication with an empty list, which is
      # how a spec marks a call the provider makes to us.
      def secured?(node)
        security = node['security']
        !(security.is_a?(Array) && security.empty?)
      end

      def tags_of(node, at)
        tags = node['tags']
        return [] if tags.nil?
        return tags.grep(String) if tags.is_a?(Array)

        warn_shape('`tags` must be a list of strings', "#{at}.tags")
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

      # @return [Hash] the request body members of IR::Operation
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

      # @return [Array<IR::Response>] in spec order
      def responses(node, key, at)
        listed = node['responses']
        return [] if listed.nil?

        unless listed.is_a?(Hash)
          warn_shape('`responses` must be an object', "#{at}.responses")
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
        warn_shape("response key #{code.inspect} is not a status code, a range or `default`", at)
        nil
      end

      # Two different silences, two different warnings: a close race between
      # real candidates is an ambiguity a human resolves, while nothing
      # scoring at all means the spec says nothing we can read.
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
                     'the operation declares no operationId; it is referred to as ' \
                     "#{operation.key.inspect} in this report and in the generated code",
                     json_path: at, severity: :info)
      end

      def no_role(result, at)
        profile.warn(:operation_unmapped,
                     'too little in the spec says what this operation is for, so no role was ' \
                     "assigned (#{scores_of(result)}); it needs a role in an overlay",
                     json_path: at)
      end

      def ambiguous(result, at)
        profile.warn(:operation_role_ambiguous,
                     'two roles fit this operation equally well, so neither was assigned ' \
                     "(#{scores_of(result)}); pick one in an overlay",
                     json_path: at)
      end

      # @return [String] "create_payout 8.0, webhook 8.0 of 13.0 votes cast"
      def scores_of(result)
        listed = result.scores.take(3).reject { |_, score| score.zero? }
                       .map { |role, score| "#{role} #{format('%.1f', score)}" }
        "#{listed.join(', ')} of #{format('%.1f', result.cast)} votes cast"
      end

      def off_contract(operation, at)
        role = operation.role.value
        return unless OFF_CONTRACT.include?(role)

        profile.warn(:operation_unmapped,
                     "recognised as #{role}, which Provider::BaseService has no method for; " \
                     'it is generated as a separate public method and not mapped to the contract',
                     json_path: at, severity: :info)
      end

      def warn_shape(message, at)
        profile.warn(:spec_element_unsupported, message, json_path: at)
        nil
      end

      # @return [String, nil] a scalar as written, nil when absent or not text
      def text(value)
        return nil unless value.is_a?(String)

        stripped = value.strip
        stripped.empty? ? nil : stripped
      end
    end
  end
end
