# frozen_string_literal: true

module SpecGen
  module IR
    # A path, query, header or cookie parameter of an operation. Carries a
    # role like a Field does, because path identifiers, idempotency and
    # signature headers are parameters, not body fields.
    #
    #   name         verbatim
    #   location     :path | :query | :header | :cookie
    #   role         Derived<Symbol> one of Roles::FIELD, or unknown
    #   required     verbatim (path parameters are always required)
    #   type         schema type verbatim
    #   format       schema format verbatim
    #   description  verbatim
    #   example      verbatim
    #   json_path    "$.paths['/x'].post.parameters[0]" or the component path
    Parameter = Struct.new(:name, :location, :role, :required, :type, :format, :description,
                           :example, :json_path, keyword_init: true)

    # Vocabulary and checks of Parameter.
    class Parameter
      include Node

      LOCATIONS = %i[path query header cookie].freeze

      # @param name [String]
      # @param location [Symbol] one of LOCATIONS
      # @param role [Derived]
      # @param required [Boolean]
      # @param type [String, nil]
      # @param format [String, nil]
      # @param description [String, nil]
      # @param example [Object, nil]
      # @param json_path [String, nil]
      # @raise [ArgumentError]
      def initialize(name:, location:, role:, required: false, type: nil, format: nil,
                     description: nil, example: nil, json_path: nil)
        Node.assert_text!(name, 'parameter name')
        Node.assert_member!(LOCATIONS, location, 'parameter location')
        Node.assert_derived!(role, 'parameter role', allowed: Roles::FIELD)
        super
      end

      # @return [Boolean]
      def required?
        required == true
      end

      # @return [Boolean] whether the parameter plays the given role
      def role?(role)
        self.role.value == Roles.field!(role)
      end
    end
  end
end
