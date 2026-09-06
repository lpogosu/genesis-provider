# Интеграция с провайдером «Adyen Payout API»

| | |
|---|---|
| Провайдер | `adyen_payout_v68` |
| Спецификация | `adyen_payout_v68.yaml`, версия 68, OpenAPI 3.1.0 |
| Класс сервиса | `Provider::AdyenPayoutV68Service < Provider::BaseService` |
| Файл сервиса | `adyen_payout_v68_service.rb` |

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

Значения секретов хранятся только в credentials платформы: в этом документе и в сервисе — одни имена ключей; в fixtures.json — только заглушки вида test_api_key, нужные, чтобы посчитать подпись уведомления.

## 2. ENV-переменные

| Переменная | Назначение | По умолчанию | Обязательна |
|---|---|---|---|
| `ADYEN_PAYOUT_V68_BASE_URL` | базовый URL API провайдера (константа BASE_URL) | `https://pal-test.adyen.com/pal/servlet/Payout/v68` — песочница из спецификации | нет |
| `ADYEN_PAYOUT_V68_OPEN_TIMEOUT` | таймаут соединения, секунды (константа OPEN_TIMEOUT) | 5 | нет |
| `ADYEN_PAYOUT_V68_READ_TIMEOUT` | таймаут чтения ответа, секунды (константа READ_TIMEOUT) | 15 | нет |

Продакшен-сервер в спецификации не объявлен: URL боевой среды возьмите у провайдера.

Секреты через ENV не читаются: ключи credentials — `api_key`.

## 3. Таблица методов с идемпотентностью

Методы контракта `Provider::BaseService` в порядке `rules/contract.yml`.
Ключ идемпотентности — детерминированный UUID v5 от `operation.id`
(RFC 4122 §4.3, `Digest::SHA1`, без `SecureRandom`): повтор запроса даёт тот
же ключ и дедуплицируется провайдером.

| Метод | HTTP-метод и путь провайдера | request_method | Идемпотентность | Результат |
|---|---|---|---|---|
| `check_conditions(operation, request_method)` | — (без обращения к провайдеру) | значение шлюза, передаётся в super: `create`, `status`, `check` | не применимо | `success` или `failure` базового класса |
| `create_request(operation, _request_method = 'create')` | `POST /payout` | `'create'` по умолчанию | заголовок идемпотентности в спецификации не объявлен: ключ не отправляется — подробнее — report.md | `success` с идентификатором операции у провайдера — платформа берёт его как `payload.dig(:result, :id)`; `failure` с кодом платформы по FAILURE_CODES |
| `process_callback(_payload)` | в спецификации не объявлено; метод отказывает `failure(:not_implemented, 'errors.webhooks_not_supported')` — подробнее — report.md | — | нет: входящий запрос; повторное уведомление применяет тот же статус ещё раз | `success` после `approve_operation` / `reject_operation`, без result; `failure` с кодом платформы при неверной подписи, неизвестной операции или событии |
| `fetch_status(_operation)` | в спецификации не объявлено; метод отказывает `failure(:not_implemented, 'errors.status_not_supported')` — подробнее — report.md | — | нет | `success` после перевода статуса хелпером, без result; `failure` с кодом платформы и ключом `errors.operation_not_found`, `errors.status_unknown` или ошибкой провайдера |

Не отображено на контракт Provider::BaseService: отдельные публичные методы, платформа зовёт их сама; см. report.md.

| Метод | HTTP-метод и путь провайдера | request_method | Идемпотентность | Результат |
|---|---|---|---|---|
| `confirm(operation)` — роль confirm (эвристика 0.68) | `POST /confirmThirdParty` | — | нет | тело ответа (Hash) или `failure` с кодом платформы по FAILURE_CODES |
| `post_decline_third_party(operation)` — роль не распознана (unmapped): метод с TODO | `POST /declineThirdParty` | — | нет | тело ответа (Hash) или `failure` с кодом платформы по FAILURE_CODES |
| `post_store_detail(operation)` — роль не распознана (unmapped): метод с TODO | `POST /storeDetail` | — | нет | тело ответа (Hash) или `failure` с кодом платформы по FAILURE_CODES |
| `post_store_detail_and_submit_third_party(operation)` — роль не распознана (unmapped): метод с TODO | `POST /storeDetailAndSubmitThirdParty` | — | нет | тело ответа (Hash) или `failure` с кодом платформы по FAILURE_CODES |
| `post_submit_third_party(operation)` — роль не распознана (unmapped): метод с TODO | `POST /submitThirdParty` | — | нет | тело ответа (Hash) или `failure` с кодом платформы по FAILURE_CODES |

## 4. Маппинг статусов

Спецификация не объявляет статусов операции: STATUS_MAP пуста, `map_status` возвращает nil для любого значения — подробнее — report.md.

Вебхуков в спецификации не объявлено: EVENT_MAP не генерируется, статус — только опросом `fetch_status`.

## 5. Обработка ошибок с действиями

`ERROR_MAP` читается в два шага: сначала код ошибки из тела ответа, потом
HTTP-код. Символ действия — это политика обработки на стороне платформы;
первым аргументом `failure` уходит код платформы (см. ниже).

| Код ошибки провайдера | HTTP-код | Где встречается | Действие | Что делает сервис |
|---|---|---|---|---|
| `702` | любой — читается из тела ответа | только в примерах | `reject` | `failure(platform_failure_code(response.status, :reject), 'errors.702')` |

Коды, которые у отдельной операции означают не то, что в общей таблице (ERROR_MAP_BY_OPERATION):

| Операция | HTTP-код | Действие |
|---|---|---|
| `post-confirmThirdParty` | `400` | `reject` |
| `post-confirmThirdParty` | `401` | `alert` |
| `post-confirmThirdParty` | `403` | `alert` |
| `post-confirmThirdParty` | `422` | `reject` |
| `post-confirmThirdParty` | `500` | `retry_backoff` |
| `post-declineThirdParty` | `400` | `reject` |
| `post-declineThirdParty` | `401` | `alert` |
| `post-declineThirdParty` | `403` | `alert` |
| `post-declineThirdParty` | `422` | `reject` |
| `post-declineThirdParty` | `500` | `retry_backoff` |
| `post-payout` | `400` | `reject` |
| `post-payout` | `401` | `alert` |
| `post-payout` | `403` | `alert` |
| `post-payout` | `422` | `reject` |
| `post-payout` | `500` | `retry_backoff` |
| `post-storeDetail` | `400` | `reject` |
| `post-storeDetail` | `401` | `alert` |
| `post-storeDetail` | `403` | `alert` |
| `post-storeDetail` | `422` | `reject` |
| `post-storeDetail` | `500` | `retry_backoff` |
| `post-storeDetailAndSubmitThirdParty` | `400` | `reject` |
| `post-storeDetailAndSubmitThirdParty` | `401` | `alert` |
| `post-storeDetailAndSubmitThirdParty` | `403` | `alert` |
| `post-storeDetailAndSubmitThirdParty` | `422` | `reject` |
| `post-storeDetailAndSubmitThirdParty` | `500` | `retry_backoff` |
| `post-submitThirdParty` | `400` | `reject` |
| `post-submitThirdParty` | `401` | `alert` |
| `post-submitThirdParty` | `403` | `alert` |
| `post-submitThirdParty` | `422` | `reject` |
| `post-submitThirdParty` | `500` | `retry_backoff` |

| Действие | Что это значит для платформы |
|---|---|
| `reject` | операция отклоняется, повтор не поможет |

Первым аргументом `failure` уходит код платформы, а не наше действие: по HTTP-коду ответа (FAILURE_CODES: 400 → `:bad_request`, 401 → `:unauthorized`, 403 → `:forbidden`, 404 → `:not_found`, 409 → `:conflict`, 422 → `:unprocessable_entity`, 429 → `:too_many_requests`, 500 → `:internal_server_error`, 502 → `:bad_gateway`, 503 → `:service_unavailable`, 504 → `:gateway_timeout`), иначе по действию из ERROR_MAP (FAILURE_CODES_BY_ACTION: `reject` → `:unprocessable_entity`, `retry` → `:service_unavailable`, `retry_backoff` → `:service_unavailable`, `alert` → `:internal_server_error`, `escalate` → `:unprocessable_entity`). Действие остаётся политикой обработки — оно в ERROR_MAP, RETRY_POLICY и в таблицах выше.

Политика ретраев (RETRY_POLICY): платформа повторяет запрос при действиях `retry`, `retry_backoff`; по HTTP-кодам это —. Заголовок паузы до повтора в спецификации не объявлен.

Механизм ретраев, очереди и алерты — инфраструктура платформы; сервис не повторяет запросы сам, а только отдаёт политику данными.

Код, которого нет в таблицах, получает действие по умолчанию `reject` (DEFAULT_ERROR_ACTION).

Дедупликация. Идемпотентность в спецификации не объявлена: повтор запроса провайдер не отличит от нового — подробнее — report.md.

## 6. Параметры подключения

Этот раздел закрывает `## ProviderGateway config` из описания кейса; форма другая, потому что отдельный конфиг шлюза платформе не нужен, а адрес и авторизация берутся из спецификации (ответ экспертов 5 сентября 2026, `docs/QUESTIONS.md`, вопрос 15).

Всё ниже выведено из самой спецификации: адрес, ключи учётных данных, валюты, единицы и границы суммы, ограничения полей, путь и заголовок уведомлений. Отдельного конфига сервис не требует — это сводка для сверки. Значения вычислены тем же кодом, что предпроверки `check_conditions` сервиса: суммы — во внутренних (мажорных) единицах.

```yaml
providers:
  adyen_payout_v68:
    service: Provider::AdyenPayoutV68Service
    base_url: https://pal-test.adyen.com/pal/servlet/Payout/v68  # переменная окружения ADYEN_PAYOUT_V68_BASE_URL, адрес из серверов спецификации
    credentials: [api_key]
    request_methods: [create, status, check]
    currencies: []  # TODO: валюта в спецификации не выведена
    amount:
      platform_unit: major
      multiplier: 1  # TODO: единицы суммы не выведены, множитель 1 — задайте x-specgen-amount-unit в overlay
    fields:
      currency: { max_length: 3 }  # роль currency
```

### Куда мапить поля тела запроса

Строка на каждое поле тела запроса операции создания: чем его заполняет сервис. Пустая ячейка выражения — место под ручной маппинг: платформа такого реквизита не описывает, и выдумывать его инструмент не имеет права (эксперты кейса, 5 сентября 2026). Реквизиты получателя раскрыты по способам выплаты: ключ верхнего уровня в `operation.payout_requisite` — это payment_method шлюза, он же request_method.

| Поле тела запроса | Роль | Способ выплаты | Чем заполняется |
|---|---|---|---|
| `amount.currency` | `currency` | нет | — заполните вручную |
| `amount.value` | `amount` | нет | `operation.amount` |
| `billingAddress.city` | роль не распознана | нет | — заполните вручную |
| `billingAddress.country` | роль не распознана | нет | — заполните вручную |
| `billingAddress.houseNumberOrName` | роль не распознана | нет | — заполните вручную |
| `billingAddress.postalCode` | роль не распознана | нет | — заполните вручную |
| `billingAddress.stateOrProvince` | роль не распознана | нет | — заполните вручную |
| `billingAddress.street` | роль не распознана | нет | — заполните вручную |
| `card.cvc` | роль не распознана | нет | — заполните вручную |
| `card.expiryMonth` | роль не распознана | нет | — заполните вручную |
| `card.expiryYear` | роль не распознана | нет | — заполните вручную |
| `card.holderName` | роль не распознана | нет | — заполните вручную |
| `card.issueNumber` | роль не распознана | нет | — заполните вручную |
| `card.number` | роль не распознана | нет | — заполните вручную |
| `card.startMonth` | роль не распознана | нет | — заполните вручную |
| `card.startYear` | роль не распознана | нет | — заполните вручную |
| `fraudOffset` | роль не распознана | нет | — заполните вручную |
| `fundSource.additionalData` | роль не распознана | нет | — заполните вручную |
| `fundSource.billingAddress.city` | роль не распознана | нет | — заполните вручную |
| `fundSource.billingAddress.country` | роль не распознана | нет | — заполните вручную |
| `fundSource.billingAddress.houseNumberOrName` | роль не распознана | нет | — заполните вручную |
| `fundSource.billingAddress.postalCode` | роль не распознана | нет | — заполните вручную |
| `fundSource.billingAddress.stateOrProvince` | роль не распознана | нет | — заполните вручную |
| `fundSource.billingAddress.street` | роль не распознана | нет | — заполните вручную |
| `fundSource.card.cvc` | роль не распознана | нет | — заполните вручную |
| `fundSource.card.expiryMonth` | роль не распознана | нет | — заполните вручную |
| `fundSource.card.expiryYear` | роль не распознана | нет | — заполните вручную |
| `fundSource.card.holderName` | роль не распознана | нет | — заполните вручную |
| `fundSource.card.issueNumber` | роль не распознана | нет | — заполните вручную |
| `fundSource.card.number` | роль не распознана | нет | — заполните вручную |
| `fundSource.card.startMonth` | роль не распознана | нет | — заполните вручную |
| `fundSource.card.startYear` | роль не распознана | нет | — заполните вручную |
| `fundSource.shopperEmail` | роль не распознана | нет | — заполните вручную |
| `fundSource.shopperName.firstName` | роль не распознана | нет | — заполните вручную |
| `fundSource.shopperName.lastName` | роль не распознана | нет | — заполните вручную |
| `fundSource.telephoneNumber` | `recipient_phone` | нет | — заполните вручную |
| `merchantAccount` | роль не распознана | нет | — заполните вручную |
| `recurring.contract` | роль не распознана | нет | — заполните вручную |
| `recurring.recurringDetailName` | роль не распознана | нет | — заполните вручную |
| `recurring.recurringExpiry` | роль не распознана | нет | — заполните вручную |
| …и ещё 10 полей — смотрите build_payload | — | — | — |

## 7. Схема подписи вебхука

Вебхуков в спецификации не объявлено: подписи нет, `process_callback` отказывает `failure(:not_implemented, 'errors.webhooks_not_supported')`.

## 8. Как подключить в приложение

1. Положите `adyen_payout_v68_service.rb` в каталог провайдеров платформы рядом с
   остальными наследниками `Provider::BaseService`; класс — `Provider::AdyenPayoutV68Service`.
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

- обязательное поле `billingAddress.city` без роли: в payload со значением `nil` и TODO (ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml) (подробнее — report.md)
- обязательное поле `billingAddress.country` без роли: в payload со значением `nil` и TODO (ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml) (подробнее — report.md)
- обязательное поле `billingAddress.houseNumberOrName` без роли: в payload со значением `nil` и TODO (ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml) (подробнее — report.md)
- обязательное поле `billingAddress.postalCode` без роли: в payload со значением `nil` и TODO (ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml) (подробнее — report.md)
- обязательное поле `billingAddress.street` без роли: в payload со значением `nil` и TODO (ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml) (подробнее — report.md)
- обязательное поле `fundSource.billingAddress.city` без роли: в payload со значением `nil` и TODO (ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml) (подробнее — report.md)
- обязательное поле `fundSource.billingAddress.country` без роли: в payload со значением `nil` и TODO (ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml) (подробнее — report.md)
- обязательное поле `fundSource.billingAddress.houseNumberOrName` без роли: в payload со значением `nil` и TODO (ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml) (подробнее — report.md)
- обязательное поле `fundSource.billingAddress.postalCode` без роли: в payload со значением `nil` и TODO (ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml) (подробнее — report.md)
- обязательное поле `fundSource.billingAddress.street` без роли: в payload со значением `nil` и TODO (ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml) (подробнее — report.md)
- обязательное поле `fundSource.shopperName.firstName` без роли: в payload со значением `nil` и TODO (ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml) (подробнее — report.md)
- обязательное поле `fundSource.shopperName.lastName` без роли: в payload со значением `nil` и TODO (ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml) (подробнее — report.md)
- обязательное поле `merchantAccount` без роли: в payload со значением `nil` и TODO (ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml) (подробнее — report.md)
- поле `reference` получило роль provider_operation_id с уверенностью ниже порога (эвристика 0.50): композитное сопоставление: name 2.0 (общие токены с синонимом `acquirer_reference`: reference (50%)), structure 4.0 (родитель `PayoutRequest` содержит токен `payout` из подсказок роли), type 1.0 (type string допустим для роли) = 7.0 из 14.0; следующая external_id 0.21 (подробнее — report.md)
- обязательное поле `shopperName.firstName` без роли: в payload со значением `nil` и TODO (ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml) (подробнее — report.md)
- обязательное поле `shopperName.lastName` без роли: в payload со значением `nil` и TODO (ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml) (подробнее — report.md)
- единицы суммы не выведены (без кода валюты экспоненту ISO 4217 определить нельзя): множитель 1 и TODO у AMOUNT_MULTIPLIER (подробнее — report.md)
- заголовок идемпотентности не найден: ключ не отправляется (подробнее — report.md)
- операция post-declineThirdParty не отображена на контракт: отдельный метод с TODO (подробнее — report.md)
- операция post-storeDetail не отображена на контракт: отдельный метод с TODO (подробнее — report.md)
- операция post-storeDetailAndSubmitThirdParty не отображена на контракт: отдельный метод с TODO (подробнее — report.md)
- операция post-submitThirdParty не отображена на контракт: отдельный метод с TODO (подробнее — report.md)
