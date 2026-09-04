# frozen_string_literal: true

require 'uri'

module SpecGen
  module SpecLoader
    # RFC 6901 JSON Pointer as used in `$ref` fragments: "/components/schemas/X".
    # Handles the ~0 / ~1 escapes and percent-encoding, and walks a parsed
    # document returning MISSING when the pointer leads nowhere.
    module JsonPointer
      MISSING = Object.new.freeze

      # @param pointer [String] "" for the whole document or "/a/b/0"
      # @return [Array<String>] unescaped reference tokens
      def self.keys(pointer)
        return [] if pointer.empty?

        pointer.delete_prefix('/').split('/', -1).map { |token| unescape(token) }
      end

      # @param token [String]
      # @return [String]
      def self.unescape(token)
        URI.decode_uri_component(token).gsub('~1', '/').gsub('~0', '~')
      end

      # @param document [Hash, Array]
      # @param pointer [String]
      # @return [Object] the target, or MISSING
      def self.fetch(document, pointer)
        keys(pointer).reduce(document) do |node, key|
          next MISSING if node.equal?(MISSING)

          step(node, key)
        end
      end

      # @param node [Object]
      # @param key [String]
      # @return [Object] child of node addressed by key, or MISSING
      def self.step(node, key)
        case node
        when Hash then node.fetch(key, MISSING)
        when Array then key.match?(/\A\d+\z/) ? node.fetch(key.to_i, MISSING) : MISSING
        else MISSING
        end
      end
    end
  end
end
