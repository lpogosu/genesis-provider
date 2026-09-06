# frozen_string_literal: true

# Сгенерировано инструментом integrate из govuk_pay_v1.json, версия спецификации
# 1.0.3, OpenAPI 3.0.1. Не редактируйте вручную: правки — в overlay
# (OpenAPI Overlay 1.0.0) и повторная генерация.
#
# Проверка файла:
#   ruby -c output/govuk_pay_v1_service.rb
#   bundle exec rubocop --config config/rubocop_generated.yml output/govuk_pay_v1_service.rb
#
# Контракт Provider::BaseService восстановлен по описанию кейса (допущение, см.
# docs/ASSUMPTIONS.md и INTEGRATION.md). HTTP-клиент платформы вызывается как
# client.post(url, payload, headers) и client.get(url, headers); ответ читается
# как response.status и response.body. Секреты — только provider.credentials[...]
# и ENV.fetch, литералов нет.

require 'digest'
require 'json'
require 'openssl'

# Пространство имён провайдеров платформы.
class Provider
  # Интеграция с провайдером «GOV.UK Pay API»: предпроверки, создание
  # операции, обработка уведомлений и опрос статуса по контракту
  # Provider::BaseService. Таблицы статусов, ошибок и политики ретраев —
  # замороженные хеши, сверяемые с INTEGRATION.md; TODO отмечают места, где
  # спецификация не дала ответа и инструмент взял лучшего кандидата.
  class GovukPayV1Service < Provider::BaseService
    # TODO: среда серверов не выведена, взят первый из списка — проверьте, что это песочница
    BASE_URL = ENV.fetch('GOVUK_PAY_V1_BASE_URL', 'https://publicapi.payments.service.gov.uk')
    # Таймауты в секундах; как передать их клиенту платформы, зависит от
    # клиента (его интерфейс — допущение), поэтому здесь только значения.
    OPEN_TIMEOUT = Integer(ENV.fetch('GOVUK_PAY_V1_OPEN_TIMEOUT', '5'))
    READ_TIMEOUT = Integer(ENV.fetch('GOVUK_PAY_V1_READ_TIMEOUT', '15'))
    PROVIDER = 'govuk_pay_v1'
    # TODO: единицы суммы не выведены (без кода валюты экспоненту ISO 4217 определить нельзя);
    #       множитель 1 — задайте x-specgen-amount-unit и x-specgen-exponent в overlay
    AMOUNT_MULTIPLIER = 1
    DEFAULT_ERROR_ACTION = :reject
    # Ключ идемпотентности отправляется всегда, даже если спецификация помечает заголовок
    # необязательным (параметр-заголовок Idempotency-Key совпал с алиасом rules/idempotency.yml;
    # принимают: Create a payment; объявлен required: false, но по rules/idempotency.yml
    # (send_when_optional) ключ отправляется всегда).
    IDEMPOTENCY_HEADER = 'Idempotency-Key'
    # Пространство имён UUID v5 (RFC 4122) для ключа идемпотентности: константа из
    # rules/idempotency.yml, менять нельзя — иначе повторы перестанут дедуплицироваться.
    IDEMPOTENCY_NAMESPACE = '6ba7b810-9dad-11d1-80b4-00c04fd430c8'

    # Статус провайдера → внутренний статус платформы.
    STATUS_MAP = {
      # TODO: статус не сопоставлен: статус active неоднозначен: состояние сущности (счёта, ключа,
      #       подписки), а не операции: у операции «активна» значит и «идёт», и «доступна к отмене»;
      #       задайте x-specgen-status-map в overlay
      'active' => nil,
      'cancelled' => :rejected,
      'created' => :in_progress,
      'error' => :rejected,
      # TODO: статус не сопоставлен: статус inactive неоднозначен: состояние сущности, а не
      #       операции: обратное к active; задайте x-specgen-status-map в overlay
      'inactive' => nil,
      'submitted' => :in_progress,
      'success' => :approved
    }.freeze

    # Код ошибки провайдера или HTTP-код → действие платформы
    # (reject | retry | retry_backoff | alert | escalate). Дедупликация в
    # таблицу не входит: это успешный путь, см. DEDUP_STATUS.
    ERROR_MAP = {
      # По HTTP-коду, когда тело не несёт кода ошибки.
      400 => :reject,
      401 => :alert,
      402 => :retry_backoff,
      404 => :reject,
      409 => :reject,
      412 => :reject,
      422 => :reject,
      429 => :retry_backoff
    }.freeze

    # Коды, которые у отдельной операции означают не то, что в ERROR_MAP.
    ERROR_MAP_BY_OPERATION = {
      'Authorise a MOTO payment' => {
        500 => :retry_backoff
      },
      'Cancel a payment' => {
        500 => :retry_backoff
      },
      'Cancel an agreement' => {
        500 => :retry_backoff
      },
      'Capture a payment' => {
        500 => :retry_backoff
      },
      'Create a payment' => {
        500 => :retry_backoff
      },
      'Create an agreement' => {
        500 => :retry_backoff
      },
      'Get a payment' => {
        500 => :retry_backoff
      },
      'Get a payment refund' => {
        500 => :retry_backoff
      },
      'Get all refunds for a payment' => {
        500 => :retry_backoff
      },
      'Get an agreement' => {
        500 => :retry_backoff
      },
      'Get events for a payment' => {
        500 => :retry_backoff
      },
      'Search agreements' => {
        500 => :retry_backoff
      },
      'Search disputes' => {
        500 => :retry_backoff
      },
      'Search payments' => {
        500 => :retry_backoff
      },
      'Search refunds' => {
        500 => :retry_backoff
      },
      'Submit a refund for a payment' => {
        500 => :retry_backoff
      }
    }.freeze

    # Код отказа для платформы: первый аргумент failure. Это код платформы в
    # духе HTTP, а не наше действие из ERROR_MAP, — платформа ветвится по
    # своему словарю, а смысл отказа остаётся вторым аргументом, в ключе
    # локализации. Таблица напечатана целиком: провайдер вправе ответить
    # кодом, которого спецификация не объявляла.
    FAILURE_CODES = {
      400 => :bad_request,
      401 => :unauthorized,
      403 => :forbidden,
      404 => :not_found,
      409 => :conflict,
      422 => :unprocessable_entity,
      429 => :too_many_requests,
      500 => :internal_server_error,
      502 => :bad_gateway,
      503 => :service_unavailable,
      504 => :gateway_timeout
    }.freeze

    # Запасной путь для HTTP-кода вне FAILURE_CODES: код платформы по
    # действию из ERROR_MAP.
    FAILURE_CODES_BY_ACTION = {
      reject: :unprocessable_entity,
      retry: :service_unavailable,
      retry_backoff: :service_unavailable,
      alert: :internal_server_error,
      escalate: :unprocessable_entity
    }.freeze

    # Политика ретраев — данные, не механизм: какие действия из ERROR_MAP
    # платформа повторяет и какие коды несут заголовок паузы. Сами ретраи,
    # очереди и алерты — инфраструктура платформы.
    RETRY_POLICY = {
      actions: %i[retry retry_backoff],
      statuses: [402, 429],
      retry_after_header: nil,
      retry_after_statuses: []
    }.freeze

    # Предпроверки до обращения к провайдеру: валюта, границы суммы, обязательные реквизиты
    # получателя, условная обязательность полей. Вызывает super, чтобы не потерять проверки базового
    # класса.
    # @param operation [Object]
    # @param request_method [Object]
    # @return [Object] success | failure
    def check_conditions(operation, request_method)
      result = super
      return result unless result.success?

      # minimum: 0 в единицах провайдера; множитель не выведен — пересчёт делает to_provider_units
      # (задано явно 1.00)
      if operation.amount < to_provider_units(0)
        return failure(:unprocessable_entity, 'errors.amount_below_minimum')
      end

      # maximum: 10000000 в единицах провайдера; множитель не выведен — пересчёт делает
      # to_provider_units (задано явно 1.00)
      if operation.amount > to_provider_units(10_000_000)
        return failure(:unprocessable_entity, 'errors.amount_above_maximum')
      end

      # reference: maxLength 255 (задано явно 1.00)
      if operation.provider_operation_key.to_s.length > 255
        return failure(:unprocessable_entity, 'errors.provider_operation_id_too_long')
      end

      success
    end

    # Создание операции у провайдера: сборка тела запроса из ролей, перевод суммы в единицы
    # провайдера, заголовки авторизации и идемпотентности, разбор ответа и кодов ошибок.
    # Вторая операция создания в спецификации: Authorise a MOTO payment; контракт даёт один метод,
    # она осталась снаружи.
    # @param operation [Object]
    # @param request_method [Object]
    # @return [Object] success | failure
    def create_request(operation, _request_method = 'create')
      payload = build_payload(operation)
      url = "#{BASE_URL}/v1/payments"
      response = client.post(url, payload, request_headers(operation))
      body = parse_json(response.body)
      return accept_created(operation, body) if response.status == 201

      provider_failure(response, body)
    end

    # Обработка входящего уведомления: проверка подписи, сопоставление операции по идентификаторам,
    # перевод статуса провайдера во внутренний и вызов approve_operation или reject_operation.
    # @param payload [Object]
    # @return [Object] success | failure
    def process_callback(_payload)
      # TODO: спецификация не описывает вебхуков: статус только опросом (fetch_status); метод
      #       отказывает
      failure(:not_implemented, 'errors.webhooks_not_supported')
    end

    # Опрос статуса операции у провайдера. Единственный путь получить статус, если провайдер не
    # отправляет вебхуки.
    # @param operation [Object]
    # @return [Object] success | failure
    def fetch_status(operation)
      url = "#{BASE_URL}/v1/payments/#{operation.provider_operation_key}"
      response = client.get(url, auth_headers)
      body = parse_json(response.body)
      return failure(:not_found, 'errors.operation_not_found') if response.status == 404
      return provider_failure(response, body) unless response.status == 200

      internal = map_status(body.dig('refund_summary', 'status'))
      return failure(:unprocessable_entity, 'errors.status_unknown') if internal.nil?

      apply_internal_status(operation, internal)
    end

    # Операция Search agreements (роль unmapped, эвристика 0.00) не отображена на контракт
    # BaseService: отдельный публичный метод.
    # TODO: роль операции не распознана (ни один сигнал не совпал ни с одной ролью) — проверьте,
    #       нужна ли она интеграции
    # @return [Object]
    def search_agreements
      url = "#{BASE_URL}/v1/agreements"
      response = client.get(url, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 200

      body
    end

    # Операция Create an agreement (роль unmapped, эвристика 0.00) не отображена на контракт
    # BaseService: отдельный публичный метод.
    # TODO: роль операции не распознана (ни одна роль не прошла отсечку формы: webhook 3.0, cancel
    #       2.0, confirm 2.0 из 8.0 поданных голосов; отсечены по форме: create_payout — ни в пути,
    #       ни в operationId нет ни одного платёжного существительного (vetoes.domain_nouns в
    #       rules/operations.yml), create_deposit — ни в пути, ни в operationId нет ни одного
    #       платёжного существительного (vetoes.domain_nouns в rules/operations.yml)) — проверьте,
    #       нужна ли она интеграции
    # @param operation [Object]
    # @return [Object]
    def create_an_agreement(operation)
      payload = build_create_an_agreement_payload(operation)
      url = "#{BASE_URL}/v1/agreements"
      response = client.post(url, payload, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 201

      body
    end

    # Операция Get an agreement (роль unmapped, эвристика 0.00) не отображена на контракт
    # BaseService: отдельный публичный метод.
    # TODO: роль операции не распознана (ни одна роль не прошла отсечку формы: cancel 1.0 из 11.0
    #       поданных голосов; отсечены по форме: fetch_status — ни в пути, ни в operationId нет ни
    #       одного платёжного существительного (vetoes.domain_nouns в rules/operations.yml), balance
    #       — ни в пути, ни в operationId нет ни одного платёжного существительного
    #       (vetoes.domain_nouns в rules/operations.yml)) — проверьте, нужна ли она интеграции
    # @param operation [Object]
    # @return [Object]
    def get_an_agreement(operation)
      # TODO: параметр пути {agreementId} без роли — подставлен operation.provider_operation_key;
      #       задайте x-specgen-role в overlay
      url = "#{BASE_URL}/v1/agreements/#{operation.provider_operation_key}"
      response = client.get(url, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 200

      body
    end

    # Операция Cancel an agreement (роль cancel, эвристика 0.95) не отображена на контракт
    # BaseService: отдельный публичный метод.
    # @param operation [Object]
    # @return [Object]
    def cancel(operation)
      # TODO: параметр пути {agreementId} без роли — подставлен operation.provider_operation_key;
      #       задайте x-specgen-role в overlay
      url = "#{BASE_URL}/v1/agreements/#{operation.provider_operation_key}/cancel"
      response = client.post(url, {}, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 204

      accept_response(operation, body)
    end

    # Операция Authorise a MOTO payment (роль create_payout, эвристика 0.72) не отображена на
    # контракт BaseService: отдельный публичный метод.
    # TODO: метод контракта уже занят операцией Create a payment; эта операция той же роли осталась
    #       снаружи — решите, нужна ли она интеграции
    # @param operation [Object]
    # @return [Object]
    def authorise_a_moto_payment(operation)
      payload = build_authorise_a_moto_payment_payload(operation)
      url = "#{BASE_URL}/v1/auth"
      response = client.post(url, payload, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 204

      body
    end

    # Операция Search disputes (роль unmapped, эвристика 0.00) не отображена на контракт
    # BaseService: отдельный публичный метод.
    # TODO: роль операции не распознана (ни один сигнал не совпал ни с одной ролью) — проверьте,
    #       нужна ли она интеграции
    # @return [Object]
    def search_disputes
      url = "#{BASE_URL}/v1/disputes"
      response = client.get(url, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 200

      body
    end

    # Операция Search payments (роль unmapped, эвристика 0.00) не отображена на контракт
    # BaseService: отдельный публичный метод.
    # TODO: роль операции не распознана (ни одна роль не прошла отсечку формы: balance 3.0 из 14.0
    #       поданных голосов; отсечены по форме: create_payout — HTTP-метод операции не из тех,
    #       которыми выражается эта роль (vetoes.http_method в rules/operations.yml), fetch_status —
    #       успешный ответ — список, то есть листинг ресурса, а не чтение одного экземпляра
    #       (vetoes.list_response в rules/operations.yml), cancel — HTTP-метод операции не из тех,
    #       которыми выражается эта роль (vetoes.http_method в rules/operations.yml), confirm —
    #       HTTP-метод операции не из тех, которыми выражается эта роль (vetoes.http_method в
    #       rules/operations.yml), refund — HTTP-метод операции не из тех, которыми выражается эта
    #       роль (vetoes.http_method в rules/operations.yml)) — проверьте, нужна ли она интеграции
    # @return [Object]
    def search_payments
      url = "#{BASE_URL}/v1/payments"
      response = client.get(url, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 200

      body
    end

    # Операция Cancel a payment (роль cancel, эвристика 0.95) не отображена на контракт BaseService:
    # отдельный публичный метод.
    # @param operation [Object]
    # @return [Object]
    def cancel_a_payment(operation)
      url = "#{BASE_URL}/v1/payments/#{operation.provider_operation_key}/cancel"
      response = client.post(url, {}, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 204

      accept_response(operation, body)
    end

    # Операция Capture a payment (роль confirm, эвристика 0.86) не отображена на контракт
    # BaseService: отдельный публичный метод.
    # @param operation [Object]
    # @return [Object]
    def confirm(operation)
      url = "#{BASE_URL}/v1/payments/#{operation.provider_operation_key}/capture"
      response = client.post(url, {}, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 204

      accept_response(operation, body)
    end

    # Операция Get events for a payment (роль fetch_status, эвристика 0.79) не отображена на
    # контракт BaseService: отдельный публичный метод.
    # TODO: метод контракта уже занят операцией Get a payment; эта операция той же роли осталась
    #       снаружи — решите, нужна ли она интеграции
    # @param operation [Object]
    # @return [Object]
    def get_events_for_a_payment(operation)
      url = "#{BASE_URL}/v1/payments/#{operation.provider_operation_key}/events"
      response = client.get(url, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 200

      body
    end

    # Операция Get all refunds for a payment (роль fetch_status, эвристика 0.79) не отображена на
    # контракт BaseService: отдельный публичный метод.
    # TODO: метод контракта уже занят операцией Get a payment; эта операция той же роли осталась
    #       снаружи — решите, нужна ли она интеграции
    # @param operation [Object]
    # @return [Object]
    def get_all_refunds_for_a_payment(operation)
      url = "#{BASE_URL}/v1/payments/#{operation.provider_operation_key}/refunds"
      response = client.get(url, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 200

      body
    end

    # Операция Submit a refund for a payment (роль refund, эвристика 0.86) не отображена на контракт
    # BaseService: отдельный публичный метод.
    # @param operation [Object]
    # @return [Object]
    def refund(operation)
      payload = build_refund_payload(operation)
      url = "#{BASE_URL}/v1/payments/#{operation.provider_operation_key}/refunds"
      response = client.post(url, payload, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless [200, 202].include?(response.status)

      body
    end

    # Операция Get a payment refund (роль fetch_status, эвристика 0.95) не отображена на контракт
    # BaseService: отдельный публичный метод.
    # TODO: метод контракта уже занят операцией Get a payment; эта операция той же роли осталась
    #       снаружи — решите, нужна ли она интеграции
    # @param operation [Object]
    # @return [Object]
    def get_a_payment_refund(operation)
      # TODO: параметр пути {paymentId} без роли — подставлен operation.provider_operation_key;
      #       задайте x-specgen-role в overlay
      url = "#{BASE_URL}/v1/payments/#{operation.provider_operation_key}/refunds/" \
            "#{operation.provider_operation_key}"
      response = client.get(url, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 200

      body
    end

    # Операция Search refunds (роль unmapped, эвристика 0.00) не отображена на контракт BaseService:
    # отдельный публичный метод.
    # TODO: роль операции не распознана (ни одна роль не прошла отсечку формы: balance 3.0 из 12.0
    #       поданных голосов; отсечены по форме: refund — HTTP-метод операции не из тех, которыми
    #       выражается эта роль (vetoes.http_method в rules/operations.yml), fetch_status — успешный
    #       ответ — список, то есть листинг ресурса, а не чтение одного экземпляра
    #       (vetoes.list_response в rules/operations.yml), cancel — HTTP-метод операции не из тех,
    #       которыми выражается эта роль (vetoes.http_method в rules/operations.yml), create_payout
    #       — HTTP-метод операции не из тех, которыми выражается эта роль (vetoes.http_method в
    #       rules/operations.yml)) — проверьте, нужна ли она интеграции
    # @return [Object]
    def search_refunds
      url = "#{BASE_URL}/v1/refunds"
      response = client.get(url, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 200

      body
    end

    private

    # Тело запроса по ролям полей схемы CreateCardPaymentRequest; nil-значения убираются.
    def build_payload(operation)
      payload = {
        amount: to_provider_units(operation.amount),
        # TODO: роль поля не определена. Обязательно по спецификации.
        #   тип: string, minLength: 0, maxLength: 255
        #   описание из спецификации: "A human-readable description of the payment you’re creating.
        #   Paying users see this description on the payment pages. Service staff see the
        #   description in the GOV.UK Pay admin tool"
        #   обоснование: ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml
        #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
        #   rules/roles.yml
        description: 'New passport application',
        # роль provider_operation_id выведена с уверенностью ниже порога (эвристика 0.50):
        # композитное сопоставление: name 2.0 (общие токены с синонимом `acquirer_reference`:
        # reference (50%)), structure 4.0 (родитель `CreateCardPaymentRequest` содержит токен
        # `payment` из подсказок роли), type 1.0 (type string допустим для роли) = 7.0 из 14.0;
        # следующая external_id 0.21 — проверьте по report.md
        reference: operation.provider_operation_key,
        # TODO: роль поля не определена. Обязательно по спецификации.
        #   тип: string, minLength: 0, maxLength: 2000
        #   описание из спецификации: "The URL [the paying user is directed to after their payment
        #   journey on GOV.UK Pay
        #   ends](https://docs.payments.service.gov.uk/making_payments/#choose-the-return-url-and-ma
        #   tch-your-users-to-payments)."
        #   обоснование: ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml
        #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
        #   rules/roles.yml
        return_url: 'https://service-name.gov.uk/transactions/12345'
      }
      compact_payload(payload)
    end

    # Тело запроса операции Create an agreement по ролям полей схемы CreateAgreementRequest;
    # nil-значения убираются.
    def build_create_an_agreement_payload(operation)
      payload = {
        # роль external_id выведена с уверенностью ниже порога (эвристика 0.21): композитное
        # сопоставление: name 2.0 (общие токены с синонимом `client_reference`: reference (50%)),
        # type 1.0 (type string допустим для роли) = 3.0 из 14.0; следующая provider_operation_id
        # 0.21 — проверьте по report.md
        reference: operation.id
      }
      compact_payload(payload)
    end

    # Тело запроса операции Authorise a MOTO payment по ролям полей схемы AuthorisationRequest;
    # nil-значения убираются.
    def build_authorise_a_moto_payment_payload(_operation)
      payload = {
        # TODO: роль card_number выведена, но выражения платформы для неё нет. Обязательно по
        #       спецификации.
        #   тип: string, minLength: 12, maxLength: 19
        #   описание из спецификации: "The full card number from the paying user's card."
        #   где это лежит у платформы, знает только человек: заполните вручную или добавьте
        #   выражение в rules/contract.yml (раздел platform)
        card_number: nil,
        # TODO: роль поля не определена. Обязательно по спецификации.
        #   тип: string, minLength: 0, maxLength: 255
        #   описание из спецификации: "The name on the paying user's card."
        #   обоснование: ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml
        #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
        #   rules/roles.yml
        cardholder_name: 'J. Citizen',
        # TODO: роль поля не определена. Обязательно по спецификации.
        #   тип: string, minLength: 3, maxLength: 4
        #   описание из спецификации: "The card verification code (CVC) or card verification value
        #   (CVV) on the paying user's card."
        #   обоснование: ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml
        #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
        #   rules/roles.yml
        cvc: '123',
        # TODO: роль поля не определена. Обязательно по спецификации.
        #   тип: string, minLength: 5, maxLength: 5
        #   описание из спецификации: "The expiry date of the paying user's card. This value must be
        #   in `MM/YY` format."
        #   обоснование: ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml
        #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
        #   rules/roles.yml
        expiry_date: '09/22',
        # TODO: роль поля не определена. Обязательно по спецификации.
        #   тип: string, minLength: 1
        #   описание из спецификации: "This single use token authorises your request and matches it
        #   to a payment. GOV.UK Pay generated the `one_time_token` when the payment was created."
        #   обоснование: ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml
        #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
        #   rules/roles.yml
        one_time_token: '12345-edsfr-6789-gtyu'
      }
      compact_payload(payload)
    end

    # Тело запроса операции Submit a refund for a payment по ролям полей схемы PaymentRefundRequest;
    # nil-значения убираются.
    def build_refund_payload(operation)
      payload = {
        amount: to_provider_units(operation.amount)
      }
      compact_payload(payload)
    end

    # Заголовки запроса на создание: авторизация, тип содержимого и ключ идемпотентности.
    def request_headers(operation)
      auth_headers.merge('Content-Type' => 'application/json',
                         IDEMPOTENCY_HEADER => idempotency_key_for(operation))
    end

    # Заголовки авторизации: схема BearerAuth (bearer) по записи rules/auth.yml «bearer». Секрет
    # читается из provider.credentials.
    # @return [Hash]
    def auth_headers
      { 'Authorization' => "Bearer #{provider.credentials[:token]}" }
    end

    # Успешный ответ на создание: перевести статус и вернуть платформе идентификатор операции у
    # провайдера — она сохраняет его как provider_operation_key из result[:id].
    def accept_created(operation, body)
      apply_internal_status(operation, map_status(body.dig('refund_summary', 'status')))
      success(result: { id: body['payment_id'] })
    end

    # Успешный ответ провайдера на отмену или подтверждение: перевести статус, если он пришёл и
    # знаком; незнакомый статус оставляет операцию in_progress. Результата у метода нет — статус
    # меняют хелперы.
    def accept_response(operation, body)
      internal = map_status(body.dig('refund_summary', 'status'))
      return success if internal.nil?

      apply_internal_status(operation, internal)
    end

    # Перевод цели уведомления или операции во внутренний статус хелперами базового класса;
    # in_progress ничего не меняет.
    def apply_internal_status(target, internal)
      case internal
      when :approved then approve_operation(target)
      when :rejected then reject_operation(target)
      end
      success
    end

    # Статус провайдера → внутренний по STATUS_MAP; nil для незнакомого.
    def map_status(raw)
      STATUS_MAP[raw.to_s]
    end

    # Ответ с ошибкой: действие по ERROR_MAP (сначала код провайдера, потом HTTP-код) — это политика
    # обработки, а платформе уходит её код отказа.
    def provider_failure(response, body)
      code = body['code']
      action = ERROR_MAP[code] || ERROR_MAP[response.status] || DEFAULT_ERROR_ACTION
      failure(platform_failure_code(response.status, action), "errors.#{code || response.status}")
    end

    # Код отказа для платформы: по HTTP-коду ответа провайдера, иначе по действию из ERROR_MAP.
    def platform_failure_code(status, action)
      FAILURE_CODES[status] || FAILURE_CODES_BY_ACTION[action]
    end

    # Тело ответа как хеш; битый или не-объектный JSON даёт пустой хеш.
    def parse_json(text)
      parsed = JSON.parse(text.to_s)
      parsed.is_a?(Hash) ? parsed : {}
    rescue JSON::ParserError
      {}
    end

    # Рекурсивно убирает nil-значения: необязательное поле без значения не отправляется.
    def compact_payload(value)
      return value unless value.is_a?(Hash)

      value.transform_values { |item| compact_payload(item) }.compact
    end

    # Сумма из мажорных единиц платформы в единицы провайдера по AMOUNT_MULTIPLIER (ISO 4217).
    def to_provider_units(amount)
      (amount * AMOUNT_MULTIPLIER).round
    end

    # Детерминированный ключ идемпотентности от operation.id: повтор даёт тот же ключ и
    # дедуплицируется провайдером. Никакой случайности.
    def idempotency_key_for(operation)
      uuid_v5(IDEMPOTENCY_NAMESPACE, "#{PROVIDER}:#{operation.id}")
    end

    # UUID v5 по RFC 4122 §4.3: SHA-1 от пространства имён и имени, версия 5, вариант RFC. Только
    # stdlib.
    def uuid_v5(namespace, name)
      digest = Digest::SHA1.digest([namespace.delete('-')].pack('H*') + name.to_s)
      bytes = digest.bytes[0, 16]
      bytes[6] = (bytes[6] & 0x0f) | 0x50
      bytes[8] = (bytes[8] & 0x3f) | 0x80
      hex = bytes.pack('C*').unpack1('H*')
      [hex[0, 8], hex[8, 4], hex[12, 4], hex[16, 4], hex[20, 12]].join('-')
    end
  end
end
