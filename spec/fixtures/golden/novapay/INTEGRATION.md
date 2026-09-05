# Интеграция с провайдером «NovaPay Payout API»

| | |
|---|---|
| Провайдер | `novapay` |
| Спецификация | `novapay.yaml`, версия 1.0.0, OpenAPI 3.0.3 |
| Класс сервиса | `Provider::NovapayService < Provider::BaseService` |
| Файл сервиса | `novapay_service.rb` |

Документ сгенерирован инструментом integrate из той же модели провайдера,
что и сервис: таблицы ниже совпадают с константами `STATUS_MAP`, `EVENT_MAP`,
`ERROR_MAP` и `RETRY_POLICY` по построению. Не редактируйте вручную: правки —
в overlay (OpenAPI Overlay 1.0.0) и повторная генерация. Что инструмент не
вывел или вывел с сомнением, перечислено в `report.md` и в разделе 9.

## 1. Авторизация и хранение секрета

Тип авторизации: `api_key` — схема `ApiKeyAuth` из securitySchemes, запись справочника rules/auth.yml «api_key_header».

Учётные данные уходят в заголовке `X-API-Key` каждого запроса к провайдеру.

| Ключ credentials | Где читается | Назначение |
|---|---|---|
| `provider.credentials[:api_key]` | `auth_headers` | учётные данные для запросов к провайдеру |
| `provider.credentials[:webhook_secret]` | `verify_signature!` | секрет подписи входящих уведомлений |

Значения секретов хранятся только в credentials платформы: в этом документе и в сервисе — одни имена ключей; в fixtures.json — только заглушки вида test_api_key, нужные, чтобы посчитать подпись уведомления.

## 2. ENV-переменные

| Переменная | Назначение | По умолчанию | Обязательна |
|---|---|---|---|
| `NOVAPAY_BASE_URL` | базовый URL API провайдера (константа BASE_URL) | `https://api.sandbox.novapay.example/v1` — песочница из спецификации | нет |
| `NOVAPAY_OPEN_TIMEOUT` | таймаут соединения, секунды (константа OPEN_TIMEOUT) | 5 | нет |
| `NOVAPAY_READ_TIMEOUT` | таймаут чтения ответа, секунды (константа READ_TIMEOUT) | 15 | нет |

Продакшен: задайте `NOVAPAY_BASE_URL=https://api.novapay.example/v1` — второй сервер спецификации.

Секреты через ENV не читаются: ключи credentials — `api_key`, `webhook_secret`.

## 3. Таблица методов с идемпотентностью

Методы контракта `Provider::BaseService` в порядке `rules/contract.yml`.
Ключ идемпотентности — детерминированный UUID v5 от `operation.id`
(RFC 4122 §4.3, `Digest::SHA1`, без `SecureRandom`): повтор запроса даёт тот
же ключ и дедуплицируется провайдером.

| Метод | HTTP-метод и путь провайдера | request_method | Идемпотентность | Результат |
|---|---|---|---|---|
| `check_conditions(operation, request_method)` | — (без обращения к провайдеру) | значение шлюза, передаётся в super: `create`, `status`, `check` | не применимо | `success` или `failure` с кодом условия: `:amount_below_minimum`, `:currency_not_allowed`, `:external_id_too_long`, `:recipient_type_not_allowed`, `:recipient_phone_invalid_format` |
| `create_request(operation, _request_method = 'create')` | `POST /payouts` | `'create'` по умолчанию | заголовок `Idempotency-Key`, ключ — UUID v5 от operation.id (пространство имён из rules/idempotency.yml); на повтор провайдер отвечает: 409 со схемой успешного ответа — сервис подхватывает существующую операцию | `success` — идентификатор провайдера сохранён, статус применён; `failure` с действием из ERROR_MAP |
| `process_callback(payload)` | `POST /webhooks/payout` — входящий, вызывает провайдер | — | нет: входящий запрос; повторное уведомление применяет тот же статус ещё раз | `success` после `approve_operation` / `reject_operation`; `failure` при неверной подписи, неизвестной операции или событии |
| `fetch_status(operation)` | `GET /payouts/{payout_id}` | — | идемпотентен по семантике HTTP (RFC 9110, GET) | `success` после перевода статуса; `failure` с кодом operation_not_found, status_unknown или действием из ERROR_MAP |

Не отображено на контракт Provider::BaseService: отдельные публичные методы, платформа зовёт их сама; см. report.md.

| Метод | HTTP-метод и путь провайдера | request_method | Идемпотентность | Результат |
|---|---|---|---|---|
| `cancel(operation)` — роль cancel (эвристика 0.95) | `POST /payouts/{payout_id}/cancel` | — | нет | `success` или `failure`; до запроса — проверка CANCELLABLE_STATUSES |
| `balance` — роль balance (эвристика 0.93) | `GET /balance` | — | идемпотентен по семантике HTTP (RFC 9110, GET) | тело ответа (Hash) или `failure` с действием из ERROR_MAP |

## 4. Маппинг статусов

`STATUS_MAP` — статус провайдера во внутренний статус платформы
(`approve_operation` для `approved`, `reject_operation` для `rejected`,
`in_progress` ничего не меняет). Незнакомое значение даёт `nil` и отказ
`status_unknown`.

| Статус провайдера | Внутренний статус | Источник | Уверенность |
|---|---|---|---|
| `cancelled` | `rejected` | канон описания кейса (rules/statuses.yml) | 1.00 |
| `completed` | `approved` | канон описания кейса (rules/statuses.yml) | 1.00 |
| `failed` | `rejected` | канон описания кейса (rules/statuses.yml) | 1.00 |
| `pending` | `in_progress` | канон описания кейса (rules/statuses.yml) | 1.00 |
| `processing` | `in_progress` | канон описания кейса (rules/statuses.yml) | 1.00 |

`EVENT_MAP` — событие уведомления во внутренний статус; ветка `else` для
незнакомого события даёт отказ `unknown_event`.

| Событие уведомления | Внутренний статус | Источник | Уверенность |
|---|---|---|---|
| `payout.cancelled` | `rejected` | канон описания кейса (rules/statuses.yml) | 1.00 |
| `payout.completed` | `approved` | канон описания кейса (rules/statuses.yml) | 1.00 |
| `payout.failed` | `rejected` | канон описания кейса (rules/statuses.yml) | 1.00 |
| `payout.processing` | `in_progress` | канон описания кейса (rules/statuses.yml) | 1.00 |

## 5. Обработка ошибок с действиями

`ERROR_MAP` читается в два шага: сначала код ошибки из тела ответа, потом
HTTP-код; символ действия становится кодом отказа для платформы.

| Код ошибки провайдера | HTTP-код | Где встречается | Действие | Что делает сервис |
|---|---|---|---|---|
| `amount_limit_exceeded` | любой — читается из тела ответа | enum | `escalate` | `failure(:escalate, 'errors.amount_limit_exceeded')` |
| `bank_unavailable` | любой — читается из тела ответа | enum | `retry_backoff` | `failure(:retry_backoff, 'errors.bank_unavailable')` |
| `insufficient_balance` | любой — читается из тела ответа | enum и примеры | `escalate` | `failure(:escalate, 'errors.insufficient_balance')` |
| `internal_error` | любой — читается из тела ответа | enum | `retry_backoff` | `failure(:retry_backoff, 'errors.internal_error')` |
| `invalid_status` | любой — читается из тела ответа | только в примерах | `reject` | `failure(:reject, 'errors.invalid_status')` |
| `not_found` | любой — читается из тела ответа | только в примерах | `reject` | `failure(:reject, 'errors.not_found')` |
| `rate_limit_exceeded` | любой — читается из тела ответа | enum и примеры | `retry_backoff` | `failure(:retry_backoff, 'errors.rate_limit_exceeded')` |
| `recipient_not_found` | любой — читается из тела ответа | enum и примеры | `reject` | `failure(:reject, 'errors.recipient_not_found')` |
| `unauthorized` | любой — читается из тела ответа | только в примерах | `alert` | `failure(:alert, 'errors.unauthorized')` |
| `validation_error` | любой — читается из тела ответа | enum и примеры | `reject` | `failure(:reject, 'errors.validation_error')` |

| HTTP-код | Действие | Что делает сервис |
|---|---|---|
| `400` | `reject` | `failure(:reject, 'errors.400')` |
| `401` | `alert` | `failure(:alert, 'errors.401')` |
| `402` | `escalate` | `failure(:escalate, 'errors.402')` |
| `404` | `reject` | `failure(:reject, 'errors.404')` |
| `409` | `reject` | `failure(:reject, 'errors.409')` |
| `422` | `reject` | `failure(:reject, 'errors.422')` |
| `429` | `retry_backoff` | `failure(:retry_backoff, 'errors.429')` |
| `500` | `retry_backoff` | `failure(:retry_backoff, 'errors.500')` |

| Действие | Что это значит для платформы |
|---|---|
| `alert` | тревога дежурному: учётные данные или права, повтор упадёт так же |
| `escalate` | решение человека: баланс или лимит провайдера, платформа этого не починит |
| `reject` | операция отклоняется, повтор не поможет |
| `retry_backoff` | повторить с нарастающей паузой; Retry-After, если объявлен |

Политика ретраев (RETRY_POLICY): платформа повторяет запрос при действиях `retry`, `retry_backoff`; по HTTP-кодам это `429`, `500`. Заголовок паузы `Retry-After` объявлен у ответов `429` — платформа обязана выдержать его перед повтором.

Механизм ретраев, очереди и алерты — инфраструктура платформы; сервис не повторяет запросы сам, а только отдаёт политику данными.

Код, которого нет в таблицах, получает действие по умолчанию `reject` (DEFAULT_ERROR_ACTION).

Дедупликация. Ответ 409 у операции `createPayout` со схемой успешного ответа — не ошибка, а успешный путь по draft-ietf-httpapi-idempotency-key-header: `create_request` подхватывает существующую операцию (константа DEDUP_STATUS). В ERROR_MAP этот случай не входит.

## 6. Конфигурация ProviderGateway

Форма регистрации — допущение: реального интерфейса ProviderGateway нам не выдали. Значения ниже вычислены тем же кодом, что предпроверки `check_conditions` сервиса: суммы — во внутренних (мажорных) единицах.

```yaml
providers:
  novapay:
    service: Provider::NovapayService
    request_methods: [create, status, check]
    currencies: [RUB]
    amount:
      platform_unit: major
      provider_unit: minor
      multiplier: 100  # ISO 4217: экспонента RUB 2
      minimum: 1000  # minimum: 100000 в единицах провайдера = 1000.00 RUB в мажорных (задано явно 1.00)
    fields:
      currency: { enum: [RUB] }  # роль currency
      external_id: { max_length: 64 }  # роль external_id
      type: { enum: [sbp, card] }  # роль recipient_type
      phone: { pattern: "^7\\d{10}$" }  # роль recipient_phone
    webhook:
      path: "/webhooks/payout"
      signature_header: X-NovaPay-Signature
```

## 7. Схема подписи вебхука

| Параметр | Значение | Источник |
|---|---|---|
| заголовок с подписью | `X-NovaPay-Signature` | задано явно 1.00 |
| алгоритм | `hmac_sha256` | по справочнику 0.90 |
| кодировка | `hex` | по справочнику 0.90 |
| подписываемая строка | `raw_body` | по справочнику 0.90 |
| секрет | `provider.credentials[:webhook_secret]` | по справочнику 0.90 |

- нет заголовка с подписью — `failure(:signature_missing, 'errors.signature_missing')`, тело не разбирается
- подпись не совпала — `failure(:signature_invalid, 'errors.signature_invalid')`
- сравнение константное по времени (`OpenSSL.fixed_length_secure_compare`); строки разной длины не равны, исключения нет

Как провайдер считает подпись (и как её пересчитывает сервис), без значения секрета:

```ruby
secret = provider.credentials[:webhook_secret]
expected = OpenSSL::HMAC.hexdigest('SHA256', secret, raw_body)
given = headers['X-NovaPay-Signature']
valid = OpenSSL.fixed_length_secure_compare(expected, given)
```

## 8. Как подключить в приложение

1. Положите `novapay_service.rb` в каталог провайдеров платформы рядом с
   остальными наследниками `Provider::BaseService`; класс — `Provider::NovapayService`.
2. Задайте ключи `provider.credentials` из раздела 1 и переменные окружения из
   раздела 2. Значения секретов — только в хранилище credentials платформы.
3. Зарегистрируйте сервис в `ProviderGateway` фрагментом из раздела 6;
   значения `request_method` — из того же фрагмента.
4. Направьте маршрут входящих уведомлений провайдера на `process_callback`,
   передавая сырое тело и заголовки как `{ body: <тело>, headers: <заголовки> }`:
   сервис читает их как `payload[:body]` и `payload[:headers]` (форма
   аргумента — из `rules/contract.yml`, раздел `platform`). Подпись проверяется
   по байтам тела до разбора JSON, поэтому тело должно приходить неизменённым.
5. Включите `fetch_status` в поллинг незавершённых операций:
   это единственный путь узнать статус, если уведомление не пришло.
6. Прогоните `fixtures.json` через WebMock: в нём запросы, ответы и
   уведомления из примеров спецификации с ожидаемым внутренним статусом.
7. Пройдите по пунктам `report.md`: каждая строка там — действие, а TODO в
   сервисе указывают на то же место.

## 9. Принятые допущения

Реального класса Provider::BaseService нам не выдали. Контракт восстановлен по примеру из описания кейса и подтверждениям экспертов. Это допущение, оно продублировано в docs/ASSUMPTIONS.md и в INTEGRATION.md. Сигнатуры четырёх методов и имена хелперов видны в примере; типы возвращаемых значений и арность части хелперов выведены нами.

- №1. Контракт Provider::BaseService восстановлен по примеру из описания кейса; реального класса нет и не будет. Имена и арность четырёх методов и хелперов — как в примере. Источник: описание кейса; эксперты 4 сентября 2026: «неважно, как он устроен… базовый класс-фабрика». Где влияет: rules/contract.yml, шаблон сервиса, INTEGRATION.md.
- №2. HTTP-клиент платформы вызывается как client.post(url, payload, headers) и client.get(url, headers); ответ читается как response.status и response.body; базовый URL берётся из ENV. Источник: эксперты 4 сентября 2026: «есть какой-то клиент, к которому обращаемся через POST, передавая URL, payload и header». Где влияет: шаблон сервиса, rules/contract.yml.
- №3. Генерация не блокируется никогда. Там, где спецификация не даёт ответа, сервис получает лучшего кандидата из справочников с пометкой TODO и строкой в report.md, а не пустое значение. Источник: эксперты 4 сентября 2026: «инструмент должен больше решать сам… человек уже всё равно всё будет смотреть, но после того, как сгенерировано». Где влияет: генераторы, report.md, третий уровень доверия в CLAUDE.md.
- №4. Дубли операций отсекает платформа до вызова сервиса. Ветка кода конфликта со схемой успеха («взять существующую операцию») генерируется, потому что так говорит спецификация, но не считается ключевой функцией. Источник: эксперты 4 сентября 2026, вопрос 12 в docs/QUESTIONS.md. Где влияет: шаблон сервиса, INTEGRATION.md.
- №6. operation.amount приходит в мажорных единицах (рубли), провайдер ждёт минорные; множитель — 10 в степени экспоненты ISO 4217 для кода валюты, а не слово «копейках» в описании. Источник: описание кейса; ISO 4217. Где влияет: UnitsAnalyzer, шаблон сервиса, check_conditions.
- №7. Канонический маппинг статусов из описания кейса подтверждён экспертами; cancelled отображается в rejected, четвёртого внутреннего статуса нет. Источник: описание кейса; вопрос 3 в docs/QUESTIONS.md открыт. Где влияет: rules/statuses.yml, STATUS_MAP, EVENT_MAP.
- №8. Выражения платформы — чтение полей операции, поиск операции по идентификатору из уведомления, сохранение идентификатора провайдера, форма аргумента process_callback ({ body:, headers: }) и предикат успешного результата — наш вывод; реального класса Operation не выдали. Источник: наше решение; rules/contract.yml, раздел platform. Где влияет: build_payload, find_callback_operation, accept_response, process_callback.
- №9. Форма регистрации сервиса в ProviderGateway (YAML-фрагмент в INTEGRATION.md) — наш вывод из описания кейса; реального интерфейса шлюза не выдали, значения request_method — из ответов экспертов. Источник: наше решение; эксперты 4 сентября 2026 о request_method. Где влияет: INTEGRATION.md, раздел «Конфигурация ProviderGateway».

Выражения, которыми сервис разговаривает с платформой, — раздел platform в rules/contract.yml (источник: допущение), например `operation.amount`, `operation.id`, `operation.provider_operation_id`, `Operation.find_by(provider_operation_id: …)`, `payload[:body]`; поменялась платформа — правится справочник, не сервис.

Допущения этого прогона — то, что в коде взято по лучшему кандидату или по умолчанию:

- условная обязательность `bank_code` при type = sbp прочитана как намёк в описании с уверенностью 0.50 (подробнее — report.md)
- условная обязательность `card_number` при type = card прочитана как намёк в описании с уверенностью 0.50 (подробнее — report.md)
- условие cancel_status_restriction прочитано из прозы: pending, processing (эвристика 0.60) (подробнее — report.md)
