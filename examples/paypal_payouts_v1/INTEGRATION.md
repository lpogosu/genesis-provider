# Интеграция с провайдером «Payouts»

| | |
|---|---|
| Провайдер | `paypal_payouts_v1` |
| Спецификация | `paypal_payouts_v1.json`, версия 1.9, OpenAPI 3.0.3 |
| Класс сервиса | `Provider::PaypalPayoutsV1Service < Provider::BaseService` |
| Файл сервиса | `paypal_payouts_v1_service.rb` |

Документ сгенерирован инструментом integrate из той же модели провайдера,
что и сервис: таблицы ниже совпадают с константами `STATUS_MAP`, `EVENT_MAP`,
`ERROR_MAP` и `RETRY_POLICY` по построению. Не редактируйте вручную: правки —
в overlay (OpenAPI Overlay 1.0.0) и повторная генерация. Что инструмент не
вывел или вывел с сомнением, перечислено в `report.md` и в разделе 9.

## 1. Авторизация и хранение секрета

Тип авторизации: `oauth2` — схема `Oauth2` из securitySchemes, запись справочника rules/auth.yml «oauth2_client_credentials».

Учётные данные уходят в заголовке `Authorization` каждого запроса к провайдеру.

Получение токена OAuth2 (поток client_credentials, tokenUrl: /v1/oauth2/token) спецификация не описывает: сгенерирован метод-заглушка `access_token` с TODO и NotImplementedError — реализуйте его под клиент платформы.

| Ключ credentials | Где читается | Назначение |
|---|---|---|
| `provider.credentials[:client_id]` | `auth_headers` | учётные данные для запросов к провайдеру |
| `provider.credentials[:client_secret]` | `auth_headers` | учётные данные для запросов к провайдеру |

Значения секретов хранятся только в credentials платформы: в этом документе и в сервисе — одни имена ключей; в fixtures.json — только заглушки вида test_api_key, нужные, чтобы посчитать подпись уведомления.

## 2. ENV-переменные

| Переменная | Назначение | По умолчанию | Обязательна |
|---|---|---|---|
| `PAYPAL_PAYOUTS_V1_BASE_URL` | базовый URL API провайдера (константа BASE_URL) | `https://api-m.sandbox.paypal.com` — песочница из спецификации | нет |
| `PAYPAL_PAYOUTS_V1_OPEN_TIMEOUT` | таймаут соединения, секунды (константа OPEN_TIMEOUT) | 5 | нет |
| `PAYPAL_PAYOUTS_V1_READ_TIMEOUT` | таймаут чтения ответа, секунды (константа READ_TIMEOUT) | 15 | нет |

Продакшен: задайте `PAYPAL_PAYOUTS_V1_BASE_URL=https://api-m.paypal.com` — второй сервер спецификации.

Секреты через ENV не читаются: ключи credentials — `client_id`, `client_secret`.

## 3. Таблица методов с идемпотентностью

Методы контракта `Provider::BaseService` в порядке `rules/contract.yml`.
Ключ идемпотентности — детерминированный UUID v5 от `operation.id`
(RFC 4122 §4.3, `Digest::SHA1`, без `SecureRandom`): повтор запроса даёт тот
же ключ и дедуплицируется провайдером.

| Метод | HTTP-метод и путь провайдера | request_method | Идемпотентность | Результат |
|---|---|---|---|---|
| `check_conditions(operation, request_method)` | — (без обращения к провайдеру) | значение шлюза, передаётся в super: `create`, `status`, `check` | не применимо | `success` или `failure` с кодом платформы `:unprocessable_entity` и ключом условия: `errors.external_id_invalid_format`, `errors.external_id_too_long` |
| `create_request(operation, _request_method = 'create')` | `POST /v1/payments/payouts` | `'create'` по умолчанию | заголовок `PayPal-Request-Id`, ключ — UUID v5 от operation.id (пространство имён из rules/idempotency.yml); на повтор провайдер отвечает: ответ на повтор в спецификации не описан — подробнее — report.md | `success` с идентификатором операции у провайдера — платформа берёт его как `payload.dig(:result, :id)`; `failure` с кодом платформы по FAILURE_CODES |
| `process_callback(_payload)` | в спецификации не объявлено; метод отказывает `failure(:not_implemented, 'errors.webhooks_not_supported')` — подробнее — report.md | — | нет: входящий запрос; повторное уведомление применяет тот же статус ещё раз | `success` после `approve_operation` / `reject_operation`, без result; `failure` с кодом платформы при неверной подписи, неизвестной операции или событии |
| `fetch_status(operation)` | `GET /v1/payments/payouts/{id}` | — | идемпотентен по семантике HTTP (RFC 9110, GET) | `success` после перевода статуса хелпером, без result; `failure` с кодом платформы и ключом `errors.operation_not_found`, `errors.status_unknown` или ошибкой провайдера |

Не отображено на контракт Provider::BaseService: отдельные публичные методы, платформа зовёт их сама; см. report.md.

| Метод | HTTP-метод и путь провайдера | request_method | Идемпотентность | Результат |
|---|---|---|---|---|
| `payouts_item_get(operation)` — роль fetch_status (эвристика 0.95) | `GET /v1/payments/payouts-item/{payout_item_id}` | — | идемпотентен по семантике HTTP (RFC 9110, GET) | тело ответа (Hash) или `failure` с кодом платформы по FAILURE_CODES |
| `cancel(operation)` — роль cancel (эвристика 0.95) | `POST /v1/payments/payouts-item/{payout_item_id}/cancel` | — | нет | `success` или `failure` с кодом платформы; до запроса — проверка CANCELLABLE_STATUSES |

## 4. Маппинг статусов

`STATUS_MAP` — статус провайдера во внутренний статус платформы
(`approve_operation` для `approved`, `reject_operation` для `rejected`,
`in_progress` ничего не меняет). Незнакомое значение даёт `nil` и отказ
`status_unknown`.

| Статус провайдера | Внутренний статус | Источник | Уверенность |
|---|---|---|---|
| `BLOCKED` | — | не сопоставлено, см. report.md | — |
| `FAILED` | `rejected` | канон описания кейса (rules/statuses.yml) | 1.00 |
| `ONHOLD` | — | не сопоставлено, см. report.md | — |
| `PENDING` | `in_progress` | канон описания кейса (rules/statuses.yml) | 1.00 |
| `REFUNDED` | — | не сопоставлено, см. report.md | — |
| `RETURNED` | `rejected` | синоним справочника rules/statuses.yml | 0.90 |
| `REVERSED` | — | не сопоставлено, см. report.md | — |
| `SUCCESS` | `approved` | синоним справочника rules/statuses.yml | 0.90 |
| `UNCLAIMED` | `in_progress` | синоним справочника rules/statuses.yml | 0.90 |

Вебхуков в спецификации не объявлено: EVENT_MAP не генерируется, статус — только опросом `fetch_status`.

## 5. Обработка ошибок с действиями

`ERROR_MAP` читается в два шага: сначала код ошибки из тела ответа, потом
HTTP-код. Символ действия — это политика обработки на стороне платформы;
первым аргументом `failure` уходит код платформы (см. ниже).

| HTTP-код | Действие | Что делает сервис |
|---|---|---|
| `400` | `reject` | `failure(:bad_request, 'errors.http_400')` |
| `403` | `alert` | `failure(:forbidden, 'errors.http_403')` |
| `404` | `reject` | `failure(:not_found, 'errors.http_404')` |

Коды, которые у отдельной операции означают не то, что в общей таблице (ERROR_MAP_BY_OPERATION):

| Операция | HTTP-код | Действие |
|---|---|---|
| `payouts-item.cancel` | `500` | `retry_backoff` |
| `payouts-item.get` | `500` | `retry_backoff` |
| `payouts.get` | `500` | `retry_backoff` |
| `payouts.post` | `500` | `retry_backoff` |

| Действие | Что это значит для платформы |
|---|---|
| `alert` | тревога дежурному: учётные данные или права, повтор упадёт так же |
| `reject` | операция отклоняется, повтор не поможет |

Первым аргументом `failure` уходит код платформы, а не наше действие: по HTTP-коду ответа (FAILURE_CODES: 400 → `:bad_request`, 401 → `:unauthorized`, 403 → `:forbidden`, 404 → `:not_found`, 409 → `:conflict`, 422 → `:unprocessable_entity`, 429 → `:too_many_requests`, 500 → `:internal_server_error`, 502 → `:bad_gateway`, 503 → `:service_unavailable`, 504 → `:gateway_timeout`), иначе по действию из ERROR_MAP (FAILURE_CODES_BY_ACTION: `reject` → `:unprocessable_entity`, `retry` → `:service_unavailable`, `retry_backoff` → `:service_unavailable`, `alert` → `:internal_server_error`, `escalate` → `:unprocessable_entity`). Действие остаётся политикой обработки — оно в ERROR_MAP, RETRY_POLICY и в таблицах выше.

Политика ретраев (RETRY_POLICY): платформа повторяет запрос при действиях `retry`, `retry_backoff`; по HTTP-кодам это —. Заголовок паузы до повтора в спецификации не объявлен.

Механизм ретраев, очереди и алерты — инфраструктура платформы; сервис не повторяет запросы сам, а только отдаёт политику данными.

Код, которого нет в таблицах, получает действие по умолчанию `reject` (DEFAULT_ERROR_ACTION).

Дедупликация. Успешный путь дедупликации не выведен: ни одна операция с заголовком идемпотентности не объявляет ответ на повтор со схемой успеха, поэтому ответ с кодом конфликта обрабатывается как ошибка — подробнее — report.md.

## 6. Параметры подключения

Этот раздел закрывает `## ProviderGateway config` из описания кейса; форма другая, потому что отдельный конфиг шлюза платформе не нужен, а адрес и авторизация берутся из спецификации (ответ экспертов 5 сентября 2026, `docs/QUESTIONS.md`, вопрос 15).

Всё ниже выведено из самой спецификации: адрес, ключи учётных данных, валюты, единицы и границы суммы, ограничения полей, путь и заголовок уведомлений. Отдельного конфига сервис не требует — это сводка для сверки. Значения вычислены тем же кодом, что предпроверки `check_conditions` сервиса: суммы — во внутренних (мажорных) единицах.

```yaml
providers:
  paypal_payouts_v1:
    service: Provider::PaypalPayoutsV1Service
    base_url: https://api-m.sandbox.paypal.com  # переменная окружения PAYPAL_PAYOUTS_V1_BASE_URL, адрес из серверов спецификации
    credentials: [client_id, client_secret]
    request_methods: [create, status, check]
    currencies: []  # TODO: валюта в спецификации не выведена
    amount:
      platform_unit: major
      multiplier: 1  # TODO: единицы суммы не выведены, множитель 1 — задайте x-specgen-amount-unit в overlay
    fields:
      sender_batch_id: { pattern: "^.*$", max_length: 256 }  # роль external_id
      recipient_type: { pattern: "^.*$", max_length: 13 }  # роль recipient_type
      sender_item_id: { max_length: 63 }  # роль external_id
```

### Куда мапить поля тела запроса

Строка на каждое поле тела запроса операции создания: чем его заполняет сервис. Пустая ячейка выражения — место под ручной маппинг: платформа такого реквизита не описывает, и выдумывать его инструмент не имеет права (эксперты кейса, 5 сентября 2026). Реквизиты получателя раскрыты по способам выплаты: ключ верхнего уровня в `operation.payout_requisite` — это payment_method шлюза, он же request_method.

| Поле тела запроса | Роль | Способ выплаты | Чем заполняется |
|---|---|---|---|
| `sender_batch_header.sender_batch_id` | `external_id` | нет | `operation.id` |
| `sender_batch_header.recipient_type` | `recipient_type` | нет | — заполните вручную |
| `sender_batch_header.email_subject` | роль не распознана | нет | — заполните вручную |
| `sender_batch_header.email_message` | роль не распознана | нет | — заполните вручную |
| `sender_batch_header.note` | роль не распознана | нет | — заполните вручную |
| `items` | роль не распознана | нет | — заполните вручную |

## 7. Схема подписи вебхука

Вебхуков в спецификации не объявлено: подписи нет, `process_callback` отказывает `failure(:not_implemented, 'errors.webhooks_not_supported')`.

## 8. Как подключить в приложение

1. Положите `paypal_payouts_v1_service.rb` в каталог провайдеров платформы рядом с
   остальными наследниками `Provider::BaseService`; класс — `Provider::PaypalPayoutsV1Service`.
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
- №3. Генерация не блокируется никогда. Там, где спецификация не даёт ответа, сервис получает лучшего кандидата из справочников с пометкой TODO и строкой в report.md, а не пустое значение. Источник: эксперты 4 сентября 2026: «инструмент должен больше решать сам… человек уже всё равно всё будет смотреть, но после того, как сгенерировано». Где влияет: генераторы, report.md, третий уровень доверия (docs/PRINCIPLES.md).
- №4. Дубли операций отсекает платформа до вызова сервиса. Ветка кода конфликта со схемой успеха («взять существующую операцию») генерируется, потому что так говорит спецификация, но не считается ключевой функцией. Источник: эксперты 4 сентября 2026, вопрос 12 в docs/QUESTIONS.md. Где влияет: шаблон сервиса, INTEGRATION.md.
- №6. operation.amount приходит в мажорных единицах (рубли), провайдер ждёт минорные; множитель — 10 в степени экспоненты ISO 4217 для кода валюты, а не слово «копейках» в описании. Источник: описание кейса; ISO 4217. Где влияет: UnitsAnalyzer, шаблон сервиса, check_conditions.
- №7. Канонический маппинг статусов из описания кейса подтверждён экспертами; cancelled отображается в rejected, четвёртого внутреннего статуса нет. Источник: описание кейса; вопрос 3 в docs/QUESTIONS.md открыт. Где влияет: rules/statuses.yml, STATUS_MAP, EVENT_MAP.
- №10. Аргумент process_callback — уже разобранный JSON уведомления. Подпись считается по сырым байтам тела, которых в разобранном JSON нет, поэтому проверку вызывает маршрут вебхука публичным методом verify_webhook_signature до разбора тела; внутри process_callback подпись проверяется, только если маршрут положил байты и заголовки в аргумент. Источник: эксперты 5 сентября 2026: process_callback «получает уже разобранный JSON внутри payload». Где влияет: шаблон сервиса, INTEGRATION.md раздел 8, report.md чек-лист.
- №11. Валюта запроса берётся из спецификации — из единственного значения enum, const или example поля с ролью currency, — а не у платформы: поля currency у операции нет. Источник: эксперты 5 сентября 2026: в перечне полей операции валюты нет, «адрес, авторизация и т.д. должны браться из open api документа провайдера». Где влияет: константа CURRENCY сервиса, build_payload, INTEGRATION.md.
- №12. Реквизит, для которого в таблице requisites rules/contract.yml нет выражения, вслепую не генерируется: поле получает TODO и строку «куда мапить» в INTEGRATION.md. Догадка о спецификации обязательна, догадка о платформе запрещена. Источник: эксперты 5 сентября 2026: «Для поля из спеки, которого нет в известной схеме платформы, не генерировать вслепую. Лучше TODO и явное место маппинга в INTEGRATION.md». Где влияет: build_payload, report.md, INTEGRATION.md.
- №13. Ключ верхнего уровня в payout_requisite — это payment_method шлюза, он же request_method. Значение enum роли recipient_type из спецификации сопоставляется с ним по нормализованному имени. Источник: эксперты 5 сентября 2026: «request_method — логический метод шлюза (gateway.payment_method: sbp, p2p, …), в одном сервисе — ветки по request_method и/или форме payout_requisite»; сопоставление имён — наше решение. Где влияет: ветка case request_method в сборке реквизитов.

Выражения, которыми сервис разговаривает с платформой, — раздел platform в rules/contract.yml (источник: эксперты кейса 5 сентября 2026 (вопросы 18–25 в docs/QUESTIONS.md) и допущение), например `operation.amount`, `operation.id`, `operation.provider_operation_key`, `payload`; поменялась платформа — правится справочник, не сервис.

Допущения этого прогона — то, что в коде взято по лучшему кандидату или по умолчанию:

- поле статуса в ответе операции payouts.get не найдено по ролям: подставлено body['status'] (подробнее — report.md)
- единицы суммы не выведены (type: object без дробного example: единицы не выведены): множитель 1 и TODO у AMOUNT_MULTIPLIER (подробнее — report.md)
- код ответа на повтор не выведен (ни одна операция с заголовком (payouts.post) не объявляет ответ 409 со схемой успешного ответа): ветка дедупликации не сгенерирована (подробнее — report.md)
- статус `BLOCKED` не сопоставлен: в STATUS_MAP nil (подробнее — report.md)
- статус `ONHOLD` не сопоставлен: в STATUS_MAP nil (подробнее — report.md)
- статус `REFUNDED` не сопоставлен: в STATUS_MAP nil (подробнее — report.md)
- статус `REVERSED` не сопоставлен: в STATUS_MAP nil (подробнее — report.md)
