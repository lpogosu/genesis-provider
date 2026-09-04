# frozen_string_literal: true

module SpecGen
  module IR
    # Одна пара «путь + метод» из спецификации вместе с ролью, которую она
    # играет для сгенерированного сервиса. Операция, которая не отображается
    # ни на один метод контракта, получает явную роль :unmapped и всё равно
    # попадает сюда — чтобы отчёт мог её перечислить, а не выбросить
    # функциональность молча.
    #
    #   id                  operationId дословно; nil, если его нет в спеке
    #   role                Derived<Symbol>, одна из Roles::OPERATION
    #   http_method         :get | :post | ... (`method` перекрыл бы
    #                       Object#method)
    #   path                шаблон пути дословно, например "/payouts/{id}"
    #   summary             дословно
    #   tags                дословно
    #   parameters          [Parameter]
    #   request_schema      имя схемы тела запроса или nil
    #   request_required    requestBody.required
    #   request_media_type  "application/json", если спецификация не говорит
    #                       иного
    #   request_examples    {имя => значение} из examples у requestBody
    #   responses           [Response] в порядке спецификации
    #   secured             false, если операция объявляет `security: []`
    #   json_path           "$.paths['/payouts'].post"
    Operation = Struct.new(:id, :role, :http_method, :path, :summary, :tags, :parameters,
                           :request_schema, :request_required, :request_media_type,
                           :request_examples, :responses, :secured, :json_path,
                           keyword_init: true)

    # Словарь значений, проверки и выборки Operation.
    class Operation
      include Node

      METHODS = %i[get post put patch delete head options trace].freeze
      JSON = 'application/json'

      # @param role [Derived] выведенная, одна из Roles::OPERATION
      # @param http_method [Symbol] один из METHODS
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
        Node.assert_derived!(role, 'роль операции', allowed: Roles::OPERATION,
                                                    allow_unknown: false)
        Node.assert_member!(METHODS, http_method, 'HTTP-метод')
        Node.assert_text!(path, 'путь операции')
        unless path.start_with?('/')
          raise ArgumentError,
                "путь операции: должен начинаться с '/', получено #{path.inspect}"
        end

        super
      end

      # Устойчивый идентификатор, которым ErrorRule, Idempotency и Webhook
      # ссылаются на операцию даже тогда, когда в спецификации нет
      # operationId.
      # @return [String] operationId или "POST /payouts"
      def key
        id || "#{http_method.to_s.upcase} #{path}"
      end

      # @param status [String, Integer]
      # @return [Response, nil]
      def response(status)
        responses.find { |response| response.status == status.to_s }
      end

      # @return [Array<Response>] ответы 2xx в порядке спецификации
      def success_responses
        responses.select(&:success?)
      end

      # @param location [Symbol] одно из Parameter::LOCATIONS
      # @return [Array<Parameter>]
      def parameters_in(location)
        parameters.select { |parameter| parameter.location == location }
      end

      # @return [Boolean] явно не отображена ни на один метод контракта
      def unmapped?
        role.value == :unmapped
      end

      # @return [Boolean] отображается на метод Provider::BaseService
      def contract?
        Roles.contract?(role.value)
      end
    end
  end
end
