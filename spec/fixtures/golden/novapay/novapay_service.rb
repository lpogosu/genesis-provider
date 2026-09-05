# frozen_string_literal: true

# Сгенерировано инструментом integrate из novapay.yaml, версия спецификации
# 1.0.0, OpenAPI 3.0.3. Не редактируйте вручную: правки — в overlay
# (OpenAPI Overlay 1.0.0) и повторная генерация.
#
# Проверка файла:
#   ruby -c output/novapay_service.rb
#   bundle exec rubocop --config config/rubocop_generated.yml output/novapay_service.rb
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
  # Интеграция с провайдером «NovaPay Payout API»: предпроверки, создание
  # операции, обработка уведомлений и опрос статуса по контракту
  # Provider::BaseService. Таблицы статусов, ошибок и политики ретраев —
  # замороженные хеши, сверяемые с INTEGRATION.md; TODO отмечают места, где
  # спецификация не дала ответа и инструмент взял лучшего кандидата.
  class NovapayService < Provider::BaseService
    BASE_URL = ENV.fetch('NOVAPAY_BASE_URL', 'https://api.sandbox.novapay.example/v1')
    # Таймауты в секундах; как передать их клиенту платформы, зависит от
    # клиента (его интерфейс — допущение), поэтому здесь только значения.
    OPEN_TIMEOUT = Integer(ENV.fetch('NOVAPAY_OPEN_TIMEOUT', '5'))
    READ_TIMEOUT = Integer(ENV.fetch('NOVAPAY_READ_TIMEOUT', '15'))
    PROVIDER = 'novapay'
    # operation.amount — в мажорных единицах; провайдер ждёт minor (ISO 4217: экспонента RUB 2,
    # валюта RUB).
    AMOUNT_MULTIPLIER = 100
    DEFAULT_ERROR_ACTION = :reject
    DEDUP_STATUS = 409
    # Ключ идемпотентности отправляется всегда, даже если спецификация помечает заголовок
    # необязательным (параметр-заголовок Idempotency-Key совпал с алиасом rules/idempotency.yml;
    # принимают: createPayout; объявлен required: false, но по rules/idempotency.yml
    # (send_when_optional) ключ отправляется всегда).
    IDEMPOTENCY_HEADER = 'Idempotency-Key'
    # Пространство имён UUID v5 (RFC 4122) для ключа идемпотентности: константа из
    # rules/idempotency.yml, менять нельзя — иначе повторы перестанут дедуплицироваться.
    IDEMPOTENCY_NAMESPACE = '6ba7b810-9dad-11d1-80b4-00c04fd430c8'
    CANCELLABLE_STATUSES = %i[in_progress].freeze
    # параметр-заголовок X-NovaPay-Signature совпал с header_names rules/signatures.yml
    SIGNATURE_HEADER = 'X-NovaPay-Signature'
    # профиль rules/signatures.yml novapay совпал по заголовку X-NovaPay-Signature; описание
    # подтверждает: "HMAC-SHA256"
    SIGNATURE_ALGORITHM = 'SHA256'
    # профиль rules/signatures.yml novapay совпал по заголовку X-NovaPay-Signature
    SIGNATURE_SECRET_KEY = :webhook_secret

    # Статус провайдера → внутренний статус платформы.
    STATUS_MAP = {
      'cancelled' => :rejected,
      'completed' => :approved,
      'failed' => :rejected,
      'pending' => :in_progress,
      'processing' => :in_progress
    }.freeze

    # Код ошибки провайдера или HTTP-код → действие платформы
    # (reject | retry | retry_backoff | alert | escalate). Дедупликация в
    # таблицу не входит: это успешный путь, см. DEDUP_STATUS.
    ERROR_MAP = {
      # По коду ошибки провайдера из тела ответа.
      'amount_limit_exceeded' => :escalate,
      'bank_unavailable' => :retry_backoff,
      'insufficient_balance' => :escalate,
      'internal_error' => :retry_backoff,
      'invalid_status' => :reject,
      'not_found' => :reject,
      'rate_limit_exceeded' => :retry_backoff,
      'recipient_not_found' => :reject,
      'unauthorized' => :alert,
      'validation_error' => :reject,
      # По HTTP-коду, когда тело не несёт кода ошибки.
      400 => :reject,
      401 => :alert,
      402 => :escalate,
      404 => :reject,
      409 => :reject,
      422 => :reject,
      429 => :retry_backoff,
      500 => :retry_backoff
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
      'payout.cancelled' => :rejected,
      'payout.completed' => :approved,
      'payout.failed' => :rejected,
      'payout.processing' => :in_progress
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

      # minimum: 100000 в единицах провайдера = 1000.00 RUB в мажорных (задано явно 1.00)
      if operation.amount < 1000
        return failure(:amount_below_minimum, 'errors.amount_below_minimum')
      end

      # currency: допустимые значения RUB (задано явно 1.00)
      unless %w[RUB].include?(operation.currency)
        return failure(:currency_not_allowed, 'errors.currency_not_allowed')
      end

      # external_id: maxLength 64 (задано явно 1.00)
      if operation.id.to_s.length > 64
        return failure(:external_id_too_long, 'errors.external_id_too_long')
      end

      # type: допустимые значения sbp, card (задано явно 1.00)
      unless %w[sbp card].include?(operation.recipient_type)
        return failure(:recipient_type_not_allowed, 'errors.recipient_type_not_allowed')
      end

      # phone: pattern ^7\d{10}$ (задано явно 1.00)
      unless operation.recipient_phone.to_s.match?(/^7\d{10}$/)
        return failure(:recipient_phone_invalid_format, 'errors.recipient_phone_invalid_format')
      end

      success
    end

    # Создание операции у провайдера: сборка тела запроса из ролей, перевод суммы в единицы
    # провайдера, заголовки авторизации и идемпотентности, разбор ответа и кодов ошибок.
    # @param operation [Object]
    # @param request_method [Object]
    # @return [Object] success | failure
    def create_request(operation, _request_method = 'create')
      payload = build_payload(operation)
      url = "#{BASE_URL}/payouts"
      response = client.post(url, payload, request_headers(operation))
      body = parse_json(response.body)
      return accept_response(operation, body) if response.status == 201
      # Повтор с тем же ключом идемпотентности: ответ с кодом конфликта несёт схему успешного
      # ответа, по draft-ietf-httpapi-idempotency-key-header это прежний результат, а не ошибка —
      # подхватываем существующую операцию.
      return accept_response(operation, body) if response.status == DEDUP_STATUS

      provider_failure(response, body)
    end

    # Обработка входящего уведомления: проверка подписи, сопоставление операции по идентификаторам,
    # перевод статуса провайдера во внутренний и вызов approve_operation или reject_operation.
    # @param payload [Object]
    # @return [Object] success | failure
    def process_callback(payload)
      raw_body = payload[:body].to_s
      headers = payload[:headers] || {}
      problem = verify_signature!(raw_body, headers)
      return problem if problem

      body = parse_json(raw_body)
      operation = find_callback_operation(body)
      return failure(:operation_not_found, 'errors.operation_not_found') if operation.nil?

      internal = EVENT_MAP[body['event']]
      return failure(:unknown_event, 'errors.unknown_event') if internal.nil?

      apply_internal_status(operation, internal)
    end

    # Опрос статуса операции у провайдера. Единственный путь получить статус, если провайдер не
    # отправляет вебхуки.
    # @param operation [Object]
    # @return [Object] success | failure
    def fetch_status(operation)
      url = "#{BASE_URL}/payouts/#{operation.provider_operation_id}"
      response = client.get(url, auth_headers)
      body = parse_json(response.body)
      return failure(:operation_not_found, 'errors.operation_not_found') if response.status == 404
      return provider_failure(response, body) unless response.status == 200

      internal = map_status(body['status'])
      return failure(:status_unknown, 'errors.status_unknown') if internal.nil?

      apply_internal_status(operation, internal)
    end

    # Операция cancelPayout (роль cancel, эвристика 0.95) не отображена на контракт BaseService:
    # отдельный публичный метод.
    # @param operation [Object]
    # @return [Object]
    def cancel(operation)
      # Отмена возможна только в статусах провайдера pending, processing (эвристика 0.60), во
      # внутренних терминах — CANCELLABLE_STATUSES.
      unless CANCELLABLE_STATUSES.include?(operation.status)
        return failure(:cancel_not_allowed, 'errors.cancel_not_allowed')
      end

      url = "#{BASE_URL}/payouts/#{operation.provider_operation_id}/cancel"
      response = client.post(url, {}, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 200

      accept_response(operation, body)
    end

    # Операция getBalance (роль balance, эвристика 0.93) не отображена на контракт BaseService:
    # отдельный публичный метод.
    # @return [Object]
    def balance
      url = "#{BASE_URL}/balance"
      response = client.get(url, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 200

      body
    end

    private

    # Тело запроса по ролям полей схемы CreatePayoutRequest; nil-значения убираются.
    def build_payload(operation)
      payload = {
        amount: to_provider_units(operation.amount),
        currency: operation.currency,
        external_id: operation.id,
        recipient: {
          type: operation.recipient_type,
          phone: operation.recipient_phone,
          # обязательно при type = sbp (намёк в описании 0.50)
          bank_code: operation.bank_code,
          bank_name: operation.bank_name,
          # обязательно при type = card (намёк в описании 0.50)
          card_number: operation.card_number
        }
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

    # Успешный ответ провайдера: запомнить его идентификатор и перевести статус, если он пришёл и
    # знаком; незнакомый статус оставляет операцию in_progress.
    def accept_response(operation, body)
      provider_id = body['id']
      operation.update(provider_operation_id: provider_id) if provider_id
      internal = map_status(body['status'])
      return success if internal.nil?

      apply_internal_status(operation, internal)
    end

    # Перевод операции во внутренний статус хелперами базового класса; in_progress ничего не меняет.
    def apply_internal_status(operation, internal)
      case internal
      when :approved then approve_operation(operation)
      when :rejected then reject_operation(operation)
      end
      success
    end

    # Статус провайдера → внутренний по STATUS_MAP; nil для незнакомого.
    def map_status(raw)
      STATUS_MAP[raw.to_s]
    end

    # Ответ с ошибкой: действие по ERROR_MAP (сначала код провайдера, потом HTTP-код), символ
    # действия — код отказа для платформы.
    def provider_failure(response, body)
      code = body.dig('error', 'code')
      action = ERROR_MAP[code] || ERROR_MAP[response.status] || DEFAULT_ERROR_ACTION
      failure(action, "errors.#{code || response.status}")
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

    # Проверяет подпись входящего уведомления до любой другой логики: сравнение константное по
    # времени, отсутствующий заголовок — отказ.
    # @param raw_body [String]
    # @param headers [Hash]
    # @return [Object, nil] результат отказа или nil, если подпись верна
    def verify_signature!(raw_body, headers)
      given = header_value(headers, SIGNATURE_HEADER)
      return failure(:signature_missing, 'errors.signature_missing') if given.nil?

      secret = provider.credentials[SIGNATURE_SECRET_KEY]
      expected = OpenSSL::HMAC.hexdigest(SIGNATURE_ALGORITHM, secret, raw_body)
      unless secure_equal?(expected, given)
        return failure(:signature_invalid, 'errors.signature_invalid')
      end

      nil
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

    # Операция платформы по идентификаторам из уведомления: сначала идентификатор провайдера, потом
    # внешний — он может быть необязательным.
    def find_callback_operation(body)
      Operation.find_by(provider_operation_id: body['payout_id']) ||
        Operation.find_by(id: body['external_id'])
    end
  end
end
