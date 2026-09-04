# frozen_string_literal: true

module SpecGen
  module Analyzers
    # One rule for naming a schema, shared by every analyzer that mentions
    # one. Operations, responses and webhooks refer to schemas by name, and
    # the SchemaAnalyzer files them under that same name, so both sides have
    # to derive it the same way - hence this module rather than two similar
    # private methods.
    #
    # A schema that came from a `$ref` keeps its component name: the
    # resolver replaced the reference with its target but left the original
    # pointer behind in `x-specgen-ref`, so the name survives dereferencing.
    # An inline schema has no name of its own and gets a synthetic one built
    # from where it sits: "getBalance.responses.200".
    module SchemaNaming
      # Left by SpecLoader::RefResolver on every dereferenced object.
      MARKER = SpecLoader::RefResolver::MARKER
      SEPARATOR = '.'

      # @param schema [Object] a resolved schema object
      # @param context [Array<String>] where it sits, e.g.
      #   ["createPayout", "requestBody"]
      # @return [String, nil] nil when there is no schema at all
      def self.name_for(schema, context)
        return nil unless schema.is_a?(Hash)

        component_of(schema) || synthetic(context)
      end

      # @param schema [Hash]
      # @return [String, nil] component name when the schema came from a $ref
      def self.component_of(schema)
        ref = schema[MARKER]
        return nil unless ref.is_a?(String)

        name = ref.split('/').last.to_s
        name.empty? ? nil : name
      end

      # @param context [Array<String>]
      # @return [String, nil]
      def self.synthetic(context)
        parts = Array(context).compact.map(&:to_s).reject(&:empty?)
        parts.empty? ? nil : parts.join(SEPARATOR)
      end

      # Where a component schema lives, whichever use site it was found
      # through. A schema keeps one JSONPath: warnings and overlay targets
      # have to point at the component itself, not at the copy the resolver
      # left inside an operation.
      # @param name [String] component name
      # @return [String] "$.components.schemas.Recipient"
      def self.component_path(name)
        SpecLoader::JsonPath.build(['components', 'schemas', name])
      end

      # How an operation is named inside a synthetic schema name: by its
      # operationId, or - when the spec has none - by method and path, so
      # the name stays stable and unique without one.
      # @param id [String, nil] operationId
      # @param http_method [String, Symbol]
      # @param path [String]
      # @return [String] "createPayout" or "post_payouts_payout_id"
      def self.operation_key(id, http_method, path)
        return id.strip if id.is_a?(String) && !id.strip.empty?

        Rules::Normalizer.call("#{http_method}_#{path}")
      end
    end
  end
end
