# frozen_string_literal: true

# Сгенерировано инструментом integrate из adyen_payout_v68.yaml, версия спецификации
# 68, OpenAPI 3.1.0. Не редактируйте вручную: правки — в overlay
# (OpenAPI Overlay 1.0.0) и повторная генерация.
#
# Проверка файла:
#   ruby -c output/adyen_payout_v68_service.rb
#   bundle exec rubocop --config config/rubocop_generated.yml output/adyen_payout_v68_service.rb
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
  # Интеграция с провайдером «Adyen Payout API»: предпроверки, создание
  # операции, обработка уведомлений и опрос статуса по контракту
  # Provider::BaseService. Таблицы статусов, ошибок и политики ретраев —
  # замороженные хеши, сверяемые с INTEGRATION.md; TODO отмечают места, где
  # спецификация не дала ответа и инструмент взял лучшего кандидата.
  class AdyenPayoutV68Service < Provider::BaseService
    BASE_URL = ENV.fetch('ADYEN_PAYOUT_V68_BASE_URL', 'https://pal-test.adyen.com/pal/servlet/Payout/v68')
    # Таймауты в секундах; как передать их клиенту платформы, зависит от
    # клиента (его интерфейс — допущение), поэтому здесь только значения.
    OPEN_TIMEOUT = Integer(ENV.fetch('ADYEN_PAYOUT_V68_OPEN_TIMEOUT', '5'))
    READ_TIMEOUT = Integer(ENV.fetch('ADYEN_PAYOUT_V68_READ_TIMEOUT', '15'))
    PROVIDER = 'adyen_payout_v68'
    # TODO: единицы суммы не выведены (без кода валюты экспоненту ISO 4217 определить нельзя);
    #       множитель 1 — задайте x-specgen-amount-unit и x-specgen-exponent в overlay
    AMOUNT_MULTIPLIER = 1
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
      # По коду ошибки провайдера из тела ответа.
      '702' => :reject
    }.freeze

    # Коды, которые у отдельной операции означают не то, что в ERROR_MAP.
    ERROR_MAP_BY_OPERATION = {
      'post-confirmThirdParty' => {
        400 => :reject,
        401 => :alert,
        403 => :alert,
        422 => :reject,
        500 => :retry_backoff
      },
      'post-declineThirdParty' => {
        400 => :reject,
        401 => :alert,
        403 => :alert,
        422 => :reject,
        500 => :retry_backoff
      },
      'post-payout' => {
        400 => :reject,
        401 => :alert,
        403 => :alert,
        422 => :reject,
        500 => :retry_backoff
      },
      'post-storeDetail' => {
        400 => :reject,
        401 => :alert,
        403 => :alert,
        422 => :reject,
        500 => :retry_backoff
      },
      'post-storeDetailAndSubmitThirdParty' => {
        400 => :reject,
        401 => :alert,
        403 => :alert,
        422 => :reject,
        500 => :retry_backoff
      },
      'post-submitThirdParty' => {
        400 => :reject,
        401 => :alert,
        403 => :alert,
        422 => :reject,
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

      # currency: maxLength 3 (задано явно 1.00)
      # TODO: условие для поля currency: у платформы нет выражения для его роли (rules/contract.yml,
      #       раздел platform)
      success
    end

    # Создание операции у провайдера: сборка тела запроса из ролей, перевод суммы в единицы
    # провайдера, заголовки авторизации и идемпотентности, разбор ответа и кодов ошибок.
    # @param operation [Object]
    # @param request_method [Object]
    # @return [Object] success | failure
    def create_request(operation, _request_method = 'create')
      payload = build_payload(operation)
      url = "#{BASE_URL}/payout"
      response = client.post(url, payload, request_headers)
      body = parse_json(response.body)
      return accept_created(operation, body) if response.status == 200

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
    def fetch_status(_operation)
      # TODO: спецификация не описывает операцию опроса статуса (fetch_status) — метод отказывает
      failure(:not_implemented, 'errors.status_not_supported')
    end

    # Операция post-confirmThirdParty (роль confirm, эвристика 0.68) не отображена на контракт
    # BaseService: отдельный публичный метод.
    # @param operation [Object]
    # @return [Object]
    def confirm(operation)
      payload = build_confirm_payload(operation)
      url = "#{BASE_URL}/confirmThirdParty"
      response = client.post(url, payload, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 200

      accept_response(operation, body)
    end

    # Операция post-declineThirdParty (роль unmapped, эвристика 0.00) не отображена на контракт
    # BaseService: отдельный публичный метод.
    # TODO: роль операции не распознана (ни одна роль не прошла отсечку формы: create_payout 3.0,
    #       create_deposit 3.0, webhook 3.0 из 8.0 поданных голосов; отсечены по форме: cancel — ни
    #       в пути, ни в operationId нет ни одного платёжного существительного (vetoes.domain_nouns
    #       в rules/operations.yml)) — проверьте, нужна ли она интеграции
    # @param operation [Object]
    # @return [Object]
    def post_decline_third_party(operation)
      payload = build_post_decline_third_party_payload(operation)
      url = "#{BASE_URL}/declineThirdParty"
      response = client.post(url, payload, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 200

      body
    end

    # Операция post-storeDetail (роль unmapped, эвристика 0.00) не отображена на контракт
    # BaseService: отдельный публичный метод.
    # TODO: роль операции не распознана (ни один сигнал не совпал ни с одной ролью) — проверьте,
    #       нужна ли она интеграции
    # @param operation [Object]
    # @return [Object]
    def post_store_detail(operation)
      payload = build_post_store_detail_payload(operation)
      url = "#{BASE_URL}/storeDetail"
      response = client.post(url, payload, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 200

      body
    end

    # Операция post-storeDetailAndSubmitThirdParty (роль unmapped, эвристика 0.00) не отображена на
    # контракт BaseService: отдельный публичный метод.
    # TODO: роль операции не распознана (ни одна роль не прошла отсечку формы: webhook 3.0, cancel
    #       2.0, confirm 2.0 из 8.0 поданных голосов; отсечены по форме: create_payout — ни в пути,
    #       ни в operationId нет ни одного платёжного существительного (vetoes.domain_nouns в
    #       rules/operations.yml), create_deposit — ни в пути, ни в operationId нет ни одного
    #       платёжного существительного (vetoes.domain_nouns в rules/operations.yml)) — проверьте,
    #       нужна ли она интеграции
    # @param operation [Object]
    # @return [Object]
    def post_store_detail_and_submit_third_party(operation)
      payload = build_post_store_detail_and_submit_third_party_payload(operation)
      url = "#{BASE_URL}/storeDetailAndSubmitThirdParty"
      response = client.post(url, payload, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 200

      body
    end

    # Операция post-submitThirdParty (роль unmapped, эвристика 0.00) не отображена на контракт
    # BaseService: отдельный публичный метод.
    # TODO: роль операции не распознана (ни одна роль не прошла отсечку формы: webhook 3.0, cancel
    #       2.0, confirm 2.0 из 8.0 поданных голосов; отсечены по форме: create_payout — ни в пути,
    #       ни в operationId нет ни одного платёжного существительного (vetoes.domain_nouns в
    #       rules/operations.yml), create_deposit — ни в пути, ни в operationId нет ни одного
    #       платёжного существительного (vetoes.domain_nouns в rules/operations.yml)) — проверьте,
    #       нужна ли она интеграции
    # @param operation [Object]
    # @return [Object]
    def post_submit_third_party(operation)
      payload = build_post_submit_third_party_payload(operation)
      url = "#{BASE_URL}/submitThirdParty"
      response = client.post(url, payload, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 200

      body
    end

    private

    # Тело запроса по ролям полей схемы PayoutRequest; nil-значения убираются.
    def build_payload(operation)
      payload = {
        amount: {
          # TODO: роль currency выведена, но выражения платформы для неё нет. Обязательно по
          #       спецификации.
          #   тип: string, minLength: 3, maxLength: 3
          #   описание из спецификации: "The three-character [ISO currency
          #   code](https://docs.adyen.com/development-resources/currency-codes#currency-codes) of
          #   the amount."
          #   где это лежит у платформы, знает только человек: заполните вручную или добавьте
          #   выражение в rules/contract.yml (раздел platform)
          currency: nil,
          value: to_provider_units(operation.amount)
        },
        'billingAddress' => {
          # TODO: роль поля не определена. Обязательно по спецификации.
          #   тип: string, maxLength: 3000
          #   описание из спецификации: "The name of the city. Maximum length: 3000 characters."
          #   обоснование: ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml
          #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
          #   rules/roles.yml
          city: nil,
          # TODO: роль поля не определена. Обязательно по спецификации.
          #   тип: string
          #   описание из спецификации: "The two-character ISO-3166-1 alpha-2 country code. For
          #   example, **US**.
          #   > If you don't know the country or are not collecting the country from the shopper,
          #   provide `country` as `ZZ`."
          #   обоснование: ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml
          #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
          #   rules/roles.yml
          country: nil,
          # TODO: роль поля не определена. Обязательно по спецификации.
          #   тип: string, maxLength: 3000
          #   описание из спецификации: "The number or name of the house. Maximum length: 3000
          #   characters."
          #   обоснование: ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml
          #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
          #   rules/roles.yml
          'houseNumberOrName' => nil,
          # TODO: роль поля не определена. Обязательно по спецификации.
          #   тип: string
          #   описание из спецификации: "A maximum of five digits for an address in the US, or a
          #   maximum of ten characters for an address in all other countries."
          #   обоснование: ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml
          #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
          #   rules/roles.yml
          'postalCode' => nil,
          # TODO: роль поля не определена. Обязательно по спецификации.
          #   тип: string, maxLength: 3000
          #   описание из спецификации: "The name of the street. Maximum length: 3000 characters.
          #   > The house number should not be included in this field; it should be separately
          #   provided via `houseNumberOrName`."
          #   обоснование: ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml
          #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
          #   rules/roles.yml
          street: nil
        },
        'fundSource' => {
          'billingAddress' => {
            # TODO: роль поля не определена. Обязательно по спецификации.
            #   тип: string, maxLength: 3000
            #   описание из спецификации: "The name of the city. Maximum length: 3000 characters."
            #   обоснование: ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml
            #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
            #   rules/roles.yml
            city: nil,
            # TODO: роль поля не определена. Обязательно по спецификации.
            #   тип: string
            #   описание из спецификации: "The two-character ISO-3166-1 alpha-2 country code. For
            #   example, **US**.
            #   > If you don't know the country or are not collecting the country from the shopper,
            #   provide `country` as `ZZ`."
            #   обоснование: ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml
            #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
            #   rules/roles.yml
            country: nil,
            # TODO: роль поля не определена. Обязательно по спецификации.
            #   тип: string, maxLength: 3000
            #   описание из спецификации: "The number or name of the house. Maximum length: 3000
            #   characters."
            #   обоснование: ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml
            #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
            #   rules/roles.yml
            'houseNumberOrName' => nil,
            # TODO: роль поля не определена. Обязательно по спецификации.
            #   тип: string
            #   описание из спецификации: "A maximum of five digits for an address in the US, or a
            #   maximum of ten characters for an address in all other countries."
            #   обоснование: ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml
            #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
            #   rules/roles.yml
            'postalCode' => nil,
            # TODO: роль поля не определена. Обязательно по спецификации.
            #   тип: string, maxLength: 3000
            #   описание из спецификации: "The name of the street. Maximum length: 3000 characters.
            #   > The house number should not be included in this field; it should be separately
            #   provided via `houseNumberOrName`."
            #   обоснование: ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml
            #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
            #   rules/roles.yml
            street: nil
          },
          'shopperName' => {
            # TODO: роль поля не определена. Обязательно по спецификации.
            #   тип: string, maxLength: 80
            #   описание из спецификации: "The first name."
            #   обоснование: ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml
            #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
            #   rules/roles.yml
            'firstName' => nil,
            # TODO: роль поля не определена. Обязательно по спецификации.
            #   тип: string, maxLength: 80
            #   описание из спецификации: "The last name."
            #   обоснование: ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml
            #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
            #   rules/roles.yml
            'lastName' => nil
          }
        },
        # TODO: роль поля не определена. Обязательно по спецификации.
        #   тип: string
        #   описание из спецификации: "The merchant account identifier, with which you want to
        #   process the transaction."
        #   обоснование: ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml
        #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
        #   rules/roles.yml
        'merchantAccount' => nil,
        # роль provider_operation_id выведена с уверенностью ниже порога (эвристика 0.50):
        # композитное сопоставление: name 2.0 (общие токены с синонимом `acquirer_reference`:
        # reference (50%)), structure 4.0 (родитель `PayoutRequest` содержит токен `payout` из
        # подсказок роли), type 1.0 (type string допустим для роли) = 7.0 из 14.0; следующая
        # external_id 0.21 — проверьте по report.md
        reference: operation.provider_operation_key,
        'shopperName' => {
          # TODO: роль поля не определена. Обязательно по спецификации.
          #   тип: string, maxLength: 80
          #   описание из спецификации: "The first name."
          #   обоснование: ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml
          #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
          #   rules/roles.yml
          'firstName' => nil,
          # TODO: роль поля не определена. Обязательно по спецификации.
          #   тип: string, maxLength: 80
          #   описание из спецификации: "The last name."
          #   обоснование: ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml
          #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
          #   rules/roles.yml
          'lastName' => nil
        }
      }
      compact_payload(payload)
    end

    # Тело запроса операции post-confirmThirdParty по ролям полей схемы ModifyRequest; nil-значения
    # убираются.
    def build_confirm_payload(_operation)
      payload = {
        # TODO: роль поля не определена. Обязательно по спецификации.
        #   тип: string
        #   описание из спецификации: "The merchant account identifier, with which you want to
        #   process the transaction."
        #   обоснование: ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml
        #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
        #   rules/roles.yml
        'merchantAccount' => nil,
        # TODO: роль поля не определена. Обязательно по спецификации.
        #   тип: string
        #   описание из спецификации: "The PSP reference received in the `/submitThirdParty`
        #   response."
        #   обоснование: ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml
        #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
        #   rules/roles.yml
        'originalReference' => nil
      }
      compact_payload(payload)
    end

    # Тело запроса операции post-declineThirdParty по ролям полей схемы ModifyRequest; nil-значения
    # убираются.
    def build_post_decline_third_party_payload(_operation)
      payload = {
        # TODO: роль поля не определена. Обязательно по спецификации.
        #   тип: string
        #   описание из спецификации: "The merchant account identifier, with which you want to
        #   process the transaction."
        #   обоснование: ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml
        #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
        #   rules/roles.yml
        'merchantAccount' => nil,
        # TODO: роль поля не определена. Обязательно по спецификации.
        #   тип: string
        #   описание из спецификации: "The PSP reference received in the `/submitThirdParty`
        #   response."
        #   обоснование: ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml
        #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
        #   rules/roles.yml
        'originalReference' => nil
      }
      compact_payload(payload)
    end

    # Тело запроса операции post-storeDetail по ролям полей схемы StoreDetailRequest; nil-значения
    # убираются.
    def build_post_store_detail_payload(_operation)
      payload = {
        'billingAddress' => {
          # TODO: роль поля не определена. Обязательно по спецификации.
          #   тип: string, maxLength: 3000
          #   описание из спецификации: "The name of the city. Maximum length: 3000 characters."
          #   обоснование: ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml
          #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
          #   rules/roles.yml
          city: nil,
          # TODO: роль поля не определена. Обязательно по спецификации.
          #   тип: string
          #   описание из спецификации: "The two-character ISO-3166-1 alpha-2 country code. For
          #   example, **US**.
          #   > If you don't know the country or are not collecting the country from the shopper,
          #   provide `country` as `ZZ`."
          #   обоснование: ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml
          #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
          #   rules/roles.yml
          country: nil,
          # TODO: роль поля не определена. Обязательно по спецификации.
          #   тип: string, maxLength: 3000
          #   описание из спецификации: "The number or name of the house. Maximum length: 3000
          #   characters."
          #   обоснование: ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml
          #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
          #   rules/roles.yml
          'houseNumberOrName' => nil,
          # TODO: роль поля не определена. Обязательно по спецификации.
          #   тип: string
          #   описание из спецификации: "A maximum of five digits for an address in the US, or a
          #   maximum of ten characters for an address in all other countries."
          #   обоснование: ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml
          #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
          #   rules/roles.yml
          'postalCode' => nil,
          # TODO: роль поля не определена. Обязательно по спецификации.
          #   тип: string, maxLength: 3000
          #   описание из спецификации: "The name of the street. Maximum length: 3000 characters.
          #   > The house number should not be included in this field; it should be separately
          #   provided via `houseNumberOrName`."
          #   обоснование: ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml
          #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
          #   rules/roles.yml
          street: nil
        },
        # TODO: роль поля не определена. Обязательно по спецификации.
        #   тип: string date
        #   описание из спецификации: "The date of birth.
        #   Format: [ISO-8601](https://www.w3.org/TR/NOTE-datetime); example: YYYY-MM-DD
        #   For Paysafecard it must be the same as used when registering the Paysafecard account.
        #   > This field is mandatory for natural persons."
        #   обоснование: ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml
        #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
        #   rules/roles.yml
        'dateOfBirth' => nil,
        # TODO: роль поля не определена. Обязательно по спецификации.
        #   тип: string, enum: NaturalPerson, Company
        #   описание из спецификации: "The type of the entity the payout is processed for."
        #   обоснование: ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml
        #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
        #   rules/roles.yml
        'entityType' => nil,
        # TODO: роль поля не определена. Обязательно по спецификации.
        #   тип: string
        #   описание из спецификации: "The merchant account identifier, with which you want to
        #   process the transaction."
        #   обоснование: ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml
        #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
        #   rules/roles.yml
        'merchantAccount' => nil,
        # TODO: роль поля не определена. Обязательно по спецификации.
        #   тип: string, maxLength: 2
        #   описание из спецификации: "The shopper's nationality.
        #
        #   A valid value is an ISO 2-character country code (e.g. 'NL')."
        #   обоснование: ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml
        #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
        #   rules/roles.yml
        nationality: nil,
        recurring: {},
        # TODO: роль поля не определена. Обязательно по спецификации.
        #   тип: string
        #   описание из спецификации: "The shopper's email address."
        #   обоснование: ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml
        #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
        #   rules/roles.yml
        'shopperEmail' => nil,
        'shopperName' => {
          # TODO: роль поля не определена. Обязательно по спецификации.
          #   тип: string, maxLength: 80
          #   описание из спецификации: "The first name."
          #   обоснование: ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml
          #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
          #   rules/roles.yml
          'firstName' => nil,
          # TODO: роль поля не определена. Обязательно по спецификации.
          #   тип: string, maxLength: 80
          #   описание из спецификации: "The last name."
          #   обоснование: ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml
          #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
          #   rules/roles.yml
          'lastName' => nil
        },
        # TODO: роль поля не определена. Обязательно по спецификации.
        #   тип: string
        #   описание из спецификации: "The shopper's reference for the payment transaction."
        #   обоснование: ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml
        #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
        #   rules/roles.yml
        'shopperReference' => nil
      }
      compact_payload(payload)
    end

    # Тело запроса операции post-storeDetailAndSubmitThirdParty по ролям полей схемы
    # StoreDetailAndSubmitRequest; nil-значения убираются.
    def build_post_store_detail_and_submit_third_party_payload(operation)
      payload = {
        amount: {
          # TODO: роль currency выведена, но выражения платформы для неё нет. Обязательно по
          #       спецификации.
          #   тип: string, minLength: 3, maxLength: 3
          #   описание из спецификации: "The three-character [ISO currency
          #   code](https://docs.adyen.com/development-resources/currency-codes#currency-codes) of
          #   the amount."
          #   где это лежит у платформы, знает только человек: заполните вручную или добавьте
          #   выражение в rules/contract.yml (раздел platform)
          currency: nil,
          value: to_provider_units(operation.amount)
        },
        'billingAddress' => {
          # TODO: роль поля не определена. Обязательно по спецификации.
          #   тип: string, maxLength: 3000
          #   описание из спецификации: "The name of the city. Maximum length: 3000 characters."
          #   обоснование: ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml
          #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
          #   rules/roles.yml
          city: nil,
          # TODO: роль поля не определена. Обязательно по спецификации.
          #   тип: string
          #   описание из спецификации: "The two-character ISO-3166-1 alpha-2 country code. For
          #   example, **US**.
          #   > If you don't know the country or are not collecting the country from the shopper,
          #   provide `country` as `ZZ`."
          #   обоснование: ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml
          #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
          #   rules/roles.yml
          country: nil,
          # TODO: роль поля не определена. Обязательно по спецификации.
          #   тип: string, maxLength: 3000
          #   описание из спецификации: "The number or name of the house. Maximum length: 3000
          #   characters."
          #   обоснование: ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml
          #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
          #   rules/roles.yml
          'houseNumberOrName' => nil,
          # TODO: роль поля не определена. Обязательно по спецификации.
          #   тип: string
          #   описание из спецификации: "A maximum of five digits for an address in the US, or a
          #   maximum of ten characters for an address in all other countries."
          #   обоснование: ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml
          #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
          #   rules/roles.yml
          'postalCode' => nil,
          # TODO: роль поля не определена. Обязательно по спецификации.
          #   тип: string, maxLength: 3000
          #   описание из спецификации: "The name of the street. Maximum length: 3000 characters.
          #   > The house number should not be included in this field; it should be separately
          #   provided via `houseNumberOrName`."
          #   обоснование: ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml
          #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
          #   rules/roles.yml
          street: nil
        },
        # TODO: роль поля не определена. Обязательно по спецификации.
        #   тип: string date
        #   описание из спецификации: "The date of birth.
        #   Format: [ISO-8601](https://www.w3.org/TR/NOTE-datetime); example: YYYY-MM-DD
        #   For Paysafecard it must be the same as used when registering the Paysafecard account.
        #   > This field is mandatory for natural persons."
        #   обоснование: ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml
        #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
        #   rules/roles.yml
        'dateOfBirth' => nil,
        # TODO: роль поля не определена. Обязательно по спецификации.
        #   тип: string, enum: NaturalPerson, Company
        #   описание из спецификации: "The type of the entity the payout is processed for."
        #   обоснование: ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml
        #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
        #   rules/roles.yml
        'entityType' => nil,
        # TODO: роль поля не определена. Обязательно по спецификации.
        #   тип: string
        #   описание из спецификации: "The merchant account identifier, with which you want to
        #   process the transaction."
        #   обоснование: ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml
        #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
        #   rules/roles.yml
        'merchantAccount' => nil,
        # TODO: роль поля не определена. Обязательно по спецификации.
        #   тип: string, maxLength: 2
        #   описание из спецификации: "The shopper's nationality.
        #
        #   A valid value is an ISO 2-character country code (e.g. 'NL')."
        #   обоснование: ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml
        #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
        #   rules/roles.yml
        nationality: nil,
        recurring: {},
        # роль external_id выведена с уверенностью ниже порога (эвристика 0.21): композитное
        # сопоставление: name 2.0 (общие токены с синонимом `client_reference`: reference (50%)),
        # type 1.0 (type string допустим для роли) = 3.0 из 14.0; следующая provider_operation_id
        # 0.21 — проверьте по report.md
        reference: operation.id,
        # TODO: роль поля не определена. Обязательно по спецификации.
        #   тип: string
        #   описание из спецификации: "The shopper's email address."
        #   обоснование: ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml
        #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
        #   rules/roles.yml
        'shopperEmail' => nil,
        'shopperName' => {
          # TODO: роль поля не определена. Обязательно по спецификации.
          #   тип: string, maxLength: 80
          #   описание из спецификации: "The first name."
          #   обоснование: ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml
          #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
          #   rules/roles.yml
          'firstName' => nil,
          # TODO: роль поля не определена. Обязательно по спецификации.
          #   тип: string, maxLength: 80
          #   описание из спецификации: "The last name."
          #   обоснование: ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml
          #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
          #   rules/roles.yml
          'lastName' => nil
        },
        # TODO: роль поля не определена. Обязательно по спецификации.
        #   тип: string
        #   описание из спецификации: "The shopper's reference for the payment transaction."
        #   обоснование: ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml
        #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
        #   rules/roles.yml
        'shopperReference' => nil
      }
      compact_payload(payload)
    end

    # Тело запроса операции post-submitThirdParty по ролям полей схемы SubmitRequest; nil-значения
    # убираются.
    def build_post_submit_third_party_payload(operation)
      payload = {
        amount: {
          # TODO: роль currency выведена, но выражения платформы для неё нет. Обязательно по
          #       спецификации.
          #   тип: string, minLength: 3, maxLength: 3
          #   описание из спецификации: "The three-character [ISO currency
          #   code](https://docs.adyen.com/development-resources/currency-codes#currency-codes) of
          #   the amount."
          #   где это лежит у платформы, знает только человек: заполните вручную или добавьте
          #   выражение в rules/contract.yml (раздел platform)
          currency: nil,
          value: to_provider_units(operation.amount)
        },
        # TODO: роль поля не определена. Обязательно по спецификации.
        #   тип: string
        #   описание из спецификации: "The merchant account identifier you want to process the
        #   transaction request with."
        #   обоснование: ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml
        #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
        #   rules/roles.yml
        'merchantAccount' => nil,
        recurring: {},
        # роль external_id выведена с уверенностью ниже порога (эвристика 0.21): композитное
        # сопоставление: name 2.0 (общие токены с синонимом `client_reference`: reference (50%)),
        # type 1.0 (type string допустим для роли) = 3.0 из 14.0; следующая provider_operation_id
        # 0.21 — проверьте по report.md
        reference: operation.id,
        # TODO: роль поля не определена. Обязательно по спецификации.
        #   тип: string
        #   описание из спецификации: "This is the `recurringDetailReference` you want to use for
        #   this payout.
        #
        #   You can use the value LATEST to select the most recently used recurring detail."
        #   обоснование: ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml
        #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
        #   rules/roles.yml
        'selectedRecurringDetailReference' => nil,
        # TODO: роль поля не определена. Обязательно по спецификации.
        #   тип: string
        #   описание из спецификации: "The shopper's email address."
        #   обоснование: ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml
        #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
        #   rules/roles.yml
        'shopperEmail' => nil,
        'shopperName' => {
          # TODO: роль поля не определена. Обязательно по спецификации.
          #   тип: string, maxLength: 80
          #   описание из спецификации: "The first name."
          #   обоснование: ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml
          #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
          #   rules/roles.yml
          'firstName' => nil,
          # TODO: роль поля не определена. Обязательно по спецификации.
          #   тип: string, maxLength: 80
          #   описание из спецификации: "The last name."
          #   обоснование: ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml
          #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
          #   rules/roles.yml
          'lastName' => nil
        },
        # TODO: роль поля не определена. Обязательно по спецификации.
        #   тип: string
        #   описание из спецификации: "The shopper's reference for the payout transaction."
        #   обоснование: ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml
        #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
        #   rules/roles.yml
        'shopperReference' => nil
      }
      compact_payload(payload)
    end

    # Заголовки запроса на создание: авторизация и тип содержимого.
    def request_headers
      auth_headers.merge('Content-Type' => 'application/json')
    end

    # Заголовки авторизации: схема ApiKeyAuth (api_key) по записи rules/auth.yml «api_key_header».
    # Секрет читается из provider.credentials.
    # @return [Hash]
    def auth_headers
      { 'X-API-Key' => provider.credentials[:api_key] }
    end

    # Успешный ответ на создание: перевести статус и вернуть платформе идентификатор операции у
    # провайдера — она сохраняет его как provider_operation_key из result[:id].
    def accept_created(operation, body)
      apply_internal_status(operation, map_status(body['status']))
      success(result: { id: body['pspReference'] })
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
    def provider_failure(response, body)
      code = body['errorCode']
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
