# Отчёт о разборе спецификации «CardPay Global Payouts API»

| | |
|---|---|
| Провайдер | `cardpay` |
| Спецификация | `cardpay.yaml`, версия 2.4.0, OpenAPI 3.0.3 |
| Класс сервиса | `Provider::CardpayService` |
| Файл сервиса | `cardpay_service.rb` |

Отчёт сгенерирован инструментом integrate из той же модели провайдера, что и
сервис: всё, о чём здесь сказано, лежит в сгенерированных файлах рядом.
Каждая строка ниже — действие, а не констатация: если элемент спецификации
попал в отчёт, к нему приложено, что сделал инструмент и чем это закрыть.
Генерация не блокируется никогда, поэтому отчёт описывает готовые файлы, а не
причину отказа.

## 1. Сводка

| Показатель | Значение |
|---|---|
| Операции | всего 6: отображено на контракт 3, вне контракта 3, без роли (unmapped) 0 |
| Схемы и поля | схем 13, полей 58: скалярных 51, контейнеров 7 |
| Роли полей | 32 из 51 скалярных: по справочнику 28, эвристика выше порога 4 |
| Поля без роли | 19: обязательных 7, необязательных 12 |
| Статусы | 5: сопоставлено 5, не сопоставлено 0 |
| События вебхука | 4: сопоставлено 4, не сопоставлено 0 |
| Коды ошибок | кодов провайдера 13: в enum 8, только в примерах 5; общих правил по HTTP-коду 7 |
| Условия взаимодействия | 10: из структуры 9, из прозы описаний 1 |
| Предупреждения | 42: ошибок 0, предупреждений 15, справок 27 |

Сгенерированные артефакты:

| Файл | Что это | Строк |
|---|---|---|
| `cardpay_service.rb` | сервис по контракту базового класса | 509 |
| `INTEGRATION.md` | документация интеграции | 260 |
| `fixtures.json` | примеры запросов, ответов и уведомлений | 632 |
| `report.md` | этот отчёт | считается в момент записи |

### Сверка сгенерированного со спецификацией

Тела из `fixtures.json` проверены схемами той же спецификации, из которой они
выведены: запрос — схемой тела своей операции, ответ — схемой своего кода
ответа, уведомление — схемой тела вебхука. Это замыкает круг: спецификация →
разбор → генерация → обратно к спецификации. Тела, которых спецификация не
обещала (операция без `requestBody`, ответ `204`), в счёт не идут — проверять
там нечего.

**Сверено тел: 30; прошли схему: 27; не прошли: 1; синтезированы и схему не проходят: 1; сверить не с чем: 1.**

**Не прошли схему — 1** — тело взято из примеров спецификации дословно и не проходит её же схему: спорят спецификация и её собственная схема, и это надо прочитать глазами

- **уведомление webhook transfer.returned** — поле `failure.reason_code` не проходит `enum`; место: `$.paths['/webhooks/transfer-events'].post.requestBody.content['application/json'].schema`

**Синтезированы и схему не проходят — 1** — значение собрал генератор по типу поля либо фикстура негативна намеренно, поэтому расхождение с `pattern` или `enum` законно и ошибкой прогона не считается

- **уведомление webhook unknown_event** — поле `event_type` не проходит `enum`; место: `$.paths['/webhooks/transfer-events'].post.requestBody.content['application/json'].schema`

**Сверить не с чем — 1** — схемы в спецификации нет, сверять не с чем — это пробел спецификации, а не итог проверки

- **ответ transferEventCallback 202** — спецификация обещала тело, но не описала его — сверить нечего; место: `$.paths['/webhooks/transfer-events'].post.responses['202']`

### Прогон собранного класса

Сгенерированный класс загружен в изолированный модуль: на месте
`Provider::BaseService` — подмена, записывающая вызовы хелперов, на месте
HTTP-клиента — заглушка, отвечающая телами из `fixtures.json`. Сети в
прогоне нет. Проверяется то, чего сверка со схемами показать не может:
что класс загружается, зовёт клиента по адресу и методу своей операции,
отправляет заголовок авторизации со значением из учётных данных и
детерминированный ключ идемпотентности, собирает тело запроса из ролей,
читает идентификатор из ответа и переводит каждый статус и каждое
событие в тот хелпер платформы, который обещает INTEGRATION.md.

**Проверок: 37; прошло: 30; не прошло: 0; не проверено: 7.**

**Не проверено — 7** — вызывать было нечем или незачем: спецификация не описала операции, фикстура не даёт данных либо инструмент сам оставил в этом месте TODO — пробел уже назван в разделах ниже

- **прогон: verify_webhook_signature — подпись уведомления webhook transfer.declined** — профиль подписи проверяет допуск метки времени по часам, а фикстура подписана фиксированной меткой (SPECGEN_TIMESTAMP): итог такой проверки зависел бы от даты прогона, а не от кода
- **прогон: verify_webhook_signature — подпись уведомления webhook transfer.queued** — профиль подписи проверяет допуск метки времени по часам, а фикстура подписана фиксированной меткой (SPECGEN_TIMESTAMP): итог такой проверки зависел бы от даты прогона, а не от кода
- **прогон: verify_webhook_signature — подпись уведомления webhook transfer.returned** — профиль подписи проверяет допуск метки времени по часам, а фикстура подписана фиксированной меткой (SPECGEN_TIMESTAMP): итог такой проверки зависел бы от даты прогона, а не от кода
- **прогон: verify_webhook_signature — подпись уведомления webhook transfer.succeeded** — профиль подписи проверяет допуск метки времени по часам, а фикстура подписана фиксированной меткой (SPECGEN_TIMESTAMP): итог такой проверки зависел бы от даты прогона, а не от кода
- **прогон: verify_webhook_signature — подпись уведомления webhook signature_invalid** — профиль подписи проверяет допуск метки времени по часам, а фикстура подписана фиксированной меткой (SPECGEN_TIMESTAMP): итог такой проверки зависел бы от даты прогона, а не от кода
- **прогон: verify_webhook_signature — подпись уведомления webhook unknown_event** — профиль подписи проверяет допуск метки времени по часам, а фикстура подписана фиксированной меткой (SPECGEN_TIMESTAMP): итог такой проверки зависел бы от даты прогона, а не от кода
- **прогон: process_callback — уведомление webhook signature_invalid** — профиль подписи проверяет допуск метки времени по часам, а фикстура подписана фиксированной меткой (SPECGEN_TIMESTAMP): итог такой проверки зависел бы от даты прогона, а не от кода

## 2. Покрытие спецификации

**Покрытие: 66 % (64 из 97 элементов). В границах контракта: 94 % (64 из 68).**

Формула первой цифры — доля покрытых элементов от всех: сумма покрытого по
семи измерениям, делённая на сумму найденного. Среднее по измерениям
отброшено намеренно: измерения разного размера, и четыре события вебхука не
должны весить столько же, сколько триста полей схем. Покрытым считается
элемент, у которого в сгенерированном коде есть ветка, выражение или строка
таблицы; поля тел запросов считаются по операциям, поля входящих тел — по
схемам.

Цифры две, потому что и вопроса два. Первая отвечает «сколько спецификации
задействовано»: она считается от всех найденных элементов и ничего не прощает.
Вторая — «сколько не упущено из того, что контракт `Provider::BaseService`
вообще способен использовать»: его четыре метода читают из входящего тела поле
события уведомления и поля с ролями `status`, `provider_operation_id`,
`error_code`, `external_id`, собирают тело запроса по ролям — и места, куда
положить, например, адрес держателя счёта, у них нет ни одного.

Знаменатель второй цифры меньше первого на 29 элементов, и вот они все, по
видам:

- **Поля тел запросов** — 4: необязательные поля без роли — в payload они не идут намеренно (docs/PRINCIPLES.md, раздел «Что генерируем при неполной спеке»), а не по недосмотру
- **Поля тел ответов и уведомлений** — 25: роль поля не входит в читаемые сервисом или не выведена вовсе — методам контракта такое поле прочитать некуда

Больше не вычтено ничего: коды ответов, статусы, события вебхука, условия
взаимодействия, обязательные поля тел запросов и поля запросов с выведенной
ролью остаются в знаменателе второй цифры целиком — даже когда не покрыты,
потому что их непокрытие — пробел интеграции, а не свойство контракта.
Вычтенное не спрятано: каждый вычтенный элемент назван ниже, в «Что не покрыто
и почему», со своей причиной и своей корзиной.

| Измерение | Найдено | Покрыто | Покрытие |
|---|---|---|---|
| Операции | 6 | 6 | 100 % |
| Поля тел запросов | 15 | 8 | 53 % |
| Поля тел ответов и уведомлений | 38 | 13 | 34 % |
| Коды ответов | 19 | 19 | 100 % |
| Статусы | 5 | 5 | 100 % |
| События вебхука | 4 | 4 | 100 % |
| Условия взаимодействия | 10 | 9 | 90 % |

### Что не покрыто и почему

Непокрыто 33: вне контракта 8, структурных исключений 21, требует ручной
работы 4. Корзина каждого элемента вычислена из его причины, таблица причин —
Generators::Report::Gap::BUCKETS.

**Требует ручной работы — 4.** Единственная корзина, адресованная человеку:
здесь спецификация описала то, что контракт умеет использовать, а интеграция
этого не взяла. Перечислена целиком, поимённо и первой — это и есть список
того, что стоит доделать руками.

**Поля тел запросов** — не покрыто 3

- `createTransfer: destination.expiry_month` — обязательное поле без роли: в payload попало с TODO и значением по умолчанию, значение подставит человек
- `createTransfer: destination.expiry_year` — обязательное поле без роли: в payload попало с TODO и значением по умолчанию, значение подставит человек
- `createTransfer: destination.wallet_id` — обязательное поле без роли: в payload попало с TODO и значением по умолчанию, значение подставит человек

**Условия взаимодействия** — не покрыто 1

- `field_max_length transfer_id` — проверка не сгенерирована: у платформы нет выражения для поля transfer_id

**Вне контракта — 8.** Ресурсы спецификации, которых методы контракта не
касаются вовсе: чужие операции и их поля, коды и схемы. Контракт про выплаты;
считать пробелом интеграции отсутствие в ней подписок, споров или хранения
карт — то же самое, что считать пробелом отсутствие метода для чужого API.
Свёрнуто числом с примерами.

- **Поля тел ответов и уведомлений** — 8, например: `RefundResource.transfer_id`, `RefundResource.amount_minor`, `RefundResource.currency`

**Структурные исключения метрики — 21.** Элементы, которым в методах контракта
нет места по построению: поле входящего тела засчитывается, только когда его
роль читает один из четырёх методов; необязательное поле без роли в payload не
идёт намеренно; код, объявленный диапазоном, ветки не даёт. Это устройство
метрики и контракта, а не пропуск разбора. Свёрнуто числом с примерами.

- **Поля тел запросов** — 4, например: `createTransfer: destination.holder_name`, `createTransfer: destination.issuer_country`, `createTransfer: statement_descriptor`
- **Поля тел ответов и уведомлений** — 17, например: `TransferResource.amount_minor`, `TransferResource.currency`, `TransferResource.destination.method`

## 3. Неоднозначности

Элементы, о которых спецификация говорит недостаточно, чтобы решение было
однозначным. Инструмент решил сам — что именно, сказано под каждым кодом; от
человека нужна проверка, а не заполнение пропуска.

### `conditional_required_hint` — 4

Что сделал инструмент: поле помечено условно обязательным, условие вынесено в комментарий над записью payload

- **`$.components.schemas.Destination`** — `expiry_month` выглядит условно обязательным (`method` = card), но схема не задаёт условия; фрагмент ниже задаёт его формально

  ```yaml
  - target: "$.components.schemas.Destination"
    update:
      x-jsonschema-if:
        properties:
          method:
            const: card
      x-jsonschema-then:
        required: [expiry_month]
  ```
- **`$.components.schemas.Destination`** — `expiry_year` выглядит условно обязательным (`method` = card), но схема не задаёт условия; фрагмент ниже задаёт его формально

  ```yaml
  - target: "$.components.schemas.Destination"
    update:
      x-jsonschema-if:
        properties:
          method:
            const: card
      x-jsonschema-then:
        required: [expiry_year]
  ```
- **`$.components.schemas.Destination`** — `pan` выглядит условно обязательным (`method` = card), но схема не задаёт условия; фрагмент ниже задаёт его формально

  ```yaml
  - target: "$.components.schemas.Destination"
    update:
      x-jsonschema-if:
        properties:
          method:
            const: card
      x-jsonschema-then:
        required: [pan]
  ```
- **`$.components.schemas.Destination`** — `wallet_id` выглядит условно обязательным (`method` = wallet), но схема не задаёт условия; фрагмент ниже задаёт его формально

  ```yaml
  - target: "$.components.schemas.Destination"
    update:
      x-jsonschema-if:
        properties:
          method:
            const: wallet
      x-jsonschema-then:
        required: [wallet_id]
  ```

### `field_role_low_confidence` — 1

Что сделал инструмент: роль присвоена лучшему кандидату, в коде рядом с полем — комментарий с уверенностью

- **`$.paths['/webhooks/transfer-events'].post.parameters[1]`** — обязательный параметр `webhook-timestamp` (заголовок): роль recipient_phone выведена с низкой уверенностью 0.24 (порог 0.60); кандидаты: recipient_phone 0.24; без него запрос не уйдёт, поэтому в код оно попадёт как recipient_phone с TODO — проверьте роль и закрепите её фрагментом ниже

  ```yaml
  - target: "$.paths['/webhooks/transfer-events'].post.parameters[1]"
    update:
      x-specgen-role: recipient_phone  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```

### `required_field_role_unknown` — 4

Что сделал инструмент: в исходящем теле поле включено в payload со значением примера или nil и TODO рядом; во входящем — ищется структурно

- **`$.components.schemas.TransferEvent.properties.event_id`** — обязательное поле `event_id` (string, max_length 64): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; без него запрос не уйдёт, поэтому в код оно попадёт с TODO — задайте роль фрагментом ниже или добавьте синоним в rules/roles.yml

  ```yaml
  - target: "$.components.schemas.TransferEvent.properties.event_id"
    update:
      x-specgen-role: TODO  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.TransferEvent.properties.event_type`** — обязательное поле `event_type` (string, enum ["transfer.succeeded", "transfer.declined", "transfer.returned", "transfer.queued"]): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; без него запрос не уйдёт, поэтому в код оно попадёт с TODO — задайте роль фрагментом ниже или добавьте синоним в rules/roles.yml

  ```yaml
  - target: "$.components.schemas.TransferEvent.properties.event_type"
    update:
      x-specgen-role: TODO  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.TransferEvent.properties.occurred_at`** — обязательное поле `occurred_at` (string, format date-time): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; без него запрос не уйдёт, поэтому в код оно попадёт с TODO — задайте роль фрагментом ниже или добавьте синоним в rules/roles.yml

  ```yaml
  - target: "$.components.schemas.TransferEvent.properties.occurred_at"
    update:
      x-specgen-role: TODO  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.paths['/webhooks/transfer-events'].post.parameters[0]`** — обязательный параметр `webhook-id` (заголовок) (string, max_length 64): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; без него запрос не уйдёт, поэтому в код оно попадёт с TODO — задайте роль фрагментом ниже или добавьте синоним в rules/roles.yml

  ```yaml
  - target: "$.paths['/webhooks/transfer-events'].post.parameters[0]"
    update:
      x-specgen-role: TODO  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```

### `spec_element_unsupported` — 1

Что сделал инструмент: значение расширения отвергнуто, элемент разобран без него

- **`$.components.schemas.CreateTransferRequest.properties.metadata`** — `metadata` — свободная карта (`additionalProperties` или объект без `properties`): ключи спецификацией не перечислены, поэтому значением поля остаётся хеш, который заполняют вручную
  готового overlay-фрагмента нет: исправляется правкой спецификации

### Как собрать overlay

Фрагменты выше — действия одного документа OpenAPI Overlay 1.0.0
(<https://spec.openapis.org/overlay/v1.0.0.html>). Соберите файл
`cardpay.overlay.yaml`, вставив их подряд под ключ `actions`,
замените значения `TODO` и перегенерируйте:

```yaml
overlay: 1.0.0
info:
  title: cardpay disambiguation
  version: 1.0.0
actions:
- target: "$..."
  update:
    x-specgen-role: ...
```

```sh
./integrate --spec cardpay.yaml --provider cardpay --overlay cardpay.overlay.yaml
```

Склеивать руками не обязательно: флаг `--fix` пишет этот файл пятым артефактом
рядом с остальными. Слоты в нём закомментированы — выбор между кандидатами
остаётся за человеком, потому что раскомментированная строка читается
инструментом как достоверная.

## 4. Операции вне контракта и без роли

Операция, которой нет места в контракте базового класса, не выбрасывается: для
неё генерируется отдельный публичный метод, и здесь сказано какой. Роль
операции закрепляется синонимом в `rules/operations.yml` — расширения
`x-specgen-role` для операции в модели нет (`docs/IR.md`, таблица расширений).

| Операция | HTTP-метод и путь | Роль | Что сгенерировано | Что сделать |
|---|---|---|---|---|
| `cancelTransfer` | `POST /v2/transfers/{transfer_id}/cancel` | `cancel` (эвристика 0.95) | `cancel(operation)` | ничего: в `Provider::BaseService` нет метода для такой роли, платформа зовёт этот метод напрямую |
| `createRefund` | `POST /v2/refunds` | `refund` (эвристика 0.92) | `refund(operation)` | ничего: в `Provider::BaseService` нет метода для такой роли, платформа зовёт этот метод напрямую |
| `getAccountBalance` | `GET /v2/accounts/balance` | `balance` (эвристика 0.95) | `balance()` | ничего: в `Provider::BaseService` нет метода для такой роли, платформа зовёт этот метод напрямую |

## 5. Противоречия в самой спецификации

Спецификация расходится сама с собой или со своими соседями: enum против
примеров, коды ответов одной операции против другой, проза против структуры.
Инструмент выбрал, чему верить, и продолжил; правится это правкой
спецификации, а не настройкой инструмента.

### `error_code_undeclared` — 5

Что сделал инструмент: код добавлен в ERROR_MAP: карта строится как объединение enum и примеров

- **`$.paths['/v2/transfers'].post.responses['401'].content['application/json'].example.error.code`** — код unauthorized встречается в примере, но не объявлен в enum поля кода ошибки ($.components.schemas.TransferFailure.properties.reason_code); карта ошибок строится как объединение enum и примеров, спецификацию стоит поправить
- **`$.paths['/v2/transfers'].post.responses['429'].content['application/json'].example.error.code`** — код rate_limited встречается в примере, но не объявлен в enum поля кода ошибки ($.components.schemas.TransferFailure.properties.reason_code); карта ошибок строится как объединение enum и примеров, спецификацию стоит поправить
- **`$.paths['/v2/transfers/{transfer_id}'].get.responses['404'].content['application/json'].example.error.code`** — код transfer_not_found встречается в примере, но не объявлен в enum поля кода ошибки ($.components.schemas.TransferFailure.properties.reason_code); карта ошибок строится как объединение enum и примеров, спецификацию стоит поправить
- **`$.paths['/v2/transfers/{transfer_id}/cancel'].post.responses['409'].content['application/json'].example.error.code`** — код transfer_not_cancelable встречается в примере, но не объявлен в enum поля кода ошибки ($.components.schemas.TransferFailure.properties.reason_code); карта ошибок строится как объединение enum и примеров, спецификацию стоит поправить
- **`$.paths['/webhooks/transfer-events'].post.requestBody.content['application/json'].examples.returned.value.failure.reason_code`** — код account_closed встречается в примере, но не объявлен в enum поля кода ошибки ($.components.schemas.TransferFailure.properties.reason_code); карта ошибок строится как объединение enum и примеров, спецификацию стоит поправить

### `error_code_unused` — 3

Что сделал инструмент: правило для кода построено по rules/errors.yml, в примерах его проверить нечем

- **`$.components.schemas.TransferFailure.properties.reason_code.enum[1]`** — код expired_card объявлен в enum, но не встречается ни в одном примере; правило обработки построено по справочнику
- **`$.components.schemas.TransferFailure.properties.reason_code.enum[3]`** — код issuer_unavailable объявлен в enum, но не встречается ни в одном примере; правило обработки построено по справочнику
- **`$.components.schemas.TransferFailure.properties.reason_code.enum[4]`** — код limit_exceeded объявлен в enum, но не встречается ни в одном примере; правило обработки построено по справочнику

### `field_role_conflict` — 1

Что сделал инструмент: роль оставлена полю с большей уверенностью, второе получило следующего кандидата

- **`$.components.schemas.RefundResource.properties.transfer_id`** — обязательное поле `transfer_id`: роль provider_operation_id (0.90) уже у `refund_id` (0.90) в той же схеме; других кандидатов нет, роль не выведена — задайте её фрагментом ниже

### `undeclared_status_code` — 5

Что сделал инструмент: для кода достроено общее правило ERROR_MAP по HTTP-коду

- **`$.paths['/v2/accounts/balance'].get`** — операция getAccountBalance не объявляет 400, 404, 409, 422, 429, 500, объявленные у соседних операций (createTransfer, getTransfer); для них достроены общие правила
- **`$.paths['/v2/refunds'].post`** — операция createRefund не объявляет 401, 409, 429, 500, объявленные у соседних операций (createTransfer); для них достроены общие правила
- **`$.paths['/v2/transfers'].post`** — операция createTransfer не объявляет 404, объявленные у соседних операций (getTransfer); для них достроены общие правила
- **`$.paths['/v2/transfers/{transfer_id}'].get`** — операция getTransfer не объявляет 400, 409, 422, 429, 500, объявленные у соседних операций (createTransfer); для них достроены общие правила
- **`$.paths['/v2/transfers/{transfer_id}/cancel'].post`** — операция cancelTransfer не объявляет 400, 401, 422, 429, 500, объявленные у соседних операций (createTransfer); для них достроены общие правила

## 6. Справки

Факты, о которых читателю стоит знать; решения за человека инструмент здесь не
принимал. Списки сокращены до первых 5 элементов в группе — полный набор
виден в `./integrate analyze --spec cardpay.yaml`.

**`field_role_unknown`** — 15

- `$.components.schemas.AccountBalance.properties.available_minor` — необязательное поле `available_minor` (integer, format int64): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; в запрос оно не попадёт; если оно нужно, задайте роль фрагментом ниже
- `$.components.schemas.AccountBalance.properties.pending_minor` — необязательное поле `pending_minor` (integer, format int64): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; в запрос оно не попадёт; если оно нужно, задайте роль фрагментом ниже
- `$.components.schemas.AccountBalance.properties.updated_at` — необязательное поле `updated_at` (string, format date-time): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; в запрос оно не попадёт; если оно нужно, задайте роль фрагментом ниже
- `$.components.schemas.CreateTransferRequest.properties.statement_descriptor` — необязательное поле `statement_descriptor` (string, pattern "^[A-Za-z0-9 .\\-]{1,22}$", max_length 22): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; в запрос оно не попадёт; если оно нужно, задайте роль фрагментом ниже
- `$.components.schemas.Destination.properties.expiry_month` — необязательное поле `expiry_month` (integer, minimum 1, maximum 12): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; в запрос оно не попадёт; если оно нужно, задайте роль фрагментом ниже
- и ещё 10 с тем же кодом

**`operation_unmapped`** — 3, подробности в разделе 4

- `$.paths['/v2/accounts/balance'].get` — распознана как balance, но в Provider::BaseService нет метода для такой роли; она генерируется отдельным публичным методом и остаётся вне контракта
- `$.paths['/v2/refunds'].post` — распознана как refund, но в Provider::BaseService нет метода для такой роли; она генерируется отдельным публичным методом и остаётся вне контракта
- `$.paths['/v2/transfers/{transfer_id}/cancel'].post` — распознана как cancel, но в Provider::BaseService нет метода для такой роли; она генерируется отдельным публичным методом и остаётся вне контракта

## 7. Что доделать руками

1. Заполните обязательное поле `destination.expiry_month` в build_payload: роль не выведена (ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml) — добавьте синоним в `rules/roles.yml` или задайте `x-specgen-role` в overlay
2. Заполните обязательное поле `destination.expiry_year` в build_payload: роль не выведена (ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml) — добавьте синоним в `rules/roles.yml` или задайте `x-specgen-role` в overlay
3. Заполните обязательное поле `destination.wallet_id` в build_payload: роль не выведена (ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml) — добавьте синоним в `rules/roles.yml` или задайте `x-specgen-role` в overlay
4. Заполните реквизит `expiry_month` для способа выплаты `card`: выражения платформы для него нет, добавьте его в rules/contract.yml (platform.requisites) или подставьте значение из `operation.payout_requisite` вручную
5. Заполните реквизит `expiry_year` для способа выплаты `card`: выражения платформы для него нет, добавьте его в rules/contract.yml (platform.requisites) или подставьте значение из `operation.payout_requisite` вручную
6. Заполните реквизит `holder_name` для способа выплаты `card`: выражения платформы для него нет, добавьте его в rules/contract.yml (platform.requisites) или подставьте значение из `operation.payout_requisite` вручную
7. Заполните реквизит `issuer_country` для способа выплаты `card`: выражения платформы для него нет, добавьте его в rules/contract.yml (platform.requisites) или подставьте значение из `operation.payout_requisite` вручную
8. Заполните реквизит `holder_name` для способа выплаты `wallet`: выражения платформы для него нет, добавьте его в rules/contract.yml (platform.requisites) или подставьте значение из `operation.payout_requisite` вручную
9. Заполните реквизит `issuer_country` для способа выплаты `wallet`: выражения платформы для него нет, добавьте его в rules/contract.yml (platform.requisites) или подставьте значение из `operation.payout_requisite` вручную
10. Заполните реквизит `wallet_id` для способа выплаты `wallet`: выражения платформы для него нет, добавьте его в rules/contract.yml (platform.requisites) или подставьте значение из `operation.payout_requisite` вручную
11. Вызовите `verify_webhook_signature(raw_body, headers)` на маршруте вебхука до разбора JSON: `process_callback` получает уже разобранное тело, а HMAC считается по сырым байтам — либо кладите байты и заголовки в аргумент по выражениям rules/contract.yml
12. Решите судьбу необязательного поля `destination.holder_name`: роли нет, в payload оно не попало
13. Решите судьбу необязательного поля `destination.issuer_country`: роли нет, в payload оно не попало
14. Решите судьбу необязательного поля `statement_descriptor`: роли нет, в payload оно не попало
15. Решите судьбу необязательного поля `metadata`: роли нет, в payload оно не попало
16. Проверьте значения фикстуры `createRefund 400`: тело собрано не из примеров спецификации (`schema_example`)
17. Проверьте значения фикстуры `transferEventCallback 200`: тело собрано не из примеров спецификации (`schema_example`)
18. Проверьте значения фикстуры `transferEventCallback 202`: тело собрано не из примеров спецификации (`undeclared`)
19. Проверьте значения фикстуры `webhook transfer.queued`: тело собрано не из примеров спецификации (`schema_example`)
20. Проверьте значения фикстуры `webhook signature_invalid`: тело собрано не из примеров спецификации (`synthesized`)
21. Проверьте значения фикстуры `webhook unknown_event`: тело собрано не из примеров спецификации (`synthesized`)

Итого: 21 пункт.
