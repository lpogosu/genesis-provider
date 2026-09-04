# frozen_string_literal: true

module SpecGen
  module SpecLoader
    # Builds JSONPath strings from key arrays, using the bracket notation the
    # OpenAPI Overlay specification uses for keys with special characters:
    #
    #   JsonPath.build(['paths', '/payouts', 'post']) # => "$.paths['/payouts'].post"
    #   JsonPath.build(['servers', 0, 'url'])         # => "$.servers[0].url"
    module JsonPath
      ROOT = '$'
      IDENTIFIER = /\A[A-Za-z_][A-Za-z0-9_]*\z/

      # @param keys [Array<String, Integer>] key path from the document root
      # @return [String]
      def self.build(keys)
        keys.reduce(ROOT) { |path, key| path + segment(key) }
      end

      # @param key [String, Integer]
      # @return [String] one path segment
      def self.segment(key)
        return "[#{key}]" if key.is_a?(Integer)

        key = key.to_s
        return ".#{key}" if key.match?(IDENTIFIER)

        "['#{key.gsub(/['\\]/) { |char| "\\#{char}" }}']"
      end
    end
  end
end
