# frozen_string_literal: true

module SpecGen
  module IR
    # One path + method of the spec, with the role it plays for the
    # generated service. An operation that maps to no contract method gets
    # the explicit role :unmapped and still appears here, so that the report
    # can list it instead of silently dropping functionality.
    #
    #   id                  operationId verbatim, nil when the spec has none
    #   role                Derived<Symbol> one of Roles::OPERATION
    #   http_method         :get | :post | ... (`method` would shadow Object#method)
    #   path                path template verbatim, e.g. "/payouts/{id}"
    #   summary             verbatim
    #   tags                verbatim
    #   parameters          [Parameter]
    #   request_schema      name of the request body schema, or nil
    #   request_required    requestBody.required
    #   request_media_type  "application/json" unless the spec says otherwise
    #   request_examples    {name => value} from requestBody examples
    #   responses           [Response] in spec order
    #   secured             false when the operation declares `security: []`
    #   json_path           "$.paths['/payouts'].post"
    Operation = Struct.new(:id, :role, :http_method, :path, :summary, :tags, :parameters,
                           :request_schema, :request_required, :request_media_type,
                           :request_examples, :responses, :secured, :json_path,
                           keyword_init: true)

    # Vocabulary, checks and lookups of Operation.
    class Operation
      include Node

      METHODS = %i[get post put patch delete head options trace].freeze
      JSON = 'application/json'

      # @param role [Derived] known, one of Roles::OPERATION
      # @param http_method [Symbol] one of METHODS
      # @param path [String]
      # @param id [String, nil]
      # @param summary [String, nil]
      # @param tags [Array<String>]
      # @param parameters [Array<Parameter>]
      # @param request_schema [String, nil]
      # @param request_required [Boolean]
      # @param request_media_type [String]
      # @param request_examples [Hash{String => Object}]
      # @param responses [Array<Response>]
      # @param secured [Boolean]
      # @param json_path [String, nil]
      # @raise [ArgumentError]
      def initialize(role:, http_method:, path:, id: nil, summary: nil, tags: [], parameters: [],
                     request_schema: nil, request_required: false, request_media_type: JSON,
                     request_examples: {}, responses: [], secured: true, json_path: nil)
        Node.assert_derived!(role, 'operation role', allowed: Roles::OPERATION,
                                                     allow_unknown: false)
        Node.assert_member!(METHODS, http_method, 'HTTP method')
        Node.assert_text!(path, 'operation path')
        unless path.start_with?('/')
          raise ArgumentError,
                "operation path must start with '/', got #{path.inspect}"
        end

        super
      end

      # Stable identifier used by ErrorRule, Idempotency and Webhook to refer
      # to an operation even when the spec has no operationId.
      # @return [String] operationId or "POST /payouts"
      def key
        id || "#{http_method.to_s.upcase} #{path}"
      end

      # @param status [String, Integer]
      # @return [Response, nil]
      def response(status)
        responses.find { |response| response.status == status.to_s }
      end

      # @return [Array<Response>] 2xx responses in spec order
      def success_responses
        responses.select(&:success?)
      end

      # @param location [Symbol] one of Parameter::LOCATIONS
      # @return [Array<Parameter>]
      def parameters_in(location)
        parameters.select { |parameter| parameter.location == location }
      end

      # @return [Boolean] explicitly not mapped to any contract method
      def unmapped?
        role.value == :unmapped
      end

      # @return [Boolean] maps onto a Provider::BaseService method
      def contract?
        Roles.contract?(role.value)
      end
    end
  end
end
