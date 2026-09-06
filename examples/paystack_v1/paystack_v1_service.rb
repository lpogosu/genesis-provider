# frozen_string_literal: true

# Сгенерировано инструментом integrate из paystack_v1.yaml, версия спецификации
# 1.0.0, OpenAPI 3.0.1. Не редактируйте вручную: правки — в overlay
# (OpenAPI Overlay 1.0.0) и повторная генерация.
#
# Проверка файла:
#   ruby -c output/paystack_v1_service.rb
#   bundle exec rubocop --config config/rubocop_generated.yml output/paystack_v1_service.rb
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
  # Интеграция с провайдером «Paystack»: предпроверки, создание
  # операции, обработка уведомлений и опрос статуса по контракту
  # Provider::BaseService. Таблицы статусов, ошибок и политики ретраев —
  # замороженные хеши, сверяемые с INTEGRATION.md; TODO отмечают места, где
  # спецификация не дала ответа и инструмент взял лучшего кандидата.
  class PaystackV1Service < Provider::BaseService
    # TODO: среда серверов не выведена, взят первый из списка — проверьте, что это песочница
    BASE_URL = ENV.fetch('PAYSTACK_V1_BASE_URL', 'https://api.paystack.co')
    # Таймауты в секундах; как передать их клиенту платформы, зависит от
    # клиента (его интерфейс — допущение), поэтому здесь только значения.
    OPEN_TIMEOUT = Integer(ENV.fetch('PAYSTACK_V1_OPEN_TIMEOUT', '5'))
    READ_TIMEOUT = Integer(ENV.fetch('PAYSTACK_V1_READ_TIMEOUT', '15'))
    PROVIDER = 'paystack_v1'
    # operation.amount — в мажорных единицах; провайдер ждёт minor при любой валюте спецификации
    # (ISO 4217: у всех валют enum (NGN, GHS, ZAR, USD) экспонента 2).
    AMOUNT_MULTIPLIER = 100
    DEFAULT_ERROR_ACTION = :reject
    # Пространство имён UUID v5 (RFC 4122) для ключа идемпотентности: константа из
    # rules/idempotency.yml, менять нельзя — иначе повторы перестанут дедуплицироваться.
    IDEMPOTENCY_NAMESPACE = '6ba7b810-9dad-11d1-80b4-00c04fd430c8'

    # Статус провайдера → внутренний статус платформы.
    # TODO: спецификация не объявляет статусов операции — таблица пуста.
    STATUS_MAP = {}.freeze

    # Код ошибки провайдера или HTTP-код → действие платформы
    # (reject | retry | retry_backoff | alert | escalate). Дедупликация в
    # таблицу не входит: это успешный путь, см. DEDUP_STATUS.
    ERROR_MAP = {
      # По HTTP-коду, когда тело не несёт кода ошибки.
      404 => :reject
    }.freeze

    # Коды, которые у отдельной операции означают не то, что в ERROR_MAP.
    ERROR_MAP_BY_OPERATION = {
      'balance_fetch' => {
        401 => :alert
      },
      'balance_ledger' => {
        401 => :alert
      },
      'bulkCharge_charges' => {
        401 => :alert
      },
      'bulkCharge_fetch' => {
        401 => :alert
      },
      'bulkCharge_initiate' => {
        401 => :alert
      },
      'bulkCharge_list' => {
        401 => :alert
      },
      'bulkCharge_pause' => {
        401 => :alert
      },
      'bulkCharge_resume' => {
        401 => :alert
      },
      'charge_check' => {
        401 => :alert
      },
      'charge_create' => {
        401 => :alert
      },
      'charge_submitAddress' => {
        401 => :alert
      },
      'charge_submitBirthday' => {
        401 => :alert
      },
      'charge_submitOtp' => {
        401 => :alert
      },
      'charge_submitPhone' => {
        401 => :alert
      },
      'charge_submitPin' => {
        401 => :alert
      },
      'customer_create' => {
        401 => :alert
      },
      'customer_deactivateAuthorization' => {
        401 => :alert
      },
      'customer_fetch' => {
        401 => :alert
      },
      'customer_list' => {
        401 => :alert
      },
      'customer_riskAction' => {
        401 => :alert
      },
      'customer_update' => {
        401 => :alert
      },
      'customer_validatte' => {
        401 => :alert
      },
      'dedicatedAccount_addSplit' => {
        401 => :alert
      },
      'dedicatedAccount_availableProviders' => {
        401 => :alert
      },
      'dedicatedAccount_create' => {
        401 => :alert
      },
      'dedicatedAccount_deactivate' => {
        401 => :alert
      },
      'dedicatedAccount_fetch' => {
        401 => :alert
      },
      'dedicatedAccount_list' => {
        401 => :alert
      },
      'delete_transferrecipient_code' => {
        401 => :alert
      },
      'dispute_download' => {
        401 => :alert
      },
      'dispute_evidence' => {
        401 => :alert
      },
      'dispute_fetch' => {
        401 => :alert
      },
      'dispute_list' => {
        401 => :alert
      },
      'dispute_resolve' => {
        401 => :alert
      },
      'dispute_transaction' => {
        401 => :alert
      },
      'dispute_update' => {
        401 => :alert
      },
      'dispute_uploadUrl' => {
        401 => :alert
      },
      'integration_fetchPaymentSessionTimeout' => {
        401 => :alert
      },
      'integration_updatePaymentSessionTimeout' => {
        401 => :alert
      },
      'page_addProducts' => {
        401 => :alert
      },
      'page_checkSlugAvailability' => {
        401 => :alert
      },
      'page_create' => {
        401 => :alert
      },
      'page_fetch' => {
        401 => :alert
      },
      'page_list' => {
        401 => :alert
      },
      'page_update' => {
        401 => :alert
      },
      'paymentRequest_archive' => {
        401 => :alert
      },
      'paymentRequest_create' => {
        401 => :alert
      },
      'paymentRequest_fetch' => {
        401 => :alert
      },
      'paymentRequest_finalize' => {
        401 => :alert
      },
      'paymentRequest_list' => {
        401 => :alert
      },
      'paymentRequest_notify' => {
        401 => :alert
      },
      'paymentRequest_totals' => {
        401 => :alert
      },
      'paymentRequest_update' => {
        401 => :alert
      },
      'paymentRequest_verify' => {
        401 => :alert
      },
      'plan_create' => {
        401 => :alert
      },
      'plan_fetch' => {
        401 => :alert
      },
      'plan_list' => {
        401 => :alert
      },
      'plan_update' => {
        401 => :alert
      },
      'product_create' => {
        401 => :alert
      },
      'product_delete' => {
        401 => :alert
      },
      'product_fetch' => {
        401 => :alert
      },
      'product_list' => {
        401 => :alert
      },
      'product_update' => {
        401 => :alert
      },
      'put_transferrecipient_code' => {
        401 => :alert
      },
      'refund_create' => {
        401 => :alert
      },
      'refund_fetch' => {
        401 => :alert
      },
      'refund_list' => {
        401 => :alert
      },
      'settlements_fetch' => {
        401 => :alert
      },
      'settlements_transaction' => {
        401 => :alert
      },
      'split_addSubaccount' => {
        401 => :alert
      },
      'split_create' => {
        401 => :alert
      },
      'split_fetch' => {
        401 => :alert
      },
      'split_list' => {
        401 => :alert
      },
      'split_removeSubaccount' => {
        401 => :alert
      },
      'split_update' => {
        401 => :alert
      },
      'subaccount_create' => {
        401 => :alert
      },
      'subaccount_fetch' => {
        401 => :alert
      },
      'subaccount_list' => {
        401 => :alert
      },
      'subaccount_update' => {
        401 => :alert
      },
      'subscription_create' => {
        401 => :alert
      },
      'subscription_disable' => {
        401 => :alert
      },
      'subscription_enable' => {
        401 => :alert
      },
      'subscription_fetch' => {
        401 => :alert
      },
      'subscription_list' => {
        401 => :alert
      },
      'subscription_manageEmail' => {
        401 => :alert
      },
      'subscription_manageLink' => {
        401 => :alert
      },
      'transaction_chargeAuthorization' => {
        401 => :alert
      },
      'transaction_checkAuthorization' => {
        401 => :alert
      },
      'transaction_download' => {
        401 => :alert
      },
      'transaction_event' => {
        401 => :alert
      },
      'transaction_fetch' => {
        401 => :alert
      },
      'transaction_initialize' => {
        401 => :alert
      },
      'transaction_list' => {
        401 => :alert
      },
      'transaction_partialDebit' => {
        401 => :alert
      },
      'transaction_session' => {
        401 => :alert
      },
      'transaction_timeline' => {
        401 => :alert
      },
      'transaction_totals' => {
        401 => :alert
      },
      'transaction_verify' => {
        401 => :alert
      },
      'transfer_bulk' => {
        401 => :alert
      },
      'transfer_disableOtp' => {
        401 => :alert
      },
      'transfer_disableOtpFinalize' => {
        401 => :alert
      },
      'transfer_download' => {
        401 => :alert
      },
      'transfer_enableOtp' => {
        401 => :alert
      },
      'transfer_fetch' => {
        401 => :alert
      },
      'transfer_finalize' => {
        401 => :alert
      },
      'transfer_initiate' => {
        401 => :alert
      },
      'transfer_list' => {
        401 => :alert
      },
      'transfer_resendOtp' => {
        401 => :alert
      },
      'transfer_verify' => {
        401 => :alert
      },
      'transferrecipient_bulk' => {
        401 => :alert
      },
      'transferrecipient_create' => {
        401 => :alert
      },
      'transferrecipient_fetch' => {
        401 => :alert
      },
      'transferrecipient_list' => {
        401 => :alert
      },
      'verification_avs' => {
        401 => :alert
      },
      'verification_bvnMatch' => {
        401 => :alert
      },
      'verification_fetchBanks' => {
        401 => :alert
      },
      'verification_listCountries' => {
        401 => :alert
      },
      'verification_resolveAccountNumber' => {
        401 => :alert
      },
      'verification_resolveBvn' => {
        401 => :alert
      },
      'verification_resolveCardBin' => {
        401 => :alert
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
      statuses: [],
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

      success
    end

    # Создание операции у провайдера: сборка тела запроса из ролей, перевод суммы в единицы
    # провайдера, заголовки авторизации и идемпотентности, разбор ответа и кодов ошибок.
    # Вторая операция создания в спецификации: transaction_initialize,
    # transaction_chargeAuthorization, transaction_checkAuthorization, transaction_partialDebit,
    # paymentRequest_create, transferrecipient_create, transferrecipient_bulk, transfer_finalize,
    # transfer_bulk, transfer_resendOtp, transfer_disableOtpFinalize, charge_create,
    # charge_submitPin, charge_submitOtp, charge_submitPhone, charge_submitBirthday,
    # charge_submitAddress, bulkCharge_initiate; контракт даёт один метод, она осталась снаружи.
    # @param operation [Object]
    # @param request_method [Object]
    # @return [Object] success | failure
    def create_request(operation, _request_method = 'create')
      payload = build_payload(operation)
      url = "#{BASE_URL}/transfer"
      response = client.post(url, payload, request_headers)
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
      # TODO: параметр пути {code} без роли — подставлен operation.provider_operation_key; задайте
      #       x-specgen-role в overlay
      url = "#{BASE_URL}/transfer/#{operation.provider_operation_key}"
      response = client.get(url, auth_headers)
      body = parse_json(response.body)
      return failure(:not_found, 'errors.operation_not_found') if response.status == 404
      return provider_failure(response, body) unless response.status == 200

      internal = map_status(body['status'])
      return failure(:unprocessable_entity, 'errors.status_unknown') if internal.nil?

      apply_internal_status(operation, internal)
    end

    # Операция transaction_initialize (роль create_payout, эвристика 0.77) не отображена на контракт
    # BaseService: отдельный публичный метод.
    # TODO: метод контракта уже занят операцией transfer_initiate; эта операция той же роли осталась
    #       снаружи — решите, нужна ли она интеграции
    # @param operation [Object]
    # @return [Object]
    def transaction_initialize(operation)
      payload = build_transaction_initialize_payload(operation)
      url = "#{BASE_URL}/transaction/initialize"
      response = client.post(url, payload, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 201

      body
    end

    # Операция transaction_verify (роль fetch_status, эвристика 0.82) не отображена на контракт
    # BaseService: отдельный публичный метод.
    # TODO: метод контракта уже занят операцией transfer_fetch; эта операция той же роли осталась
    #       снаружи — решите, нужна ли она интеграции
    # @param operation [Object]
    # @return [Object]
    def transaction_verify(operation)
      url = "#{BASE_URL}/transaction/verify/#{operation.provider_operation_key}"
      response = client.get(url, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 200

      body
    end

    # Операция transaction_list (роль fetch_status, эвристика 0.77) не отображена на контракт
    # BaseService: отдельный публичный метод.
    # TODO: метод контракта уже занят операцией transfer_fetch; эта операция той же роли осталась
    #       снаружи — решите, нужна ли она интеграции
    # @return [Object]
    def transaction_list
      url = "#{BASE_URL}/transaction"
      response = client.get(url, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 200

      body
    end

    # Операция transaction_fetch (роль fetch_status, эвристика 0.95) не отображена на контракт
    # BaseService: отдельный публичный метод.
    # TODO: метод контракта уже занят операцией transfer_fetch; эта операция той же роли осталась
    #       снаружи — решите, нужна ли она интеграции
    # @param operation [Object]
    # @return [Object]
    def transaction_fetch(operation)
      url = "#{BASE_URL}/transaction/#{operation.provider_operation_key}"
      response = client.get(url, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 200

      body
    end

    # Операция transaction_timeline (роль fetch_status, эвристика 0.82) не отображена на контракт
    # BaseService: отдельный публичный метод.
    # TODO: метод контракта уже занят операцией transfer_fetch; эта операция той же роли осталась
    #       снаружи — решите, нужна ли она интеграции
    # @param operation [Object]
    # @return [Object]
    def transaction_timeline(operation)
      url = "#{BASE_URL}/transaction/timeline/#{operation.id}"
      response = client.get(url, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 200

      body
    end

    # Операция transaction_totals (роль fetch_status, эвристика 0.77) не отображена на контракт
    # BaseService: отдельный публичный метод.
    # TODO: метод контракта уже занят операцией transfer_fetch; эта операция той же роли осталась
    #       снаружи — решите, нужна ли она интеграции
    # @return [Object]
    def transaction_totals
      url = "#{BASE_URL}/transaction/totals"
      response = client.get(url, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 200

      body
    end

    # Операция transaction_download (роль fetch_status, эвристика 0.77) не отображена на контракт
    # BaseService: отдельный публичный метод.
    # TODO: метод контракта уже занят операцией transfer_fetch; эта операция той же роли осталась
    #       снаружи — решите, нужна ли она интеграции
    # @return [Object]
    def transaction_download
      url = "#{BASE_URL}/transaction/export"
      response = client.get(url, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 200

      body
    end

    # Операция transaction_chargeAuthorization (роль create_payout, эвристика 0.77) не отображена на
    # контракт BaseService: отдельный публичный метод.
    # TODO: метод контракта уже занят операцией transfer_initiate; эта операция той же роли осталась
    #       снаружи — решите, нужна ли она интеграции
    # @param operation [Object]
    # @return [Object]
    def transaction_charge_authorization(operation)
      payload = build_transaction_charge_authorization_payload(operation)
      url = "#{BASE_URL}/transaction/charge_authorization"
      response = client.post(url, payload, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 201

      body
    end

    # Операция transaction_checkAuthorization (роль create_payout, эвристика 0.77) не отображена на
    # контракт BaseService: отдельный публичный метод.
    # TODO: метод контракта уже занят операцией transfer_initiate; эта операция той же роли осталась
    #       снаружи — решите, нужна ли она интеграции
    # @param operation [Object]
    # @return [Object]
    def transaction_check_authorization(operation)
      payload = build_transaction_check_authorization_payload(operation)
      url = "#{BASE_URL}/transaction/check_authorization"
      response = client.post(url, payload, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 201

      body
    end

    # Операция transaction_partialDebit (роль create_payout, эвристика 0.77) не отображена на
    # контракт BaseService: отдельный публичный метод.
    # TODO: метод контракта уже занят операцией transfer_initiate; эта операция той же роли осталась
    #       снаружи — решите, нужна ли она интеграции
    # @param operation [Object]
    # @return [Object]
    def transaction_partial_debit(operation)
      payload = build_transaction_partial_debit_payload(operation)
      url = "#{BASE_URL}/transaction/partial_debit"
      response = client.post(url, payload, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 201

      body
    end

    # Операция transaction_event (роль fetch_status, эвристика 0.61) не отображена на контракт
    # BaseService: отдельный публичный метод.
    # TODO: метод контракта уже занят операцией transfer_fetch; эта операция той же роли осталась
    #       снаружи — решите, нужна ли она интеграции
    # @param operation [Object]
    # @return [Object]
    def transaction_event(operation)
      url = "#{BASE_URL}/transaction/#{operation.provider_operation_key}/event"
      response = client.get(url, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 200

      body
    end

    # Операция transaction_session (роль fetch_status, эвристика 0.77) не отображена на контракт
    # BaseService: отдельный публичный метод.
    # TODO: метод контракта уже занят операцией transfer_fetch; эта операция той же роли осталась
    #       снаружи — решите, нужна ли она интеграции
    # @param operation [Object]
    # @return [Object]
    def transaction_session(operation)
      url = "#{BASE_URL}/transaction/#{operation.provider_operation_key}/session"
      response = client.get(url, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 200

      body
    end

    # Операция split_create (роль unmapped, эвристика 0.00) не отображена на контракт BaseService:
    # отдельный публичный метод.
    # TODO: роль операции не распознана (ни одна роль не прошла отсечку формы: webhook 3.0, cancel
    #       2.0, confirm 2.0 из 8.0 поданных голосов; отсечены по форме: create_payout — ни в пути,
    #       ни в operationId нет ни одного платёжного существительного (vetoes.domain_nouns в
    #       rules/operations.yml), create_deposit — ни в пути, ни в operationId нет ни одного
    #       платёжного существительного (vetoes.domain_nouns в rules/operations.yml)) — проверьте,
    #       нужна ли она интеграции
    # @param operation [Object]
    # @return [Object]
    def split_create(operation)
      payload = build_split_create_payload(operation)
      url = "#{BASE_URL}/split"
      response = client.post(url, payload, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 201

      body
    end

    # Операция split_list (роль unmapped, эвристика 0.00) не отображена на контракт BaseService:
    # отдельный публичный метод.
    # TODO: роль операции не распознана (ни один сигнал не совпал ни с одной ролью) — проверьте,
    #       нужна ли она интеграции
    # @return [Object]
    def split_list
      url = "#{BASE_URL}/split"
      response = client.get(url, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 200

      body
    end

    # Операция split_fetch (роль unmapped, эвристика 0.00) не отображена на контракт BaseService:
    # отдельный публичный метод.
    # TODO: роль операции не распознана (ни одна роль не прошла отсечку формы: cancel 1.0 из 11.0
    #       поданных голосов; отсечены по форме: fetch_status — ни в пути, ни в operationId нет ни
    #       одного платёжного существительного (vetoes.domain_nouns в rules/operations.yml), balance
    #       — ни в пути, ни в operationId нет ни одного платёжного существительного
    #       (vetoes.domain_nouns в rules/operations.yml)) — проверьте, нужна ли она интеграции
    # @param operation [Object]
    # @return [Object]
    def split_fetch(operation)
      url = "#{BASE_URL}/split/#{operation.provider_operation_key}"
      response = client.get(url, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 200

      body
    end

    # Операция split_update (роль unmapped, эвристика 0.00) не отображена на контракт BaseService:
    # отдельный публичный метод.
    # TODO: роль операции не распознана (ни одна роль не прошла отсечку формы: create_payout 1.0,
    #       create_deposit 1.0, webhook 1.0 из 4.0 поданных голосов; отсечены по форме: fetch_status
    #       — ни в пути, ни в operationId нет ни одного платёжного существительного
    #       (vetoes.domain_nouns в rules/operations.yml)) — проверьте, нужна ли она интеграции
    # @param operation [Object]
    # @return [Object]
    def split_update(operation)
      payload = build_split_update_payload(operation)
      url = "#{BASE_URL}/split/#{operation.provider_operation_key}"
      response = client.put(url, payload, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 200

      body
    end

    # Операция split_addSubaccount (роль unmapped, эвристика 0.00) не отображена на контракт
    # BaseService: отдельный публичный метод.
    # TODO: роль операции не распознана (ни один сигнал не совпал ни с одной ролью) — проверьте,
    #       нужна ли она интеграции
    # @param operation [Object]
    # @return [Object]
    def split_add_subaccount(operation)
      payload = build_split_add_subaccount_payload(operation)
      url = "#{BASE_URL}/split/#{operation.provider_operation_key}/subaccount/add"
      response = client.post(url, payload, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 201

      body
    end

    # Операция split_removeSubaccount (роль unmapped, эвристика 0.00) не отображена на контракт
    # BaseService: отдельный публичный метод.
    # TODO: роль операции не распознана (ни один сигнал не совпал ни с одной ролью) — проверьте,
    #       нужна ли она интеграции
    # @param operation [Object]
    # @return [Object]
    def split_remove_subaccount(operation)
      payload = build_split_remove_subaccount_payload(operation)
      url = "#{BASE_URL}/split/#{operation.provider_operation_key}/subaccount/remove"
      response = client.post(url, payload, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 201

      body
    end

    # Операция customer_create (роль unmapped, эвристика 0.00) не отображена на контракт
    # BaseService: отдельный публичный метод.
    # TODO: роль операции не распознана (ни одна роль не прошла отсечку формы: webhook 3.0, cancel
    #       2.0, confirm 2.0 из 8.0 поданных голосов; отсечены по форме: create_payout — ни в пути,
    #       ни в operationId нет ни одного платёжного существительного (vetoes.domain_nouns в
    #       rules/operations.yml), create_deposit — ни в пути, ни в operationId нет ни одного
    #       платёжного существительного (vetoes.domain_nouns в rules/operations.yml)) — проверьте,
    #       нужна ли она интеграции
    # @param operation [Object]
    # @return [Object]
    def customer_create(operation)
      payload = build_customer_create_payload(operation)
      url = "#{BASE_URL}/customer"
      response = client.post(url, payload, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 201

      body
    end

    # Операция customer_list (роль unmapped, эвристика 0.00) не отображена на контракт BaseService:
    # отдельный публичный метод.
    # TODO: роль операции не распознана (ни один сигнал не совпал ни с одной ролью) — проверьте,
    #       нужна ли она интеграции
    # @return [Object]
    def customer_list
      url = "#{BASE_URL}/customer"
      response = client.get(url, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 200

      body
    end

    # Операция customer_fetch (роль unmapped, эвристика 0.00) не отображена на контракт BaseService:
    # отдельный публичный метод.
    # TODO: роль операции не распознана (ни одна роль не прошла отсечку формы: cancel 1.0 из 11.0
    #       поданных голосов; отсечены по форме: fetch_status — ни в пути, ни в operationId нет ни
    #       одного платёжного существительного (vetoes.domain_nouns в rules/operations.yml), balance
    #       — ни в пути, ни в operationId нет ни одного платёжного существительного
    #       (vetoes.domain_nouns в rules/operations.yml)) — проверьте, нужна ли она интеграции
    # @param operation [Object]
    # @return [Object]
    def customer_fetch(operation)
      # TODO: параметр пути {code} без роли — подставлен operation.provider_operation_key; задайте
      #       x-specgen-role в overlay
      url = "#{BASE_URL}/customer/#{operation.provider_operation_key}"
      response = client.get(url, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 200

      body
    end

    # Операция customer_update (роль unmapped, эвристика 0.00) не отображена на контракт
    # BaseService: отдельный публичный метод.
    # TODO: роль операции не распознана (ни одна роль не прошла отсечку формы: create_payout 1.0,
    #       create_deposit 1.0, webhook 1.0 из 4.0 поданных голосов; отсечены по форме: fetch_status
    #       — ни в пути, ни в operationId нет ни одного платёжного существительного
    #       (vetoes.domain_nouns в rules/operations.yml)) — проверьте, нужна ли она интеграции
    # @param operation [Object]
    # @return [Object]
    def customer_update(operation)
      # TODO: параметр пути {code} без роли — подставлен operation.provider_operation_key; задайте
      #       x-specgen-role в overlay
      payload = build_customer_update_payload(operation)
      url = "#{BASE_URL}/customer/#{operation.provider_operation_key}"
      response = client.put(url, payload, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 200

      body
    end

    # Операция customer_riskAction (роль unmapped, эвристика 0.00) не отображена на контракт
    # BaseService: отдельный публичный метод.
    # TODO: роль операции не распознана (ни один сигнал не совпал ни с одной ролью) — проверьте,
    #       нужна ли она интеграции
    # @param operation [Object]
    # @return [Object]
    def customer_risk_action(operation)
      payload = build_customer_risk_action_payload(operation)
      url = "#{BASE_URL}/customer/set_risk_action"
      response = client.post(url, payload, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 201

      body
    end

    # Операция customer_deactivateAuthorization (роль unmapped, эвристика 0.00) не отображена на
    # контракт BaseService: отдельный публичный метод.
    # TODO: роль операции не распознана (ни один сигнал не совпал ни с одной ролью) — проверьте,
    #       нужна ли она интеграции
    # @param operation [Object]
    # @return [Object]
    def customer_deactivate_authorization(operation)
      payload = build_customer_deactivate_authorization_payload(operation)
      url = "#{BASE_URL}/customer/deactivate_authorization"
      response = client.post(url, payload, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 201

      body
    end

    # Операция customer_validatte (роль unmapped, эвристика 0.00) не отображена на контракт
    # BaseService: отдельный публичный метод.
    # TODO: роль операции не распознана (ни один сигнал не совпал ни с одной ролью) — проверьте,
    #       нужна ли она интеграции
    # @param operation [Object]
    # @return [Object]
    def customer_validatte(operation)
      # TODO: параметр пути {code} без роли — подставлен operation.provider_operation_key; задайте
      #       x-specgen-role в overlay
      payload = build_customer_validatte_payload(operation)
      url = "#{BASE_URL}/customer/#{operation.provider_operation_key}/identification"
      response = client.post(url, payload, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 201

      body
    end

    # Операция dedicatedAccount_create (роль unmapped, эвристика 0.00) не отображена на контракт
    # BaseService: отдельный публичный метод.
    # TODO: роль операции не распознана (ни одна роль не прошла отсечку формы: webhook 3.0, cancel
    #       2.0, confirm 2.0 из 14.0 поданных голосов; отсечены по форме: balance — HTTP-метод
    #       операции не из тех, которыми выражается эта роль (vetoes.http_method в
    #       rules/operations.yml), create_payout — ни в пути, ни в operationId нет ни одного
    #       платёжного существительного (vetoes.domain_nouns в rules/operations.yml), create_deposit
    #       — ни в пути, ни в operationId нет ни одного платёжного существительного
    #       (vetoes.domain_nouns в rules/operations.yml)) — проверьте, нужна ли она интеграции
    # @param operation [Object]
    # @return [Object]
    def dedicated_account_create(operation)
      payload = build_dedicated_account_create_payload(operation)
      url = "#{BASE_URL}/dedicated_account"
      response = client.post(url, payload, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 201

      body
    end

    # Операция dedicatedAccount_list (роль balance, эвристика 0.82) не отображена на контракт
    # BaseService: отдельный публичный метод.
    # @return [Object]
    def balance
      url = "#{BASE_URL}/dedicated_account"
      response = client.get(url, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 200

      body
    end

    # Операция dedicatedAccount_fetch (роль balance, эвристика 0.79) не отображена на контракт
    # BaseService: отдельный публичный метод.
    # @param operation [Object]
    # @return [Object]
    def dedicated_account_fetch(operation)
      # TODO: параметр пути {account_id} без роли — подставлен operation.provider_operation_key;
      #       задайте x-specgen-role в overlay
      url = "#{BASE_URL}/dedicated_account/#{operation.provider_operation_key}"
      response = client.get(url, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 200

      body
    end

    # Операция dedicatedAccount_deactivate (роль unmapped, эвристика 0.00) не отображена на контракт
    # BaseService: отдельный публичный метод.
    # TODO: роль операции не распознана (ни одна роль не прошла отсечку формы: cancel 3.0 из 14.0
    #       поданных голосов; отсечены по форме: balance — HTTP-метод операции не из тех, которыми
    #       выражается эта роль (vetoes.http_method в rules/operations.yml), fetch_status — ни в
    #       пути, ни в operationId нет ни одного платёжного существительного (vetoes.domain_nouns в
    #       rules/operations.yml)) — проверьте, нужна ли она интеграции
    # @param operation [Object]
    # @return [Object]
    def dedicated_account_deactivate(operation)
      # TODO: параметр пути {account_id} без роли — подставлен operation.provider_operation_key;
      #       задайте x-specgen-role в overlay
      url = "#{BASE_URL}/dedicated_account/#{operation.provider_operation_key}"
      response = client.delete(url, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 200

      body
    end

    # Операция dedicatedAccount_availableProviders (роль balance, эвристика 0.77) не отображена на
    # контракт BaseService: отдельный публичный метод.
    # @return [Object]
    def dedicated_account_available_providers
      url = "#{BASE_URL}/dedicated_account/available_providers"
      response = client.get(url, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 200

      body
    end

    # Операция dedicatedAccount_addSplit (роль unmapped, эвристика 0.00) не отображена на контракт
    # BaseService: отдельный публичный метод.
    # TODO: роль операции не распознана (ни одна роль не прошла отсечку формы: create_payout 3.0,
    #       create_deposit 3.0, webhook 3.0 из 11.0 поданных голосов; отсечены по форме: balance —
    #       HTTP-метод операции не из тех, которыми выражается эта роль (vetoes.http_method в
    #       rules/operations.yml)) — проверьте, нужна ли она интеграции
    # @param operation [Object]
    # @return [Object]
    def dedicated_account_add_split(operation)
      payload = build_dedicated_account_add_split_payload(operation)
      url = "#{BASE_URL}/dedicated_account/split"
      response = client.post(url, payload, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 201

      body
    end

    # Операция subaccount_create (роль unmapped, эвристика 0.00) не отображена на контракт
    # BaseService: отдельный публичный метод.
    # TODO: роль операции не распознана (ни одна роль не прошла отсечку формы: webhook 3.0, cancel
    #       2.0, confirm 2.0 из 8.0 поданных голосов; отсечены по форме: create_payout — ни в пути,
    #       ни в operationId нет ни одного платёжного существительного (vetoes.domain_nouns в
    #       rules/operations.yml), create_deposit — ни в пути, ни в operationId нет ни одного
    #       платёжного существительного (vetoes.domain_nouns в rules/operations.yml)) — проверьте,
    #       нужна ли она интеграции
    # @param operation [Object]
    # @return [Object]
    def subaccount_create(operation)
      payload = build_subaccount_create_payload(operation)
      url = "#{BASE_URL}/subaccount"
      response = client.post(url, payload, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 201

      body
    end

    # Операция subaccount_list (роль unmapped, эвристика 0.00) не отображена на контракт
    # BaseService: отдельный публичный метод.
    # TODO: роль операции не распознана (ни один сигнал не совпал ни с одной ролью) — проверьте,
    #       нужна ли она интеграции
    # @return [Object]
    def subaccount_list
      url = "#{BASE_URL}/subaccount"
      response = client.get(url, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 200

      body
    end

    # Операция subaccount_fetch (роль unmapped, эвристика 0.00) не отображена на контракт
    # BaseService: отдельный публичный метод.
    # TODO: роль операции не распознана (ни одна роль не прошла отсечку формы: cancel 1.0 из 11.0
    #       поданных голосов; отсечены по форме: fetch_status — ни в пути, ни в operationId нет ни
    #       одного платёжного существительного (vetoes.domain_nouns в rules/operations.yml), balance
    #       — ни в пути, ни в operationId нет ни одного платёжного существительного
    #       (vetoes.domain_nouns в rules/operations.yml)) — проверьте, нужна ли она интеграции
    # @param operation [Object]
    # @return [Object]
    def subaccount_fetch(operation)
      # TODO: параметр пути {code} без роли — подставлен operation.provider_operation_key; задайте
      #       x-specgen-role в overlay
      url = "#{BASE_URL}/subaccount/#{operation.provider_operation_key}"
      response = client.get(url, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 200

      body
    end

    # Операция subaccount_update (роль unmapped, эвристика 0.00) не отображена на контракт
    # BaseService: отдельный публичный метод.
    # TODO: роль операции не распознана (ни одна роль не прошла отсечку формы: create_payout 1.0,
    #       create_deposit 1.0, webhook 1.0 из 4.0 поданных голосов; отсечены по форме: fetch_status
    #       — ни в пути, ни в operationId нет ни одного платёжного существительного
    #       (vetoes.domain_nouns в rules/operations.yml)) — проверьте, нужна ли она интеграции
    # @param operation [Object]
    # @return [Object]
    def subaccount_update(operation)
      # TODO: параметр пути {code} без роли — подставлен operation.provider_operation_key; задайте
      #       x-specgen-role в overlay
      payload = build_subaccount_update_payload(operation)
      url = "#{BASE_URL}/subaccount/#{operation.provider_operation_key}"
      response = client.put(url, payload, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 200

      body
    end

    # Операция plan_create (роль unmapped, эвристика 0.00) не отображена на контракт BaseService:
    # отдельный публичный метод.
    # TODO: роль операции не распознана (ни одна роль не прошла отсечку формы: webhook 3.0, cancel
    #       2.0, confirm 2.0 из 8.0 поданных голосов; отсечены по форме: create_payout — ни в пути,
    #       ни в operationId нет ни одного платёжного существительного (vetoes.domain_nouns в
    #       rules/operations.yml), create_deposit — ни в пути, ни в operationId нет ни одного
    #       платёжного существительного (vetoes.domain_nouns в rules/operations.yml)) — проверьте,
    #       нужна ли она интеграции
    # @param operation [Object]
    # @return [Object]
    def plan_create(operation)
      payload = build_plan_create_payload(operation)
      url = "#{BASE_URL}/plan"
      response = client.post(url, payload, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 201

      body
    end

    # Операция plan_list (роль unmapped, эвристика 0.00) не отображена на контракт BaseService:
    # отдельный публичный метод.
    # TODO: роль операции не распознана (ни один сигнал не совпал ни с одной ролью) — проверьте,
    #       нужна ли она интеграции
    # @return [Object]
    def plan_list
      url = "#{BASE_URL}/plan"
      response = client.get(url, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 200

      body
    end

    # Операция plan_fetch (роль unmapped, эвристика 0.00) не отображена на контракт BaseService:
    # отдельный публичный метод.
    # TODO: роль операции не распознана (ни одна роль не прошла отсечку формы: cancel 1.0 из 11.0
    #       поданных голосов; отсечены по форме: fetch_status — ни в пути, ни в operationId нет ни
    #       одного платёжного существительного (vetoes.domain_nouns в rules/operations.yml), balance
    #       — ни в пути, ни в operationId нет ни одного платёжного существительного
    #       (vetoes.domain_nouns в rules/operations.yml)) — проверьте, нужна ли она интеграции
    # @param operation [Object]
    # @return [Object]
    def plan_fetch(operation)
      # TODO: параметр пути {code} без роли — подставлен operation.provider_operation_key; задайте
      #       x-specgen-role в overlay
      url = "#{BASE_URL}/plan/#{operation.provider_operation_key}"
      response = client.get(url, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 200

      body
    end

    # Операция plan_update (роль unmapped, эвристика 0.00) не отображена на контракт BaseService:
    # отдельный публичный метод.
    # TODO: роль операции не распознана (ни одна роль не прошла отсечку формы: create_payout 1.0,
    #       create_deposit 1.0, webhook 1.0 из 4.0 поданных голосов; отсечены по форме: fetch_status
    #       — ни в пути, ни в operationId нет ни одного платёжного существительного
    #       (vetoes.domain_nouns в rules/operations.yml)) — проверьте, нужна ли она интеграции
    # @param operation [Object]
    # @return [Object]
    def plan_update(operation)
      # TODO: параметр пути {code} без роли — подставлен operation.provider_operation_key; задайте
      #       x-specgen-role в overlay
      payload = build_plan_update_payload(operation)
      url = "#{BASE_URL}/plan/#{operation.provider_operation_key}"
      response = client.put(url, payload, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 200

      body
    end

    # Операция subscription_create (роль unmapped, эвристика 0.00) не отображена на контракт
    # BaseService: отдельный публичный метод.
    # TODO: роль операции не распознана (ни одна роль не прошла отсечку формы: webhook 3.0, cancel
    #       2.0, confirm 2.0 из 8.0 поданных голосов; отсечены по форме: create_payout — ни в пути,
    #       ни в operationId нет ни одного платёжного существительного (vetoes.domain_nouns в
    #       rules/operations.yml), create_deposit — ни в пути, ни в operationId нет ни одного
    #       платёжного существительного (vetoes.domain_nouns в rules/operations.yml)) — проверьте,
    #       нужна ли она интеграции
    # @param operation [Object]
    # @return [Object]
    def subscription_create(operation)
      payload = build_subscription_create_payload(operation)
      url = "#{BASE_URL}/subscription"
      response = client.post(url, payload, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 201

      body
    end

    # Операция subscription_list (роль unmapped, эвристика 0.00) не отображена на контракт
    # BaseService: отдельный публичный метод.
    # TODO: роль операции не распознана (ни один сигнал не совпал ни с одной ролью) — проверьте,
    #       нужна ли она интеграции
    # @return [Object]
    def subscription_list
      url = "#{BASE_URL}/subscription"
      response = client.get(url, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 200

      body
    end

    # Операция subscription_fetch (роль unmapped, эвристика 0.00) не отображена на контракт
    # BaseService: отдельный публичный метод.
    # TODO: роль операции не распознана (ни одна роль не прошла отсечку формы: cancel 1.0 из 11.0
    #       поданных голосов; отсечены по форме: fetch_status — ни в пути, ни в operationId нет ни
    #       одного платёжного существительного (vetoes.domain_nouns в rules/operations.yml), balance
    #       — ни в пути, ни в operationId нет ни одного платёжного существительного
    #       (vetoes.domain_nouns в rules/operations.yml)) — проверьте, нужна ли она интеграции
    # @param operation [Object]
    # @return [Object]
    def subscription_fetch(operation)
      # TODO: параметр пути {code} без роли — подставлен operation.provider_operation_key; задайте
      #       x-specgen-role в overlay
      url = "#{BASE_URL}/subscription/#{operation.provider_operation_key}"
      response = client.get(url, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 200

      body
    end

    # Операция subscription_disable (роль unmapped, эвристика 0.00) не отображена на контракт
    # BaseService: отдельный публичный метод.
    # TODO: роль операции не распознана (ни один сигнал не совпал ни с одной ролью) — проверьте,
    #       нужна ли она интеграции
    # @param operation [Object]
    # @return [Object]
    def subscription_disable(operation)
      payload = build_subscription_disable_payload(operation)
      url = "#{BASE_URL}/subscription/disable"
      response = client.post(url, payload, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 201

      body
    end

    # Операция subscription_enable (роль unmapped, эвристика 0.00) не отображена на контракт
    # BaseService: отдельный публичный метод.
    # TODO: роль операции не распознана (ни один сигнал не совпал ни с одной ролью) — проверьте,
    #       нужна ли она интеграции
    # @param operation [Object]
    # @return [Object]
    def subscription_enable(operation)
      payload = build_subscription_enable_payload(operation)
      url = "#{BASE_URL}/subscription/enable"
      response = client.post(url, payload, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 201

      body
    end

    # Операция subscription_manageLink (роль unmapped, эвристика 0.00) не отображена на контракт
    # BaseService: отдельный публичный метод.
    # TODO: роль операции не распознана (ни один сигнал не совпал ни с одной ролью) — проверьте,
    #       нужна ли она интеграции
    # @param operation [Object]
    # @return [Object]
    def subscription_manage_link(operation)
      # TODO: параметр пути {code} без роли — подставлен operation.provider_operation_key; задайте
      #       x-specgen-role в overlay
      url = "#{BASE_URL}/subscription/#{operation.provider_operation_key}/manage/link"
      response = client.post(url, {}, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 201

      body
    end

    # Операция subscription_manageEmail (роль unmapped, эвристика 0.00) не отображена на контракт
    # BaseService: отдельный публичный метод.
    # TODO: роль операции не распознана (ни один сигнал не совпал ни с одной ролью) — проверьте,
    #       нужна ли она интеграции
    # @param operation [Object]
    # @return [Object]
    def subscription_manage_email(operation)
      # TODO: параметр пути {code} без роли — подставлен operation.provider_operation_key; задайте
      #       x-specgen-role в overlay
      url = "#{BASE_URL}/subscription/#{operation.provider_operation_key}/manage/email"
      response = client.post(url, {}, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 201

      body
    end

    # Операция product_create (роль unmapped, эвристика 0.00) не отображена на контракт BaseService:
    # отдельный публичный метод.
    # TODO: роль операции не распознана (ни одна роль не прошла отсечку формы: webhook 3.0, cancel
    #       2.0, confirm 2.0 из 8.0 поданных голосов; отсечены по форме: create_payout — ни в пути,
    #       ни в operationId нет ни одного платёжного существительного (vetoes.domain_nouns в
    #       rules/operations.yml), create_deposit — ни в пути, ни в operationId нет ни одного
    #       платёжного существительного (vetoes.domain_nouns в rules/operations.yml)) — проверьте,
    #       нужна ли она интеграции
    # @param operation [Object]
    # @return [Object]
    def product_create(operation)
      payload = build_product_create_payload(operation)
      url = "#{BASE_URL}/product"
      response = client.post(url, payload, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 201

      body
    end

    # Операция product_list (роль unmapped, эвристика 0.00) не отображена на контракт BaseService:
    # отдельный публичный метод.
    # TODO: роль операции не распознана (ни один сигнал не совпал ни с одной ролью) — проверьте,
    #       нужна ли она интеграции
    # @return [Object]
    def product_list
      url = "#{BASE_URL}/product"
      response = client.get(url, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 200

      body
    end

    # Операция product_fetch (роль unmapped, эвристика 0.00) не отображена на контракт BaseService:
    # отдельный публичный метод.
    # TODO: роль операции не распознана (ни одна роль не прошла отсечку формы: cancel 1.0 из 11.0
    #       поданных голосов; отсечены по форме: fetch_status — ни в пути, ни в operationId нет ни
    #       одного платёжного существительного (vetoes.domain_nouns в rules/operations.yml), balance
    #       — ни в пути, ни в operationId нет ни одного платёжного существительного
    #       (vetoes.domain_nouns в rules/operations.yml)) — проверьте, нужна ли она интеграции
    # @param operation [Object]
    # @return [Object]
    def product_fetch(operation)
      url = "#{BASE_URL}/product/#{operation.provider_operation_key}"
      response = client.get(url, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 200

      body
    end

    # Операция product_update (роль unmapped, эвристика 0.00) не отображена на контракт BaseService:
    # отдельный публичный метод.
    # TODO: роль операции не распознана (ни одна роль не прошла отсечку формы: create_payout 1.0,
    #       create_deposit 1.0, webhook 1.0 из 4.0 поданных голосов; отсечены по форме: fetch_status
    #       — ни в пути, ни в operationId нет ни одного платёжного существительного
    #       (vetoes.domain_nouns в rules/operations.yml)) — проверьте, нужна ли она интеграции
    # @param operation [Object]
    # @return [Object]
    def product_update(operation)
      payload = build_product_update_payload(operation)
      url = "#{BASE_URL}/product/#{operation.provider_operation_key}"
      response = client.put(url, payload, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 200

      body
    end

    # Операция product_delete (роль unmapped, эвристика 0.00) не отображена на контракт BaseService:
    # отдельный публичный метод.
    # TODO: роль операции не распознана (ни одна роль не прошла отсечку формы: balance 1.0 из 11.0
    #       поданных голосов; отсечены по форме: cancel — ни в пути, ни в operationId нет ни одного
    #       платёжного существительного (vetoes.domain_nouns в rules/operations.yml), fetch_status —
    #       ни в пути, ни в operationId нет ни одного платёжного существительного
    #       (vetoes.domain_nouns в rules/operations.yml)) — проверьте, нужна ли она интеграции
    # @param operation [Object]
    # @return [Object]
    def product_delete(operation)
      url = "#{BASE_URL}/product/#{operation.provider_operation_key}"
      response = client.delete(url, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 200

      body
    end

    # Операция page_create (роль unmapped, эвристика 0.00) не отображена на контракт BaseService:
    # отдельный публичный метод.
    # TODO: роль операции не распознана (ни одна роль не прошла отсечку формы: webhook 3.0, cancel
    #       2.0, confirm 2.0 из 8.0 поданных голосов; отсечены по форме: create_payout — ни в пути,
    #       ни в operationId нет ни одного платёжного существительного (vetoes.domain_nouns в
    #       rules/operations.yml), create_deposit — ни в пути, ни в operationId нет ни одного
    #       платёжного существительного (vetoes.domain_nouns в rules/operations.yml)) — проверьте,
    #       нужна ли она интеграции
    # @param operation [Object]
    # @return [Object]
    def page_create(operation)
      payload = build_page_create_payload(operation)
      url = "#{BASE_URL}/page"
      response = client.post(url, payload, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 201

      body
    end

    # Операция page_list (роль unmapped, эвристика 0.00) не отображена на контракт BaseService:
    # отдельный публичный метод.
    # TODO: роль операции не распознана (ни один сигнал не совпал ни с одной ролью) — проверьте,
    #       нужна ли она интеграции
    # @return [Object]
    def page_list
      url = "#{BASE_URL}/page"
      response = client.get(url, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 200

      body
    end

    # Операция page_fetch (роль unmapped, эвристика 0.00) не отображена на контракт BaseService:
    # отдельный публичный метод.
    # TODO: роль операции не распознана (ни одна роль не прошла отсечку формы: cancel 1.0 из 11.0
    #       поданных голосов; отсечены по форме: fetch_status — ни в пути, ни в operationId нет ни
    #       одного платёжного существительного (vetoes.domain_nouns в rules/operations.yml), balance
    #       — ни в пути, ни в operationId нет ни одного платёжного существительного
    #       (vetoes.domain_nouns в rules/operations.yml)) — проверьте, нужна ли она интеграции
    # @param operation [Object]
    # @return [Object]
    def page_fetch(operation)
      url = "#{BASE_URL}/page/#{operation.provider_operation_key}"
      response = client.get(url, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 200

      body
    end

    # Операция page_update (роль unmapped, эвристика 0.00) не отображена на контракт BaseService:
    # отдельный публичный метод.
    # TODO: роль операции не распознана (ни одна роль не прошла отсечку формы: create_payout 1.0,
    #       create_deposit 1.0, webhook 1.0 из 4.0 поданных голосов; отсечены по форме: fetch_status
    #       — ни в пути, ни в operationId нет ни одного платёжного существительного
    #       (vetoes.domain_nouns в rules/operations.yml)) — проверьте, нужна ли она интеграции
    # @param operation [Object]
    # @return [Object]
    def page_update(operation)
      payload = build_page_update_payload(operation)
      url = "#{BASE_URL}/page/#{operation.provider_operation_key}"
      response = client.put(url, payload, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 200

      body
    end

    # Операция page_checkSlugAvailability (роль unmapped, эвристика 0.00) не отображена на контракт
    # BaseService: отдельный публичный метод.
    # TODO: роль операции не распознана (ни одна роль не прошла отсечку формы: cancel 1.0 из 11.0
    #       поданных голосов; отсечены по форме: fetch_status — ни в пути, ни в operationId нет ни
    #       одного платёжного существительного (vetoes.domain_nouns в rules/operations.yml), balance
    #       — ни в пути, ни в operationId нет ни одного платёжного существительного
    #       (vetoes.domain_nouns в rules/operations.yml)) — проверьте, нужна ли она интеграции
    # @param operation [Object]
    # @return [Object]
    def page_check_slug_availability(operation)
      # TODO: параметр пути {slug} без роли — подставлен operation.provider_operation_key; задайте
      #       x-specgen-role в overlay
      url = "#{BASE_URL}/page/check_slug_availability/#{operation.provider_operation_key}"
      response = client.get(url, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 200

      body
    end

    # Операция page_addProducts (роль unmapped, эвристика 0.00) не отображена на контракт
    # BaseService: отдельный публичный метод.
    # TODO: роль операции не распознана (ни один сигнал не совпал ни с одной ролью) — проверьте,
    #       нужна ли она интеграции
    # @param operation [Object]
    # @return [Object]
    def page_add_products(operation)
      payload = build_page_add_products_payload(operation)
      url = "#{BASE_URL}/page/#{operation.provider_operation_key}/product"
      response = client.post(url, payload, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 201

      body
    end

    # Операция paymentRequest_create (роль create_payout, эвристика 0.95) не отображена на контракт
    # BaseService: отдельный публичный метод.
    # TODO: метод контракта уже занят операцией transfer_initiate; эта операция той же роли осталась
    #       снаружи — решите, нужна ли она интеграции
    # @param operation [Object]
    # @return [Object]
    def payment_request_create(operation)
      payload = build_payment_request_create_payload(operation)
      url = "#{BASE_URL}/paymentrequest"
      response = client.post(url, payload, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 201

      body
    end

    # Операция paymentRequest_list (роль fetch_status, эвристика 0.72) не отображена на контракт
    # BaseService: отдельный публичный метод.
    # TODO: метод контракта уже занят операцией transfer_fetch; эта операция той же роли осталась
    #       снаружи — решите, нужна ли она интеграции
    # @return [Object]
    def payment_request_list
      url = "#{BASE_URL}/paymentrequest"
      response = client.get(url, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 200

      body
    end

    # Операция paymentRequest_fetch (роль fetch_status, эвристика 0.95) не отображена на контракт
    # BaseService: отдельный публичный метод.
    # TODO: метод контракта уже занят операцией transfer_fetch; эта операция той же роли осталась
    #       снаружи — решите, нужна ли она интеграции
    # @param operation [Object]
    # @return [Object]
    def payment_request_fetch(operation)
      url = "#{BASE_URL}/paymentrequest/#{operation.provider_operation_key}"
      response = client.get(url, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 200

      body
    end

    # Операция paymentRequest_update (роль unmapped, эвристика 0.00) не отображена на контракт
    # BaseService: отдельный публичный метод.
    # TODO: роль операции не распознана (ни одна роль не прошла отсечку формы: create_deposit 1.0,
    #       webhook 1.0 из 10.0 поданных голосов; отсечены по форме: fetch_status — HTTP-метод
    #       операции не из тех, которыми выражается эта роль (vetoes.http_method в
    #       rules/operations.yml), create_payout — HTTP-метод операции не из тех, которыми
    #       выражается эта роль (vetoes.http_method в rules/operations.yml), cancel — HTTP-метод
    #       операции не из тех, которыми выражается эта роль (vetoes.http_method в
    #       rules/operations.yml), confirm — HTTP-метод операции не из тех, которыми выражается эта
    #       роль (vetoes.http_method в rules/operations.yml), refund — HTTP-метод операции не из
    #       тех, которыми выражается эта роль (vetoes.http_method в rules/operations.yml)) —
    #       проверьте, нужна ли она интеграции
    # @param operation [Object]
    # @return [Object]
    def payment_request_update(operation)
      payload = build_payment_request_update_payload(operation)
      url = "#{BASE_URL}/paymentrequest/#{operation.provider_operation_key}"
      response = client.put(url, payload, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 200

      body
    end

    # Операция paymentRequest_verify (роль fetch_status, эвристика 0.79) не отображена на контракт
    # BaseService: отдельный публичный метод.
    # TODO: метод контракта уже занят операцией transfer_fetch; эта операция той же роли осталась
    #       снаружи — решите, нужна ли она интеграции
    # @param operation [Object]
    # @return [Object]
    def payment_request_verify(operation)
      url = "#{BASE_URL}/paymentrequest/verify/#{operation.provider_operation_key}"
      response = client.get(url, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 200

      body
    end

    # Операция paymentRequest_notify (роль cancel, эвристика 0.54) не отображена на контракт
    # BaseService: отдельный публичный метод.
    # @param operation [Object]
    # @return [Object]
    def cancel(operation)
      url = "#{BASE_URL}/paymentrequest/notify/#{operation.provider_operation_key}"
      response = client.post(url, {}, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 201

      accept_response(operation, body)
    end

    # Операция paymentRequest_totals (роль fetch_status, эвристика 0.72) не отображена на контракт
    # BaseService: отдельный публичный метод.
    # TODO: метод контракта уже занят операцией transfer_fetch; эта операция той же роли осталась
    #       снаружи — решите, нужна ли она интеграции
    # @return [Object]
    def payment_request_totals
      url = "#{BASE_URL}/paymentrequest/totals"
      response = client.get(url, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 200

      body
    end

    # Операция paymentRequest_finalize (роль cancel, эвристика 0.54) не отображена на контракт
    # BaseService: отдельный публичный метод.
    # @param operation [Object]
    # @return [Object]
    def payment_request_finalize(operation)
      url = "#{BASE_URL}/paymentrequest/finalize/#{operation.provider_operation_key}"
      response = client.post(url, {}, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 201

      accept_response(operation, body)
    end

    # Операция paymentRequest_archive (роль cancel, эвристика 0.54) не отображена на контракт
    # BaseService: отдельный публичный метод.
    # @param operation [Object]
    # @return [Object]
    def payment_request_archive(operation)
      url = "#{BASE_URL}/paymentrequest/archive/#{operation.provider_operation_key}"
      response = client.post(url, {}, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 201

      accept_response(operation, body)
    end

    # Операция settlements_fetch (роль unmapped, эвристика 0.00) не отображена на контракт
    # BaseService: отдельный публичный метод.
    # TODO: роль операции не распознана (ни одна роль не прошла отсечку формы: cancel 1.0 из 8.0
    #       поданных голосов; отсечены по форме: fetch_status — ни в пути, ни в operationId нет ни
    #       одного платёжного существительного (vetoes.domain_nouns в rules/operations.yml), balance
    #       — ни в пути, ни в operationId нет ни одного платёжного существительного
    #       (vetoes.domain_nouns в rules/operations.yml)) — проверьте, нужна ли она интеграции
    # @return [Object]
    def settlements_fetch
      url = "#{BASE_URL}/settlement"
      response = client.get(url, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 200

      body
    end

    # Операция settlements_transaction (роль fetch_status, эвристика 0.75) не отображена на контракт
    # BaseService: отдельный публичный метод.
    # TODO: метод контракта уже занят операцией transfer_fetch; эта операция той же роли осталась
    #       снаружи — решите, нужна ли она интеграции
    # @param operation [Object]
    # @return [Object]
    def settlements_transaction(operation)
      # TODO: параметр пути {id} без роли — подставлен operation.provider_operation_key; задайте
      #       x-specgen-role в overlay
      url = "#{BASE_URL}/settlement/#{operation.provider_operation_key}/transaction"
      response = client.get(url, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 200

      body
    end

    # Операция transferrecipient_create (роль create_payout, эвристика 0.72) не отображена на
    # контракт BaseService: отдельный публичный метод.
    # TODO: метод контракта уже занят операцией transfer_initiate; эта операция той же роли осталась
    #       снаружи — решите, нужна ли она интеграции
    # @param operation [Object]
    # @return [Object]
    def transferrecipient_create(operation)
      payload = build_transferrecipient_create_payload(operation)
      url = "#{BASE_URL}/transferrecipient"
      response = client.post(url, payload, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 201

      body
    end

    # Операция transferrecipient_list (роль fetch_status, эвристика 0.80) не отображена на контракт
    # BaseService: отдельный публичный метод.
    # TODO: метод контракта уже занят операцией transfer_fetch; эта операция той же роли осталась
    #       снаружи — решите, нужна ли она интеграции
    # @return [Object]
    def transferrecipient_list
      url = "#{BASE_URL}/transferrecipient"
      response = client.get(url, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 200

      body
    end

    # Операция transferrecipient_bulk (роль create_payout, эвристика 0.80) не отображена на контракт
    # BaseService: отдельный публичный метод.
    # TODO: метод контракта уже занят операцией transfer_initiate; эта операция той же роли осталась
    #       снаружи — решите, нужна ли она интеграции
    # @param operation [Object]
    # @return [Object]
    def transferrecipient_bulk(operation)
      payload = build_transferrecipient_bulk_payload(operation)
      url = "#{BASE_URL}/transferrecipient/bulk"
      response = client.post(url, payload, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 201

      body
    end

    # Операция transferrecipient_fetch (роль fetch_status, эвристика 0.79) не отображена на контракт
    # BaseService: отдельный публичный метод.
    # TODO: метод контракта уже занят операцией transfer_fetch; эта операция той же роли осталась
    #       снаружи — решите, нужна ли она интеграции
    # @param operation [Object]
    # @return [Object]
    def transferrecipient_fetch(operation)
      # TODO: параметр пути {code} без роли — подставлен operation.provider_operation_key; задайте
      #       x-specgen-role в overlay
      url = "#{BASE_URL}/transferrecipient/#{operation.provider_operation_key}"
      response = client.get(url, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 200

      body
    end

    # Операция put_transferrecipient_code (роль unmapped, эвристика 0.00) не отображена на контракт
    # BaseService: отдельный публичный метод.
    # TODO: роль операции не распознана (ни одна роль не прошла отсечку формы: create_deposit 1.0,
    #       webhook 1.0 из 5.0 поданных голосов; отсечены по форме: fetch_status — HTTP-метод
    #       операции не из тех, которыми выражается эта роль (vetoes.http_method в
    #       rules/operations.yml), create_payout — HTTP-метод операции не из тех, которыми
    #       выражается эта роль (vetoes.http_method в rules/operations.yml), cancel — HTTP-метод
    #       операции не из тех, которыми выражается эта роль (vetoes.http_method в
    #       rules/operations.yml)) — проверьте, нужна ли она интеграции
    # @param operation [Object]
    # @return [Object]
    def put_transferrecipient_code(operation)
      # TODO: параметр пути {code} без роли — подставлен operation.provider_operation_key; задайте
      #       x-specgen-role в overlay
      payload = build_put_transferrecipient_code_payload(operation)
      url = "#{BASE_URL}/transferrecipient/#{operation.provider_operation_key}"
      response = client.put(url, payload, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 200

      body
    end

    # Операция delete_transferrecipient_code (роль cancel, эвристика 0.57) не отображена на контракт
    # BaseService: отдельный публичный метод.
    # @param operation [Object]
    # @return [Object]
    def delete_transferrecipient_code(operation)
      # TODO: параметр пути {code} без роли — подставлен operation.provider_operation_key; задайте
      #       x-specgen-role в overlay
      url = "#{BASE_URL}/transferrecipient/#{operation.provider_operation_key}"
      response = client.delete(url, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 200

      accept_response(operation, body)
    end

    # Операция transfer_list (роль fetch_status, эвристика 0.77) не отображена на контракт
    # BaseService: отдельный публичный метод.
    # TODO: метод контракта уже занят операцией transfer_fetch; эта операция той же роли осталась
    #       снаружи — решите, нужна ли она интеграции
    # @return [Object]
    def transfer_list
      url = "#{BASE_URL}/transfer"
      response = client.get(url, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 200

      body
    end

    # Операция transfer_finalize (роль create_payout, эвристика 0.77) не отображена на контракт
    # BaseService: отдельный публичный метод.
    # TODO: метод контракта уже занят операцией transfer_initiate; эта операция той же роли осталась
    #       снаружи — решите, нужна ли она интеграции
    # @param operation [Object]
    # @return [Object]
    def transfer_finalize(operation)
      payload = build_transfer_finalize_payload(operation)
      url = "#{BASE_URL}/transfer/finalize_transfer"
      response = client.post(url, payload, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 201

      body
    end

    # Операция transfer_bulk (роль create_payout, эвристика 0.77) не отображена на контракт
    # BaseService: отдельный публичный метод.
    # TODO: метод контракта уже занят операцией transfer_initiate; эта операция той же роли осталась
    #       снаружи — решите, нужна ли она интеграции
    # @param operation [Object]
    # @return [Object]
    def transfer_bulk(operation)
      payload = build_transfer_bulk_payload(operation)
      url = "#{BASE_URL}/transfer/bulk"
      response = client.post(url, payload, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 201

      body
    end

    # Операция transfer_verify (роль fetch_status, эвристика 0.82) не отображена на контракт
    # BaseService: отдельный публичный метод.
    # TODO: метод контракта уже занят операцией transfer_fetch; эта операция той же роли осталась
    #       снаружи — решите, нужна ли она интеграции
    # @param operation [Object]
    # @return [Object]
    def transfer_verify(operation)
      url = "#{BASE_URL}/transfer/verify/#{operation.provider_operation_key}"
      response = client.get(url, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 200

      body
    end

    # Операция transfer_download (роль fetch_status, эвристика 0.77) не отображена на контракт
    # BaseService: отдельный публичный метод.
    # TODO: метод контракта уже занят операцией transfer_fetch; эта операция той же роли осталась
    #       снаружи — решите, нужна ли она интеграции
    # @return [Object]
    def transfer_download
      url = "#{BASE_URL}/transfer/export"
      response = client.get(url, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 200

      body
    end

    # Операция transfer_resendOtp (роль create_payout, эвристика 0.77) не отображена на контракт
    # BaseService: отдельный публичный метод.
    # TODO: метод контракта уже занят операцией transfer_initiate; эта операция той же роли осталась
    #       снаружи — решите, нужна ли она интеграции
    # @param operation [Object]
    # @return [Object]
    def transfer_resend_otp(operation)
      payload = build_transfer_resend_otp_payload(operation)
      url = "#{BASE_URL}/transfer/resend_otp"
      response = client.post(url, payload, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 201

      body
    end

    # Операция transfer_disableOtp (роль cancel, эвристика 0.77) не отображена на контракт
    # BaseService: отдельный публичный метод.
    # @return [Object]
    def transfer_disable_otp
      url = "#{BASE_URL}/transfer/disable_otp"
      response = client.post(url, {}, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 201

      body
    end

    # Операция transfer_disableOtpFinalize (роль create_payout, эвристика 0.77) не отображена на
    # контракт BaseService: отдельный публичный метод.
    # TODO: метод контракта уже занят операцией transfer_initiate; эта операция той же роли осталась
    #       снаружи — решите, нужна ли она интеграции
    # @param operation [Object]
    # @return [Object]
    def transfer_disable_otp_finalize(operation)
      payload = build_transfer_disable_otp_finalize_payload(operation)
      url = "#{BASE_URL}/transfer/disable_otp_finalize"
      response = client.post(url, payload, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 201

      body
    end

    # Операция transfer_enableOtp (роль cancel, эвристика 0.77) не отображена на контракт
    # BaseService: отдельный публичный метод.
    # @return [Object]
    def transfer_enable_otp
      url = "#{BASE_URL}/transfer/enable_otp"
      response = client.post(url, {}, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 201

      body
    end

    # Операция balance_fetch (роль balance, эвристика 0.95) не отображена на контракт BaseService:
    # отдельный публичный метод.
    # @return [Object]
    def balance_fetch
      url = "#{BASE_URL}/balance"
      response = client.get(url, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 200

      body
    end

    # Операция balance_ledger (роль balance, эвристика 0.77) не отображена на контракт BaseService:
    # отдельный публичный метод.
    # @return [Object]
    def balance_ledger
      url = "#{BASE_URL}/balance/ledger"
      response = client.get(url, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 200

      body
    end

    # Операция charge_create (роль create_deposit, эвристика 0.95) не отображена на контракт
    # BaseService: отдельный публичный метод.
    # TODO: метод контракта уже занят операцией transfer_initiate; эта операция той же роли осталась
    #       снаружи — решите, нужна ли она интеграции
    # @param operation [Object]
    # @return [Object]
    def charge_create(operation)
      payload = build_charge_create_payload(operation)
      url = "#{BASE_URL}/charge"
      response = client.post(url, payload, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 201

      body
    end

    # Операция charge_submitPin (роль create_deposit, эвристика 0.95) не отображена на контракт
    # BaseService: отдельный публичный метод.
    # TODO: метод контракта уже занят операцией transfer_initiate; эта операция той же роли осталась
    #       снаружи — решите, нужна ли она интеграции
    # @param operation [Object]
    # @return [Object]
    def charge_submit_pin(operation)
      payload = build_charge_submit_pin_payload(operation)
      url = "#{BASE_URL}/charge/submit_pin"
      response = client.post(url, payload, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 201

      body
    end

    # Операция charge_submitOtp (роль create_deposit, эвристика 0.95) не отображена на контракт
    # BaseService: отдельный публичный метод.
    # TODO: метод контракта уже занят операцией transfer_initiate; эта операция той же роли осталась
    #       снаружи — решите, нужна ли она интеграции
    # @param operation [Object]
    # @return [Object]
    def charge_submit_otp(operation)
      payload = build_charge_submit_otp_payload(operation)
      url = "#{BASE_URL}/charge/submit_otp"
      response = client.post(url, payload, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 201

      body
    end

    # Операция charge_submitPhone (роль create_deposit, эвристика 0.95) не отображена на контракт
    # BaseService: отдельный публичный метод.
    # TODO: метод контракта уже занят операцией transfer_initiate; эта операция той же роли осталась
    #       снаружи — решите, нужна ли она интеграции
    # @param operation [Object]
    # @return [Object]
    def charge_submit_phone(operation)
      payload = build_charge_submit_phone_payload(operation)
      url = "#{BASE_URL}/charge/submit_phone"
      response = client.post(url, payload, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 201

      body
    end

    # Операция charge_submitBirthday (роль create_deposit, эвристика 0.95) не отображена на контракт
    # BaseService: отдельный публичный метод.
    # TODO: метод контракта уже занят операцией transfer_initiate; эта операция той же роли осталась
    #       снаружи — решите, нужна ли она интеграции
    # @param operation [Object]
    # @return [Object]
    def charge_submit_birthday(operation)
      payload = build_charge_submit_birthday_payload(operation)
      url = "#{BASE_URL}/charge/submit_birthday"
      response = client.post(url, payload, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 201

      body
    end

    # Операция charge_submitAddress (роль create_deposit, эвристика 0.95) не отображена на контракт
    # BaseService: отдельный публичный метод.
    # TODO: метод контракта уже занят операцией transfer_initiate; эта операция той же роли осталась
    #       снаружи — решите, нужна ли она интеграции
    # @param operation [Object]
    # @return [Object]
    def charge_submit_address(operation)
      payload = build_charge_submit_address_payload(operation)
      url = "#{BASE_URL}/charge/submit_address"
      response = client.post(url, payload, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 201

      body
    end

    # Операция charge_check (роль fetch_status, эвристика 0.95) не отображена на контракт
    # BaseService: отдельный публичный метод.
    # TODO: метод контракта уже занят операцией transfer_fetch; эта операция той же роли осталась
    #       снаружи — решите, нужна ли она интеграции
    # @param operation [Object]
    # @return [Object]
    def charge_check(operation)
      url = "#{BASE_URL}/charge/#{operation.provider_operation_key}"
      response = client.get(url, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 200

      body
    end

    # Операция bulkCharge_initiate (роль create_deposit, эвристика 0.95) не отображена на контракт
    # BaseService: отдельный публичный метод.
    # TODO: метод контракта уже занят операцией transfer_initiate; эта операция той же роли осталась
    #       снаружи — решите, нужна ли она интеграции
    # @param operation [Object]
    # @return [Object]
    def bulk_charge_initiate(operation)
      payload = build_bulk_charge_initiate_payload(operation)
      url = "#{BASE_URL}/bulkcharge"
      response = client.post(url, payload, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 201

      body
    end

    # Операция bulkCharge_list (роль fetch_status, эвристика 0.69) не отображена на контракт
    # BaseService: отдельный публичный метод.
    # TODO: метод контракта уже занят операцией transfer_fetch; эта операция той же роли осталась
    #       снаружи — решите, нужна ли она интеграции
    # @return [Object]
    def bulk_charge_list
      url = "#{BASE_URL}/bulkcharge"
      response = client.get(url, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 200

      body
    end

    # Операция bulkCharge_fetch (роль fetch_status, эвристика 0.95) не отображена на контракт
    # BaseService: отдельный публичный метод.
    # TODO: метод контракта уже занят операцией transfer_fetch; эта операция той же роли осталась
    #       снаружи — решите, нужна ли она интеграции
    # @param operation [Object]
    # @return [Object]
    def bulk_charge_fetch(operation)
      # TODO: параметр пути {code} без роли — подставлен operation.provider_operation_key; задайте
      #       x-specgen-role в overlay
      url = "#{BASE_URL}/bulkcharge/#{operation.provider_operation_key}"
      response = client.get(url, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 200

      body
    end

    # Операция bulkCharge_charges (роль fetch_status, эвристика 0.58) не отображена на контракт
    # BaseService: отдельный публичный метод.
    # TODO: метод контракта уже занят операцией transfer_fetch; эта операция той же роли осталась
    #       снаружи — решите, нужна ли она интеграции
    # @param operation [Object]
    # @return [Object]
    def bulk_charge_charges(operation)
      # TODO: параметр пути {code} без роли — подставлен operation.provider_operation_key; задайте
      #       x-specgen-role в overlay
      url = "#{BASE_URL}/bulkcharge/#{operation.provider_operation_key}/charges"
      response = client.get(url, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 200

      body
    end

    # Операция bulkCharge_pause (роль fetch_status, эвристика 0.77) не отображена на контракт
    # BaseService: отдельный публичный метод.
    # TODO: метод контракта уже занят операцией transfer_fetch; эта операция той же роли осталась
    #       снаружи — решите, нужна ли она интеграции
    # @param operation [Object]
    # @return [Object]
    def bulk_charge_pause(operation)
      # TODO: параметр пути {code} без роли — подставлен operation.provider_operation_key; задайте
      #       x-specgen-role в overlay
      url = "#{BASE_URL}/bulkcharge/pause/#{operation.provider_operation_key}"
      response = client.get(url, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 200

      body
    end

    # Операция bulkCharge_resume (роль fetch_status, эвристика 0.77) не отображена на контракт
    # BaseService: отдельный публичный метод.
    # TODO: метод контракта уже занят операцией transfer_fetch; эта операция той же роли осталась
    #       снаружи — решите, нужна ли она интеграции
    # @param operation [Object]
    # @return [Object]
    def bulk_charge_resume(operation)
      # TODO: параметр пути {code} без роли — подставлен operation.provider_operation_key; задайте
      #       x-specgen-role в overlay
      url = "#{BASE_URL}/bulkcharge/resume/#{operation.provider_operation_key}"
      response = client.get(url, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 200

      body
    end

    # Операция integration_fetchPaymentSessionTimeout (роль fetch_status, эвристика 0.95) не
    # отображена на контракт BaseService: отдельный публичный метод.
    # TODO: метод контракта уже занят операцией transfer_fetch; эта операция той же роли осталась
    #       снаружи — решите, нужна ли она интеграции
    # @return [Object]
    def integration_fetch_payment_session_timeout
      url = "#{BASE_URL}/integration/payment_session_timeout"
      response = client.get(url, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 200

      body
    end

    # Операция integration_updatePaymentSessionTimeout (роль unmapped, эвристика 0.00) не отображена
    # на контракт BaseService: отдельный публичный метод.
    # TODO: роль операции не распознана (ни одна роль не прошла отсечку формы: create_deposit 1.0,
    #       webhook 1.0 из 8.0 поданных голосов; отсечены по форме: create_payout — HTTP-метод
    #       операции не из тех, которыми выражается эта роль (vetoes.http_method в
    #       rules/operations.yml), fetch_status — HTTP-метод операции не из тех, которыми выражается
    #       эта роль (vetoes.http_method в rules/operations.yml), cancel — HTTP-метод операции не из
    #       тех, которыми выражается эта роль (vetoes.http_method в rules/operations.yml), confirm —
    #       HTTP-метод операции не из тех, которыми выражается эта роль (vetoes.http_method в
    #       rules/operations.yml), refund — HTTP-метод операции не из тех, которыми выражается эта
    #       роль (vetoes.http_method в rules/operations.yml)) — проверьте, нужна ли она интеграции
    # @param operation [Object]
    # @return [Object]
    def integration_update_payment_session_timeout(operation)
      payload = build_integration_update_payment_session_timeout_payload(operation)
      url = "#{BASE_URL}/integration/payment_session_timeout"
      response = client.put(url, payload, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 200

      body
    end

    # Операция refund_create (роль refund, эвристика 0.92) не отображена на контракт BaseService:
    # отдельный публичный метод.
    # @param operation [Object]
    # @return [Object]
    def refund(operation)
      payload = build_refund_payload(operation)
      url = "#{BASE_URL}/refund"
      response = client.post(url, payload, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 201

      body
    end

    # Операция refund_list (роль unmapped, эвристика 0.00) не отображена на контракт BaseService:
    # отдельный публичный метод.
    # TODO: роль операции не распознана (ни одна роль не прошла отсечку формы: fetch_status 3.0,
    #       balance 3.0, cancel 1.0 из 12.0 поданных голосов; отсечены по форме: refund — HTTP-метод
    #       операции не из тех, которыми выражается эта роль (vetoes.http_method в
    #       rules/operations.yml)) — проверьте, нужна ли она интеграции
    # @return [Object]
    def refund_list
      url = "#{BASE_URL}/refund"
      response = client.get(url, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 200

      body
    end

    # Операция refund_fetch (роль unmapped, эвристика 0.00) не отображена на контракт BaseService:
    # отдельный публичный метод.
    # TODO: роль операции не распознана (ни одна роль не прошла отсечку формы: cancel 1.0 из 12.0
    #       поданных голосов; отсечены по форме: fetch_status — ни в пути, ни в operationId нет ни
    #       одного платёжного существительного (vetoes.domain_nouns в rules/operations.yml), refund
    #       — HTTP-метод операции не из тех, которыми выражается эта роль (vetoes.http_method в
    #       rules/operations.yml), balance — ни в пути, ни в operationId нет ни одного платёжного
    #       существительного (vetoes.domain_nouns в rules/operations.yml)) — проверьте, нужна ли она
    #       интеграции
    # @param operation [Object]
    # @return [Object]
    def refund_fetch(operation)
      url = "#{BASE_URL}/refund/#{operation.provider_operation_key}"
      response = client.get(url, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 200

      body
    end

    # Операция dispute_list (роль unmapped, эвристика 0.00) не отображена на контракт BaseService:
    # отдельный публичный метод.
    # TODO: роль операции не распознана (ни один сигнал не совпал ни с одной ролью) — проверьте,
    #       нужна ли она интеграции
    # @return [Object]
    def dispute_list
      url = "#{BASE_URL}/dispute"
      response = client.get(url, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 200

      body
    end

    # Операция dispute_fetch (роль unmapped, эвристика 0.00) не отображена на контракт BaseService:
    # отдельный публичный метод.
    # TODO: роль операции не распознана (ни одна роль не прошла отсечку формы: cancel 1.0 из 11.0
    #       поданных голосов; отсечены по форме: fetch_status — ни в пути, ни в operationId нет ни
    #       одного платёжного существительного (vetoes.domain_nouns в rules/operations.yml), balance
    #       — ни в пути, ни в operationId нет ни одного платёжного существительного
    #       (vetoes.domain_nouns в rules/operations.yml)) — проверьте, нужна ли она интеграции
    # @param operation [Object]
    # @return [Object]
    def dispute_fetch(operation)
      url = "#{BASE_URL}/dispute/#{operation.provider_operation_key}"
      response = client.get(url, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 200

      body
    end

    # Операция dispute_update (роль unmapped, эвристика 0.00) не отображена на контракт BaseService:
    # отдельный публичный метод.
    # TODO: роль операции не распознана (ни одна роль не прошла отсечку формы: create_payout 1.0,
    #       create_deposit 1.0, webhook 1.0 из 4.0 поданных голосов; отсечены по форме: fetch_status
    #       — ни в пути, ни в operationId нет ни одного платёжного существительного
    #       (vetoes.domain_nouns в rules/operations.yml)) — проверьте, нужна ли она интеграции
    # @param operation [Object]
    # @return [Object]
    def dispute_update(operation)
      payload = build_dispute_update_payload(operation)
      url = "#{BASE_URL}/dispute/#{operation.provider_operation_key}"
      response = client.put(url, payload, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 200

      body
    end

    # Операция dispute_uploadUrl (роль unmapped, эвристика 0.00) не отображена на контракт
    # BaseService: отдельный публичный метод.
    # TODO: роль операции не распознана (ни один сигнал не совпал ни с одной ролью) — проверьте,
    #       нужна ли она интеграции
    # @param operation [Object]
    # @return [Object]
    def dispute_upload_url(operation)
      url = "#{BASE_URL}/dispute/#{operation.provider_operation_key}/upload_url"
      response = client.get(url, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 200

      body
    end

    # Операция dispute_download (роль unmapped, эвристика 0.00) не отображена на контракт
    # BaseService: отдельный публичный метод.
    # TODO: роль операции не распознана (ни один сигнал не совпал ни с одной ролью) — проверьте,
    #       нужна ли она интеграции
    # @return [Object]
    def dispute_download
      url = "#{BASE_URL}/dispute/export"
      response = client.get(url, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 200

      body
    end

    # Операция dispute_transaction (роль fetch_status, эвристика 0.81) не отображена на контракт
    # BaseService: отдельный публичный метод.
    # TODO: метод контракта уже занят операцией transfer_fetch; эта операция той же роли осталась
    #       снаружи — решите, нужна ли она интеграции
    # @param operation [Object]
    # @return [Object]
    def dispute_transaction(operation)
      url = "#{BASE_URL}/dispute/transaction/#{operation.provider_operation_key}"
      response = client.get(url, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 200

      body
    end

    # Операция dispute_resolve (роль unmapped, эвристика 0.00) не отображена на контракт
    # BaseService: отдельный публичный метод.
    # TODO: роль операции не распознана (ни один сигнал не совпал ни с одной ролью) — проверьте,
    #       нужна ли она интеграции
    # @param operation [Object]
    # @return [Object]
    def dispute_resolve(operation)
      payload = build_dispute_resolve_payload(operation)
      url = "#{BASE_URL}/dispute/#{operation.provider_operation_key}/resolve"
      response = client.put(url, payload, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 200

      body
    end

    # Операция dispute_evidence (роль unmapped, эвристика 0.00) не отображена на контракт
    # BaseService: отдельный публичный метод.
    # TODO: роль операции не распознана (ни один сигнал не совпал ни с одной ролью) — проверьте,
    #       нужна ли она интеграции
    # @param operation [Object]
    # @return [Object]
    def dispute_evidence(operation)
      payload = build_dispute_evidence_payload(operation)
      url = "#{BASE_URL}/dispute/#{operation.provider_operation_key}/evidence"
      response = client.post(url, payload, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 201

      body
    end

    # Операция verification_bvnMatch (роль unmapped, эвристика 0.00) не отображена на контракт
    # BaseService: отдельный публичный метод.
    # TODO: роль операции не распознана (ни один сигнал не совпал ни с одной ролью) — проверьте,
    #       нужна ли она интеграции
    # @param operation [Object]
    # @return [Object]
    def verification_bvn_match(operation)
      payload = build_verification_bvn_match_payload(operation)
      url = "#{BASE_URL}/bvn/match"
      response = client.post(url, payload, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 201

      body
    end

    # Операция verification_resolveBvn (роль unmapped, эвристика 0.00) не отображена на контракт
    # BaseService: отдельный публичный метод.
    # TODO: роль операции не распознана (ни одна роль не прошла отсечку формы: balance 3.0, cancel
    #       1.0 из 6.0 поданных голосов; отсечены по форме: fetch_status — ни в пути, ни в
    #       operationId нет ни одного платёжного существительного (vetoes.domain_nouns в
    #       rules/operations.yml)) — проверьте, нужна ли она интеграции
    # @param operation [Object]
    # @return [Object]
    def verification_resolve_bvn(operation)
      # TODO: параметр пути {bvn} без роли — подставлен operation.provider_operation_key; задайте
      #       x-specgen-role в overlay
      url = "#{BASE_URL}/bank/resolve_bvn/#{operation.provider_operation_key}"
      response = client.get(url, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 200

      body
    end

    # Операция verification_resolveAccountNumber (роль balance, эвристика 0.69) не отображена на
    # контракт BaseService: отдельный публичный метод.
    # @return [Object]
    def verification_resolve_account_number
      url = "#{BASE_URL}/bank/resolve"
      response = client.get(url, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 200

      body
    end

    # Операция verification_resolveCardBin (роль unmapped, эвристика 0.00) не отображена на контракт
    # BaseService: отдельный публичный метод.
    # TODO: роль операции не распознана (ни одна роль не прошла отсечку формы: balance 3.0, cancel
    #       1.0 из 6.0 поданных голосов; отсечены по форме: fetch_status — ни в пути, ни в
    #       operationId нет ни одного платёжного существительного (vetoes.domain_nouns в
    #       rules/operations.yml)) — проверьте, нужна ли она интеграции
    # @param operation [Object]
    # @return [Object]
    def verification_resolve_card_bin(operation)
      # TODO: параметр пути {bin} без роли — подставлен operation.provider_operation_key; задайте
      #       x-specgen-role в overlay
      url = "#{BASE_URL}/decision/bin/#{operation.provider_operation_key}"
      response = client.get(url, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 200

      body
    end

    # Операция verification_listCountries (роль unmapped, эвристика 0.00) не отображена на контракт
    # BaseService: отдельный публичный метод.
    # TODO: роль операции не распознана (ни один сигнал не совпал ни с одной ролью) — проверьте,
    #       нужна ли она интеграции
    # @return [Object]
    def verification_list_countries
      url = "#{BASE_URL}/country"
      response = client.get(url, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 200

      body
    end

    # Операция verification_fetchBanks (роль unmapped, эвристика 0.00) не отображена на контракт
    # BaseService: отдельный публичный метод.
    # TODO: роль операции не распознана (ни одна роль не прошла отсечку формы: cancel 1.0 из 8.0
    #       поданных голосов; отсечены по форме: fetch_status — ни в пути, ни в operationId нет ни
    #       одного платёжного существительного (vetoes.domain_nouns в rules/operations.yml), balance
    #       — ни в пути, ни в operationId нет ни одного платёжного существительного
    #       (vetoes.domain_nouns в rules/operations.yml)) — проверьте, нужна ли она интеграции
    # @return [Object]
    def verification_fetch_banks
      url = "#{BASE_URL}/bank"
      response = client.get(url, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 200

      body
    end

    # Операция verification_avs (роль unmapped, эвристика 0.00) не отображена на контракт
    # BaseService: отдельный публичный метод.
    # TODO: роль операции не распознана (ни один сигнал не совпал ни с одной ролью) — проверьте,
    #       нужна ли она интеграции
    # @return [Object]
    def verification_avs
      url = "#{BASE_URL}/address_verification/states"
      response = client.get(url, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 200

      body
    end

    private

    # Тело запроса по ролям полей схемы transfer_initiate.requestBody; nil-значения убираются.
    def build_payload(operation)
      payload = {
        # TODO: роль поля не определена. Обязательно по спецификации.
        #   тип: string
        #   описание из спецификации: "Where should we transfer from? Only balance is allowed for
        #   now"
        #   обоснование: роль currency отдана `currency` (0.90);
        #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
        #   rules/roles.yml
        source: nil,
        amount: to_provider_units(operation.amount),
        # TODO: роль recipient_type выведена, но выражения платформы для неё нет. Обязательно по
        #       спецификации.
        #   тип: string
        #   описание из спецификации: "The transfer recipient's code"
        #   где это лежит у платформы, знает только человек: заполните вручную или добавьте
        #   выражение в rules/contract.yml (раздел platform)
        recipient: nil,
        # роль provider_operation_id выведена с уверенностью ниже порога (эвристика 0.50):
        # композитное сопоставление: name 2.0 (общие токены с синонимом `acquirer_reference`:
        # reference (50%)), structure 4.0 (родитель `transfer_initiate.requestBody` содержит токен
        # `transfer` из подсказок роли), type 1.0 (type string допустим для роли) = 7.0 из 14.0;
        # следующая external_id 0.21 — проверьте по report.md
        reference: operation.provider_operation_key
      }
      compact_payload(payload)
    end

    # Тело запроса операции transaction_initialize по ролям полей схемы
    # transaction_initialize.requestBody; nil-значения убираются.
    def build_transaction_initialize_payload(operation)
      payload = {
        # TODO: роль поля не определена. Обязательно по спецификации.
        #   тип: string
        #   описание из спецификации: "Customer's email address"
        #   обоснование: ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml
        #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
        #   rules/roles.yml
        email: nil,
        amount: to_provider_units(operation.amount),
        # роль provider_operation_id выведена с уверенностью ниже порога (эвристика 0.50):
        # композитное сопоставление: name 2.0 (общие токены с синонимом `acquirer_reference`:
        # reference (50%)), structure 4.0 (родитель `transaction_initialize.requestBody` содержит
        # токен `transaction` из подсказок роли), type 1.0 (type string допустим для роли) = 7.0 из
        # 14.0; следующая external_id 0.21 — проверьте по report.md
        reference: operation.provider_operation_key
      }
      compact_payload(payload)
    end

    # Тело запроса операции transaction_chargeAuthorization по ролям полей схемы
    # transaction_chargeAuthorization.requestBody; nil-значения убираются.
    def build_transaction_charge_authorization_payload(operation)
      payload = {
        # TODO: роль поля не определена. Обязательно по спецификации.
        #   тип: string
        #   описание из спецификации: "Customer's email address"
        #   обоснование: ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml
        #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
        #   rules/roles.yml
        email: nil,
        amount: to_provider_units(operation.amount),
        # TODO: роль поля не определена. Обязательно по спецификации.
        #   тип: string
        #   описание из спецификации: "Valid authorization code to charge"
        #   обоснование: ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml
        #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
        #   rules/roles.yml
        authorization_code: nil,
        # роль provider_operation_id выведена с уверенностью ниже порога (эвристика 0.50):
        # композитное сопоставление: name 2.0 (общие токены с синонимом `acquirer_reference`:
        # reference (50%)), structure 4.0 (родитель `transaction_chargeAuthorization.requestBody`
        # содержит токен `transaction` из подсказок роли), type 1.0 (type string допустим для роли)
        # = 7.0 из 14.0; следующая external_id 0.21 — проверьте по report.md
        reference: operation.provider_operation_key
      }
      compact_payload(payload)
    end

    # Тело запроса операции transaction_checkAuthorization по ролям полей схемы
    # transaction_checkAuthorization.requestBody; nil-значения убираются.
    def build_transaction_check_authorization_payload(operation)
      payload = {
        # TODO: роль поля не определена. Обязательно по спецификации.
        #   тип: string
        #   описание из спецификации: "Customer's email address"
        #   обоснование: ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml
        #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
        #   rules/roles.yml
        email: nil,
        amount: to_provider_units(operation.amount)
      }
      compact_payload(payload)
    end

    # Тело запроса операции transaction_partialDebit по ролям полей схемы
    # transaction_partialDebit.requestBody; nil-значения убираются.
    def build_transaction_partial_debit_payload(operation)
      payload = {
        # TODO: роль поля не определена. Обязательно по спецификации.
        #   тип: string
        #   описание из спецификации: "Customer's email address"
        #   обоснование: ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml
        #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
        #   rules/roles.yml
        email: nil,
        amount: to_provider_units(operation.amount),
        # TODO: роль поля не определена. Обязательно по спецификации.
        #   тип: string
        #   описание из спецификации: "Valid authorization code to charge"
        #   обоснование: ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml
        #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
        #   rules/roles.yml
        authorization_code: nil,
        # TODO: роль currency выведена, но выражения платформы для неё нет. Обязательно по
        #       спецификации.
        #   тип: string, enum: NGN, GHS, ZAR, USD
        #   описание из спецификации: "The transaction currency"
        #   где это лежит у платформы, знает только человек: заполните вручную или добавьте
        #   выражение в rules/contract.yml (раздел platform)
        currency: nil,
        # роль provider_operation_id выведена с уверенностью ниже порога (эвристика 0.50):
        # композитное сопоставление: name 2.0 (общие токены с синонимом `acquirer_reference`:
        # reference (50%)), structure 4.0 (родитель `transaction_partialDebit.requestBody` содержит
        # токен `transaction` из подсказок роли), type 1.0 (type string допустим для роли) = 7.0 из
        # 14.0; следующая external_id 0.21 — проверьте по report.md
        reference: operation.provider_operation_key
      }
      compact_payload(payload)
    end

    # Тело запроса операции split_create по ролям полей схемы split_create.requestBody; nil-значения
    # убираются.
    def build_split_create_payload(_operation)
      payload = {
        # TODO: роль поля не определена. Обязательно по спецификации.
        #   тип: string
        #   описание из спецификации: "Name of the transaction split"
        #   обоснование: ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml
        #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
        #   rules/roles.yml
        name: nil,
        # TODO: роль recipient_type выведена, но выражения платформы для неё нет. Обязательно по
        #       спецификации.
        #   тип: string, enum: percentage, flat
        #   описание из спецификации: "The type of transaction split you want to create."
        #   где это лежит у платформы, знает только человек: заполните вручную или добавьте
        #   выражение в rules/contract.yml (раздел platform)
        type: nil,
        # TODO: массив (элементы: schema) — по ролям не собирается, заполните вручную
        subaccounts: [],
        # TODO: роль currency выведена, но выражения платформы для неё нет. Обязательно по
        #       спецификации.
        #   тип: string, enum: NGN, GHS, ZAR, USD
        #   описание из спецификации: "The transaction currency"
        #   где это лежит у платформы, знает только человек: заполните вручную или добавьте
        #   выражение в rules/contract.yml (раздел platform)
        currency: nil
      }
      compact_payload(payload)
    end

    # Тело запроса операции split_update по ролям полей схемы split_update.requestBody; nil-значения
    # убираются.
    def build_split_update_payload(_operation)
      payload = {}
      compact_payload(payload)
    end

    # Тело запроса операции split_addSubaccount по ролям полей схемы
    # split_addSubaccount.requestBody; nil-значения убираются.
    def build_split_add_subaccount_payload(_operation)
      payload = {}
      compact_payload(payload)
    end

    # Тело запроса операции split_removeSubaccount по ролям полей схемы schema; nil-значения
    # убираются.
    def build_split_remove_subaccount_payload(operation)
      payload = {
        status: operation.status
      }
      compact_payload(payload)
    end

    # Тело запроса операции customer_create по ролям полей схемы customer_create.requestBody;
    # nil-значения убираются.
    def build_customer_create_payload(_operation)
      payload = {
        # TODO: роль поля не определена. Обязательно по спецификации.
        #   тип: string
        #   описание из спецификации: "Customer's email address"
        #   обоснование: ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml
        #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
        #   rules/roles.yml
        email: nil
      }
      compact_payload(payload)
    end

    # Тело запроса операции customer_update по ролям полей схемы 1; nil-значения убираются.
    def build_customer_update_payload(_operation)
      payload = {}
      compact_payload(payload)
    end

    # Тело запроса операции customer_riskAction по ролям полей схемы 3; nil-значения убираются.
    def build_customer_risk_action_payload(operation)
      payload = {
        # роль external_id выведена с уверенностью ниже порога (эвристика 0.21): композитное
        # сопоставление: name 2.0 (общие токены с синонимом `customer_reference`: customer (50%)),
        # type 1.0 (type string допустим для роли) = 3.0 из 14.0; следующая recipient_phone 0.21 —
        # проверьте по report.md
        customer: operation.id
      }
      compact_payload(payload)
    end

    # Тело запроса операции customer_deactivateAuthorization по ролям полей схемы 2; nil-значения
    # убираются.
    def build_customer_deactivate_authorization_payload(_operation)
      payload = {
        # TODO: роль поля не определена. Обязательно по спецификации.
        #   тип: string
        #   описание из спецификации: "Customer's authorization code to be deactivated"
        #   обоснование: ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml
        #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
        #   rules/roles.yml
        authorization_code: nil
      }
      compact_payload(payload)
    end

    # Тело запроса операции customer_validatte по ролям полей схемы 4; nil-значения убираются.
    def build_customer_validatte_payload(operation)
      payload = {
        # TODO: роль recipient_type выведена, но выражения платформы для неё нет. Обязательно по
        #       спецификации.
        #   тип: string, enum: bvn, bank_account
        #   описание из спецификации: "Predefined types of identification."
        #   где это лежит у платформы, знает только человек: заполните вручную или добавьте
        #   выражение в rules/contract.yml (раздел platform)
        type: nil,
        # TODO: роль поля не определена. Обязательно по спецификации.
        #   тип: string
        #   описание из спецификации: "Two-letter country code of identification issuer"
        #   обоснование: ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml
        #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
        #   rules/roles.yml
        country: nil,
        # TODO: роль поля не определена. Обязательно по спецификации.
        #   тип: string
        #   описание из спецификации: "Customer's Bank Verification Number"
        #   обоснование: ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml
        #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
        #   rules/roles.yml
        bvn: nil,
        # TODO: роль bank_code выведена, но выражения платформы для неё нет. Обязательно по
        #       спецификации.
        #   тип: string
        #   описание из спецификации: "You can get the list of bank codes by calling the List Banks
        #   endpoint (https://api.paystack.co/bank)."
        #   где это лежит у платформы, знает только человек: заполните вручную или добавьте
        #   выражение в rules/contract.yml (раздел platform)
        bank_code: nil,
        # TODO: роль поля не определена. Обязательно по спецификации.
        #   тип: string
        #   описание из спецификации: "Customer's bank account number."
        #   обоснование: ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml
        #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
        #   rules/roles.yml
        account_number: nil,
        # обязательно при type = bvn (намёк в описании 0.50)
        value: to_provider_units(operation.amount)
      }
      compact_payload(payload)
    end

    # Тело запроса операции dedicatedAccount_create по ролям полей схемы
    # dedicatedAccount_create.requestBody; nil-значения убираются.
    def build_dedicated_account_create_payload(operation)
      payload = {
        # роль external_id выведена с уверенностью ниже порога (эвристика 0.21): композитное
        # сопоставление: name 2.0 (общие токены с синонимом `customer_reference`: customer (50%)),
        # type 1.0 (type string допустим для роли) = 3.0 из 14.0; следующая recipient_phone 0.21 —
        # проверьте по report.md
        customer: operation.id
      }
      compact_payload(payload)
    end

    # Тело запроса операции dedicatedAccount_addSplit по ролям полей схемы
    # dedicatedAccount_addSplit.requestBody; nil-значения убираются.
    def build_dedicated_account_add_split_payload(_operation)
      payload = {
        # TODO: роль поля не определена. Обязательно по спецификации.
        #   тип: string
        #   описание из спецификации: "Valid Dedicated virtual account"
        #   обоснование: ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml
        #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
        #   rules/roles.yml
        account_number: nil
      }
      compact_payload(payload)
    end

    # Тело запроса операции subaccount_create по ролям полей схемы subaccount_create.requestBody;
    # nil-значения убираются.
    def build_subaccount_create_payload(_operation)
      payload = {
        # TODO: роль поля не определена. Обязательно по спецификации.
        #   тип: string
        #   описание из спецификации: "Name of business for subaccount"
        #   обоснование: ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml
        #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
        #   rules/roles.yml
        business_name: nil,
        # TODO: роль bank_name выведена, но выражения платформы для неё нет. Обязательно по
        #       спецификации.
        #   тип: string
        #   описание из спецификации: "Bank code for the bank. You can get the list of Bank Codes by
        #   calling the List Banks endpoint."
        #   где это лежит у платформы, знает только человек: заполните вручную или добавьте
        #   выражение в rules/contract.yml (раздел platform)
        settlement_bank: nil,
        # TODO: роль поля не определена. Обязательно по спецификации.
        #   тип: string
        #   описание из спецификации: "Bank account number"
        #   обоснование: ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml
        #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
        #   rules/roles.yml
        account_number: nil,
        # TODO: роль поля не определена. Обязательно по спецификации.
        #   тип: number float
        #   описание из спецификации: "Customer's phone number"
        #   обоснование: ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml
        #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
        #   rules/roles.yml
        percentage_charge: nil
      }
      compact_payload(payload)
    end

    # Тело запроса операции subaccount_update по ролям полей схемы subaccount_update.requestBody;
    # nil-значения убираются.
    def build_subaccount_update_payload(_operation)
      payload = {}
      compact_payload(payload)
    end

    # Тело запроса операции plan_create по ролям полей схемы plan_create.requestBody; nil-значения
    # убираются.
    def build_plan_create_payload(operation)
      payload = {
        # TODO: роль поля не определена. Обязательно по спецификации.
        #   тип: string
        #   описание из спецификации: "Name of plan"
        #   обоснование: ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml
        #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
        #   rules/roles.yml
        name: nil,
        amount: to_provider_units(operation.amount),
        # TODO: роль поля не определена. Обязательно по спецификации.
        #   тип: string
        #   описание из спецификации: "Interval in words. Valid intervals are daily, weekly,
        #   monthly,biannually, annually"
        #   обоснование: ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml
        #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
        #   rules/roles.yml
        interval: nil
      }
      compact_payload(payload)
    end

    # Тело запроса операции plan_update по ролям полей схемы plan_update.requestBody; nil-значения
    # убираются.
    def build_plan_update_payload(operation)
      payload = {
        amount: to_provider_units(operation.amount)
      }
      compact_payload(payload)
    end

    # Тело запроса операции subscription_create по ролям полей схемы
    # subscription_create.requestBody; nil-значения убираются.
    def build_subscription_create_payload(operation)
      payload = {
        # роль external_id выведена с уверенностью ниже порога (эвристика 0.21): композитное
        # сопоставление: name 2.0 (общие токены с синонимом `customer_reference`: customer (50%)),
        # type 1.0 (type string допустим для роли) = 3.0 из 14.0; следующая recipient_phone 0.21 —
        # проверьте по report.md
        customer: operation.id,
        # TODO: роль поля не определена. Обязательно по спецификации.
        #   тип: string
        #   описание из спецификации: "Plan code"
        #   обоснование: ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml
        #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
        #   rules/roles.yml
        plan: nil
      }
      compact_payload(payload)
    end

    # Тело запроса операции subscription_disable по ролям полей схемы schema; nil-значения
    # убираются.
    def build_subscription_disable_payload(operation)
      payload = {
        status: operation.status
      }
      compact_payload(payload)
    end

    # Тело запроса операции subscription_enable по ролям полей схемы
    # subscription_enable.requestBody; nil-значения убираются.
    def build_subscription_enable_payload(operation)
      payload = {
        # TODO: роль поля не определена. Обязательно по спецификации.
        #   тип: string
        #   описание из спецификации: "Subscription code"
        #   обоснование: ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml
        #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
        #   rules/roles.yml
        code: nil,
        # роль idempotency_key выведена с уверенностью ниже порога (эвристика 0.21): композитное
        # сопоставление: name 2.0 (общие токены с синонимом `idempotency_token`: token (50%)), type
        # 1.0 (type string допустим для роли) = 3.0 из 14.0; других кандидатов нет — проверьте по
        # report.md
        token: idempotency_key_for(operation)
      }
      compact_payload(payload)
    end

    # Тело запроса операции product_create по ролям полей схемы product_create.requestBody;
    # nil-значения убираются.
    def build_product_create_payload(operation)
      payload = {
        # TODO: роль поля не определена. Обязательно по спецификации.
        #   тип: string
        #   описание из спецификации: "Name of product"
        #   обоснование: ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml
        #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
        #   rules/roles.yml
        name: nil,
        # TODO: роль поля не определена. Обязательно по спецификации.
        #   тип: string
        #   описание из спецификации: "The description of the product"
        #   обоснование: ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml
        #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
        #   rules/roles.yml
        description: nil,
        price: to_provider_units(operation.amount),
        # TODO: роль currency выведена, но выражения платформы для неё нет. Обязательно по
        #       спецификации.
        #   тип: string
        #   описание из спецификации: "Currency in which price is set. Allowed values are: NGN, GHS,
        #   ZAR or USD"
        #   где это лежит у платформы, знает только человек: заполните вручную или добавьте
        #   выражение в rules/contract.yml (раздел platform)
        currency: nil
      }
      compact_payload(payload)
    end

    # Тело запроса операции product_update по ролям полей схемы product_update.requestBody;
    # nil-значения убираются.
    def build_product_update_payload(operation)
      payload = {
        price: to_provider_units(operation.amount)
      }
      compact_payload(payload)
    end

    # Тело запроса операции page_create по ролям полей схемы page_create.requestBody; nil-значения
    # убираются.
    def build_page_create_payload(operation)
      payload = {
        # TODO: роль поля не определена. Обязательно по спецификации.
        #   тип: string
        #   описание из спецификации: "Name of page"
        #   обоснование: ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml
        #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
        #   rules/roles.yml
        name: nil,
        amount: to_provider_units(operation.amount)
      }
      compact_payload(payload)
    end

    # Тело запроса операции page_update по ролям полей схемы page_update.requestBody; nil-значения
    # убираются.
    def build_page_update_payload(operation)
      payload = {
        amount: to_provider_units(operation.amount)
      }
      compact_payload(payload)
    end

    # Тело запроса операции page_addProducts по ролям полей схемы page_addProducts.requestBody;
    # nil-значения убираются.
    def build_page_add_products_payload(_operation)
      payload = {
        # TODO: массив (элементы: array) — по ролям не собирается, заполните вручную
        product: []
      }
      compact_payload(payload)
    end

    # Тело запроса операции paymentRequest_create по ролям полей схемы
    # paymentRequest_create.requestBody; nil-значения убираются.
    def build_payment_request_create_payload(operation)
      payload = {
        # TODO: роль recipient_phone выведена, но выражения платформы для неё нет. Обязательно по
        #       спецификации.
        #   тип: string
        #   описание из спецификации: "Customer id or code"
        #   где это лежит у платформы, знает только человек: заполните вручную или добавьте
        #   выражение в rules/contract.yml (раздел platform)
        customer: nil,
        amount: to_provider_units(operation.amount),
        invoice_number: operation.id
      }
      compact_payload(payload)
    end

    # Тело запроса операции paymentRequest_update по ролям полей схемы
    # paymentRequest_update.requestBody; nil-значения убираются.
    def build_payment_request_update_payload(operation)
      payload = {
        amount: to_provider_units(operation.amount),
        invoice_number: operation.id
      }
      compact_payload(payload)
    end

    # Тело запроса операции transferrecipient_create по ролям полей схемы
    # transferrecipient_create.requestBody; nil-значения убираются.
    def build_transferrecipient_create_payload(_operation)
      payload = {
        # TODO: роль recipient_type выведена, но выражения платформы для неё нет. Обязательно по
        #       спецификации.
        #   тип: string
        #   описание из спецификации: "Recipient Type (Only nuban at this time)"
        #   где это лежит у платформы, знает только человек: заполните вручную или добавьте
        #   выражение в rules/contract.yml (раздел platform)
        type: nil,
        # TODO: роль поля не определена. Обязательно по спецификации.
        #   тип: string
        #   описание из спецификации: "Recipient's name"
        #   обоснование: ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml
        #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
        #   rules/roles.yml
        name: nil,
        # TODO: роль поля не определена. Обязательно по спецификации.
        #   тип: string
        #   описание из спецификации: "Recipient's bank account number"
        #   обоснование: ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml
        #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
        #   rules/roles.yml
        account_number: nil,
        # TODO: роль bank_code выведена, но выражения платформы для неё нет. Обязательно по
        #       спецификации.
        #   тип: string
        #   описание из спецификации: "Recipient's bank code. You can get the list of Bank Codes by
        #   calling the List Banks endpoint"
        #   где это лежит у платформы, знает только человек: заполните вручную или добавьте
        #   выражение в rules/contract.yml (раздел platform)
        bank_code: nil
      }
      compact_payload(payload)
    end

    # Тело запроса операции transferrecipient_bulk по ролям полей схемы
    # transferrecipient_bulk.requestBody; nil-значения убираются.
    def build_transferrecipient_bulk_payload(_operation)
      payload = {
        # TODO: массив (элементы: schema) — по ролям не собирается, заполните вручную
        batch: []
      }
      compact_payload(payload)
    end

    # Тело запроса операции put_transferrecipient_code по ролям полей схемы
    # put_transferrecipient_code.requestBody; nil-значения убираются.
    def build_put_transferrecipient_code_payload(_operation)
      payload = {}
      compact_payload(payload)
    end

    # Тело запроса операции transfer_finalize по ролям полей схемы transfer_finalize.requestBody;
    # nil-значения убираются.
    def build_transfer_finalize_payload(operation)
      payload = {
        transfer_code: operation.provider_operation_key,
        # TODO: роль поля не определена. Обязательно по спецификации.
        #   тип: string
        #   описание из спецификации: "OTP sent to business phone to verify transfer"
        #   обоснование: ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml
        #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
        #   rules/roles.yml
        otp: nil
      }
      compact_payload(payload)
    end

    # Тело запроса операции transfer_bulk по ролям полей схемы transfer_bulk.requestBody;
    # nil-значения убираются.
    def build_transfer_bulk_payload(operation)
      payload = {
        # роль amount выведена с уверенностью ниже порога (эвристика 0.50): композитное
        # сопоставление: name 2.0 (общие токены с синонимом `source_amount`: source (50%)),
        # structure 4.0 (родитель `transfer_bulk.requestBody` содержит токен `transfer` из подсказок
        # роли), type 1.0 (type string допустим для роли) = 7.0 из 14.0; следующая currency 0.50 —
        # проверьте по report.md
        source: to_provider_units(operation.amount)
      }
      compact_payload(payload)
    end

    # Тело запроса операции transfer_resendOtp по ролям полей схемы transfer_resendOtp.requestBody;
    # nil-значения убираются.
    def build_transfer_resend_otp_payload(operation)
      payload = {
        transfer_code: operation.provider_operation_key,
        # TODO: роль поля не определена. Обязательно по спецификации.
        #   тип: string
        #   описание из спецификации: "Either resend_otp or transfer"
        #   обоснование: ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml
        #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
        #   rules/roles.yml
        reason: nil
      }
      compact_payload(payload)
    end

    # Тело запроса операции transfer_disableOtpFinalize по ролям полей схемы
    # transfer_disableOtpFinalize.requestBody; nil-значения убираются.
    def build_transfer_disable_otp_finalize_payload(_operation)
      payload = {
        # TODO: роль поля не определена. Обязательно по спецификации.
        #   тип: string
        #   описание из спецификации: "OTP sent to business phone to verify disabling OTP
        #   requirement"
        #   обоснование: ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml
        #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
        #   rules/roles.yml
        otp: nil
      }
      compact_payload(payload)
    end

    # Тело запроса операции charge_create по ролям полей схемы charge_create.requestBody;
    # nil-значения убираются.
    def build_charge_create_payload(operation)
      payload = {
        # TODO: роль поля не определена. Обязательно по спецификации.
        #   тип: string
        #   описание из спецификации: "Customer's email address"
        #   обоснование: ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml
        #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
        #   rules/roles.yml
        email: nil,
        amount: to_provider_units(operation.amount),
        # роль external_id выведена с уверенностью ниже порога (эвристика 0.21): композитное
        # сопоставление: name 2.0 (общие токены с синонимом `client_reference`: reference (50%)),
        # type 1.0 (type string допустим для роли) = 3.0 из 14.0; следующая provider_operation_id
        # 0.21 — проверьте по report.md
        reference: operation.id
      }
      compact_payload(payload)
    end

    # Тело запроса операции charge_submitPin по ролям полей схемы charge_submitPin.requestBody;
    # nil-значения убираются.
    def build_charge_submit_pin_payload(operation)
      payload = {
        # TODO: роль поля не определена. Обязательно по спецификации.
        #   тип: string
        #   описание из спецификации: "Customer's PIN"
        #   обоснование: ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml
        #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
        #   rules/roles.yml
        pin: nil,
        # роль external_id выведена с уверенностью ниже порога (эвристика 0.21): композитное
        # сопоставление: name 2.0 (общие токены с синонимом `client_reference`: reference (50%)),
        # type 1.0 (type string допустим для роли) = 3.0 из 14.0; следующая provider_operation_id
        # 0.21 — проверьте по report.md
        reference: operation.id
      }
      compact_payload(payload)
    end

    # Тело запроса операции charge_submitOtp по ролям полей схемы charge_submitOtp.requestBody;
    # nil-значения убираются.
    def build_charge_submit_otp_payload(operation)
      payload = {
        # TODO: роль поля не определена. Обязательно по спецификации.
        #   тип: string
        #   описание из спецификации: "Customer's OTP"
        #   обоснование: ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml
        #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
        #   rules/roles.yml
        otp: nil,
        # роль external_id выведена с уверенностью ниже порога (эвристика 0.21): композитное
        # сопоставление: name 2.0 (общие токены с синонимом `client_reference`: reference (50%)),
        # type 1.0 (type string допустим для роли) = 3.0 из 14.0; следующая provider_operation_id
        # 0.21 — проверьте по report.md
        reference: operation.id
      }
      compact_payload(payload)
    end

    # Тело запроса операции charge_submitPhone по ролям полей схемы charge_submitPhone.requestBody;
    # nil-значения убираются.
    def build_charge_submit_phone_payload(operation)
      payload = {
        # TODO: роль recipient_phone выведена, но выражения платформы для неё нет. Обязательно по
        #       спецификации.
        #   тип: string
        #   описание из спецификации: "Customer's mobile number"
        #   где это лежит у платформы, знает только человек: заполните вручную или добавьте
        #   выражение в rules/contract.yml (раздел platform)
        phone: nil,
        # роль external_id выведена с уверенностью ниже порога (эвристика 0.21): композитное
        # сопоставление: name 2.0 (общие токены с синонимом `client_reference`: reference (50%)),
        # type 1.0 (type string допустим для роли) = 3.0 из 14.0; следующая provider_operation_id
        # 0.21 — проверьте по report.md
        reference: operation.id
      }
      compact_payload(payload)
    end

    # Тело запроса операции charge_submitBirthday по ролям полей схемы
    # charge_submitBirthday.requestBody; nil-значения убираются.
    def build_charge_submit_birthday_payload(operation)
      payload = {
        # TODO: роль поля не определена. Обязательно по спецификации.
        #   тип: string
        #   описание из спецификации: "Customer's birthday in the format YYYY-MM-DD e.g 2016-09-21"
        #   обоснование: ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml
        #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
        #   rules/roles.yml
        birthday: nil,
        # роль external_id выведена с уверенностью ниже порога (эвристика 0.21): композитное
        # сопоставление: name 2.0 (общие токены с синонимом `client_reference`: reference (50%)),
        # type 1.0 (type string допустим для роли) = 3.0 из 14.0; следующая provider_operation_id
        # 0.21 — проверьте по report.md
        reference: operation.id
      }
      compact_payload(payload)
    end

    # Тело запроса операции charge_submitAddress по ролям полей схемы
    # charge_submitAddress.requestBody; nil-значения убираются.
    def build_charge_submit_address_payload(operation)
      payload = {
        # TODO: роль поля не определена. Обязательно по спецификации.
        #   тип: string
        #   описание из спецификации: "Customer's address"
        #   обоснование: ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml
        #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
        #   rules/roles.yml
        address: nil,
        # TODO: роль поля не определена. Обязательно по спецификации.
        #   тип: string
        #   описание из спецификации: "Customer's city"
        #   обоснование: ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml
        #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
        #   rules/roles.yml
        city: nil,
        # роль status выведена с уверенностью ниже порога (эвристика 0.36): композитное
        # сопоставление: name 4.0 (общие токены с синонимом `state`: state (100%)), type 1.0 (type
        # string допустим для роли) = 5.0 из 14.0; других кандидатов нет — проверьте по report.md
        state: operation.status,
        # TODO: роль поля не определена. Обязательно по спецификации.
        #   тип: string
        #   описание из спецификации: "Customer's zipcode"
        #   обоснование: ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml
        #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
        #   rules/roles.yml
        zipcode: nil,
        # роль external_id выведена с уверенностью ниже порога (эвристика 0.21): композитное
        # сопоставление: name 2.0 (общие токены с синонимом `client_reference`: reference (50%)),
        # type 1.0 (type string допустим для роли) = 3.0 из 14.0; следующая provider_operation_id
        # 0.21 — проверьте по report.md
        reference: operation.id
      }
      compact_payload(payload)
    end

    # Тело запроса операции bulkCharge_initiate по ролям полей схемы
    # bulkCharge_initiate.requestBody; nil-значения убираются.
    def build_bulk_charge_initiate_payload(_operation)
      payload = {}
      compact_payload(payload)
    end

    # Тело запроса операции integration_updatePaymentSessionTimeout по ролям полей схемы
    # integration_updatePaymentSessionTimeout.requestBody; nil-значения убираются.
    def build_integration_update_payment_session_timeout_payload(_operation)
      payload = {
        # TODO: роль поля не определена. Обязательно по спецификации.
        #   тип: string
        #   описание из спецификации: "Time in seconds before a transaction becomes invalid"
        #   обоснование: ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml
        #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
        #   rules/roles.yml
        timeout: nil
      }
      compact_payload(payload)
    end

    # Тело запроса операции refund_create по ролям полей схемы refund_create.requestBody;
    # nil-значения убираются.
    def build_refund_payload(operation)
      payload = {
        # роль provider_operation_id выведена с уверенностью ниже порога (эвристика 0.21): роль
        # currency отдана `currency` (0.90); композитное сопоставление: name 2.0 (общие токены с
        # синонимом `transaction_id`: transaction (50%)), type 1.0 (type string допустим для роли) =
        # 3.0 из 14.0; следующая status 0.21 — проверьте по report.md
        transaction: operation.provider_operation_key,
        amount: to_provider_units(operation.amount)
      }
      compact_payload(payload)
    end

    # Тело запроса операции dispute_update по ролям полей схемы dispute_update.requestBody;
    # nil-значения убираются.
    def build_dispute_update_payload(operation)
      payload = {
        # роль amount выведена с уверенностью ниже порога (эвристика 0.21): композитное
        # сопоставление: name 2.0 (общие токены с синонимом `amount`: amount (50%)), type 1.0 (type
        # string допустим для роли) = 3.0 из 14.0; других кандидатов нет — проверьте по report.md
        refund_amount: to_provider_units(operation.amount)
      }
      compact_payload(payload)
    end

    # Тело запроса операции dispute_resolve по ролям полей схемы dispute_resolve.requestBody;
    # nil-значения убираются.
    def build_dispute_resolve_payload(operation)
      payload = {
        # роль status выведена с уверенностью ниже порога (эвристика 0.21): композитное
        # сопоставление: constraint 2.0 (значения enum читаются как статусы по rules/statuses.yml
        # (50%)), type 1.0 (type string допустим для роли) = 3.0 из 14.0; других кандидатов нет —
        # проверьте по report.md
        resolution: operation.status,
        # TODO: роль error_message выведена, но выражения платформы для неё нет. Обязательно по
        #       спецификации.
        #   тип: string
        #   описание из спецификации: "Reason for resolving"
        #   где это лежит у платформы, знает только человек: заполните вручную или добавьте
        #   выражение в rules/contract.yml (раздел platform)
        message: nil,
        # роль amount выведена с уверенностью ниже порога (эвристика 0.21): композитное
        # сопоставление: name 2.0 (общие токены с синонимом `amount`: amount (50%)), type 1.0 (type
        # string допустим для роли) = 3.0 из 14.0; других кандидатов нет — проверьте по report.md
        refund_amount: to_provider_units(operation.amount),
        # TODO: роль поля не определена. Обязательно по спецификации.
        #   тип: string
        #   описание из спецификации: "Filename of attachment returned via response from the Dispute
        #   upload URL"
        #   обоснование: ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml
        #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
        #   rules/roles.yml
        uploaded_filename: nil
      }
      compact_payload(payload)
    end

    # Тело запроса операции dispute_evidence по ролям полей схемы dispute_evidence.requestBody;
    # nil-значения убираются.
    def build_dispute_evidence_payload(_operation)
      payload = {
        # TODO: роль поля не определена. Обязательно по спецификации.
        #   тип: string
        #   описание из спецификации: "Customer email"
        #   обоснование: ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml
        #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
        #   rules/roles.yml
        customer_email: nil,
        # TODO: роль поля не определена. Обязательно по спецификации.
        #   тип: string
        #   описание из спецификации: "Customer name"
        #   обоснование: ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml
        #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
        #   rules/roles.yml
        customer_name: nil,
        # TODO: роль recipient_phone выведена, но выражения платформы для неё нет. Обязательно по
        #       спецификации.
        #   тип: string
        #   описание из спецификации: "Customer mobile number"
        #   где это лежит у платформы, знает только человек: заполните вручную или добавьте
        #   выражение в rules/contract.yml (раздел platform)
        customer_phone: nil,
        # TODO: роль поля не определена. Обязательно по спецификации.
        #   тип: string
        #   описание из спецификации: "Details of service offered"
        #   обоснование: ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml
        #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
        #   rules/roles.yml
        service_details: nil
      }
      compact_payload(payload)
    end

    # Тело запроса операции verification_bvnMatch по ролям полей схемы
    # verification_bvnMatch.requestBody; nil-значения убираются.
    def build_verification_bvn_match_payload(_operation)
      payload = {
        # TODO: роль поля не определена. Обязательно по спецификации.
        #   тип: string
        #   описание из спецификации: "Bank Account Number"
        #   обоснование: ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml
        #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
        #   rules/roles.yml
        account_number: nil,
        # TODO: роль bank_code выведена, но выражения платформы для неё нет. Обязательно по
        #       спецификации.
        #   тип: integer
        #   описание из спецификации: "You can get the list of banks codes by calling the List Bank
        #   endpoint"
        #   где это лежит у платформы, знает только человек: заполните вручную или добавьте
        #   выражение в rules/contract.yml (раздел platform)
        bank_code: nil,
        # TODO: роль поля не определена. Обязательно по спецификации.
        #   тип: string
        #   описание из спецификации: "11 digits Bank Verification Number"
        #   обоснование: ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml
        #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
        #   rules/roles.yml
        bvn: nil
      }
      compact_payload(payload)
    end

    # Заголовки запроса на создание: авторизация и тип содержимого.
    def request_headers
      auth_headers.merge('Content-Type' => 'application/json')
    end

    # Заголовки авторизации: схема bearerAuth (bearer) по записи rules/auth.yml «bearer». Секрет
    # читается из provider.credentials.
    # @return [Hash]
    def auth_headers
      { 'Authorization' => "Bearer #{provider.credentials[:token]}" }
    end

    # Успешный ответ на создание: перевести статус и вернуть платформе идентификатор операции у
    # провайдера — она сохраняет его как provider_operation_key из result[:id].
    def accept_created(operation, body)
      apply_internal_status(operation, map_status(body['status']))
      # TODO: в успешном ответе нет поля с ролью provider_operation_id — вернуть платформе нечего, и
      #       она не сохранит provider_operation_key; укажите поле через x-specgen-role в overlay
      success
    end

    # Успешный ответ провайдера на отмену или подтверждение: перевести статус, если он пришёл и
    # знаком; незнакомый статус оставляет операцию in_progress. Результата у метода нет — статус
    # меняют хелперы.
    def accept_response(operation, body)
      internal = map_status(body['status'])
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
    def provider_failure(response, _body)
      action = ERROR_MAP[response.status] || DEFAULT_ERROR_ACTION
      failure(platform_failure_code(response.status, action), "errors.http_#{response.status}")
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
