# frozen_string_literal: true

module SpecGen
  module IR
    # Root of the IR: everything the generators need to know about one
    # provider, and nothing about how it was loaded. Analyzers fill their
    # part and append warnings; after the analysis stage the profile is
    # read-only by convention.
    #
    #   info         Info
    #   servers      [Server]
    #   auth         Auth or nil (nil: the spec declares no security at all)
    #   operations   [Operation] in spec order
    #   schemas      {name => Schema}
    #   status_map   [StatusMapping]
    #   error_map    [ErrorRule]
    #   webhooks     [Webhook]
    #   units        Units or nil (nil: no amount field anywhere)
    #   idempotency  Idempotency or nil (nil: no candidate header anywhere)
    #   warnings     [Warning]
    ProviderProfile = Struct.new(:info, :servers, :auth, :operations, :schemas, :status_map,
                                 :error_map, :webhooks, :units, :idempotency, :warnings,
                                 keyword_init: true)

    # Defaults, warning collection and lookups of ProviderProfile.
    class ProviderProfile
      include Node

      # @param info [Info, nil]
      # @param servers [Array<Server>]
      # @param auth [Auth, nil]
      # @param operations [Array<Operation>]
      # @param schemas [Hash{String => Schema}]
      # @param status_map [Array<StatusMapping>]
      # @param error_map [Array<ErrorRule>]
      # @param webhooks [Array<Webhook>]
      # @param units [Units, nil]
      # @param idempotency [Idempotency, nil]
      # @param warnings [Array<Warning>]
      # @raise [ArgumentError]
      def initialize(info: nil, servers: [], auth: nil, operations: [], schemas: {}, status_map: [],
                     error_map: [], webhooks: [], units: nil, idempotency: nil, warnings: [])
        Node.assert_optional!(info, Info, 'info')
        Node.assert_optional!(auth, Auth, 'auth')
        Node.assert_optional!(units, Units, 'units')
        Node.assert_optional!(idempotency, Idempotency, 'idempotency')
        super
      end

      # Records a warning. Analyzers call this instead of touching the array.
      # @param code [Symbol] one of Warning::CODES
      # @param message [String]
      # @param json_path [String, nil]
      # @param severity [Symbol] one of Warning::SEVERITIES
      # @param suggested_overlay [String, nil]
      # @return [Warning] the recorded warning
      def warn(code, message, json_path: nil, severity: :warning, suggested_overlay: nil)
        warning = Warning.new(code:, message:, json_path:, severity:, suggested_overlay:)
        warnings << warning
        warning
      end

      # @return [Array<Warning>] by severity, then JSONPath, then code
      def sorted_warnings
        warnings.sort_by(&:sort_key)
      end

      # @return [Hash{Symbol => Array<Warning>}] every severity present as a
      #   key, most severe first, each list sorted
      def warnings_by_severity
        sorted = sorted_warnings
        Warning::SEVERITIES.to_h { |severity| [severity, sorted.select { |w| w.severity == severity }] }
      end

      # @param severity [Symbol, nil] restrict to one severity
      # @return [Boolean]
      def warnings?(severity = nil)
        return !warnings.empty? if severity.nil?

        warnings.any? { |warning| warning.severity == severity }
      end

      # @param role [Symbol] one of Roles::OPERATION
      # @return [Array<Operation>] in spec order
      def operations_by_role(role)
        Roles.operation!(role)
        operations.select { |operation| operation.role.value == role }
      end

      # @param role [Symbol] one of Roles::OPERATION
      # @return [Operation, nil] the first operation with that role
      def operation_for(role)
        operations_by_role(role).first
      end

      # @param key [String] Operation#key
      # @return [Operation, nil]
      def operation(key)
        operations.find { |operation| operation.key == key }
      end

      # @param name [String]
      # @return [Schema, nil]
      def schema(name)
        schemas[name]
      end

      # @return [Array<ErrorRule>] in table order
      def sorted_error_map
        error_map.sort_by(&:sort_key)
      end

      # Members in definition order; schemas by name, error rules by
      # selector and warnings by severity, so the output never depends on
      # the order analyzers ran in.
      # @return [Hash{Symbol => Object}]
      def to_h
        by_name = schemas.keys.sort
        super.merge(
          schemas: by_name.to_h { |name| [name, Node.dump(schemas[name])] },
          error_map: sorted_error_map.map(&:to_h),
          warnings: sorted_warnings.map(&:to_h)
        )
      end
    end
  end
end
