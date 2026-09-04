# frozen_string_literal: true

require 'uri'

module SpecGen
  module SpecLoader
    # JSON Pointer по RFC 6901 в том виде, в каком он стоит во фрагменте
    # `$ref`: "/components/schemas/X". Разбирает экранирование ~0 / ~1 и
    # процентные последовательности, обходит разобранный документ и
    # возвращает MISSING, когда указатель ведёт в пустоту.
    module JsonPointer
      MISSING = Object.new.freeze

      # @param pointer [String] "" для всего документа либо "/a/b/0"
      # @return [Array<String>] разэкранированные токены ссылки
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
      # @return [Object] цель либо MISSING
      def self.fetch(document, pointer)
        keys(pointer).reduce(document) do |node, key|
          next MISSING if node.equal?(MISSING)

          step(node, key)
        end
      end

      # @param node [Object]
      # @param key [String]
      # @return [Object] потомок узла по этому ключу либо MISSING
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
