# frozen_string_literal: true

# Сгенерировано инструментом integrate из broken.yaml, версия спецификации
# 0.1, OpenAPI 3.0.3. Не редактируйте вручную: правки — в overlay
# (OpenAPI Overlay 1.0.0) и повторная генерация.
#
# Проверка файла:
#   ruby -c output/broken_service.rb
#   bundle exec rubocop --config config/rubocop_generated.yml output/broken_service.rb
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
  # Интеграция с провайдером «Payment Gateway»: предпроверки, создание
  # операции, обработка уведомлений и опрос статуса по контракту
  # Provider::BaseService. Таблицы статусов, ошибок и политики ретраев —
  # замороженные хеши, сверяемые с INTEGRATION.md; TODO отмечают места, где
  # спецификация не дала ответа и инструмент взял лучшего кандидата.
  class BrokenService < Provider::BaseService
    # TODO: среда серверов не выведена, взят первый из списка — проверьте, что это песочница
    BASE_URL = ENV.fetch('BROKEN_BASE_URL', 'https://api.gateway.example/v1')
    # Таймауты в секундах; как передать их клиенту платформы, зависит от
    # клиента (его интерфейс — допущение), поэтому здесь только значения.
    OPEN_TIMEOUT = Integer(ENV.fetch('BROKEN_OPEN_TIMEOUT', '5'))
    READ_TIMEOUT = Integer(ENV.fetch('BROKEN_READ_TIMEOUT', '15'))
    PROVIDER = 'broken'
    # TODO: единицы суммы не выведены (без кода валюты экспоненту ISO 4217 определить нельзя);
    #       множитель 1 — задайте x-specgen-amount-unit и x-specgen-exponent в overlay
    AMOUNT_MULTIPLIER = 1
    DEFAULT_ERROR_ACTION = :reject
    # Пространство имён UUID v5 (RFC 4122) для ключа идемпотентности: константа из
    # rules/idempotency.yml, менять нельзя — иначе повторы перестанут дедуплицироваться.
    IDEMPOTENCY_NAMESPACE = '6ba7b810-9dad-11d1-80b4-00c04fd430c8'
    # TODO: header подписи не выведен (спецификация не описывает подпись уведомлений — заголовок
    #       неизвестен, метод всегда отказывает; задайте x-specgen-signature в overlay); взято
    #       значение по умолчанию
    SIGNATURE_HEADER = nil
    # TODO: algorithm подписи не выведен (спецификация не описывает подпись уведомлений — заголовок
    #       неизвестен, метод всегда отказывает; задайте x-specgen-signature в overlay); взято
    #       значение по умолчанию
    SIGNATURE_ALGORITHM = 'SHA256'
    # TODO: secret_key подписи не выведен (спецификация не описывает подпись уведомлений — заголовок
    #       неизвестен, метод всегда отказывает; задайте x-specgen-signature в overlay); взято
    #       значение по умолчанию
    SIGNATURE_SECRET_KEY = :webhook_secret

    # Статус провайдера → внутренний статус платформы.
    STATUS_MAP = {
      'DONE' => :approved,
      # TODO: статус не сопоставлен: статус IN_REVIEW не найден ни в каноне, ни среди синонимов
      #       rules/statuses.yml; задайте x-specgen-status-map в overlay
      'IN_REVIEW' => nil,
      # TODO: статус не сопоставлен: статус NOTOK не найден ни в каноне, ни среди синонимов
      #       rules/statuses.yml; задайте x-specgen-status-map в overlay
      'NOTOK' => nil,
      # TODO: статус не сопоставлен: статус PART_DONE целиком не найден ни в каноне, ни среди
      #       синонимов rules/statuses.yml; как статус читается только хвост done (approved), но
      #       ведущее слово `part` меняет смысл (modifiers rules/statuses.yml) — снимать его нельзя;
      #       задайте x-specgen-status-map в overlay
      'PART_DONE' => nil,
      'WAITING' => :in_progress
    }.freeze

    # Код ошибки провайдера или HTTP-код → действие платформы
    # (reject | retry | retry_backoff | alert | escalate). Дедупликация в
    # таблицу не входит: это успешный путь, см. DEDUP_STATUS.
    ERROR_MAP = {
      # По коду ошибки провайдера из тела ответа.
      'E100' => :reject,
      'E200' => :reject,
      'E300' => :reject,
      'E777' => :reject,
      'E999' => :reject,
      # По HTTP-коду, когда тело не несёт кода ошибки.
      400 => :reject
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

    # Событие уведомления → внутренний статус; nil — событие не сопоставлено.
    EVENT_MAP = {
      'DONE' => :approved,
      # TODO: событие не сопоставлено: поле события не найдено, событие читается по значению поля
      #       статуса `st`; статус IN_REVIEW не найден ни в каноне, ни среди синонимов
      #       rules/statuses.yml; задайте x-specgen-status-map в overlay
      'IN_REVIEW' => nil,
      # TODO: событие не сопоставлено: поле события не найдено, событие читается по значению поля
      #       статуса `st`; статус NOTOK не найден ни в каноне, ни среди синонимов
      #       rules/statuses.yml; задайте x-specgen-status-map в overlay
      'NOTOK' => nil,
      # TODO: событие не сопоставлено: поле события не найдено, событие читается по значению поля
      #       статуса `st`; статус PART_DONE целиком не найден ни в каноне, ни среди синонимов
      #       rules/statuses.yml; как статус читается только хвост done (approved), но ведущее слово
      #       `part` меняет смысл (modifiers rules/statuses.yml) — снимать его нельзя; задайте
      #       x-specgen-status-map в overlay
      'PART_DONE' => nil,
      'WAITING' => :in_progress
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
    # @param operation [Object]
    # @param request_method [Object]
    # @return [Object] success | failure
    def create_request(operation, _request_method = 'create')
      payload = build_payload(operation)
      url = "#{BASE_URL}/transactions"
      response = client.post(url, payload, request_headers)
      body = parse_json(response.body)
      return accept_created(operation, body) if response.status == 200

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

      internal = map_status(payload['st'])
      return failure(:unprocessable_entity, 'errors.unknown_event') if internal.nil?

      apply_internal_status(target, internal)
    end

    # Опрос статуса операции у провайдера. Единственный путь получить статус, если провайдер не
    # отправляет вебхуки.
    # @param operation [Object]
    # @return [Object] success | failure
    def fetch_status(operation)
      # TODO: параметр пути {ref} без роли — подставлен operation.provider_operation_key; задайте
      #       x-specgen-role в overlay
      url = "#{BASE_URL}/transactions/#{operation.provider_operation_key}"
      response = client.get(url, auth_headers)
      body = parse_json(response.body)
      return failure(:not_found, 'errors.operation_not_found') if response.status == 404
      return provider_failure(response, body) unless response.status == 200

      internal = map_status(body['st'])
      return failure(:unprocessable_entity, 'errors.status_unknown') if internal.nil?

      apply_internal_status(operation, internal)
    end

    # Операция post_transactions_ref_void (роль cancel, эвристика 0.95) не отображена на контракт
    # BaseService: отдельный публичный метод.
    # @param operation [Object]
    # @return [Object]
    def cancel(operation)
      # TODO: параметр пути {ref} без роли — подставлен operation.provider_operation_key; задайте
      #       x-specgen-role в overlay
      url = "#{BASE_URL}/transactions/#{operation.provider_operation_key}/void"
      response = client.post(url, {}, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 200

      accept_response(operation, body)
    end

    # Операция get_reports_daily (роль unmapped, эвристика 0.00) не отображена на контракт
    # BaseService: отдельный публичный метод.
    # TODO: роль операции не распознана (ни один сигнал не совпал ни с одной ролью) — проверьте,
    #       нужна ли она интеграции
    # @return [Object]
    def reports_daily
      url = "#{BASE_URL}/reports/daily"
      response = client.get(url, auth_headers)
      body = parse_json(response.body)
      return provider_failure(response, body) unless response.status == 200

      body
    end

    # Операция get_limits (роль balance, эвристика 0.95) не отображена на контракт BaseService:
    # отдельный публичный метод.
    # @return [Object]
    def balance
      url = "#{BASE_URL}/limits"
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
      # TODO: спецификация не описывает подпись уведомлений — заголовок неизвестен, метод всегда
      #       отказывает; задайте x-specgen-signature в overlay
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

    # Тело запроса по ролям полей схемы TxnCreate; nil-значения убираются.
    def build_payload(operation)
      payload = {
        # роль amount выведена с уверенностью ниже порога (эвристика 0.43): композитное
        # сопоставление: name 5.0 (токен `amt` из подсказок роли amount (rules/roles.yml)), type 1.0
        # (type integer допустим для роли) = 6.0 из 14.0; других кандидатов нет — проверьте по
        # report.md
        amt: to_provider_units(operation.amount),
        # TODO: роль поля не определена. Обязательно по спецификации.
        #   тип: string
        #   обоснование: ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml
        #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
        #   rules/roles.yml
        cur: nil,
        # TODO: роль поля не определена. Обязательно по спецификации.
        #   тип: string, maxLength: 32
        #   обоснование: ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml
        #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
        #   rules/roles.yml
        xref_tag_9: nil,
        party: {
          # TODO: роль поля не определена. Обязательно по спецификации.
          #   тип: string, enum: P2P, CARD, ACC
          #   обоснование: ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml
          #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
          #   rules/roles.yml
          kind: nil,
          # TODO: роль поля не определена. Обязательно по спецификации.
          #   тип: string, maxLength: 34
          #   обоснование: ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml
          #   заполните вручную или задайте x-specgen-role в overlay / добавьте синоним в
          #   rules/roles.yml
          acct: nil
        }
      }
      compact_payload(payload)
    end

    # Заголовки запроса на создание: авторизация и тип содержимого.
    def request_headers
      auth_headers.merge('Content-Type' => 'application/json')
    end

    # Заголовки авторизации: схема ApiKey (api_key) по записи rules/auth.yml «api_key_header».
    # Секрет читается из provider.credentials.
    # @return [Hash]
    def auth_headers
      { 'X-Key' => provider.credentials[:api_key] }
    end

    # Успешный ответ на создание: перевести статус и вернуть платформе идентификатор операции у
    # провайдера — она сохраняет его как provider_operation_key из result[:id].
    def accept_created(operation, body)
      apply_internal_status(operation, map_status(body['st']))
      # TODO: в успешном ответе нет поля с ролью provider_operation_id — вернуть платформе нечего, и
      #       она не сохранит provider_operation_key; укажите поле через x-specgen-role в overlay
      success
    end

    # Успешный ответ провайдера на отмену или подтверждение: перевести статус, если он пришёл и
    # знаком; незнакомый статус оставляет операцию in_progress. Результата у метода нет — статус
    # меняют хелперы.
    def accept_response(operation, body)
      internal = map_status(body['st'])
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
      code = body['err']
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
    def callback_target(_payload)
      # TODO: в схеме уведомления нет полей с ролями provider_operation_id / external_id — понять,
      #       какой операции касается уведомление, не по чему
      nil
    end
  end
end
