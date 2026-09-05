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
    # Валюта запроса: платформа её не сообщает, поле currency у операции есть не всегда — код взят
    # из спецификации (enum: [RUB] у поля `currency`).
    CURRENCY = 'RUB'
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
      'amount_limit_exceeded' => :reject,
      'bank_unavailable' => :retry_backoff,
      'insufficient_balance' => :retry_backoff,
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
      402 => :retry_backoff,
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
      statuses: [402, 429, 500],
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
        return failure(:unprocessable_entity, 'errors.amount_below_minimum')
      end

      # external_id: maxLength 64 (задано явно 1.00)
      if operation.id.to_s.length > 64
        return failure(:unprocessable_entity, 'errors.external_id_too_long')
      end

      # phone: pattern ^7\d{10}$ (задано явно 1.00)
      # TODO: условие для поля phone: значение зависит от способа выплаты и собирается в
      #       recipient_requisites — проверьте его там, где способ выплаты известен
      success
    end

    # Создание операции у провайдера: сборка тела запроса из ролей, перевод суммы в единицы
    # провайдера, заголовки авторизации и идемпотентности, разбор ответа и кодов ошибок.
    # @param operation [Object]
    # @param request_method [Object]
    # @return [Object] success | failure
    def create_request(operation, request_method = 'create')
      payload = build_payload(operation, request_method)
      url = "#{BASE_URL}/payouts"
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

      internal = EVENT_MAP[payload['event']]
      return failure(:unprocessable_entity, 'errors.unknown_event') if internal.nil?

      apply_internal_status(target, internal)
    end

    # Опрос статуса операции у провайдера. Единственный путь получить статус, если провайдер не
    # отправляет вебхуки.
    # @param operation [Object]
    # @return [Object] success | failure
    def fetch_status(operation)
      url = "#{BASE_URL}/payouts/#{operation.provider_operation_key}"
      response = client.get(url, auth_headers)
      body = parse_json(response.body)
      return failure(:not_found, 'errors.operation_not_found') if response.status == 404
      return provider_failure(response, body) unless response.status == 200

      internal = map_status(body['status'])
      return failure(:unprocessable_entity, 'errors.status_unknown') if internal.nil?

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
        return failure(:unprocessable_entity, 'errors.cancel_not_allowed')
      end

      url = "#{BASE_URL}/payouts/#{operation.provider_operation_key}/cancel"
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

    # Проверяет подпись входящего уведомления до любой другой логики: сравнение константное по
    # времени, отсутствующий заголовок — отказ.
    # @param raw_body [String]
    # @param headers [Hash]
    # @return [Object, nil] результат отказа или nil, если подпись верна
    def verify_webhook_signature(raw_body, headers)
      given = header_value(headers, SIGNATURE_HEADER)
      return failure(:unauthorized, 'errors.signature_missing') if given.nil?

      secret = provider.credentials[SIGNATURE_SECRET_KEY]
      expected = OpenSSL::HMAC.hexdigest(SIGNATURE_ALGORITHM, secret, raw_body)
      unless secure_equal?(expected, given)
        return failure(:unauthorized, 'errors.signature_invalid')
      end

      nil
    end

    private

    # Тело запроса по ролям полей схемы CreatePayoutRequest; nil-значения убираются.
    def build_payload(operation, request_method)
      payload = {
        amount: to_provider_units(operation.amount),
        currency: CURRENCY,
        external_id: operation.id,
        recipient: recipient_requisites(operation, request_method)
      }
      compact_payload(payload)
    end

    # Реквизиты получателя для тела запроса (поле recipient). Форма хеша operation.payout_requisite
    # задана платформой и зависит от способа выплаты, поэтому ветка по request_method (он же
    # payment_method шлюза), а состав полей в ветке — из условной обязательности спецификации.
    # @param operation [Object]
    # @param request_method [Object]
    # @return [Hash] реквизиты получателя; nil-значения убираются в build_payload
    def recipient_requisites(operation, request_method)
      case request_method
      when 'sbp'
        {
          type: 'sbp',
          phone: operation.payout_requisite.dig('sbp', 'phone'),
          # обязательно при type = sbp (намёк в описании 0.50)
          bank_code: operation.payout_requisite.dig('sbp', 'bank_code'),
          bank_name: operation.payout_requisite.dig('sbp', 'bank_name')
        }
      when 'card'
        {
          type: 'card',
          # TODO: роль recipient_phone выведена, но выражения платформы для неё нет. Обязательно по
          #       спецификации.
          #   тип: string, pattern: ^7\d{10}$
          #   описание из спецификации: "Телефон получателя (11 цифр, начинается с 7)"
          #   где это лежит у платформы, знает только человек: заполните вручную или добавьте
          #   выражение в rules/contract.yml (раздел platform)
          phone: nil,
          # обязательно при type = card (намёк в описании 0.50)
          card_number: operation.payout_requisite['card_number']
        }
      else
        # TODO: способ выплаты вне sbp, card: спецификация его не объявляла, собрать реквизиты не из
        #       чего
        {}
      end
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
      payload['payout_id'] || payload['external_id']
    end
  end
end
