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
| `check_conditions(operation, request_method)` | — (без обращения к провайдеру) | значение шлюза, передаётся в super: `create`, `status`, `check` | не применимо | `success` или `failure` с кодом платформы `:unprocessable_entity` и ключом условия: `errors.amount_below_minimum`, `errors.external_id_too_long` |
| `create_request(operation, request_method = 'create')` | `POST /payouts` | `'create'` по умолчанию | заголовок `Idempotency-Key`, ключ — UUID v5 от operation.id (пространство имён из rules/idempotency.yml); на повтор провайдер отвечает: 409 со схемой успешного ответа — сервис подхватывает существующую операцию | `success` с идентификатором операции у провайдера — платформа берёт его как `payload.dig(:result, :id)`; `failure` с кодом платформы по FAILURE_CODES |
| `process_callback(payload)` | `POST /webhooks/payout` — входящий, вызывает провайдер | — | нет: входящий запрос; повторное уведомление применяет тот же статус ещё раз | `success` после `approve_operation` / `reject_operation`, без result; `failure` с кодом платформы при неверной подписи, неизвестной операции или событии |
| `fetch_status(operation)` | `GET /payouts/{payout_id}` | — | идемпотентен по семантике HTTP (RFC 9110, GET) | `success` после перевода статуса хелпером, без result; `failure` с кодом платформы и ключом `errors.operation_not_found`, `errors.status_unknown` или ошибкой провайдера |

Не отображено на контракт Provider::BaseService: отдельные публичные методы, платформа зовёт их сама; см. report.md.

| Метод | HTTP-метод и путь провайдера | request_method | Идемпотентность | Результат |
|---|---|---|---|---|
| `cancel(operation)` — роль cancel (эвристика 0.95) | `POST /payouts/{payout_id}/cancel` | — | нет | `success` или `failure` с кодом платформы; до запроса — проверка CANCELLABLE_STATUSES |
| `balance` — роль balance (эвристика 0.93) | `GET /balance` | — | идемпотентен по семантике HTTP (RFC 9110, GET) | тело ответа (Hash) или `failure` с кодом платформы по FAILURE_CODES |

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
HTTP-код. Символ действия — это политика обработки на стороне платформы;
первым аргументом `failure` уходит код платформы (см. ниже).

| Код ошибки провайдера | HTTP-код | Где встречается | Действие | Что делает сервис |
|---|---|---|---|---|
| `amount_limit_exceeded` | любой — читается из тела ответа | enum | `reject` | `failure(platform_failure_code(response.status, :reject), 'errors.amount_limit_exceeded')` |
| `bank_unavailable` | любой — читается из тела ответа | enum | `retry_backoff` | `failure(platform_failure_code(response.status, :retry_backoff), 'errors.bank_unavailable')` |
| `insufficient_balance` | любой — читается из тела ответа | enum и примеры | `retry_backoff` | `failure(platform_failure_code(response.status, :retry_backoff), 'errors.insufficient_balance')` |
| `internal_error` | любой — читается из тела ответа | enum | `retry_backoff` | `failure(platform_failure_code(response.status, :retry_backoff), 'errors.internal_error')` |
| `invalid_status` | любой — читается из тела ответа | только в примерах | `reject` | `failure(platform_failure_code(response.status, :reject), 'errors.invalid_status')` |
| `not_found` | любой — читается из тела ответа | только в примерах | `reject` | `failure(platform_failure_code(response.status, :reject), 'errors.not_found')` |
| `rate_limit_exceeded` | любой — читается из тела ответа | enum и примеры | `retry_backoff` | `failure(platform_failure_code(response.status, :retry_backoff), 'errors.rate_limit_exceeded')` |
| `recipient_not_found` | любой — читается из тела ответа | enum и примеры | `reject` | `failure(platform_failure_code(response.status, :reject), 'errors.recipient_not_found')` |
| `unauthorized` | любой — читается из тела ответа | только в примерах | `alert` | `failure(platform_failure_code(response.status, :alert), 'errors.unauthorized')` |
| `validation_error` | любой — читается из тела ответа | enum и примеры | `reject` | `failure(platform_failure_code(response.status, :reject), 'errors.validation_error')` |

| HTTP-код | Действие | Что делает сервис |
|---|---|---|
| `400` | `reject` | `failure(:bad_request, 'errors.400')` |
| `401` | `alert` | `failure(:unauthorized, 'errors.401')` |
| `402` | `retry_backoff` | `failure(:service_unavailable, 'errors.402')` |
| `404` | `reject` | `failure(:not_found, 'errors.404')` |
| `409` | `reject` | `failure(:conflict, 'errors.409')` |
| `422` | `reject` | `failure(:unprocessable_entity, 'errors.422')` |
| `429` | `retry_backoff` | `failure(:too_many_requests, 'errors.429')` |
| `500` | `retry_backoff` | `failure(:internal_server_error, 'errors.500')` |

| Действие | Что это значит для платформы |
|---|---|
| `alert` | тревога дежурному: учётные данные или права, повтор упадёт так же |
| `reject` | операция отклоняется, повтор не поможет |
| `retry_backoff` | повторить с нарастающей паузой; Retry-After, если объявлен |

Первым аргументом `failure` уходит код платформы, а не наше действие: по HTTP-коду ответа (FAILURE_CODES: 400 → `:bad_request`, 401 → `:unauthorized`, 403 → `:forbidden`, 404 → `:not_found`, 409 → `:conflict`, 422 → `:unprocessable_entity`, 429 → `:too_many_requests`, 500 → `:internal_server_error`, 502 → `:bad_gateway`, 503 → `:service_unavailable`, 504 → `:gateway_timeout`), иначе по действию из ERROR_MAP (FAILURE_CODES_BY_ACTION: `reject` → `:unprocessable_entity`, `retry` → `:service_unavailable`, `retry_backoff` → `:service_unavailable`, `alert` → `:internal_server_error`, `escalate` → `:unprocessable_entity`). Действие остаётся политикой обработки — оно в ERROR_MAP, RETRY_POLICY и в таблицах выше.

Политика ретраев (RETRY_POLICY): платформа повторяет запрос при действиях `retry`, `retry_backoff`; по HTTP-кодам это `402`, `429`, `500`. Заголовок паузы `Retry-After` объявлен у ответов `429` — платформа обязана выдержать его перед повтором.

Механизм ретраев, очереди и алерты — инфраструктура платформы; сервис не повторяет запросы сам, а только отдаёт политику данными.

Код, которого нет в таблицах, получает действие по умолчанию `reject` (DEFAULT_ERROR_ACTION).

Дедупликация. Ответ 409 у операции `createPayout` со схемой успешного ответа — не ошибка, а успешный путь по draft-ietf-httpapi-idempotency-key-header: `create_request` подхватывает существующую операцию (константа DEDUP_STATUS). В ERROR_MAP этот случай не входит.

## 6. Параметры подключения

Этот раздел закрывает `## ProviderGateway config` из описания кейса; форма другая, потому что отдельный конфиг шлюза платформе не нужен, а адрес и авторизация берутся из спецификации (ответ экспертов 5 сентября 2026, `docs/QUESTIONS.md`, вопрос 15).

Всё ниже выведено из самой спецификации: адрес, ключи учётных данных, валюты, единицы и границы суммы, ограничения полей, путь и заголовок уведомлений. Отдельного конфига сервис не требует — это сводка для сверки. Значения вычислены тем же кодом, что предпроверки `check_conditions` сервиса: суммы — во внутренних (мажорных) единицах.

```yaml
providers:
  novapay:
    service: Provider::NovapayService
    base_url: https://api.sandbox.novapay.example/v1  # переменная окружения NOVAPAY_BASE_URL, адрес из серверов спецификации
    credentials: [api_key, webhook_secret]
    request_methods: [create, status, check]
    currencies: [RUB]  # константа CURRENCY сервиса: enum: [RUB] у поля `currency`
    amount:
      platform_unit: major
      provider_unit: minor
      multiplier: 100  # ISO 4217: экспонента RUB 2
      minimum: 1000  # minimum: 100000 в единицах провайдера = 1000.00 RUB в мажорных (задано явно 1.00)
    fields:
      external_id: { max_length: 64 }  # роль external_id
      phone: { pattern: "^7\\d{10}$" }  # роль recipient_phone
    webhook:
      path: "/webhooks/payout"
      signature_header: X-NovaPay-Signature
```

### Куда мапить поля тела запроса

Строка на каждое поле тела запроса операции создания: чем его заполняет сервис. Пустая ячейка выражения — место под ручной маппинг: платформа такого реквизита не описывает, и выдумывать его инструмент не имеет права (эксперты кейса, 5 сентября 2026). Реквизиты получателя раскрыты по способам выплаты: ключ верхнего уровня в `operation.payout_requisite` — это payment_method шлюза, он же request_method.

| Поле тела запроса | Роль | Способ выплаты | Чем заполняется |
|---|---|---|---|
| `amount` | `amount` | нет | `operation.amount` |
| `currency` | `currency` | нет | `CURRENCY` |
| `external_id` | `external_id` | нет | `operation.id` |
| `recipient.type` | `recipient_type` | `sbp` | `'sbp'` |
| `recipient.type` | `recipient_type` | `card` | `'card'` |
| `recipient.phone` | `recipient_phone` | `sbp` | `operation.payout_requisite.dig('sbp', 'phone')` |
| `recipient.phone` | `recipient_phone` | `card` | — заполните вручную |
| `recipient.bank_code` | `bank_code` | `sbp` | `operation.payout_requisite.dig('sbp', 'bank_code')` |
| `recipient.bank_name` | `bank_name` | `sbp` | `operation.payout_requisite.dig('sbp', 'bank_name')` |
| `recipient.bank_name` | `bank_name` | `card` | — заполните вручную |
| `recipient.card_number` | `card_number` | `card` | `operation.payout_requisite['card_number']` |

## 7. Схема подписи вебхука

| Параметр | Значение | Источник |
|---|---|---|
| заголовок с подписью | `X-NovaPay-Signature` | задано явно 1.00 |
| алгоритм | `hmac_sha256` | по справочнику 0.90 |
| кодировка | `hex` | по справочнику 0.90 |
| подписываемая строка | `raw_body` | по справочнику 0.90 |
| секрет | `provider.credentials[:webhook_secret]` | по справочнику 0.90 |

- нет заголовка с подписью — `failure(:unauthorized, 'errors.signature_missing')`, тело не разбирается
- подпись не совпала — `failure(:unauthorized, 'errors.signature_invalid')`
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
3. Сверьте параметры подключения из раздела 6 с тем, как провайдер заведён
   у вас: адрес, ключи учётных данных, валюты и границы суммы выведены из
   спецификации, отдельного конфига сервис не требует.
4. Направьте маршрут входящих уведомлений провайдера на `process_callback`,
   передавая уже разобранный JSON (`payload`). Подпись считается по
   сырым байтам тела, которых в разобранном JSON уже нет, поэтому вызовите
   `verify_webhook_signature(raw_body, headers)` в самом маршруте, до разбора
   тела; форма аргумента задана в `rules/contract.yml`, раздел `platform`.
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
- №10. Аргумент process_callback — уже разобранный JSON уведомления. Подпись считается по сырым байтам тела, которых в разобранном JSON нет, поэтому проверку вызывает маршрут вебхука публичным методом verify_webhook_signature до разбора тела; внутри process_callback подпись проверяется, только если маршрут положил байты и заголовки в аргумент. Источник: эксперты 5 сентября 2026: process_callback «получает уже разобранный JSON внутри payload». Где влияет: шаблон сервиса, INTEGRATION.md раздел 8, report.md чек-лист.
- №11. Валюта запроса берётся из спецификации — из единственного значения enum, const или example поля с ролью currency, — а не у платформы: поля currency у операции нет. Источник: эксперты 5 сентября 2026: в перечне полей операции валюты нет, «адрес, авторизация и т.д. должны браться из open api документа провайдера». Где влияет: константа CURRENCY сервиса, build_payload, INTEGRATION.md.
- №12. Реквизит, для которого в таблице requisites rules/contract.yml нет выражения, вслепую не генерируется: поле получает TODO и строку «куда мапить» в INTEGRATION.md. Догадка о спецификации обязательна, догадка о платформе запрещена. Источник: эксперты 5 сентября 2026: «Для поля из спеки, которого нет в известной схеме платформы, не генерировать вслепую. Лучше TODO и явное место маппинга в INTEGRATION.md». Где влияет: build_payload, report.md, INTEGRATION.md.
- №13. Ключ верхнего уровня в payout_requisite — это payment_method шлюза, он же request_method. Значение enum роли recipient_type из спецификации сопоставляется с ним по нормализованному имени. Источник: эксперты 5 сентября 2026: «request_method — логический метод шлюза (gateway.payment_method: sbp, p2p, …), в одном сервисе — ветки по request_method и/или форме payout_requisite»; сопоставление имён — наше решение. Где влияет: ветка case request_method в сборке реквизитов.

Выражения, которыми сервис разговаривает с платформой, — раздел platform в rules/contract.yml (источник: эксперты кейса 5 сентября 2026 (вопросы 18–25 в docs/QUESTIONS.md) и допущение), например `operation.amount`, `operation.id`, `operation.provider_operation_key`, `payload`; поменялась платформа — правится справочник, не сервис.

Допущения этого прогона — то, что в коде взято по лучшему кандидату или по умолчанию:

- условная обязательность `bank_code` при type = sbp прочитана как намёк в описании с уверенностью 0.50 (подробнее — report.md)
- условная обязательность `card_number` при type = card прочитана как намёк в описании с уверенностью 0.50 (подробнее — report.md)
- условие cancel_status_restriction прочитано из прозы: pending, processing (эвристика 0.60) (подробнее — report.md)
