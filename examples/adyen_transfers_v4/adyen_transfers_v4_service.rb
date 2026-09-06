# frozen_string_literal: true

# Сгенерировано инструментом integrate из adyen_transfers_v4.yaml, версия спецификации
# 4, OpenAPI 3.1.0. Не редактируйте вручную: правки — в overlay
# (OpenAPI Overlay 1.0.0) и повторная генерация.
#
# Проверка файла:
#   ruby -c output/adyen_transfers_v4_service.rb
#   bundle exec rubocop --config config/rubocop_generated.yml output/adyen_transfers_v4_service.rb
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
  # Интеграция с провайдером «Transfers API»: предпроверки, создание
  # операции, обработка уведомлений и опрос статуса по контракту
  # Provider::BaseService. Таблицы статусов, ошибок и политики ретраев —
  # замороженные хеши, сверяемые с INTEGRATION.md; TODO отмечают места, где
  # спецификация не дала ответа и инструмент взял лучшего кандидата.
  class AdyenTransfersV4Service < Provider::BaseService
    BASE_URL = ENV.fetch('ADYEN_TRANSFERS_V4_BASE_URL', 'https://balanceplatform-api-test.adyen.com/btl/v4')
    # Таймауты в секундах; как передать их клиенту платформы, зависит от
    # клиента (его интерфейс — допущение), поэтому здесь только значения.
    OPEN_TIMEOUT = Integer(ENV.fetch('ADYEN_TRANSFERS_V4_OPEN_TIMEOUT', '5'))
    READ_TIMEOUT = Integer(ENV.fetch('ADYEN_TRANSFERS_V4_READ_TIMEOUT', '15'))
    PROVIDER = 'adyen_transfers_v4'
    # TODO: единицы суммы не выведены (без кода валюты экспоненту ISO 4217 определить нельзя);
    #       множитель 1 — задайте x-specgen-amount-unit и x-specgen-exponent в overlay
    AMOUNT_MULTIPLIER = 1
    DEFAULT_ERROR_ACTION = :reject
    # Ключ идемпотентности отправляется всегда, даже если спецификация помечает заголовок
    # необязательным (параметр-заголовок Idempotency-Key совпал с алиасом rules/idempotency.yml;
    # принимают: post-grants, post-transfers, post-transfers-approve, post-transfers-cancel,
    # post-transfers-transferId-returns; объявлен required: false, но по rules/idempotency.yml
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
      'Active' => nil,
      # TODO: статус не сопоставлен: статус authorised неоднозначен: британское написание
      #       authorized; у Adyen это «средства зарезервированы», у других — «списаны»; задайте
      #       x-specgen-status-map в overlay
      'Authorised' => nil,
      'Declined' => :rejected,
      'Failed' => :rejected,
      'Pending' => :in_progress,
      # TODO: статус не сопоставлен: статус Repaid не найден ни в каноне, ни среди синонимов
      #       rules/statuses.yml; задайте x-specgen-status-map в overlay
      'Repaid' => nil,
      'Revoked' => :rejected,
      # TODO: статус не сопоставлен: статус WrittenOff не найден ни в каноне, ни среди синонимов
      #       rules/statuses.yml; задайте x-specgen-status-map в overlay
      'WrittenOff' => nil,
      'accepted' => :in_progress,
      'approvalPending' => :in_progress,
      # TODO: статус не сопоставлен: значение atmWithdrawal называет тип операции, а не её исход:
      #       слово `withdrawal` из not_status_words rules/statuses.yml; похоже, что в одном enum
      #       смешаны статусы и виды проводки; задайте x-specgen-status-map в overlay
      'atmWithdrawal' => nil,
      'atmWithdrawalReversalPending' => :in_progress,
      # TODO: статус не сопоставлен: событие atmWithdrawalReversed читается как статус reversed;
      #       статус reversed неоднозначен: успешная операция, затем развёрнута провайдером; задайте
      #       x-specgen-status-map в overlay
      'atmWithdrawalReversed' => nil,
      # TODO: статус не сопоставлен: событие authAdjustmentAuthorised читается как статус
      #       authorised; статус authorised неоднозначен: британское написание authorized; у Adyen
      #       это «средства зарезервированы», у других — «списаны»; задайте x-specgen-status-map в
      #       overlay
      'authAdjustmentAuthorised' => nil,
      'authAdjustmentError' => :rejected,
      'authAdjustmentRefused' => :rejected,
      # TODO: статус не сопоставлен: статус authorised неоднозначен: британское написание
      #       authorized; у Adyen это «средства зарезервированы», у других — «списаны»; задайте
      #       x-specgen-status-map в overlay
      'authorised' => nil,
      # TODO: статус не сопоставлен: значение bankTransfer называет тип операции, а не её исход:
      #       слово `transfer` из not_status_words rules/statuses.yml; похоже, что в одном enum
      #       смешаны статусы и виды проводки; задайте x-specgen-status-map в overlay
      'bankTransfer' => nil,
      'bankTransferPending' => :in_progress,
      'booked' => :approved,
      'bookingPending' => :in_progress,
      'cancelled' => :rejected,
      'capturePending' => :in_progress,
      'captureReversalPending' => :in_progress,
      # TODO: статус не сопоставлен: событие captureReversed читается как статус reversed; статус
      #       reversed неоднозначен: успешная операция, затем развёрнута провайдером; задайте
      #       x-specgen-status-map в overlay
      'captureReversed' => nil,
      'captured' => :approved,
      'capturedExternally' => :approved,
      # TODO: статус не сопоставлен: статус chargeback неоднозначен: успешная операция, деньги
      #       отозваны держателем карты; задайте x-specgen-status-map в overlay
      'chargeback' => nil,
      # TODO: статус не сопоставлен: событие chargebackExternally читается как статус chargeback;
      #       статус chargeback неоднозначен: успешная операция, деньги отозваны держателем карты;
      #       задайте x-specgen-status-map в overlay
      'chargebackExternally' => nil,
      'chargebackPending' => :in_progress,
      'chargebackReversalPending' => :in_progress,
      # TODO: статус не сопоставлен: событие chargebackReversed читается как статус reversed; статус
      #       reversed неоднозначен: успешная операция, затем развёрнута провайдером; задайте
      #       x-specgen-status-map в overlay
      'chargebackReversed' => nil,
      'credited' => :approved,
      # TODO: статус не сопоставлен: значение depositCorrection называет тип операции, а не её
      #       исход: слово `correction` из not_status_words rules/statuses.yml; похоже, что в одном
      #       enum смешаны статусы и виды проводки; задайте x-specgen-status-map в overlay
      'depositCorrection' => nil,
      'depositCorrectionPending' => :in_progress,
      # TODO: статус не сопоставлен: значение dispute называет тип операции, а не её исход: слово
      #       `dispute` из not_status_words rules/statuses.yml; похоже, что в одном enum смешаны
      #       статусы и виды проводки; задайте x-specgen-status-map в overlay
      'dispute' => nil,
      # TODO: статус не сопоставлен: событие disputeClosed читается как статус closed; статус closed
      #       неоднозначен: закрыт спор, счёт или сессия — исход самой операции этим словом не
      #       назван; задайте x-specgen-status-map в overlay
      'disputeClosed' => nil,
      'disputeExpired' => :rejected,
      # TODO: статус не сопоставлен: значение disputeNeedsReview называет тип операции, а не её
      #       исход: слово `dispute` из not_status_words rules/statuses.yml; похоже, что в одном
      #       enum смешаны статусы и виды проводки; задайте x-specgen-status-map в overlay
      'disputeNeedsReview' => nil,
      'error' => :rejected,
      'expired' => :rejected,
      'failed' => :rejected,
      # TODO: статус не сопоставлен: значение fee называет тип операции, а не её исход: слово `fee`
      #       из not_status_words rules/statuses.yml; похоже, что в одном enum смешаны статусы и
      #       виды проводки; задайте x-specgen-status-map в overlay
      'fee' => nil,
      'feePending' => :in_progress,
      # TODO: статус не сопоставлен: значение interchangeAdjusted называет тип операции, а не её
      #       исход: слово `adjusted` из not_status_words rules/statuses.yml; похоже, что в одном
      #       enum смешаны статусы и виды проводки; задайте x-specgen-status-map в overlay
      'interchangeAdjusted' => nil,
      # TODO: статус не сопоставлен: значение internalTransfer называет тип операции, а не её исход:
      #       слово `transfer` из not_status_words rules/statuses.yml; похоже, что в одном enum
      #       смешаны статусы и виды проводки; задайте x-specgen-status-map в overlay
      'internalTransfer' => nil,
      'internalTransferPending' => :in_progress,
      # TODO: статус не сопоставлен: значение invoiceDeduction называет тип операции, а не её исход:
      #       слово `deduction` из not_status_words rules/statuses.yml; похоже, что в одном enum
      #       смешаны статусы и виды проводки; задайте x-specgen-status-map в overlay
      'invoiceDeduction' => nil,
      'invoiceDeductionPending' => :in_progress,
      'manualCorrectionPending' => :in_progress,
      # TODO: статус не сопоставлен: значение manuallyCorrected называет тип операции, а не её
      #       исход: слово `corrected` из not_status_words rules/statuses.yml; похоже, что в одном
      #       enum смешаны статусы и виды проводки; задайте x-specgen-status-map в overlay
      'manuallyCorrected' => nil,
      # TODO: статус не сопоставлен: значение matchedStatement называет тип операции, а не её исход:
      #       слово `statement` из not_status_words rules/statuses.yml; похоже, что в одном enum
      #       смешаны статусы и виды проводки; задайте x-specgen-status-map в overlay
      'matchedStatement' => nil,
      'matchedStatementPending' => :in_progress,
      # TODO: статус не сопоставлен: значение merchantPayin называет тип операции, а не её исход:
      #       слово `payin` из not_status_words rules/statuses.yml; похоже, что в одном enum смешаны
      #       статусы и виды проводки; задайте x-specgen-status-map в overlay
      'merchantPayin' => nil,
      'merchantPayinPending' => :in_progress,
      # TODO: статус не сопоставлен: событие merchantPayinReversed читается как статус reversed;
      #       статус reversed неоднозначен: успешная операция, затем развёрнута провайдером; задайте
      #       x-specgen-status-map в overlay
      'merchantPayinReversed' => nil,
      'merchantPayinReversedPending' => :in_progress,
      # TODO: статус не сопоставлен: значение miscCost называет тип операции, а не её исход: слово
      #       `cost` из not_status_words rules/statuses.yml; похоже, что в одном enum смешаны
      #       статусы и виды проводки; задайте x-specgen-status-map в overlay
      'miscCost' => nil,
      'miscCostPending' => :in_progress,
      # TODO: статус не сопоставлен: значение paymentCost называет тип операции, а не её исход:
      #       слово `cost` из not_status_words rules/statuses.yml; похоже, что в одном enum смешаны
      #       статусы и виды проводки; задайте x-specgen-status-map в overlay
      'paymentCost' => nil,
      'paymentCostPending' => :in_progress,
      'pending' => :in_progress,
      'pendingApproval' => :in_progress,
      'pendingExecution' => :in_progress,
      'received' => :in_progress,
      'refundPending' => :in_progress,
      'refundReversalPending' => :in_progress,
      # TODO: статус не сопоставлен: событие refundReversed читается как статус reversed; статус
      #       reversed неоднозначен: успешная операция, затем развёрнута провайдером; задайте
      #       x-specgen-status-map в overlay
      'refundReversed' => nil,
      # TODO: статус не сопоставлен: статус refunded неоднозначен: успешная операция, деньги затем
      #       возвращены; задайте x-specgen-status-map в overlay
      'refunded' => nil,
      # TODO: статус не сопоставлен: событие refundedExternally читается как статус refunded; статус
      #       refunded неоднозначен: успешная операция, деньги затем возвращены; задайте
      #       x-specgen-status-map в overlay
      'refundedExternally' => nil,
      'refused' => :rejected,
      'rejected' => :rejected,
      # TODO: статус не сопоставлен: значение reserveAdjustment называет тип операции, а не её
      #       исход: слово `adjustment` из not_status_words rules/statuses.yml; похоже, что в одном
      #       enum смешаны статусы и виды проводки; задайте x-specgen-status-map в overlay
      'reserveAdjustment' => nil,
      'reserveAdjustmentPending' => :in_progress,
      'returned' => :rejected,
      # TODO: статус не сопоставлен: статус reversed неоднозначен: успешная операция, затем
      #       развёрнута провайдером; задайте x-specgen-status-map в overlay
      'reversed' => nil,
      # TODO: статус не сопоставлен: событие secondChargeback читается как статус chargeback; статус
      #       chargeback неоднозначен: успешная операция, деньги отозваны держателем карты; задайте
      #       x-specgen-status-map в overlay
      'secondChargeback' => nil,
      'secondChargebackPending' => :in_progress,
      # TODO: статус не сопоставлен: статус undefined неоднозначен: то же, что unknown: состояние не
      #       названо; задайте x-specgen-status-map в overlay
      'undefined' => nil
    }.freeze

    # Код ошибки провайдера или HTTP-код → действие платформы
    # (reject | retry | retry_backoff | alert | escalate). Дедупликация в
    # таблицу не входит: это успешный путь, см. DEDUP_STATUS.
    ERROR_MAP = {
      # По HTTP-коду, когда тело не несёт кода ошибки.
      400 => :reject,
      404 => :reject,
      429 => :retry_backoff
    }.freeze

    # Коды, которые у отдельной операции означают не то, что в ERROR_MAP.
    ERROR_MAP_BY_OPERATION = {
      'get-grants' => {
        401 => :alert,
        403 => :alert,
        422 => :reject,
        500 => :retry_backoff
      },
      'get-grants-id' => {
        401 => :alert,
        403 => :alert,
        422 => :reject,
        500 => :retry_backoff
      },
      'get-transactions' => {
        401 => :alert,
        403 => :alert,
        422 => :reject,
        500 => :retry_backoff
      },
      'get-transactions-id' => {
        401 => :alert,
        403 => :alert,
        422 => :reject,
        500 => :retry_backoff
      },
      'get-transfers' => {
        401 => :alert,
        403 => :alert,
        422 => :reject,
        500 => :retry_backoff
      },
      'get-transfers-id' => {
        401 => :alert,
        403 => :alert,
        422 => :reject,
        500 => :retry_backoff
      },
      'post-cashouts' => {
        401 => :alert,
        403 => :alert,
        422 => :reject,
        500 => :retry_backoff
      },
      'post-grants' => {
        401 => :alert,
        403 => :alert,
        422 => :reject,
        500 => :retry_backoff
      },
      'post-transfers' => {
        401 => :alert,
        403 => :alert,
        422 => :reject,
        500 => :retry_backoff
      },
      'post-transfers-approve' => {
        401 => :alert,
        403 => :alert,
        422 => :reject,
        500 => :retry_backoff
      },
      'post-transfers-cancel' => {
        401 => :alert,
        403 => :alert,
        422 => :reject,
        500 => :retry_backoff
      },
      'post-transfers-transferId-returns' => {
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
      statuses: [429],
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

      # reference: maxLength 150 (задано явно 1.00)
      if operation.id.to_s.length > 150
        return failure(:unprocessable_entity, 'errors.external_id_too_long')
      end

      # type: допустимые значения individual, organization, unknown (задано явно 1.00)
      # TODO: условие для поля type: у платформы нет выражения для его роли (rules/contract.yml,
      #       раздел platform)
      # bsbCode: maxLength 6 (задано явно 1.00)
      # TODO: условие для поля bsbCode: у платформы нет выражения для его роли (rules/contract.yml,
      #       раздел platform)
      # type: допустимые значения auLocal (задано явно 1.00)
      # TODO: условие для поля type: у платформы нет выражения для его роли (rules/contract.yml,
      #       раздел platform)
      # bankCode: maxLength 3 (задано явно 1.00)
      # TODO: условие для поля bankCode: у платформы нет выражения для его роли (rules/contract.yml,
      #       раздел platform)
      # accountType: допустимые значения checking, savings (задано явно 1.00)
      # TODO: условие для поля accountType: у платформы нет выражения для его роли
      #       (rules/contract.yml, раздел platform)
      # type: допустимые значения auBsbCode, caRoutingNumber, gbSortCode, usRoutingNumber (задано
      # явно 1.00)
      # TODO: условие для поля type: у платформы нет выражения для его роли (rules/contract.yml,
      #       раздел platform)
      # clearingNumber: maxLength 5 (задано явно 1.00)
      # TODO: условие для поля clearingNumber: у платформы нет выражения для его роли
      #       (rules/contract.yml, раздел platform)
      # routingNumber: maxLength 9 (задано явно 1.00)
      # TODO: условие для поля routingNumber: у платформы нет выражения для его роли
      #       (rules/contract.yml, раздел platform)
      # reference: maxLength 80 (задано явно 1.00)
      if operation.id.to_s.length > 80
        return failure(:unprocessable_entity, 'errors.external_id_too_long')
      end

      # type: допустимые значения bankTransfer, internalTransfer, internalDirectDebit (задано явно
      # 1.00)
      # TODO: условие для поля type: у платформы нет выражения для его роли (rules/contract.yml,
      #       раздел platform)
      success
    end

    # Создание операции у провайдера: сборка тела запроса из ролей, перевод суммы в единицы
    # провайдера, заголовки авторизации и идемпотентности, разбор ответа и кодов ошибок.
    # Вторая операция создания в спецификации: post-cashouts; контракт даёт один метод, она осталась
    # снаружи.
    # @param operation [Object]
    # @param request_method [Object]
    # @return [Object] success | failure
    def create_request(operation, _request_method = 'create')
      payload = build_payload(operation)
      url = "#{BASE_URL}/transfers"
      response = client.post(url, payload, request_headers(operation))
      body = parse_json(response.body)
      return accept_created(operation, body) if [200, 202].include?(response.status)

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
      url = "#{BASE_URL}/transfers/#{operation.provider_operation_key}"
      response = client.get(url, auth_headers)
      body = parse_json(response.body)
      return failure(:not_found, 'errors.operation_not_found') if response.status == 404
      return provider_failure(response, body) unless response.status == 200

      internal = map_status(body['status'])
      return failure(:unprocessable_entity, 'errors.status_unknown') if internal.nil?

      apply_internal_status(operation, internal)
    end

    # Операция get-grants (роль unmapped, эвристика 0.00) не отображена на контракт BaseService:
    # отдельный публичный метод.
    # TODO: роль операции не распознана (ни одна роль не прошла отсечку формы: cancel 1.0 из 8.0
    #       поданных голосов; отсечены по форме: fetch_status — ни в пути, ни в operationId нет ни
    #       одного платёжного существительного (vetoes.domain_nouns в rules/operations.yml), balance
    #       — ни в пути, ни в operationId нет ни одного платёжного существительного
    #       (vetoes.domain_nouns в rules/operations.yml)) — проверьте, нужна ли она интеграции
    # @return [Object]
    def grants
      url = "#{BASE_URL}/grants"
      response = client.get(url, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 200

      body
    end

    # Операция post-grants (роль unmapped, эвристика 0.00) не отображена на контракт BaseService:
    # отдельный публичный метод.
    # TODO: роль операции не распознана (ни один сигнал не совпал ни с одной ролью) — проверьте,
    #       нужна ли она интеграции
    # @param operation [Object]
    # @return [Object]
    def post_grants(operation)
      payload = build_post_grants_payload(operation)
      url = "#{BASE_URL}/grants"
      response = client.post(url, payload, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 200

      body
    end

    # Операция get-grants-id (роль unmapped, эвристика 0.00) не отображена на контракт BaseService:
    # отдельный публичный метод.
    # TODO: роль операции не распознана (ни одна роль не прошла отсечку формы: cancel 1.0 из 11.0
    #       поданных голосов; отсечены по форме: fetch_status — ни в пути, ни в operationId нет ни
    #       одного платёжного существительного (vetoes.domain_nouns в rules/operations.yml), balance
    #       — ни в пути, ни в operationId нет ни одного платёжного существительного
    #       (vetoes.domain_nouns в rules/operations.yml)) — проверьте, нужна ли она интеграции
    # @param operation [Object]
    # @return [Object]
    def get_grants_id(operation)
      url = "#{BASE_URL}/grants/#{operation.provider_operation_key}"
      response = client.get(url, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 200

      body
    end

    # Операция get-transactions (роль unmapped, эвристика 0.00) не отображена на контракт
    # BaseService: отдельный публичный метод.
    # TODO: роль операции не распознана (ни одна роль не прошла отсечку формы: из 14.0 поданных
    #       голосов; отсечены по форме: fetch_status — успешный ответ — список, то есть листинг
    #       ресурса, а не чтение одного экземпляра (vetoes.list_response в rules/operations.yml),
    #       create_payout — HTTP-метод операции не из тех, которыми выражается эта роль
    #       (vetoes.http_method в rules/operations.yml), cancel — HTTP-метод операции не из тех,
    #       которыми выражается эта роль (vetoes.http_method в rules/operations.yml), balance — ни в
    #       пути, ни в operationId нет ни одного платёжного существительного (vetoes.domain_nouns в
    #       rules/operations.yml)) — проверьте, нужна ли она интеграции
    # @return [Object]
    def transactions
      url = "#{BASE_URL}/transactions"
      response = client.get(url, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 200

      body
    end

    # Операция get-transactions-id (роль fetch_status, эвристика 0.95) не отображена на контракт
    # BaseService: отдельный публичный метод.
    # TODO: метод контракта уже занят операцией get-transfers-id; эта операция той же роли осталась
    #       снаружи — решите, нужна ли она интеграции
    # @param operation [Object]
    # @return [Object]
    def get_transactions_id(operation)
      url = "#{BASE_URL}/transactions/#{operation.provider_operation_key}"
      response = client.get(url, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 200

      body
    end

    # Операция get-transfers (роль unmapped, эвристика 0.00) не отображена на контракт BaseService:
    # отдельный публичный метод.
    # TODO: роль операции не распознана (ни одна роль не прошла отсечку формы: из 14.0 поданных
    #       голосов; отсечены по форме: fetch_status — успешный ответ — список, то есть листинг
    #       ресурса, а не чтение одного экземпляра (vetoes.list_response в rules/operations.yml),
    #       create_payout — HTTP-метод операции не из тех, которыми выражается эта роль
    #       (vetoes.http_method в rules/operations.yml), cancel — HTTP-метод операции не из тех,
    #       которыми выражается эта роль (vetoes.http_method в rules/operations.yml), balance — ни в
    #       пути, ни в operationId нет ни одного платёжного существительного (vetoes.domain_nouns в
    #       rules/operations.yml), confirm — HTTP-метод операции не из тех, которыми выражается эта
    #       роль (vetoes.http_method в rules/operations.yml), refund — HTTP-метод операции не из
    #       тех, которыми выражается эта роль (vetoes.http_method в rules/operations.yml)) —
    #       проверьте, нужна ли она интеграции
    # @return [Object]
    def transfers
      url = "#{BASE_URL}/transfers"
      response = client.get(url, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 200

      body
    end

    # Операция post-transfers-approve (роль confirm, эвристика 0.86) не отображена на контракт
    # BaseService: отдельный публичный метод.
    # @param operation [Object]
    # @return [Object]
    def confirm(operation)
      payload = build_confirm_payload(operation)
      url = "#{BASE_URL}/transfers/approve"
      response = client.post(url, payload, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 200

      accept_response(operation, body)
    end

    # Операция post-transfers-cancel (роль cancel, эвристика 0.93) не отображена на контракт
    # BaseService: отдельный публичный метод.
    # @param operation [Object]
    # @return [Object]
    def cancel(operation)
      payload = build_cancel_payload(operation)
      url = "#{BASE_URL}/transfers/cancel"
      response = client.post(url, payload, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 200

      accept_response(operation, body)
    end

    # Операция post-transfers-transferId-returns (роль refund, эвристика 0.68) не отображена на
    # контракт BaseService: отдельный публичный метод.
    # @param operation [Object]
    # @return [Object]
    def refund(operation)
      payload = build_refund_payload(operation)
      url = "#{BASE_URL}/transfers/#{operation.provider_operation_key}/returns"
      response = client.post(url, payload, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 200

      body
    end

    # Операция post-cashouts (роль create_payout, эвристика 0.81) не отображена на контракт
    # BaseService: отдельный публичный метод.
    # TODO: метод контракта уже занят операцией post-transfers; эта операция той же роли осталась
    #       снаружи — решите, нужна ли она интеграции
    # @param operation [Object]
    # @return [Object]
    def post_cashouts(operation)
      payload = build_post_cashouts_payload(operation)
      url = "#{BASE_URL}/cashouts"
      response = client.post(url, payload, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 200

      body
    end

    private

    # Тело запроса по ролям полей схемы TransferInfo; nil-значения убираются.
    def build_payload(operation)
      payload = {
        amount: {
          # TODO: роль currency выведена, но выражения платформы для неё нет. Обязательно по
          #       спецификации.
          #   тип: string
          #   описание из спецификации: "The three-character [ISO currency
          #   code](https://docs.adyen.com/development-resources/currency-codes#currency-codes) of
          #   the amount."
          #   где это лежит у платформы, знает только человек: заполните вручную или добавьте
          #   выражение в rules/contract.yml (раздел platform)
          currency: nil,
          value: to_provider_units(operation.amount)
        },
        # TODO: роль поля не определена. Обязательно по спецификации.
        #   тип: string, enum: bank, card, internal, issuedCard, platformPayment, topUp
        #   описание из спецификации: "The category of the transfer.
        #
        #   Possible values:
        #
        #   - **bank**: A transfer involving a [transfer
        #   instrument](https://docs.adyen.com/api-explorer/legalentity/latest/post/transferInstrume
        #   nts#responses-200-id) or a bank account.
        #
        #   - **card**: A transfer involving a third-party card.
        #
        #   - **internal**: A transfer between [balance
        #   accounts](https://docs.adyen.com/api-explorer/balanceplatform/latest/post/balanceAccount
        #   s#responses-200-id) within your platform.
        #
        #   - **issuedCard**: A transfer initiated by an Adyen-issued card.
        #
        #   - **platformPayment**: Funds movements related to payments that are acquired for your
        #   users.
        #
        #   - **topUp**: An incoming transfer initiated by your user to top up their balance
        #   account."
        #   обоснование: ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml
        #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
        #   rules/roles.yml
        category: nil,
        counterparty: {
          'bankAccount' => {
            'accountHolder' => {
              address: {
                # TODO: роль поля не определена. Обязательно по спецификации.
                #   тип: string
                #   описание из спецификации: "The two-character ISO 3166-1 alpha-2 country code.
                #   For example, **US**, **NL**, or **GB**."
                #   обоснование: ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml
                #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
                #   rules/roles.yml
                country: nil
              },
              # роль external_id выведена с уверенностью ниже порога (эвристика 0.21): композитное
              # сопоставление: name 2.0 (общие токены с синонимом `client_reference`: reference
              # (50%)), type 1.0 (type string допустим для роли) = 3.0 из 14.0; следующая
              # provider_operation_id 0.21 — проверьте по report.md
              reference: operation.id
            },
            'accountIdentification' => {
              # TODO: роль поля не определена. Условно обязательно по спецификации.
              #   тип: string, minLength: 5, maxLength: 9
              #   описание из спецификации: "The bank account number, without separators or
              #   whitespace."
              #   обоснование: ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml
              #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
              #   rules/roles.yml
              'accountNumber' => nil,
              # TODO: роль поля не определена. Условно обязательно по спецификации.
              #   тип: string, minLength: 6, maxLength: 6
              #   описание из спецификации: "The 6-digit [Bank State Branch (BSB)
              #   code](https://en.wikipedia.org/wiki/Bank_state_branch), without separators or
              #   whitespace."
              #   обоснование: роль bank_code отдана `bic` (0.90);
              #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
              #   rules/roles.yml
              'bsbCode' => nil,
              # TODO: роль поля не определена. Условно обязательно по спецификации.
              #   тип: string, minLength: 3, maxLength: 3
              #   описание из спецификации: "The 3-digit bank code, with leading zeros."
              #   обоснование: роль bank_code отдана `bsbCode` (0.90);
              #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
              #   rules/roles.yml
              'bankCode' => nil,
              # TODO: роль поля не определена. Условно обязательно по спецификации.
              #   тип: string, minLength: 1, maxLength: 4
              #   описание из спецификации: "The bank account branch number, without separators or
              #   whitespace."
              #   обоснование: ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml
              #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
              #   rules/roles.yml
              'branchNumber' => nil,
              # TODO: роль поля не определена. Условно обязательно по спецификации.
              #   тип: string, minLength: 3, maxLength: 3
              #   описание из спецификации: "The 3-digit institution number, without separators or
              #   whitespace."
              #   обоснование: роль bank_code отдана `bsbCode` (0.90);
              #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
              #   rules/roles.yml
              'institutionNumber' => nil,
              # TODO: роль поля не определена. Условно обязательно по спецификации.
              #   тип: string, minLength: 5, maxLength: 5
              #   описание из спецификации: "The 5-digit transit number, without separators or
              #   whitespace."
              #   обоснование: ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml
              #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
              #   rules/roles.yml
              'transitNumber' => nil,
              # TODO: роль поля не определена. Условно обязательно по спецификации.
              #   тип: string, minLength: 3, maxLength: 3
              #   описание из спецификации: "The 3-digit clearing code, without separators or
              #   whitespace."
              #   обоснование: роль bank_code отдана `bsbCode` (0.90);
              #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
              #   rules/roles.yml
              'clearingCode' => nil,
              # TODO: роль bank_code выведена, но выражения платформы для неё нет. Условно
              #       обязательно по спецификации.
              #   тип: string
              #   описание из спецификации: "The bank's 8- or 11-character BIC or SWIFT code."
              #   где это лежит у платформы, знает только человек: заполните вручную или добавьте
              #   выражение в rules/contract.yml (раздел platform)
              bic: nil,
              # TODO: роль поля не определена. Условно обязательно по спецификации.
              #   тип: string
              #   описание из спецификации: "The international bank account number as defined in the
              #   [ISO-13616](https://www.iso.org/standard/81090.html) standard."
              #   обоснование: ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml
              #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
              #   rules/roles.yml
              iban: nil,
              # TODO: роль поля не определена. Условно обязательно по спецификации.
              #   тип: string, minLength: 4, maxLength: 5
              #   описание из спецификации: "The 4- to 5-digit clearing number
              #   ([Clearingnummer](https://sv.wikipedia.org/wiki/Clearingnummer)), without
              #   separators or whitespace."
              #   обоснование: роль bank_code отдана `bic` (0.90);
              #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
              #   rules/roles.yml
              'clearingNumber' => nil,
              # TODO: роль поля не определена. Условно обязательно по спецификации.
              #   тип: string, minLength: 6, maxLength: 6
              #   описание из спецификации: "The 6-digit [sort
              #   code](https://en.wikipedia.org/wiki/Sort_code), without separators or whitespace."
              #   обоснование: роль bank_code отдана `bic` (0.90);
              #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
              #   rules/roles.yml
              'sortCode' => nil,
              # TODO: роль поля не определена. Условно обязательно по спецификации.
              #   тип: string, minLength: 9, maxLength: 9
              #   описание из спецификации: "The 9-digit [routing
              #   number](https://en.wikipedia.org/wiki/ABA_routing_transit_number), without
              #   separators or whitespace."
              #   обоснование: роль bank_code отдана `bic` (0.90);
              #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
              #   rules/roles.yml
              'routingNumber' => nil
            },
            # роль provider_operation_id выведена с уверенностью ниже порога (эвристика 0.21):
            # композитное сопоставление: name 2.0 (общие токены с синонимом `payment_id`: payment,
            # id (50%)), type 1.0 (type string допустим для роли) = 3.0 из 14.0; следующая
            # recipient_type 0.21 — проверьте по report.md
            'storedPaymentMethodId' => operation.provider_operation_key
          },
          card: {
            'cardHolder' => {
              address: {
                # TODO: роль поля не определена. Обязательно по спецификации.
                #   тип: string
                #   описание из спецификации: "The two-character ISO 3166-1 alpha-2 country code.
                #   For example, **US**, **NL**, or **GB**."
                #   обоснование: ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml
                #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
                #   rules/roles.yml
                country: nil
              },
              # роль external_id выведена с уверенностью ниже порога (эвристика 0.21): композитное
              # сопоставление: name 2.0 (общие токены с синонимом `client_reference`: reference
              # (50%)), type 1.0 (type string допустим для роли) = 3.0 из 14.0; следующая
              # provider_operation_id 0.21 — проверьте по report.md
              reference: operation.id
            },
            'cardIdentification' => {
              # роль provider_operation_id выведена с уверенностью ниже порога (эвристика 0.21):
              # композитное сопоставление: name 2.0 (общие токены с синонимом `payment_id`: payment,
              # id (50%)), type 1.0 (type string допустим для роли) = 3.0 из 14.0; следующая
              # recipient_type 0.21 — проверьте по report.md
              'storedPaymentMethodId' => operation.provider_operation_key
            }
          },
          # роль provider_operation_id выведена с уверенностью ниже порога (эвристика 0.26):
          # композитное сопоставление: name 2.7 (общие токены с синонимом `transfer_id`: transfer,
          # id (67%)), type 1.0 (type string допустим для роли) = 3.7 из 14.0; других кандидатов нет
          # — проверьте по report.md
          'transferInstrumentId' => operation.provider_operation_key
        },
        # роль provider_operation_id выведена с уверенностью ниже порога (эвристика 0.55):
        # композитное сопоставление: name 2.7 (общие токены с синонимом `payment_id`: payment, id
        # (67%)), structure 4.0 (родитель `TransferInfo` содержит токен `transfer` из подсказок
        # роли), type 1.0 (type string допустим для роли) = 7.7 из 14.0; других кандидатов нет —
        # проверьте по report.md
        'paymentInstrumentId' => operation.provider_operation_key,
        # роль external_id выведена с уверенностью ниже порога (эвристика 0.21): роль
        # provider_operation_id отдана `paymentInstrumentId` (0.55); композитное сопоставление: name
        # 2.0 (общие токены с синонимом `client_reference`: reference (50%)), type 1.0 (type string
        # допустим для роли) = 3.0 из 14.0; других кандидатов нет — проверьте по report.md
        reference: operation.id,
        'ultimateParty' => {
          address: {
            # TODO: роль поля не определена. Обязательно по спецификации.
            #   тип: string
            #   описание из спецификации: "The two-character ISO 3166-1 alpha-2 country code. For
            #   example, **US**, **NL**, or **GB**."
            #   обоснование: ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml
            #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
            #   rules/roles.yml
            country: nil
          },
          'fundingInstrument' => {
            'cardIdentification' => {
              # роль provider_operation_id выведена с уверенностью ниже порога (эвристика 0.21):
              # композитное сопоставление: name 2.0 (общие токены с синонимом `payment_id`: payment,
              # id (50%)), type 1.0 (type string допустим для роли) = 3.0 из 14.0; следующая
              # recipient_type 0.21 — проверьте по report.md
              'storedPaymentMethodId' => operation.provider_operation_key
            },
            # роль external_id выведена с уверенностью ниже порога (эвристика 0.21): композитное
            # сопоставление: name 2.0 (общие токены с синонимом `client_reference`: reference
            # (50%)), type 1.0 (type string допустим для роли) = 3.0 из 14.0; следующая
            # provider_operation_id 0.21 — проверьте по report.md
            reference: operation.id
          },
          # роль external_id выведена с уверенностью ниже порога (эвристика 0.21): композитное
          # сопоставление: name 2.0 (общие токены с синонимом `client_reference`: reference (50%)),
          # type 1.0 (type string допустим для роли) = 3.0 из 14.0; следующая provider_operation_id
          # 0.21 — проверьте по report.md
          reference: operation.id
        }
      }
      compact_payload(payload)
    end

    # Тело запроса операции post-grants по ролям полей схемы CapitalGrantInfo; nil-значения
    # убираются.
    def build_post_grants_payload(operation)
      payload = {
        counterparty: {
          # роль provider_operation_id выведена с уверенностью ниже порога (эвристика 0.26):
          # композитное сопоставление: name 2.7 (общие токены с синонимом `transfer_id`: transfer,
          # id (67%)), type 1.0 (type string допустим для роли) = 3.7 из 14.0; других кандидатов нет
          # — проверьте по report.md
          'transferInstrumentId' => operation.provider_operation_key
        },
        # TODO: роль поля не определена. Обязательно по спецификации.
        #   тип: string
        #   описание из спецификации: "The identifier of the grant account used for the grant."
        #   обоснование: ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml
        #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
        #   rules/roles.yml
        'grantAccountId' => nil,
        # TODO: роль поля не определена. Обязательно по спецификации.
        #   тип: string
        #   описание из спецификации: "The identifier of the grant offer that has been selected and
        #   from which the grant details will be used."
        #   обоснование: ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml
        #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
        #   rules/roles.yml
        'grantOfferId' => nil
      }
      compact_payload(payload)
    end

    # Тело запроса операции post-transfers-approve по ролям полей схемы ApproveTransfersRequest;
    # nil-значения убираются.
    def build_confirm_payload(_operation)
      payload = {}
      compact_payload(payload)
    end

    # Тело запроса операции post-transfers-cancel по ролям полей схемы CancelTransfersRequest;
    # nil-значения убираются.
    def build_cancel_payload(_operation)
      payload = {}
      compact_payload(payload)
    end

    # Тело запроса операции post-transfers-transferId-returns по ролям полей схемы
    # ReturnTransferRequest; nil-значения убираются.
    def build_refund_payload(operation)
      payload = {
        amount: {
          # TODO: роль currency выведена, но выражения платформы для неё нет. Обязательно по
          #       спецификации.
          #   тип: string
          #   описание из спецификации: "The three-character [ISO currency
          #   code](https://docs.adyen.com/development-resources/currency-codes#currency-codes) of
          #   the amount."
          #   где это лежит у платформы, знает только человек: заполните вручную или добавьте
          #   выражение в rules/contract.yml (раздел platform)
          currency: nil,
          value: to_provider_units(operation.amount)
        },
        # роль provider_operation_id выведена с уверенностью ниже порога (эвристика 0.50):
        # композитное сопоставление: name 2.0 (общие токены с синонимом `acquirer_reference`:
        # reference (50%)), structure 4.0 (родитель `ReturnTransferRequest` содержит токен
        # `transfer` из подсказок роли), type 1.0 (type string допустим для роли) = 7.0 из 14.0;
        # следующая external_id 0.21 — проверьте по report.md
        reference: operation.provider_operation_key
      }
      compact_payload(payload)
    end

    # Тело запроса операции post-cashouts по ролям полей схемы CashOutInfo; nil-значения убираются.
    def build_post_cashouts_payload(operation)
      payload = {
        amount: {
          # TODO: роль currency выведена, но выражения платформы для неё нет. Обязательно по
          #       спецификации.
          #   тип: string
          #   описание из спецификации: "The three-character [ISO currency
          #   code](https://docs.adyen.com/development-resources/currency-codes#currency-codes) of
          #   the amount."
          #   где это лежит у платформы, знает только человек: заполните вручную или добавьте
          #   выражение в rules/contract.yml (раздел platform)
          currency: nil,
          value: to_provider_units(operation.amount)
        },
        counterparty: {
          # роль provider_operation_id выведена с уверенностью ниже порога (эвристика 0.26):
          # композитное сопоставление: name 2.7 (общие токены с синонимом `transfer_id`: transfer,
          # id (67%)), type 1.0 (type string допустим для роли) = 3.7 из 14.0; других кандидатов нет
          # — проверьте по report.md
          'transferInstrumentId' => operation.provider_operation_key
        },
        fee: {
          amount: {
            # TODO: роль currency выведена, но выражения платформы для неё нет. Обязательно по
            #       спецификации.
            #   тип: string
            #   описание из спецификации: "The three-character [ISO currency
            #   code](https://docs.adyen.com/development-resources/currency-codes#currency-codes) of
            #   the amount."
            #   где это лежит у платформы, знает только человек: заполните вручную или добавьте
            #   выражение в rules/contract.yml (раздел platform)
            currency: nil,
            value: to_provider_units(operation.amount)
          }
        },
        id: operation.provider_operation_key,
        # TODO: роль поля не определена. Обязательно по спецификации.
        #   тип: string
        #   описание из спецификации: "The unique identifier of the balance account that initiates
        #   the cashout request."
        #   обоснование: ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml
        #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
        #   rules/roles.yml
        'instructingBalanceAccountId' => nil
      }
      compact_payload(payload)
    end

    # Заголовки запроса на создание: авторизация, тип содержимого и ключ идемпотентности.
    def request_headers(operation)
      auth_headers.merge('Content-Type' => 'application/json',
                         IDEMPOTENCY_HEADER => idempotency_key_for(operation))
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
      success(result: { id: body['id'] })
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
