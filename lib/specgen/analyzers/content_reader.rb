# frozen_string_literal: true

module SpecGen
  module Analyzers
    # Reads a `content` map - the one shape shared by request bodies,
    # responses and webhook payloads: which media type to generate for,
    # which schema the body has, and which examples the spec offers.
    #
    # JSON wins when the spec offers it, because that is what the generated
    # service speaks; a spec that offers only something else is not an error
    # and the first declared type is taken instead. Examples are normalised
    # into one shape, {name => value}, so fixtures.json does not have to
    # know whether the spec wrote `examples` or a bare `example`.
    module ContentReader
      JSON = IR::Operation::JSON
      JSON_HINT = 'json'

      # @param content [Object] the `content` map
      # @return [String, nil] media type to read, nil when there is none
      def self.media_type(content)
        return nil unless content.is_a?(Hash)

        types = content.keys.grep(String)
        return nil if types.empty?
        return JSON if types.include?(JSON)

        types.find { |type| type.include?(JSON_HINT) } || types.first
      end

      # @param content [Object]
      # @param media [String, nil]
      # @return [Hash] the media type object, empty when absent or malformed
      def self.body(content, media)
        value = content.is_a?(Hash) ? content[media] : nil
        value.is_a?(Hash) ? value : {}
      end

      # @param content [Object]
      # @param media [String, nil]
      # @param context [Array<String>] for SchemaNaming
      # @return [String, nil] name of the body schema
      def self.schema_name(content, media, context)
        SchemaNaming.name_for(body(content, media)['schema'], context)
      end

      # @param content [Object]
      # @param media [String, nil]
      # @return [Hash{String => Object}] a bare `example` is filed under
      #   Response::DEFAULT_EXAMPLE
      def self.examples(content, media)
        node = body(content, media)
        listed = node['examples']
        return listed.to_h { |name, item| [name.to_s, value_of(item)] } if listed.is_a?(Hash)
        return { IR::Response::DEFAULT_EXAMPLE => node['example'] } if node.key?('example')

        {}
      end

      # An Example Object carries the payload under `value`; anything else
      # is taken as the payload itself.
      # @param item [Object]
      # @return [Object]
      def self.value_of(item)
        item.is_a?(Hash) && item.key?('value') ? item['value'] : item
      end
    end
  end
end
