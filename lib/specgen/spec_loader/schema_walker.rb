# frozen_string_literal: true

module SpecGen
  module SpecLoader
    # Enumerates every Schema Object in a document together with its key
    # path, following the places OpenAPI 3.x allows schemas (components,
    # parameters, request bodies, responses, headers) and the JSON Schema
    # keywords that nest subschemas. Stops at `$ref` nodes: the resolver
    # deals with those, and the walker is meant to run on the raw document
    # so that errors point at a schema's definition, not at its uses.
    class SchemaWalker
      OPERATIONS = %w[get put post delete options head patch trace].freeze
      COMPONENT_KINDS = {
        'schemas' => :schema, 'parameters' => :parameter, 'headers' => :parameter,
        'requestBodies' => :media, 'responses' => :response
      }.freeze
      NESTED_MAP = %w[properties patternProperties dependentSchemas $defs definitions].freeze
      NESTED_ONE = %w[items additionalProperties not if then else contains propertyNames
                      unevaluatedProperties unevaluatedItems].freeze
      NESTED_LIST = %w[allOf anyOf oneOf prefixItems].freeze

      # @param data [Hash] raw document
      # @yieldparam schema [Hash]
      # @yieldparam keys [Array<String, Integer>] key path from the root
      def self.each_schema(data, &)
        new(data).each_schema(&)
      end

      # @param data [Hash]
      def initialize(data)
        @data = data
      end

      # @yieldparam schema [Hash]
      # @yieldparam keys [Array<String, Integer>]
      # @return [Enumerator] when no block is given
      def each_schema(&block)
        return enum_for(:each_schema) unless block

        walk_components(&block)
        walk_path_items('paths', &block)
        walk_path_items('webhooks', &block)
      end

      private

      def walk_components(&block)
        components = @data['components']
        return unless components.is_a?(Hash)

        COMPONENT_KINDS.each do |section, handler|
          hash_each(components[section], ['components', section]) do |node, keys|
            send(handler, node, keys, &block)
          end
        end
      end

      def walk_path_items(section, &block)
        hash_each(@data[section], [section]) do |item, keys|
          parameters(item['parameters'], keys + ['parameters'], &block)
          OPERATIONS.each do |verb|
            operation(item[verb], keys + [verb], &block) if item[verb].is_a?(Hash)
          end
        end
      end

      def operation(operation, keys, &block)
        parameters(operation['parameters'], keys + ['parameters'], &block)
        media(operation['requestBody'], keys + ['requestBody'], &block)
        hash_each(operation['responses'], keys + ['responses']) { |r, k| response(r, k, &block) }
      end

      def response(response, keys, &block)
        media(response, keys, &block)
        hash_each(response['headers'], keys + ['headers']) { |h, k| parameter(h, k, &block) }
      end

      def media(holder, keys, &block)
        return unless holder.is_a?(Hash)

        hash_each(holder['content'], keys + ['content']) do |media_type, media_keys|
          schema(media_type['schema'], media_keys + ['schema'], &block)
        end
      end

      def parameters(list, keys, &block)
        return unless list.is_a?(Array)

        list.each_with_index { |param, index| parameter(param, keys + [index], &block) }
      end

      def parameter(param, keys, &)
        schema(param['schema'], keys + ['schema'], &) if param.is_a?(Hash)
      end

      def schema(node, keys, &block)
        return unless node.is_a?(Hash) && !node.key?('$ref')

        yield node, keys
        NESTED_MAP.each { |kw| hash_each(node[kw], keys + [kw]) { |s, k| schema(s, k, &block) } }
        NESTED_ONE.each { |kw| schema(node[kw], keys + [kw], &block) }
        NESTED_LIST.each { |kw| list_each(node[kw], keys + [kw]) { |s, k| schema(s, k, &block) } }
      end

      def hash_each(hash, keys)
        return unless hash.is_a?(Hash)

        hash.each { |key, value| yield value, keys + [key] if value.is_a?(Hash) }
      end

      def list_each(list, keys)
        return unless list.is_a?(Array)

        list.each_with_index { |value, index| yield value, keys + [index] }
      end
    end
  end
end
