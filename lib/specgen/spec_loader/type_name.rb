# frozen_string_literal: true

module SpecGen
  module SpecLoader
    # Names a parsed value the way a spec author would read it in an error
    # message: "object", "array", "string", never "Hash" or "NilClass".
    module TypeName
      NAMES = {
        Hash => 'object', Array => 'array', String => 'string', Integer => 'number',
        Float => 'number', TrueClass => 'boolean', FalseClass => 'boolean', NilClass => 'null'
      }.freeze

      # @param value [Object]
      # @return [String]
      def self.of(value)
        NAMES.fetch(value.class) { value.class.name.downcase }
      end
    end
  end
end
