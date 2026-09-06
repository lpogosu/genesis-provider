# frozen_string_literal: true

# Сгенерировано инструментом integrate из cardpay.yaml, версия спецификации
# 2.4.0, OpenAPI 3.0.3. Не редактируйте вручную: правки — в overlay
# (OpenAPI Overlay 1.0.0) и повторная генерация.
#
# Проверка файла:
#   ruby -c output/cardpay_service.rb
#   bundle exec rubocop --config config/rubocop_generated.yml output/cardpay_service.rb
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
  # Интеграция с провайдером «CardPay Global Payouts API»: предпроверки, создание
  # операции, обработка уведомлений и опрос статуса по контракту
  # Provider::BaseService. Таблицы статусов, ошибок и политики ретраев —
  # замороженные хеши, сверяемые с INTEGRATION.md; TODO отмечают места, где
  # спецификация не дала ответа и инструмент взял лучшего кандидата.
  class CardpayService < Provider::BaseService
    BASE_URL = ENV.fetch('CARDPAY_BASE_URL', 'https://api.sandbox.cardpay.example')
    # Таймауты в секундах; как передать их клиенту платформы, зависит от
    # клиента (его интерфейс — допущение), поэтому здесь только значения.
    OPEN_TIMEOUT = Integer(ENV.fetch('CARDPAY_OPEN_TIMEOUT', '5'))
    READ_TIMEOUT = Integer(ENV.fetch('CARDPAY_READ_TIMEOUT', '15'))
    PROVIDER = 'cardpay'
    # operation.amount — в мажорных единицах; провайдер ждёт minor (ISO 4217: экспонента USD 2,
    # валюта USD).
    AMOUNT_MULTIPLIER = 100
    # Валюта запроса: платформа её не сообщает, поле currency у операции есть не всегда — код взят
    # из спецификации (enum: [USD] у поля `currency`).
    CURRENCY = 'USD'
    DEFAULT_ERROR_ACTION = :reject
    DEDUP_STATUS = 409
    # Ключ идемпотентности отправляется всегда, даже если спецификация помечает заголовок
    # необязательным (параметр-заголовок X-Request-Id совпал с алиасом rules/idempotency.yml;
    # принимают: createTransfer).
    IDEMPOTENCY_HEADER = 'X-Request-Id'
    # Пространство имён UUID v5 (RFC 4122) для ключа идемпотентности: константа из
    # rules/idempotency.yml, менять нельзя — иначе повторы перестанут дедуплицироваться.
    IDEMPOTENCY_NAMESPACE = '6ba7b810-9dad-11d1-80b4-00c04fd430c8'
    CANCELLABLE_STATUSES = %i[in_progress].freeze
    # параметр-заголовок webhook-signature совпал с header_names rules/signatures.yml
    SIGNATURE_HEADER = 'webhook-signature'
    # профиль rules/signatures.yml standard_webhooks совпал по заголовку webhook-signature; описание
    # подтверждает: "HMAC-SHA256"
    SIGNATURE_ALGORITHM = 'SHA256'
    # профиль rules/signatures.yml standard_webhooks совпал по заголовку webhook-signature
    SIGNATURE_SECRET_KEY = :webhook_secret
    SIGNATURE_ID_HEADER = 'webhook-id'
    SIGNATURE_TIMESTAMP_HEADER = 'webhook-timestamp'
    # профиль rules/signatures.yml standard_webhooks совпал по заголовку webhook-signature
    SIGNATURE_TOLERANCE = 300
    SIGNATURE_VALUE_PREFIX = 'v1,'

    # Статус провайдера → внутренний статус платформы.
    STATUS_MAP = {
      'declined' => :rejected,
      'queued' => :in_progress,
      'returned' => :rejected,
      'sending' => :in_progress,
      'succeeded' => :approved
    }.freeze

    # Код ошибки провайдера или HTTP-код → действие платформы
    # (reject | retry | retry_backoff | alert | escalate). Дедупликация в
    # таблицу не входит: это успешный путь, см. DEDUP_STATUS.
    ERROR_MAP = {
      # По коду ошибки провайдера из тела ответа.
      'account_closed' => :reject,
      'card_declined' => :reject,
      'duplicate_request' => :reject,
      'expired_card' => :reject,
      'insufficient_funds' => :retry_backoff,
      'internal_error' => :retry_backoff,
      'invalid_card_number' => :reject,
      'issuer_unavailable' => :retry_backoff,
      'limit_exceeded' => :reject,
      'rate_limited' => :retry_backoff,
      'transfer_not_cancelable' => :reject,
      'transfer_not_found' => :reject,
      'unauthorized' => :alert,
      # По HTTP-коду, когда тело не несёт кода ошибки.
      400 => :reject,
      401 => :alert,
      404 => :reject,
      409 => :reject,
      422 => :reject,
      429 => :retry_backoff,
      500 => :retry_backoff
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
      statuses: [429, 500],
      retry_after_header: 'Retry-After',
      retry_after_statuses: [429]
    }.freeze

    # Событие уведомления → внутренний статус; nil — событие не сопоставлено.
    EVENT_MAP = {
      'transfer.declined' => :rejected,
      'transfer.queued' => :in_progress,
      'transfer.returned' => :rejected,
      'transfer.succeeded' => :approved
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

      # minimum: 500 в единицах провайдера = 5.00 USD в мажорных (задано явно 1.00)
      return failure(:unprocessable_entity, 'errors.amount_below_minimum') if operation.amount < 5
      # maximum: 5000000 в единицах провайдера = 50000.00 USD в мажорных (задано явно 1.00)
      if operation.amount > 50_000
        return failure(:unprocessable_entity, 'errors.amount_above_maximum')
      end

      # merchant_reference: maxLength 40 (задано явно 1.00)
      if operation.id.to_s.length > 40
        return failure(:unprocessable_entity, 'errors.external_id_too_long')
      end

      success
    end

    # Создание операции у провайдера: сборка тела запроса из ролей, перевод суммы в единицы
    # провайдера, заголовки авторизации и идемпотентности, разбор ответа и кодов ошибок.
    # @param operation [Object]
    # @param request_method [Object]
    # @return [Object] success | failure
    def create_request(operation, request_method = 'create')
      payload = build_payload(operation, request_method)
      url = "#{BASE_URL}/v2/transfers"
      response = client.post(url, payload, request_headers(operation))
      body = parse_json(response.body)
      return accept_created(operation, body) if response.status == 201
      # Повтор с тем же ключом идемпотентности: ответ с кодом конфликта несёт схему успешного
      # ответа, по draft-ietf-httpapi-idempotency-key-header это прежний результат, а не ошибка —
      # подхватываем существующую операцию.
      return accept_created(operation, body) if response.status == DEDUP_STATUS

      provider_failure(response, body)
    end

    # Обработка входящего уведомления: проверка подписи, сопоставление операции по идентификаторам,
    # перевод статуса провайдера во внутренний и вызов approve_operation или reject_operation.
    # @param payload [Object]
    # @return [Object] success | failure
    def process_callback(payload)
      problem = verify_signature!(payload)
      return problem if problem

      target = callback_target(payload)
      return failure(:not_found, 'errors.operation_not_found') if target.nil?

      internal = EVENT_MAP[payload['event_type']]
      return failure(:unprocessable_entity, 'errors.unknown_event') if internal.nil?

      apply_internal_status(target, internal)
    end

    # Опрос статуса операции у провайдера. Единственный путь получить статус, если провайдер не
    # отправляет вебхуки.
    # @param operation [Object]
    # @return [Object] success | failure
    def fetch_status(operation)
      url = "#{BASE_URL}/v2/transfers/#{operation.provider_operation_key}"
      response = client.get(url, auth_headers)
      body = parse_json(response.body)
      return failure(:not_found, 'errors.operation_not_found') if response.status == 404
      return provider_failure(response, body) unless response.status == 200

      internal = map_status(body['state'])
      return failure(:unprocessable_entity, 'errors.status_unknown') if internal.nil?

      apply_internal_status(operation, internal)
    end

    # Операция cancelTransfer (роль cancel, эвристика 0.95) не отображена на контракт BaseService:
    # отдельный публичный метод.
    # @param operation [Object]
    # @return [Object]
    def cancel(operation)
      # Отмена возможна только в статусах провайдера queued (эвристика 0.60), во внутренних терминах
      # — CANCELLABLE_STATUSES.
      unless CANCELLABLE_STATUSES.include?(operation.status)
        return failure(:unprocessable_entity, 'errors.cancel_not_allowed')
      end

      url = "#{BASE_URL}/v2/transfers/#{operation.provider_operation_key}/cancel"
      response = client.post(url, {}, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 200

      accept_response(operation, body)
    end

    # Операция createRefund (роль refund, эвристика 0.92) не отображена на контракт BaseService:
    # отдельный публичный метод.
    # @param operation [Object]
    # @return [Object]
    def refund(operation)
      payload = build_refund_payload(operation)
      url = "#{BASE_URL}/v2/refunds"
      response = client.post(url, payload, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 201

      body
    end

    # Операция getAccountBalance (роль balance, эвристика 0.95) не отображена на контракт
    # BaseService: отдельный публичный метод.
    # @return [Object]
    def balance
      url = "#{BASE_URL}/v2/accounts/balance"
      response = client.get(url, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 200

      body
    end

    # Проверяет подпись входящего уведомления до любой другой логики: сравнение константное по
    # времени, отсутствующий заголовок — отказ.
    # @param raw_body [String]
    # @param headers [Hash]
    # @return [Object, nil] результат отказа или nil, если подпись верна
    def verify_webhook_signature(raw_body, headers)
      given = header_value(headers, SIGNATURE_HEADER)
      return failure(:unauthorized, 'errors.signature_missing') if given.nil?

      timestamp = header_value(headers, SIGNATURE_TIMESTAMP_HEADER)
      return failure(:unauthorized, 'errors.signature_missing') if timestamp.nil?
      if (Time.now.to_i - timestamp.to_i).abs > SIGNATURE_TOLERANCE
        return failure(:unauthorized, 'errors.signature_expired')
      end

      signed = [header_value(headers, SIGNATURE_ID_HEADER), timestamp, raw_body].join('.')

      secret = provider.credentials[SIGNATURE_SECRET_KEY]
      expected = [OpenSSL::HMAC.digest(SIGNATURE_ALGORITHM, secret, signed)].pack('m0')
      unless signature_matches?(expected, given)
        return failure(:unauthorized, 'errors.signature_invalid')
      end

      nil
    end

    private

    # Тело запроса по ролям полей схемы CreateTransferRequest; nil-значения убираются.
    def build_payload(operation, request_method)
      payload = {
        amount_minor: to_provider_units(operation.amount),
        currency: CURRENCY,
        merchant_reference: operation.id,
        destination: destination_requisites(operation, request_method)
      }
      compact_payload(payload)
    end

    # Реквизиты получателя для тела запроса (поле destination). Форма хеша
    # operation.payout_requisite задана платформой и зависит от способа выплаты, поэтому ветка по
    # request_method (он же payment_method шлюза), а состав полей в ветке — из условной
    # обязательности спецификации.
    # @param operation [Object]
    # @param request_method [Object]
    # @return [Hash] реквизиты получателя; nil-значения убираются в build_payload
    def destination_requisites(operation, request_method)
      case request_method
      when 'card'
        {
          method: 'card',
          # обязательно при method = card (намёк в описании 0.50)
          pan: operation.payout_requisite['card_number'],
          # TODO: роль поля не определена. Условно обязательно по спецификации.
          #   тип: integer, minimum: 1, maximum: 12
          #   описание из спецификации: "Card expiry month, 1 to 12. Required when method is card."
          #   обоснование: ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml
          #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
          #   rules/roles.yml
          expiry_month: 11,
          # TODO: роль поля не определена. Условно обязательно по спецификации.
          #   тип: integer, minimum: 2026, maximum: 2050
          #   описание из спецификации: "Card expiry year, four digits. Required when method is
          #   card."
          #   обоснование: ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml
          #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
          #   rules/roles.yml
          expiry_year: 2029
        }
      when 'wallet'
        # TODO: способ выплаты платформы для значения wallet неизвестен: в таблице requisites
        #       (rules/contract.yml) такого ключа нет. Взято значение спецификации — сверьте его с
        #       payment_method шлюза и опишите, где эти реквизиты лежат в operation.payout_requisite
        {
          method: 'wallet',
          # TODO: роль поля не определена. Условно обязательно по спецификации.
          #   тип: string, maxLength: 32
          #   описание из спецификации: "Identifier of the beneficiary wallet account. Required when
          #   method is wallet."
          #   обоснование: ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml
          #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
          #   rules/roles.yml
          wallet_id: 'wlt_5KD2H8ZQ'
        }
      else
        # TODO: способ выплаты вне card, wallet: спецификация его не объявляла, собрать реквизиты не
        #       из чего
        {}
      end
    end

    # Тело запроса операции createRefund по ролям полей схемы RefundRequest; nil-значения убираются.
    def build_refund_payload(operation)
      payload = {
        transfer_id: operation.provider_operation_key,
        merchant_reference: operation.id,
        amount_minor: to_provider_units(operation.amount)
      }
      compact_payload(payload)
    end

    # Заголовки запроса на создание: авторизация, тип содержимого и ключ идемпотентности.
    def request_headers(operation)
      auth_headers.merge('Content-Type' => 'application/json',
                         IDEMPOTENCY_HEADER => idempotency_key_for(operation))
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
      apply_internal_status(operation, map_status(body['state']))
      success(result: { id: body['transfer_id'] })
    end

    # Успешный ответ провайдера на отмену или подтверждение: перевести статус, если он пришёл и
    # знаком; незнакомый статус оставляет операцию in_progress. Результата у метода нет — статус
    # меняют хелперы.
    def accept_response(operation, body)
      internal = map_status(body['state'])
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
      code = body.dig('error', 'code')
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

    # Подпись по аргументу process_callback: аргумент — уже разобранный JSON, сырые байты тела
    # берутся из него по выражениям rules/contract.yml. Если маршрут вебхука их не передал, вызовите
    # verify_webhook_signature до разбора тела.
    # @param payload [Object]
    # @return [Object, nil] результат отказа или nil, если подпись верна
    def verify_signature!(payload)
      raw_body = payload['raw_body']
      headers = payload['headers']
      return nil if raw_body.nil? || headers.nil?

      verify_webhook_signature(raw_body, headers)
    end

    # Значение заголовка — список версий через пробел с префиксом; совпадение любой версии
    # принимается.
    def signature_matches?(expected, given)
      given.split.any? do |item|
        secure_equal?(expected, item.delete_prefix(SIGNATURE_VALUE_PREFIX))
      end
    end

    # Значение заголовка без учёта регистра имени; nil, если заголовка нет.
    def header_value(headers, name)
      return nil if name.nil? || headers.nil?

      headers.find { |key, _value| key.to_s.casecmp?(name) }&.last
    end

    # Константное по времени сравнение строк одинаковой длины (OpenSSL.fixed_length_secure_compare);
    # разная длина — false, а не исключение.
    def secure_equal?(expected, given)
      return false unless expected.to_s.bytesize == given.to_s.bytesize

      OpenSSL.fixed_length_secure_compare(expected.to_s, given.to_s)
    end

    # Кого касается уведомление: идентификатор операции у провайдера, потом внешний — он может быть
    # необязательным. Поиск операции в хранилище происходит вне сервиса провайдера.
    def callback_target(payload)
      payload['transfer_id'] || payload['merchant_reference']
    end
  end
end
