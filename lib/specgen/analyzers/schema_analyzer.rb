# frozen_string_literal: true

module SpecGen
  module Analyzers
    # Fills profile.schemas: every schema the generated service has to build
    # or read, under the name the rest of the IR refers to it by.
    #
    # Three sources, in a fixed order so two runs produce the same file:
    # the components in spec order, then the bodies of requests and
    # responses in operation order, then whatever those two reach through
    # nested objects and array items. A component nobody references is kept
    # as well - it is part of what the provider offers, and the report is
    # the place to notice it is unused.
    #
    # Names come from SchemaNaming, the same module the OperationAnalyzer
    # uses, so `Operation#request_schema` and `Response#schema` are keys of
    # this hash and never dangling strings.
    class SchemaAnalyzer < Base
      # Deep enough for any payment payload; a cycle the resolver did not
      # catch stops here with a warning instead of a stack overflow.
      MAX_DEPTH = 8

      # Fills `profile.schemas`.
      # @return [IR::ProviderProfile] the profile it was given
      def call
        component_schemas.each { |name, node, at| register(name, node, at) }
        body_schemas.each { |name, node, at| register(name, node, at) }
        check_links
        profile
      end

      private

      # @return [Array<Array(String, Object, String)>] name, node, JSONPath
      def component_schemas
        components = data['components']
        listed = components.is_a?(Hash) ? components['schemas'] : nil
        return [] if listed.nil?
        return unusable('`components.schemas` must be an object') unless listed.is_a?(Hash)

        listed.map { |name, node| [name.to_s, node, schema_path(name)] }
      end

      def unusable(message)
        profile.warn(:spec_element_unsupported, message,
                     json_path: json_path('components', 'schemas'))
        []
      end

      # @return [Array<Array(String, Object, String)>] in operation order
      def body_schemas
        each_operation.flat_map do |path, http_method, node|
          at = json_path('paths', path, http_method)
          key = SchemaNaming.operation_key(node['operationId'], http_method, path)
          request_schema(node, key, at) + response_schemas(node, key, at)
        end
      end

      def request_schema(node, key, at)
        body = node['requestBody']
        return [] unless body.is_a?(Hash)

        [content_schema(body['content'], [key, 'requestBody'], "#{at}.requestBody")].compact
      end

      def response_schemas(node, key, at)
        listed = node['responses']
        return [] unless listed.is_a?(Hash)

        listed.filter_map do |status, response|
          next unless response.is_a?(Hash)

          code = status.to_s
          where = "#{at}.responses#{SpecLoader::JsonPath.segment(code)}"
          content_schema(response['content'], [key, 'responses', code], where)
        end
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
                     "the body of #{context.first} declares no readable schema, so nothing " \
                     'describes what it carries',
                     json_path: at)
        nil
      end

      # Registers the schema and everything it nests. The name is written
      # before the fields are read, so a schema that reaches itself finds
      # the name taken and stops instead of recursing.
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
                         oas31: document.oas31?).call
      end

      def too_deep(name, at)
        profile.warn(:spec_element_unsupported,
                     "schemas nest deeper than #{MAX_DEPTH} levels here, so #{name} was left " \
                     'undescribed; check the spec for a schema that contains itself',
                     json_path: at)
      end

      # Every name a field points at has to be a key of profile.schemas, or
      # the generator would emit a reference to nothing.
      def check_links
        profile.schemas.each_value do |schema|
          schema.fields.each do |field|
            next if field.schema.nil? || profile.schemas.key?(field.schema)

            profile.warn(:schema_unresolved,
                         "`#{schema.name}.#{field.name}` refers to schema #{field.schema}, " \
                         'which is not described anywhere',
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
