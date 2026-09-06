# Отчёт о разборе спецификации «Paystack»

| | |
|---|---|
| Провайдер | `paystack_v1` |
| Спецификация | `paystack_v1.yaml`, версия 1.0.0, OpenAPI 3.0.1 |
| Класс сервиса | `Provider::PaystackV1Service` |
| Файл сервиса | `paystack_v1_service.rb` |

Отчёт сгенерирован инструментом integrate из той же модели провайдера, что и
сервис: всё, о чём здесь сказано, лежит в сгенерированных файлах рядом.
Каждая строка ниже — действие, а не констатация: если элемент спецификации
попал в отчёт, к нему приложено, что сделал инструмент и чем это закрыть.
Генерация не блокируется никогда, поэтому отчёт описывает готовые файлы, а не
причину отказа.

## 1. Сводка

| Показатель | Значение |
|---|---|
| Операции | всего 120: отображено на контракт 46, вне контракта 13, без роли (unmapped) 61 |
| Схемы и поля | схем 250, полей 650: скалярных 634, контейнеров 16 |
| Роли полей | 476 из 634 скалярных: по справочнику 444, эвристика ниже порога 32 |
| Поля без роли | 158: обязательных 48, необязательных 110 |
| Статусы | 0: сопоставлено 0, не сопоставлено 0 |
| События вебхука | 0: сопоставлено 0, не сопоставлено 0 |
| Коды ошибок | кодов провайдера 0: в enum 0, только в примерах 0; общих правил по HTTP-коду 1 |
| Условия взаимодействия | 9: из структуры 9, из прозы описаний 0 |
| Предупреждения | 469: ошибок 0, предупреждений 133, справок 336 |

Сгенерированные артефакты:

| Файл | Что это | Строк |
|---|---|---|
| `paystack_v1_service.rb` | сервис по контракту базового класса | 3482 |
| `INTEGRATION.md` | документация интеграции | 502 |
| `fixtures.json` | примеры запросов, ответов и уведомлений | 7843 |
| `report.md` | этот отчёт | считается в момент записи |

### Сверка сгенерированного со спецификацией

Тела из `fixtures.json` проверены схемами той же спецификации, из которой они
выведены: запрос — схемой тела своей операции, ответ — схемой своего кода
ответа, уведомление — схемой тела вебхука. Это замыкает круг: спецификация →
разбор → генерация → обратно к спецификации. Тела, которых спецификация не
обещала (операция без `requestBody`, ответ `204`), в счёт не идут — проверять
там нечего.

**Сверено тел: 484; прошли схему: 355; не прошли: 0; синтезированы и схему не проходят: 9; сверить не с чем: 120.**

**Синтезированы и схему не проходят — 9** — значение собрал генератор по типу поля либо фикстура негативна намеренно, поэтому расхождение с `pattern` или `enum` законно и ошибкой прогона не считается

- **запрос subaccount_create** — поле `percentage_charge` не проходит `format`; место: `$.paths['/subaccount'].post.requestBody.content['application/json'].schema`
- **запрос subaccount_update** — поле `percentage_charge` не проходит `format`; место: `$.paths['/subaccount/{code}'].put.requestBody.content['application/json'].schema`
- **запрос subscription_disable** — поле `тело целиком` не проходит `required`; место: `$.paths['/subscription/disable'].post.requestBody.content['application/json'].schema`
- **запрос subscription_enable** — поле `тело целиком` не проходит `required`; место: `$.paths['/subscription/enable'].post.requestBody.content['application/json'].schema`
- **запрос paymentRequest_update** — поле `due_date` не проходит `format`; место: `$.paths['/paymentrequest/{id}'].put.requestBody.content['application/json'].schema`
- **запрос transferrecipient_bulk** — поле `batch.0` не проходит `required`; место: `$.paths['/transferrecipient/bulk'].post.requestBody.content['application/json'].schema`
- **запрос put_transferrecipient_code** — поле `тело целиком` не проходит `required`; место: `$.paths['/transferrecipient/{code}'].put.requestBody.content['application/json'].schema`
- **запрос transfer_bulk** — поле `transfers.0` не проходит `required` (и ещё расхождений: 1); место: `$.paths['/transfer/bulk'].post.requestBody.content['application/json'].schema`
- и ещё 1 того же вида

**Сверить не с чем — 120** — схемы в спецификации нет, сверять не с чем — это пробел спецификации, а не итог проверки

- **ответ transaction_initialize default** — спецификация обещала тело, но не описала его — сверить нечего; место: `$.paths['/transaction/initialize'].post.responses.default`
- **ответ transaction_verify default** — спецификация обещала тело, но не описала его — сверить нечего; место: `$.paths['/transaction/verify/{reference}'].get.responses.default`
- **ответ transaction_list default** — спецификация обещала тело, но не описала его — сверить нечего; место: `$.paths['/transaction'].get.responses.default`
- **ответ transaction_fetch default** — спецификация обещала тело, но не описала его — сверить нечего; место: `$.paths['/transaction/{id}'].get.responses.default`
- **ответ transaction_timeline default** — спецификация обещала тело, но не описала его — сверить нечего; место: `$.paths['/transaction/timeline/{id_or_reference}'].get.responses.default`
- **ответ transaction_totals default** — спецификация обещала тело, но не описала его — сверить нечего; место: `$.paths['/transaction/totals'].get.responses.default`
- **ответ transaction_download default** — спецификация обещала тело, но не описала его — сверить нечего; место: `$.paths['/transaction/export'].get.responses.default`
- **ответ transaction_chargeAuthorization default** — спецификация обещала тело, но не описала его — сверить нечего; место: `$.paths['/transaction/charge_authorization'].post.responses.default`
- и ещё 112 того же вида

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

**Проверок: 131; прошло: 127; не прошло: 1; не проверено: 3.**

**Не прошло — 1** — класс сделал не то, что обещают фикстуры и таблицы INTEGRATION.md: это расхождение сгенерированного кода с сгенерированной документацией, и его надо прочитать глазами

- **прогон: create_request — тело запроса** — в теле запроса нет ключа `source`

**Не проверено — 3** — вызывать было нечем или незачем: спецификация не описала операции, фикстура не даёт данных либо инструмент сам оставил в этом месте TODO — пробел уже назван в разделах ниже

- **прогон: check_conditions — сумма ниже минимума (—)** — спецификация не задаёт минимальной суммы — проверять нечего
- **прогон: create_request — идентификатор операции в результате** — в схеме успешного ответа нет поля с ролью provider_operation_id
- **прогон: process_callback — уведомление —** — спецификация не описывает вебхуков — уведомление проверить нечем

## 2. Покрытие спецификации

**Покрытие: 51 % (610 из 1196 элементов). В границах контракта: 69 % (610 из 885).**

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

Знаменатель второй цифры меньше первого на 311 элементов, и вот они все, по
видам:

- **Поля тел запросов** — 115: необязательные поля без роли — в payload они не идут намеренно (docs/PRINCIPLES.md, раздел «Что генерируем при неполной спеке»), а не по недосмотру
- **Поля тел ответов и уведомлений** — 196: роль поля не входит в читаемые сервисом или не выведена вовсе — методам контракта такое поле прочитать некуда

Больше не вычтено ничего: коды ответов, статусы, события вебхука, условия
взаимодействия, обязательные поля тел запросов и поля запросов с выведенной
ролью остаются в знаменателе второй цифры целиком — даже когда не покрыты,
потому что их непокрытие — пробел интеграции, а не свойство контракта.
Вычтенное не спрятано: каждый вычтенный элемент назван ниже, в «Что не покрыто
и почему», со своей причиной и своей корзиной.

| Измерение | Найдено | Покрыто | Покрытие |
|---|---|---|---|
| Операции | 120 | 59 | 49 % |
| Поля тел запросов | 242 | 42 | 17 % |
| Поля тел ответов и уведомлений | 391 | 195 | 50 % |
| Коды ответов | 434 | 314 | 72 % |
| Статусы | 0 | 0 | нечего покрывать |
| События вебхука | 0 | 0 | нечего покрывать |
| Условия взаимодействия | 9 | 0 | 0 % |

### Что не покрыто и почему

Непокрыто 586: вне контракта 553, структурных исключений 21, требует ручной
работы 12. Корзина каждого элемента вычислена из его причины, таблица причин —
Generators::Report::Gap::BUCKETS.

**Требует ручной работы — 12.** Единственная корзина, адресованная человеку:
здесь спецификация описала то, что контракт умеет использовать, а интеграция
этого не взяла. Перечислена целиком, поимённо и первой — это и есть список
того, что стоит доделать руками.

**Поля тел запросов** — не покрыто 3

- `transfer_initiate: source` — обязательное поле без роли: в payload попало с TODO и значением по умолчанию, значение подставит человек
- `transfer_initiate: recipient` — роль recipient_type выведена, но выражения платформы для неё нет ни в accessors, ни в requisites (rules/contract.yml, раздел platform) — добавьте его туда или заполните поле вручную
- `transfer_initiate: currency` — роль currency выведена, но выражения платформы для неё нет ни в accessors, ни в requisites (rules/contract.yml, раздел platform) — добавьте его туда или заполните поле вручную

**Условия взаимодействия** — не покрыто 9

- `field_enum currency` — проверка не сгенерирована: у платформы нет выражения для поля currency
- `field_enum currency` — проверка не сгенерирована: у платформы нет выражения для поля currency
- `field_enum currency` — проверка не сгенерирована: у платформы нет выражения для поля currency
- `field_enum currency` — проверка не сгенерирована: у платформы нет выражения для поля currency
- `field_enum type` — проверка не сгенерирована: у платформы нет выражения для поля type
- `field_enum currency` — проверка не сгенерирована: у платформы нет выражения для поля currency
- `field_enum type` — проверка не сгенерирована: у платформы нет выражения для поля type
- `field_enum type` — проверка не сгенерирована: у платформы нет выражения для поля type
- `field_enum currency` — проверка не сгенерирована: у платформы нет выражения для поля currency

**Вне контракта — 553.** Ресурсы спецификации, которых методы контракта не
касаются вовсе: чужие операции и их поля, коды и схемы. Контракт про выплаты;
считать пробелом интеграции отсутствие в ней подписок, споров или хранения
карт — то же самое, что считать пробелом отсутствие метода для чужого API.
Свёрнуто числом с примерами.

- **Операции** — 61, например: `split_create`, `split_list`, `split_fetch`
- **Поля тел запросов** — 196, например: `transaction_initialize: email`, `transaction_initialize: currency`, `transaction_initialize: callback_url`
- **Поля тел ответов и уведомлений** — 184, например: `transaction_initialize.responses.401.message`, `transaction_verify.responses.401.message`, `transaction_verify.responses.404.message`
- **Коды ответов** — 112, например: `transaction_initialize default`, `transaction_verify default`, `transaction_list default`

**Структурные исключения метрики — 21.** Элементы, которым в методах контракта
нет места по построению: поле входящего тела засчитывается, только когда его
роль читает один из четырёх методов; необязательное поле без роли в payload не
идёт намеренно; код, объявленный диапазоном, ветки не даёт. Это устройство
метрики и контракта, а не пропуск разбора. Свёрнуто числом с примерами.

- **Поля тел запросов** — 1: `transfer_initiate: reason`
- **Поля тел ответов и уведомлений** — 12, например: `schema.message`, `schema.data`, `paymentRequest_notify.responses.401.message`
- **Коды ответов** — 8, например: `paymentRequest_notify default`, `paymentRequest_finalize default`, `paymentRequest_archive default`

## 3. Неоднозначности

Элементы, о которых спецификация говорит недостаточно, чтобы решение было
однозначным. Инструмент решил сам — что именно, сказано под каждым кодом; от
человека нужна проверка, а не заполнение пропуска.

### `conditional_required_hint` — 2

Что сделал инструмент: поле помечено условно обязательным, условие вынесено в комментарий над записью payload

- **`$.components.schemas.Customer`** — `value` выглядит условно обязательным (`type` = bvn), но схема не задаёт условия; фрагмент ниже задаёт его формально

  ```yaml
  - target: "$.components.schemas.Customer"
    update:
      x-jsonschema-if:
        properties:
          type:
            const: bvn
      x-jsonschema-then:
        required: [value]
  ```
- **`$.paths['/customer/{code}/identification'].post.requestBody.content['application/json'].schema`** — `value` выглядит условно обязательным (`type` = bvn), но схема не задаёт условия; фрагмент ниже задаёт его формально

  ```yaml
  - target: "$.paths['/customer/{code}/identification'].post.requestBody.content['application/json'].schema"
    update:
      x-jsonschema-if:
        properties:
          type:
            const: bvn
      x-jsonschema-then:
        required: [value]
  ```

### `currency_unknown` — 1

Что сделал инструмент: валюта не подставлена, множитель суммы по умолчанию

- **`$.paths['/transaction/initialize'].post.requestBody.content['application/json'].schema.properties.amount`** — поле `currency` допускает несколько валют (NGN, GHS, ZAR, USD); экспонента зависит от валюты конкретной операции — закрепите валюту в overlay или доработайте генератор под мультивалютность

  ```yaml
  - target: "$.paths['/transaction/initialize'].post.requestBody.content['application/json'].schema.properties.amount"
    update:
      x-specgen-currency: RUB  # код ISO 4217
  ```

### `field_role_low_confidence` — 38

Что сделал инструмент: роль присвоена лучшему кандидату, в коде рядом с полем — комментарий с уверенностью

- **`$.components.schemas.Customer.properties.customer`** — обязательное поле `customer`: роль external_id выведена с низкой уверенностью 0.21 (порог 0.60); кандидаты: external_id 0.21, recipient_phone 0.21; без него запрос не уйдёт, поэтому в код оно попадёт как external_id с TODO — проверьте роль и закрепите её фрагментом ниже

  ```yaml
  - target: "$.components.schemas.Customer.properties.customer"
    update:
      x-specgen-role: external_id  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.paths['/charge/submit_address'].post.requestBody.content['application/json'].schema.properties.reference`** — обязательное поле `reference`: роль external_id выведена с низкой уверенностью 0.21 (порог 0.60); кандидаты: external_id 0.21, provider_operation_id 0.21; без него запрос не уйдёт, поэтому в код оно попадёт как external_id с TODO — проверьте роль и закрепите её фрагментом ниже

  ```yaml
  - target: "$.paths['/charge/submit_address'].post.requestBody.content['application/json'].schema.properties.reference"
    update:
      x-specgen-role: external_id  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.paths['/charge/submit_address'].post.requestBody.content['application/json'].schema.properties.state`** — обязательное поле `state`: роль status выведена с низкой уверенностью 0.36 (порог 0.60); кандидаты: status 0.36; без него запрос не уйдёт, поэтому в код оно попадёт как status с TODO — проверьте роль и закрепите её фрагментом ниже

  ```yaml
  - target: "$.paths['/charge/submit_address'].post.requestBody.content['application/json'].schema.properties.state"
    update:
      x-specgen-role: status  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.paths['/charge/submit_birthday'].post.requestBody.content['application/json'].schema.properties.reference`** — обязательное поле `reference`: роль external_id выведена с низкой уверенностью 0.21 (порог 0.60); кандидаты: external_id 0.21, provider_operation_id 0.21; без него запрос не уйдёт, поэтому в код оно попадёт как external_id с TODO — проверьте роль и закрепите её фрагментом ниже

  ```yaml
  - target: "$.paths['/charge/submit_birthday'].post.requestBody.content['application/json'].schema.properties.reference"
    update:
      x-specgen-role: external_id  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.paths['/charge/submit_otp'].post.requestBody.content['application/json'].schema.properties.reference`** — обязательное поле `reference`: роль external_id выведена с низкой уверенностью 0.21 (порог 0.60); кандидаты: external_id 0.21, provider_operation_id 0.21; без него запрос не уйдёт, поэтому в код оно попадёт как external_id с TODO — проверьте роль и закрепите её фрагментом ниже

  ```yaml
  - target: "$.paths['/charge/submit_otp'].post.requestBody.content['application/json'].schema.properties.reference"
    update:
      x-specgen-role: external_id  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.paths['/charge/submit_phone'].post.requestBody.content['application/json'].schema.properties.reference`** — обязательное поле `reference`: роль external_id выведена с низкой уверенностью 0.21 (порог 0.60); кандидаты: external_id 0.21, provider_operation_id 0.21; без него запрос не уйдёт, поэтому в код оно попадёт как external_id с TODO — проверьте роль и закрепите её фрагментом ниже

  ```yaml
  - target: "$.paths['/charge/submit_phone'].post.requestBody.content['application/json'].schema.properties.reference"
    update:
      x-specgen-role: external_id  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.paths['/charge/submit_pin'].post.requestBody.content['application/json'].schema.properties.reference`** — обязательное поле `reference`: роль external_id выведена с низкой уверенностью 0.21 (порог 0.60); кандидаты: external_id 0.21, provider_operation_id 0.21; без него запрос не уйдёт, поэтому в код оно попадёт как external_id с TODO — проверьте роль и закрепите её фрагментом ниже

  ```yaml
  - target: "$.paths['/charge/submit_pin'].post.requestBody.content['application/json'].schema.properties.reference"
    update:
      x-specgen-role: external_id  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.paths['/charge/{reference}'].get.parameters[0]`** — обязательный параметр `reference` (путь): роль provider_operation_id выведена с низкой уверенностью 0.50 (порог 0.60); кандидаты: provider_operation_id 0.50, external_id 0.21; без него запрос не уйдёт, поэтому в код оно попадёт как provider_operation_id с TODO — проверьте роль и закрепите её фрагментом ниже

  ```yaml
  - target: "$.paths['/charge/{reference}'].get.parameters[0]"
    update:
      x-specgen-role: provider_operation_id  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.paths['/customer/set_risk_action'].post.requestBody.content['application/json'].schema.properties.customer`** — обязательное поле `customer`: роль external_id выведена с низкой уверенностью 0.21 (порог 0.60); кандидаты: external_id 0.21, recipient_phone 0.21; без него запрос не уйдёт, поэтому в код оно попадёт как external_id с TODO — проверьте роль и закрепите её фрагментом ниже

  ```yaml
  - target: "$.paths['/customer/set_risk_action'].post.requestBody.content['application/json'].schema.properties.customer"
    update:
      x-specgen-role: external_id  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.paths['/dedicated_account'].post.requestBody.content['application/json'].schema.properties.customer`** — обязательное поле `customer`: роль external_id выведена с низкой уверенностью 0.21 (порог 0.60); кандидаты: external_id 0.21, recipient_phone 0.21; без него запрос не уйдёт, поэтому в код оно попадёт как external_id с TODO — проверьте роль и закрепите её фрагментом ниже

  ```yaml
  - target: "$.paths['/dedicated_account'].post.requestBody.content['application/json'].schema.properties.customer"
    update:
      x-specgen-role: external_id  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.paths['/dispute/{id}'].put.requestBody.content['application/json'].schema.properties.refund_amount`** — обязательное поле `refund_amount`: роль amount выведена с низкой уверенностью 0.21 (порог 0.60); кандидаты: amount 0.21; без него запрос не уйдёт, поэтому в код оно попадёт как amount с TODO — проверьте роль и закрепите её фрагментом ниже

  ```yaml
  - target: "$.paths['/dispute/{id}'].put.requestBody.content['application/json'].schema.properties.refund_amount"
    update:
      x-specgen-role: amount  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.paths['/dispute/{id}/resolve'].put.requestBody.content['application/json'].schema.properties.refund_amount`** — обязательное поле `refund_amount`: роль amount выведена с низкой уверенностью 0.21 (порог 0.60); кандидаты: amount 0.21; без него запрос не уйдёт, поэтому в код оно попадёт как amount с TODO — проверьте роль и закрепите её фрагментом ниже

  ```yaml
  - target: "$.paths['/dispute/{id}/resolve'].put.requestBody.content['application/json'].schema.properties.refund_amount"
    update:
      x-specgen-role: amount  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.paths['/dispute/{id}/resolve'].put.requestBody.content['application/json'].schema.properties.resolution`** — обязательное поле `resolution`: роль status выведена с низкой уверенностью 0.21 (порог 0.60); кандидаты: status 0.21; без него запрос не уйдёт, поэтому в код оно попадёт как status с TODO — проверьте роль и закрепите её фрагментом ниже

  ```yaml
  - target: "$.paths['/dispute/{id}/resolve'].put.requestBody.content['application/json'].schema.properties.resolution"
    update:
      x-specgen-role: status  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.paths['/subaccount'].post.requestBody.content['application/json'].schema.properties.settlement_bank`** — обязательное поле `settlement_bank`: роль bank_name выведена с низкой уверенностью 0.21 (порог 0.60); кандидаты: bank_name 0.21, completed_at 0.21; без него запрос не уйдёт, поэтому в код оно попадёт как bank_name с TODO — проверьте роль и закрепите её фрагментом ниже

  ```yaml
  - target: "$.paths['/subaccount'].post.requestBody.content['application/json'].schema.properties.settlement_bank"
    update:
      x-specgen-role: bank_name  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.paths['/subscription'].post.requestBody.content['application/json'].schema.properties.customer`** — обязательное поле `customer`: роль external_id выведена с низкой уверенностью 0.21 (порог 0.60); кандидаты: external_id 0.21, recipient_phone 0.21; без него запрос не уйдёт, поэтому в код оно попадёт как external_id с TODO — проверьте роль и закрепите её фрагментом ниже

  ```yaml
  - target: "$.paths['/subscription'].post.requestBody.content['application/json'].schema.properties.customer"
    update:
      x-specgen-role: external_id  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.paths['/subscription/enable'].post.requestBody.content['application/json'].schema.properties.token`** — обязательное поле `token`: роль idempotency_key выведена с низкой уверенностью 0.21 (порог 0.60); кандидаты: idempotency_key 0.21; без него запрос не уйдёт, поэтому в код оно попадёт как idempotency_key с TODO — проверьте роль и закрепите её фрагментом ниже

  ```yaml
  - target: "$.paths['/subscription/enable'].post.requestBody.content['application/json'].schema.properties.token"
    update:
      x-specgen-role: idempotency_key  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.paths['/transaction/timeline/{id_or_reference}'].get.parameters[0]`** — обязательный параметр `id_or_reference` (путь): роль external_id выведена с низкой уверенностью 0.21 (порог 0.60); кандидаты: external_id 0.21; без него запрос не уйдёт, поэтому в код оно попадёт как external_id с TODO — проверьте роль и закрепите её фрагментом ниже

  ```yaml
  - target: "$.paths['/transaction/timeline/{id_or_reference}'].get.parameters[0]"
    update:
      x-specgen-role: external_id  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.paths['/transaction/verify/{reference}'].get.parameters[0]`** — обязательный параметр `reference` (путь): роль provider_operation_id выведена с низкой уверенностью 0.50 (порог 0.60); кандидаты: provider_operation_id 0.50, external_id 0.21; без него запрос не уйдёт, поэтому в код оно попадёт как provider_operation_id с TODO — проверьте роль и закрепите её фрагментом ниже

  ```yaml
  - target: "$.paths['/transaction/verify/{reference}'].get.parameters[0]"
    update:
      x-specgen-role: provider_operation_id  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.paths['/transfer'].post.requestBody.content['application/json'].schema.properties.recipient`** — обязательное поле `recipient`: роль recipient_type выведена с низкой уверенностью 0.21 (порог 0.60); кандидаты: recipient_type 0.21, recipient_phone 0.21, bank_name 0.21; без него запрос не уйдёт, поэтому в код оно попадёт как recipient_type с TODO — проверьте роль и закрепите её фрагментом ниже

  ```yaml
  - target: "$.paths['/transfer'].post.requestBody.content['application/json'].schema.properties.recipient"
    update:
      x-specgen-role: recipient_type  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.paths['/transfer/verify/{reference}'].parameters[0]`** — обязательный параметр `reference` (путь): роль provider_operation_id выведена с низкой уверенностью 0.50 (порог 0.60); кандидаты: provider_operation_id 0.50, external_id 0.21; без него запрос не уйдёт, поэтому в код оно попадёт как provider_operation_id с TODO — проверьте роль и закрепите её фрагментом ниже

  ```yaml
  - target: "$.paths['/transfer/verify/{reference}'].parameters[0]"
    update:
      x-specgen-role: provider_operation_id  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- и ещё 18 с тем же кодом

### `idempotency_header_missing` — 1

Что сделал инструмент: ключ идемпотентности не отправляется

- **`$.paths['/transaction/initialize'].post`** — ни одна операция не объявляет заголовок идемпотентности (алиасы rules/idempotency.yml: Idempotence-Key, Idempotency-Key, PayPal-Request-Id, X-Idempotency-Key, X-Request-Id, X-Unique-Transaction-Id); повтор запроса после сетевого сбоя создаст вторую выплату — уточните у провайдера или объявите заголовок в overlay

  ```yaml
  - target: "$.paths['/transaction/initialize'].post"
    update:
      parameters:
        - name: Idempotency-Key
          in: header
          required: false
          schema:
            type: string
            format: uuid
  ```

### `operation_id_missing` — 2

Что сделал инструмент: ключом операции стала пара «HTTP-метод и путь»

- **`$.paths['/transferrecipient/{code}'].delete`** — операция не объявляет operationId; в этом отчёте и в сгенерированном коде она названа "delete_transferrecipient_code"
  готового overlay-фрагмента нет: исправляется правкой спецификации
- **`$.paths['/transferrecipient/{code}'].put`** — операция не объявляет operationId; в этом отчёте и в сгенерированном коде она названа "put_transferrecipient_code"
  готового overlay-фрагмента нет: исправляется правкой спецификации

### `operation_role_ambiguous` — 13

Что сделал инструмент: взят лучший кандидат роли, метод сгенерирован по нему

- **`$.paths['/paymentrequest/archive/{id}'].post`** — две роли подходят этой операции почти одинаково; взята первая, но выбор стоит подтвердить (cancel 6.5, create_payout 5.5, confirm 4.5 из 12.0 поданных голосов); переопределить — в overlay
  готового overlay-фрагмента нет: закрепляется записью в `rules/operations.yml` или правкой спецификации
- **`$.paths['/paymentrequest/finalize/{id}'].post`** — две роли подходят этой операции почти одинаково; взята первая, но выбор стоит подтвердить (cancel 6.5, create_payout 5.5, confirm 4.5 из 12.0 поданных голосов); переопределить — в overlay
  готового overlay-фрагмента нет: закрепляется записью в `rules/operations.yml` или правкой спецификации
- **`$.paths['/paymentrequest/notify/{id}'].post`** — две роли подходят этой операции почти одинаково; взята первая, но выбор стоит подтвердить (cancel 6.5, create_payout 5.5, confirm 4.5 из 12.0 поданных голосов); переопределить — в overlay
  готового overlay-фрагмента нет: закрепляется записью в `rules/operations.yml` или правкой спецификации
- **`$.paths['/transaction/charge_authorization'].post`** — две роли подходят этой операции почти одинаково; взята первая, но выбор стоит подтвердить (create_payout 8.5, create_deposit 7.5, cancel 6.5 из 11.0 поданных голосов); переопределить — в overlay
  готового overlay-фрагмента нет: закрепляется записью в `rules/operations.yml` или правкой спецификации
- **`$.paths['/transfer/bulk'].post`** — две роли подходят этой операции почти одинаково; взята первая, но выбор стоит подтвердить (create_payout 8.5, cancel 7.5, confirm 6.5 из 11.0 поданных голосов); переопределить — в overlay
  готового overlay-фрагмента нет: закрепляется записью в `rules/operations.yml` или правкой спецификации
- **`$.paths['/transfer/disable_otp'].post`** — две роли подходят этой операции почти одинаково; взята первая, но выбор стоит подтвердить (cancel 8.5, create_payout 7.5, confirm 6.5 из 11.0 поданных голосов); переопределить — в overlay
  готового overlay-фрагмента нет: закрепляется записью в `rules/operations.yml` или правкой спецификации
- **`$.paths['/transfer/disable_otp_finalize'].post`** — две роли подходят этой операции почти одинаково; взята первая, но выбор стоит подтвердить (create_payout 8.5, cancel 7.5, confirm 6.5 из 11.0 поданных голосов); переопределить — в overlay
  готового overlay-фрагмента нет: закрепляется записью в `rules/operations.yml` или правкой спецификации
- **`$.paths['/transfer/enable_otp'].post`** — две роли подходят этой операции почти одинаково; взята первая, но выбор стоит подтвердить (cancel 8.5, create_payout 7.5, confirm 6.5 из 11.0 поданных голосов); переопределить — в overlay
  готового overlay-фрагмента нет: закрепляется записью в `rules/operations.yml` или правкой спецификации
- **`$.paths['/transfer/finalize_transfer'].post`** — две роли подходят этой операции почти одинаково; взята первая, но выбор стоит подтвердить (create_payout 8.5, cancel 7.5, confirm 6.5 из 11.0 поданных голосов); переопределить — в overlay
  готового overlay-фрагмента нет: закрепляется записью в `rules/operations.yml` или правкой спецификации
- **`$.paths['/transfer/resend_otp'].post`** — две роли подходят этой операции почти одинаково; взята первая, но выбор стоит подтвердить (create_payout 8.5, cancel 7.5, confirm 6.5 из 11.0 поданных голосов); переопределить — в overlay
  готового overlay-фрагмента нет: закрепляется записью в `rules/operations.yml` или правкой спецификации
- **`$.paths['/transferrecipient'].get`** — признаков роли мало, поэтому взят лучший кандидат с низкой уверенностью (fetch_status 4.0, balance 3.0 из 4.0 поданных голосов); проверьте его или задайте роль в overlay
  готового overlay-фрагмента нет: закрепляется записью в `rules/operations.yml` или правкой спецификации
- **`$.paths['/transferrecipient/bulk'].post`** — признаков роли мало, поэтому взят лучший кандидат с низкой уверенностью (create_payout 4.0, create_deposit 3.0, cancel 3.0 из 4.0 поданных голосов); проверьте его или задайте роль в overlay
  готового overlay-фрагмента нет: закрепляется записью в `rules/operations.yml` или правкой спецификации
- **`$.paths['/transferrecipient/{code}'].delete`** — признаков роли мало, поэтому взят лучший кандидат с низкой уверенностью (cancel 4.0, balance 1.0 из 7.0 поданных голосов); проверьте его или задайте роль в overlay
  готового overlay-фрагмента нет: закрепляется записью в `rules/operations.yml` или правкой спецификации

### `operation_tie` — 3

Что сделал инструмент: ничья разрешена связью с ресурсом, а где её нет — порядком объявления

- **`$.paths['/transfer'].post`** — на роль create_payout претендует несколько операций с одинаковой уверенностью 0.95 (paymentRequest_create (POST /paymentrequest), transfer_initiate (POST /transfer)); взята transfer_initiate: её связывает с transfer_fetch общий контейнер ресурса `transfer`, путь продолжает путь создания, общая схема успешного ответа schema
  готового overlay-фрагмента нет: исправляется правкой спецификации
- **`$.paths['/transfer/disable_otp'].post`** — на роль cancel претендует несколько операций с одинаковой уверенностью 0.77 (transfer_disableOtp (POST /transfer/disable_otp), transfer_enableOtp (POST /transfer/enable_otp)); взята transfer_disableOtp: её связывает с transfer_initiate путь продолжает путь создания, общая схема успешного ответа schema
  готового overlay-фрагмента нет: исправляется правкой спецификации
- **`$.paths['/transfer/{code}'].get`** — на роль fetch_status претендует несколько операций с одинаковой уверенностью 0.95 (transaction_fetch (GET /transaction/{id}), paymentRequest_fetch (GET /paymentrequest/{id}), transfer_fetch (GET /transfer/{code}), charge_check (GET /charge/{reference}), bulkCharge_fetch (GET /bulkcharge/{code}), integration_fetchPaymentSessionTimeout (GET /integration/payment_session_timeout)); взята transfer_fetch: её связывает с transfer_initiate общий контейнер ресурса `transfer`, путь продолжает путь создания, общая схема успешного ответа schema
  готового overlay-фрагмента нет: исправляется правкой спецификации

### `required_field_role_unknown` — 69

Что сделал инструмент: в исходящем теле поле включено в payload со значением примера или nil и TODO рядом; во входящем — ищется структурно

- **`$.components.schemas.Customer.properties.account_number`** — обязательное поле `account_number` (string): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; без него запрос не уйдёт, поэтому в код оно попадёт с TODO — задайте роль фрагментом ниже или добавьте синоним в rules/roles.yml

  ```yaml
  - target: "$.components.schemas.Customer.properties.account_number"
    update:
      x-specgen-role: TODO  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.Customer.properties.authorization_code`** — обязательное поле `authorization_code` (string): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; без него запрос не уйдёт, поэтому в код оно попадёт с TODO — задайте роль фрагментом ниже или добавьте синоним в rules/roles.yml

  ```yaml
  - target: "$.components.schemas.Customer.properties.authorization_code"
    update:
      x-specgen-role: TODO  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.Customer.properties.bvn`** — обязательное поле `bvn` (string): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; без него запрос не уйдёт, поэтому в код оно попадёт с TODO — задайте роль фрагментом ниже или добавьте синоним в rules/roles.yml

  ```yaml
  - target: "$.components.schemas.Customer.properties.bvn"
    update:
      x-specgen-role: TODO  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.Customer.properties.country`** — обязательное поле `country` (string): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; без него запрос не уйдёт, поэтому в код оно попадёт с TODO — задайте роль фрагментом ниже или добавьте синоним в rules/roles.yml

  ```yaml
  - target: "$.components.schemas.Customer.properties.country"
    update:
      x-specgen-role: TODO  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.Customer.properties.email`** — обязательное поле `email` (string): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; без него запрос не уйдёт, поэтому в код оно попадёт с TODO — задайте роль фрагментом ниже или добавьте синоним в rules/roles.yml

  ```yaml
  - target: "$.components.schemas.Customer.properties.email"
    update:
      x-specgen-role: TODO  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.paths['/bank/resolve_bvn/{bvn}'].get.parameters[0]`** — обязательный параметр `bvn` (путь) (string): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; без него запрос не уйдёт, поэтому в код оно попадёт с TODO — задайте роль фрагментом ниже или добавьте синоним в rules/roles.yml

  ```yaml
  - target: "$.paths['/bank/resolve_bvn/{bvn}'].get.parameters[0]"
    update:
      x-specgen-role: TODO  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.paths['/bulkcharge/pause/{code}'].get.parameters[0]`** — обязательный параметр `code` (путь) (string): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; без него запрос не уйдёт, поэтому в код оно попадёт с TODO — задайте роль фрагментом ниже или добавьте синоним в rules/roles.yml

  ```yaml
  - target: "$.paths['/bulkcharge/pause/{code}'].get.parameters[0]"
    update:
      x-specgen-role: TODO  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.paths['/bulkcharge/resume/{code}'].get.parameters[0]`** — обязательный параметр `code` (путь) (string): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; без него запрос не уйдёт, поэтому в код оно попадёт с TODO — задайте роль фрагментом ниже или добавьте синоним в rules/roles.yml

  ```yaml
  - target: "$.paths['/bulkcharge/resume/{code}'].get.parameters[0]"
    update:
      x-specgen-role: TODO  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.paths['/bulkcharge/{code}'].parameters[0]`** — обязательный параметр `code` (путь) (string): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; без него запрос не уйдёт, поэтому в код оно попадёт с TODO — задайте роль фрагментом ниже или добавьте синоним в rules/roles.yml

  ```yaml
  - target: "$.paths['/bulkcharge/{code}'].parameters[0]"
    update:
      x-specgen-role: TODO  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.paths['/bulkcharge/{code}/charges'].get.parameters[0]`** — обязательный параметр `code` (путь) (string): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; без него запрос не уйдёт, поэтому в код оно попадёт с TODO — задайте роль фрагментом ниже или добавьте синоним в rules/roles.yml

  ```yaml
  - target: "$.paths['/bulkcharge/{code}/charges'].get.parameters[0]"
    update:
      x-specgen-role: TODO  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.paths['/bvn/match'].post.requestBody.content['application/json'].schema.properties.account_number`** — обязательное поле `account_number` (string): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; без него запрос не уйдёт, поэтому в код оно попадёт с TODO — задайте роль фрагментом ниже или добавьте синоним в rules/roles.yml

  ```yaml
  - target: "$.paths['/bvn/match'].post.requestBody.content['application/json'].schema.properties.account_number"
    update:
      x-specgen-role: TODO  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.paths['/bvn/match'].post.requestBody.content['application/json'].schema.properties.bvn`** — обязательное поле `bvn` (string): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; без него запрос не уйдёт, поэтому в код оно попадёт с TODO — задайте роль фрагментом ниже или добавьте синоним в rules/roles.yml

  ```yaml
  - target: "$.paths['/bvn/match'].post.requestBody.content['application/json'].schema.properties.bvn"
    update:
      x-specgen-role: TODO  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.paths['/charge'].post.requestBody.content['application/json'].schema.properties.email`** — обязательное поле `email` (string): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; без него запрос не уйдёт, поэтому в код оно попадёт с TODO — задайте роль фрагментом ниже или добавьте синоним в rules/roles.yml

  ```yaml
  - target: "$.paths['/charge'].post.requestBody.content['application/json'].schema.properties.email"
    update:
      x-specgen-role: TODO  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.paths['/charge/submit_address'].post.requestBody.content['application/json'].schema.properties.address`** — обязательное поле `address` (string): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; без него запрос не уйдёт, поэтому в код оно попадёт с TODO — задайте роль фрагментом ниже или добавьте синоним в rules/roles.yml

  ```yaml
  - target: "$.paths['/charge/submit_address'].post.requestBody.content['application/json'].schema.properties.address"
    update:
      x-specgen-role: TODO  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.paths['/charge/submit_address'].post.requestBody.content['application/json'].schema.properties.city`** — обязательное поле `city` (string): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; без него запрос не уйдёт, поэтому в код оно попадёт с TODO — задайте роль фрагментом ниже или добавьте синоним в rules/roles.yml

  ```yaml
  - target: "$.paths['/charge/submit_address'].post.requestBody.content['application/json'].schema.properties.city"
    update:
      x-specgen-role: TODO  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.paths['/charge/submit_address'].post.requestBody.content['application/json'].schema.properties.zipcode`** — обязательное поле `zipcode` (string): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; без него запрос не уйдёт, поэтому в код оно попадёт с TODO — задайте роль фрагментом ниже или добавьте синоним в rules/roles.yml

  ```yaml
  - target: "$.paths['/charge/submit_address'].post.requestBody.content['application/json'].schema.properties.zipcode"
    update:
      x-specgen-role: TODO  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.paths['/charge/submit_birthday'].post.requestBody.content['application/json'].schema.properties.birthday`** — обязательное поле `birthday` (string): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; без него запрос не уйдёт, поэтому в код оно попадёт с TODO — задайте роль фрагментом ниже или добавьте синоним в rules/roles.yml

  ```yaml
  - target: "$.paths['/charge/submit_birthday'].post.requestBody.content['application/json'].schema.properties.birthday"
    update:
      x-specgen-role: TODO  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.paths['/charge/submit_otp'].post.requestBody.content['application/json'].schema.properties.otp`** — обязательное поле `otp` (string): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; без него запрос не уйдёт, поэтому в код оно попадёт с TODO — задайте роль фрагментом ниже или добавьте синоним в rules/roles.yml

  ```yaml
  - target: "$.paths['/charge/submit_otp'].post.requestBody.content['application/json'].schema.properties.otp"
    update:
      x-specgen-role: TODO  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.paths['/charge/submit_pin'].post.requestBody.content['application/json'].schema.properties.pin`** — обязательное поле `pin` (string): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; без него запрос не уйдёт, поэтому в код оно попадёт с TODO — задайте роль фрагментом ниже или добавьте синоним в rules/roles.yml

  ```yaml
  - target: "$.paths['/charge/submit_pin'].post.requestBody.content['application/json'].schema.properties.pin"
    update:
      x-specgen-role: TODO  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.paths['/customer'].post.requestBody.content['application/json'].schema.properties.email`** — обязательное поле `email` (string): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; без него запрос не уйдёт, поэтому в код оно попадёт с TODO — задайте роль фрагментом ниже или добавьте синоним в rules/roles.yml

  ```yaml
  - target: "$.paths['/customer'].post.requestBody.content['application/json'].schema.properties.email"
    update:
      x-specgen-role: TODO  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- и ещё 49 с тем же кодом

### `spec_element_unsupported` — 2

Что сделал инструмент: значение расширения отвергнуто, элемент разобран без него

- **`$.components.schemas.Response.properties.data`** — `data` — свободная карта (`additionalProperties` или объект без `properties`): ключи спецификацией не перечислены, поэтому значением поля остаётся хеш, который заполняют вручную
  готового overlay-фрагмента нет: исправляется правкой спецификации
- **`$.paths['/transaction/initialize'].post.responses['201'].content['application/json'].schema.properties.data`** — `data` — свободная карта (`additionalProperties` или объект без `properties`): ключи спецификацией не перечислены, поэтому значением поля остаётся хеш, который заполняют вручную
  готового overlay-фрагмента нет: исправляется правкой спецификации

### `webhook_missing` — 1

Что сделал инструмент: process_callback отказывает webhooks_not_supported: статус только опросом

- **`$.paths`** — спецификация не описывает входящих уведомлений (нет операции с security: [] и нет секции webhooks); статус операции сервис узнает только опросом через fetch_status
  готового overlay-фрагмента нет: исправляется правкой спецификации

### Как собрать overlay

Фрагменты выше — действия одного документа OpenAPI Overlay 1.0.0
(<https://spec.openapis.org/overlay/v1.0.0.html>). Соберите файл
`paystack_v1.overlay.yaml`, вставив их подряд под ключ `actions`,
замените значения `TODO` и перегенерируйте:

```yaml
overlay: 1.0.0
info:
  title: paystack_v1 disambiguation
  version: 1.0.0
actions:
- target: "$..."
  update:
    x-specgen-role: ...
```

```sh
./integrate --spec paystack_v1.yaml --provider paystack_v1 --overlay paystack_v1.overlay.yaml
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
| `transaction_initialize` | `POST /transaction/initialize` | `create_payout` (эвристика 0.77) | `transaction_initialize(operation)` | ничего: в `Provider::BaseService` нет метода для такой роли, платформа зовёт этот метод напрямую |
| `transaction_verify` | `GET /transaction/verify/{reference}` | `fetch_status` (эвристика 0.82) | `transaction_verify(operation)` | ничего: в `Provider::BaseService` нет метода для такой роли, платформа зовёт этот метод напрямую |
| `transaction_list` | `GET /transaction` | `fetch_status` (эвристика 0.77) | `transaction_list()` | ничего: в `Provider::BaseService` нет метода для такой роли, платформа зовёт этот метод напрямую |
| `transaction_fetch` | `GET /transaction/{id}` | `fetch_status` (эвристика 0.95) | `transaction_fetch(operation)` | ничего: в `Provider::BaseService` нет метода для такой роли, платформа зовёт этот метод напрямую |
| `transaction_timeline` | `GET /transaction/timeline/{id_or_reference}` | `fetch_status` (эвристика 0.82) | `transaction_timeline(operation)` | ничего: в `Provider::BaseService` нет метода для такой роли, платформа зовёт этот метод напрямую |
| `transaction_totals` | `GET /transaction/totals` | `fetch_status` (эвристика 0.77) | `transaction_totals()` | ничего: в `Provider::BaseService` нет метода для такой роли, платформа зовёт этот метод напрямую |
| `transaction_download` | `GET /transaction/export` | `fetch_status` (эвристика 0.77) | `transaction_download()` | ничего: в `Provider::BaseService` нет метода для такой роли, платформа зовёт этот метод напрямую |
| `transaction_chargeAuthorization` | `POST /transaction/charge_authorization` | `create_payout` (эвристика 0.77) | `transaction_charge_authorization(operation)` | ничего: в `Provider::BaseService` нет метода для такой роли, платформа зовёт этот метод напрямую |
| `transaction_checkAuthorization` | `POST /transaction/check_authorization` | `create_payout` (эвристика 0.77) | `transaction_check_authorization(operation)` | ничего: в `Provider::BaseService` нет метода для такой роли, платформа зовёт этот метод напрямую |
| `transaction_partialDebit` | `POST /transaction/partial_debit` | `create_payout` (эвристика 0.77) | `transaction_partial_debit(operation)` | ничего: в `Provider::BaseService` нет метода для такой роли, платформа зовёт этот метод напрямую |
| `transaction_event` | `GET /transaction/{id}/event` | `fetch_status` (эвристика 0.61) | `transaction_event(operation)` | ничего: в `Provider::BaseService` нет метода для такой роли, платформа зовёт этот метод напрямую |
| `transaction_session` | `GET /transaction/{id}/session` | `fetch_status` (эвристика 0.77) | `transaction_session(operation)` | ничего: в `Provider::BaseService` нет метода для такой роли, платформа зовёт этот метод напрямую |
| `split_create` | `POST /split` | не распознана (unmapped) | `split_create(operation)` | добавьте синоним пути или operationId в `rules/operations.yml` и перегенерируйте; расширения `x-specgen-role` для операции в модели нет (docs/IR.md, таблица расширений) |
| `split_list` | `GET /split` | не распознана (unmapped) | `split_list()` | добавьте синоним пути или operationId в `rules/operations.yml` и перегенерируйте; расширения `x-specgen-role` для операции в модели нет (docs/IR.md, таблица расширений) |
| `split_fetch` | `GET /split/{id}` | не распознана (unmapped) | `split_fetch(operation)` | добавьте синоним пути или operationId в `rules/operations.yml` и перегенерируйте; расширения `x-specgen-role` для операции в модели нет (docs/IR.md, таблица расширений) |
| `split_update` | `PUT /split/{id}` | не распознана (unmapped) | `split_update(operation)` | добавьте синоним пути или operationId в `rules/operations.yml` и перегенерируйте; расширения `x-specgen-role` для операции в модели нет (docs/IR.md, таблица расширений) |
| `split_addSubaccount` | `POST /split/{id}/subaccount/add` | не распознана (unmapped) | `split_add_subaccount(operation)` | добавьте синоним пути или operationId в `rules/operations.yml` и перегенерируйте; расширения `x-specgen-role` для операции в модели нет (docs/IR.md, таблица расширений) |
| `split_removeSubaccount` | `POST /split/{id}/subaccount/remove` | не распознана (unmapped) | `split_remove_subaccount(operation)` | добавьте синоним пути или operationId в `rules/operations.yml` и перегенерируйте; расширения `x-specgen-role` для операции в модели нет (docs/IR.md, таблица расширений) |
| `customer_create` | `POST /customer` | не распознана (unmapped) | `customer_create(operation)` | добавьте синоним пути или operationId в `rules/operations.yml` и перегенерируйте; расширения `x-specgen-role` для операции в модели нет (docs/IR.md, таблица расширений) |
| `customer_list` | `GET /customer` | не распознана (unmapped) | `customer_list()` | добавьте синоним пути или operationId в `rules/operations.yml` и перегенерируйте; расширения `x-specgen-role` для операции в модели нет (docs/IR.md, таблица расширений) |
| `customer_fetch` | `GET /customer/{code}` | не распознана (unmapped) | `customer_fetch(operation)` | добавьте синоним пути или operationId в `rules/operations.yml` и перегенерируйте; расширения `x-specgen-role` для операции в модели нет (docs/IR.md, таблица расширений) |
| `customer_update` | `PUT /customer/{code}` | не распознана (unmapped) | `customer_update(operation)` | добавьте синоним пути или operationId в `rules/operations.yml` и перегенерируйте; расширения `x-specgen-role` для операции в модели нет (docs/IR.md, таблица расширений) |
| `customer_riskAction` | `POST /customer/set_risk_action` | не распознана (unmapped) | `customer_risk_action(operation)` | добавьте синоним пути или operationId в `rules/operations.yml` и перегенерируйте; расширения `x-specgen-role` для операции в модели нет (docs/IR.md, таблица расширений) |
| `customer_deactivateAuthorization` | `POST /customer/deactivate_authorization` | не распознана (unmapped) | `customer_deactivate_authorization(operation)` | добавьте синоним пути или operationId в `rules/operations.yml` и перегенерируйте; расширения `x-specgen-role` для операции в модели нет (docs/IR.md, таблица расширений) |
| `customer_validatte` | `POST /customer/{code}/identification` | не распознана (unmapped) | `customer_validatte(operation)` | добавьте синоним пути или operationId в `rules/operations.yml` и перегенерируйте; расширения `x-specgen-role` для операции в модели нет (docs/IR.md, таблица расширений) |
| `dedicatedAccount_create` | `POST /dedicated_account` | не распознана (unmapped) | `dedicated_account_create(operation)` | добавьте синоним пути или operationId в `rules/operations.yml` и перегенерируйте; расширения `x-specgen-role` для операции в модели нет (docs/IR.md, таблица расширений) |
| `dedicatedAccount_list` | `GET /dedicated_account` | `balance` (эвристика 0.82) | `balance()` | ничего: в `Provider::BaseService` нет метода для такой роли, платформа зовёт этот метод напрямую |
| `dedicatedAccount_fetch` | `GET /dedicated_account/{account_id}` | `balance` (эвристика 0.79) | `dedicated_account_fetch(operation)` | ничего: в `Provider::BaseService` нет метода для такой роли, платформа зовёт этот метод напрямую |
| `dedicatedAccount_deactivate` | `DELETE /dedicated_account/{account_id}` | не распознана (unmapped) | `dedicated_account_deactivate(operation)` | добавьте синоним пути или operationId в `rules/operations.yml` и перегенерируйте; расширения `x-specgen-role` для операции в модели нет (docs/IR.md, таблица расширений) |
| `dedicatedAccount_availableProviders` | `GET /dedicated_account/available_providers` | `balance` (эвристика 0.77) | `dedicated_account_available_providers()` | ничего: в `Provider::BaseService` нет метода для такой роли, платформа зовёт этот метод напрямую |
| `dedicatedAccount_addSplit` | `POST /dedicated_account/split` | не распознана (unmapped) | `dedicated_account_add_split(operation)` | добавьте синоним пути или operationId в `rules/operations.yml` и перегенерируйте; расширения `x-specgen-role` для операции в модели нет (docs/IR.md, таблица расширений) |
| `subaccount_create` | `POST /subaccount` | не распознана (unmapped) | `subaccount_create(operation)` | добавьте синоним пути или operationId в `rules/operations.yml` и перегенерируйте; расширения `x-specgen-role` для операции в модели нет (docs/IR.md, таблица расширений) |
| `subaccount_list` | `GET /subaccount` | не распознана (unmapped) | `subaccount_list()` | добавьте синоним пути или operationId в `rules/operations.yml` и перегенерируйте; расширения `x-specgen-role` для операции в модели нет (docs/IR.md, таблица расширений) |
| `subaccount_fetch` | `GET /subaccount/{code}` | не распознана (unmapped) | `subaccount_fetch(operation)` | добавьте синоним пути или operationId в `rules/operations.yml` и перегенерируйте; расширения `x-specgen-role` для операции в модели нет (docs/IR.md, таблица расширений) |
| `subaccount_update` | `PUT /subaccount/{code}` | не распознана (unmapped) | `subaccount_update(operation)` | добавьте синоним пути или operationId в `rules/operations.yml` и перегенерируйте; расширения `x-specgen-role` для операции в модели нет (docs/IR.md, таблица расширений) |
| `plan_create` | `POST /plan` | не распознана (unmapped) | `plan_create(operation)` | добавьте синоним пути или operationId в `rules/operations.yml` и перегенерируйте; расширения `x-specgen-role` для операции в модели нет (docs/IR.md, таблица расширений) |
| `plan_list` | `GET /plan` | не распознана (unmapped) | `plan_list()` | добавьте синоним пути или operationId в `rules/operations.yml` и перегенерируйте; расширения `x-specgen-role` для операции в модели нет (docs/IR.md, таблица расширений) |
| `plan_fetch` | `GET /plan/{code}` | не распознана (unmapped) | `plan_fetch(operation)` | добавьте синоним пути или operationId в `rules/operations.yml` и перегенерируйте; расширения `x-specgen-role` для операции в модели нет (docs/IR.md, таблица расширений) |
| `plan_update` | `PUT /plan/{code}` | не распознана (unmapped) | `plan_update(operation)` | добавьте синоним пути или operationId в `rules/operations.yml` и перегенерируйте; расширения `x-specgen-role` для операции в модели нет (docs/IR.md, таблица расширений) |
| `subscription_create` | `POST /subscription` | не распознана (unmapped) | `subscription_create(operation)` | добавьте синоним пути или operationId в `rules/operations.yml` и перегенерируйте; расширения `x-specgen-role` для операции в модели нет (docs/IR.md, таблица расширений) |
| `subscription_list` | `GET /subscription` | не распознана (unmapped) | `subscription_list()` | добавьте синоним пути или operationId в `rules/operations.yml` и перегенерируйте; расширения `x-specgen-role` для операции в модели нет (docs/IR.md, таблица расширений) |
| `subscription_fetch` | `GET /subscription/{code}` | не распознана (unmapped) | `subscription_fetch(operation)` | добавьте синоним пути или operationId в `rules/operations.yml` и перегенерируйте; расширения `x-specgen-role` для операции в модели нет (docs/IR.md, таблица расширений) |
| `subscription_disable` | `POST /subscription/disable` | не распознана (unmapped) | `subscription_disable(operation)` | добавьте синоним пути или operationId в `rules/operations.yml` и перегенерируйте; расширения `x-specgen-role` для операции в модели нет (docs/IR.md, таблица расширений) |
| `subscription_enable` | `POST /subscription/enable` | не распознана (unmapped) | `subscription_enable(operation)` | добавьте синоним пути или operationId в `rules/operations.yml` и перегенерируйте; расширения `x-specgen-role` для операции в модели нет (docs/IR.md, таблица расширений) |
| `subscription_manageLink` | `POST /subscription/{code}/manage/link` | не распознана (unmapped) | `subscription_manage_link(operation)` | добавьте синоним пути или operationId в `rules/operations.yml` и перегенерируйте; расширения `x-specgen-role` для операции в модели нет (docs/IR.md, таблица расширений) |
| `subscription_manageEmail` | `POST /subscription/{code}/manage/email` | не распознана (unmapped) | `subscription_manage_email(operation)` | добавьте синоним пути или operationId в `rules/operations.yml` и перегенерируйте; расширения `x-specgen-role` для операции в модели нет (docs/IR.md, таблица расширений) |
| `product_create` | `POST /product` | не распознана (unmapped) | `product_create(operation)` | добавьте синоним пути или operationId в `rules/operations.yml` и перегенерируйте; расширения `x-specgen-role` для операции в модели нет (docs/IR.md, таблица расширений) |
| `product_list` | `GET /product` | не распознана (unmapped) | `product_list()` | добавьте синоним пути или operationId в `rules/operations.yml` и перегенерируйте; расширения `x-specgen-role` для операции в модели нет (docs/IR.md, таблица расширений) |
| `product_fetch` | `GET /product/{id}` | не распознана (unmapped) | `product_fetch(operation)` | добавьте синоним пути или operationId в `rules/operations.yml` и перегенерируйте; расширения `x-specgen-role` для операции в модели нет (docs/IR.md, таблица расширений) |
| `product_update` | `PUT /product/{id}` | не распознана (unmapped) | `product_update(operation)` | добавьте синоним пути или operationId в `rules/operations.yml` и перегенерируйте; расширения `x-specgen-role` для операции в модели нет (docs/IR.md, таблица расширений) |
| `product_delete` | `DELETE /product/{id}` | не распознана (unmapped) | `product_delete(operation)` | добавьте синоним пути или operationId в `rules/operations.yml` и перегенерируйте; расширения `x-specgen-role` для операции в модели нет (docs/IR.md, таблица расширений) |
| `page_create` | `POST /page` | не распознана (unmapped) | `page_create(operation)` | добавьте синоним пути или operationId в `rules/operations.yml` и перегенерируйте; расширения `x-specgen-role` для операции в модели нет (docs/IR.md, таблица расширений) |
| `page_list` | `GET /page` | не распознана (unmapped) | `page_list()` | добавьте синоним пути или operationId в `rules/operations.yml` и перегенерируйте; расширения `x-specgen-role` для операции в модели нет (docs/IR.md, таблица расширений) |
| `page_fetch` | `GET /page/{id}` | не распознана (unmapped) | `page_fetch(operation)` | добавьте синоним пути или operationId в `rules/operations.yml` и перегенерируйте; расширения `x-specgen-role` для операции в модели нет (docs/IR.md, таблица расширений) |
| `page_update` | `PUT /page/{id}` | не распознана (unmapped) | `page_update(operation)` | добавьте синоним пути или operationId в `rules/operations.yml` и перегенерируйте; расширения `x-specgen-role` для операции в модели нет (docs/IR.md, таблица расширений) |
| `page_checkSlugAvailability` | `GET /page/check_slug_availability/{slug}` | не распознана (unmapped) | `page_check_slug_availability(operation)` | добавьте синоним пути или operationId в `rules/operations.yml` и перегенерируйте; расширения `x-specgen-role` для операции в модели нет (docs/IR.md, таблица расширений) |
| `page_addProducts` | `POST /page/{id}/product` | не распознана (unmapped) | `page_add_products(operation)` | добавьте синоним пути или operationId в `rules/operations.yml` и перегенерируйте; расширения `x-specgen-role` для операции в модели нет (docs/IR.md, таблица расширений) |
| `paymentRequest_create` | `POST /paymentrequest` | `create_payout` (эвристика 0.95) | `payment_request_create(operation)` | ничего: в `Provider::BaseService` нет метода для такой роли, платформа зовёт этот метод напрямую |
| `paymentRequest_list` | `GET /paymentrequest` | `fetch_status` (эвристика 0.72) | `payment_request_list()` | ничего: в `Provider::BaseService` нет метода для такой роли, платформа зовёт этот метод напрямую |
| `paymentRequest_fetch` | `GET /paymentrequest/{id}` | `fetch_status` (эвристика 0.95) | `payment_request_fetch(operation)` | ничего: в `Provider::BaseService` нет метода для такой роли, платформа зовёт этот метод напрямую |
| `paymentRequest_update` | `PUT /paymentrequest/{id}` | не распознана (unmapped) | `payment_request_update(operation)` | добавьте синоним пути или operationId в `rules/operations.yml` и перегенерируйте; расширения `x-specgen-role` для операции в модели нет (docs/IR.md, таблица расширений) |
| `paymentRequest_verify` | `GET /paymentrequest/verify/{id}` | `fetch_status` (эвристика 0.79) | `payment_request_verify(operation)` | ничего: в `Provider::BaseService` нет метода для такой роли, платформа зовёт этот метод напрямую |
| `paymentRequest_notify` | `POST /paymentrequest/notify/{id}` | `cancel` (эвристика 0.54) | `cancel(operation)` | ничего: в `Provider::BaseService` нет метода для такой роли, платформа зовёт этот метод напрямую |
| `paymentRequest_totals` | `GET /paymentrequest/totals` | `fetch_status` (эвристика 0.72) | `payment_request_totals()` | ничего: в `Provider::BaseService` нет метода для такой роли, платформа зовёт этот метод напрямую |
| `paymentRequest_finalize` | `POST /paymentrequest/finalize/{id}` | `cancel` (эвристика 0.54) | `payment_request_finalize(operation)` | ничего: в `Provider::BaseService` нет метода для такой роли, платформа зовёт этот метод напрямую |
| `paymentRequest_archive` | `POST /paymentrequest/archive/{id}` | `cancel` (эвристика 0.54) | `payment_request_archive(operation)` | ничего: в `Provider::BaseService` нет метода для такой роли, платформа зовёт этот метод напрямую |
| `settlements_fetch` | `GET /settlement` | не распознана (unmapped) | `settlements_fetch()` | добавьте синоним пути или operationId в `rules/operations.yml` и перегенерируйте; расширения `x-specgen-role` для операции в модели нет (docs/IR.md, таблица расширений) |
| `settlements_transaction` | `GET /settlement/{id}/transaction` | `fetch_status` (эвристика 0.75) | `settlements_transaction(operation)` | ничего: в `Provider::BaseService` нет метода для такой роли, платформа зовёт этот метод напрямую |
| `transferrecipient_create` | `POST /transferrecipient` | `create_payout` (эвристика 0.72) | `transferrecipient_create(operation)` | ничего: в `Provider::BaseService` нет метода для такой роли, платформа зовёт этот метод напрямую |
| `transferrecipient_list` | `GET /transferrecipient` | `fetch_status` (эвристика 0.80) | `transferrecipient_list()` | ничего: в `Provider::BaseService` нет метода для такой роли, платформа зовёт этот метод напрямую |
| `transferrecipient_bulk` | `POST /transferrecipient/bulk` | `create_payout` (эвристика 0.80) | `transferrecipient_bulk(operation)` | ничего: в `Provider::BaseService` нет метода для такой роли, платформа зовёт этот метод напрямую |
| `transferrecipient_fetch` | `GET /transferrecipient/{code}` | `fetch_status` (эвристика 0.79) | `transferrecipient_fetch(operation)` | ничего: в `Provider::BaseService` нет метода для такой роли, платформа зовёт этот метод напрямую |
| `put_transferrecipient_code` | `PUT /transferrecipient/{code}` | не распознана (unmapped) | `put_transferrecipient_code(operation)` | добавьте синоним пути или operationId в `rules/operations.yml` и перегенерируйте; расширения `x-specgen-role` для операции в модели нет (docs/IR.md, таблица расширений) |
| `delete_transferrecipient_code` | `DELETE /transferrecipient/{code}` | `cancel` (эвристика 0.57) | `delete_transferrecipient_code(operation)` | ничего: в `Provider::BaseService` нет метода для такой роли, платформа зовёт этот метод напрямую |
| `transfer_list` | `GET /transfer` | `fetch_status` (эвристика 0.77) | `transfer_list()` | ничего: в `Provider::BaseService` нет метода для такой роли, платформа зовёт этот метод напрямую |
| `transfer_finalize` | `POST /transfer/finalize_transfer` | `create_payout` (эвристика 0.77) | `transfer_finalize(operation)` | ничего: в `Provider::BaseService` нет метода для такой роли, платформа зовёт этот метод напрямую |
| `transfer_bulk` | `POST /transfer/bulk` | `create_payout` (эвристика 0.77) | `transfer_bulk(operation)` | ничего: в `Provider::BaseService` нет метода для такой роли, платформа зовёт этот метод напрямую |
| `transfer_verify` | `GET /transfer/verify/{reference}` | `fetch_status` (эвристика 0.82) | `transfer_verify(operation)` | ничего: в `Provider::BaseService` нет метода для такой роли, платформа зовёт этот метод напрямую |
| `transfer_download` | `GET /transfer/export` | `fetch_status` (эвристика 0.77) | `transfer_download()` | ничего: в `Provider::BaseService` нет метода для такой роли, платформа зовёт этот метод напрямую |
| `transfer_resendOtp` | `POST /transfer/resend_otp` | `create_payout` (эвристика 0.77) | `transfer_resend_otp(operation)` | ничего: в `Provider::BaseService` нет метода для такой роли, платформа зовёт этот метод напрямую |
| `transfer_disableOtp` | `POST /transfer/disable_otp` | `cancel` (эвристика 0.77) | `transfer_disable_otp()` | ничего: в `Provider::BaseService` нет метода для такой роли, платформа зовёт этот метод напрямую |
| `transfer_disableOtpFinalize` | `POST /transfer/disable_otp_finalize` | `create_payout` (эвристика 0.77) | `transfer_disable_otp_finalize(operation)` | ничего: в `Provider::BaseService` нет метода для такой роли, платформа зовёт этот метод напрямую |
| `transfer_enableOtp` | `POST /transfer/enable_otp` | `cancel` (эвристика 0.77) | `transfer_enable_otp()` | ничего: в `Provider::BaseService` нет метода для такой роли, платформа зовёт этот метод напрямую |
| `balance_fetch` | `GET /balance` | `balance` (эвристика 0.95) | `balance_fetch()` | ничего: в `Provider::BaseService` нет метода для такой роли, платформа зовёт этот метод напрямую |
| `balance_ledger` | `GET /balance/ledger` | `balance` (эвристика 0.77) | `balance_ledger()` | ничего: в `Provider::BaseService` нет метода для такой роли, платформа зовёт этот метод напрямую |
| `charge_create` | `POST /charge` | `create_deposit` (эвристика 0.95) | `charge_create(operation)` | ничего: в `Provider::BaseService` нет метода для такой роли, платформа зовёт этот метод напрямую |
| `charge_submitPin` | `POST /charge/submit_pin` | `create_deposit` (эвристика 0.95) | `charge_submit_pin(operation)` | ничего: в `Provider::BaseService` нет метода для такой роли, платформа зовёт этот метод напрямую |
| `charge_submitOtp` | `POST /charge/submit_otp` | `create_deposit` (эвристика 0.95) | `charge_submit_otp(operation)` | ничего: в `Provider::BaseService` нет метода для такой роли, платформа зовёт этот метод напрямую |
| `charge_submitPhone` | `POST /charge/submit_phone` | `create_deposit` (эвристика 0.95) | `charge_submit_phone(operation)` | ничего: в `Provider::BaseService` нет метода для такой роли, платформа зовёт этот метод напрямую |
| `charge_submitBirthday` | `POST /charge/submit_birthday` | `create_deposit` (эвристика 0.95) | `charge_submit_birthday(operation)` | ничего: в `Provider::BaseService` нет метода для такой роли, платформа зовёт этот метод напрямую |
| `charge_submitAddress` | `POST /charge/submit_address` | `create_deposit` (эвристика 0.95) | `charge_submit_address(operation)` | ничего: в `Provider::BaseService` нет метода для такой роли, платформа зовёт этот метод напрямую |
| `charge_check` | `GET /charge/{reference}` | `fetch_status` (эвристика 0.95) | `charge_check(operation)` | ничего: в `Provider::BaseService` нет метода для такой роли, платформа зовёт этот метод напрямую |
| `bulkCharge_initiate` | `POST /bulkcharge` | `create_deposit` (эвристика 0.95) | `bulk_charge_initiate(operation)` | ничего: в `Provider::BaseService` нет метода для такой роли, платформа зовёт этот метод напрямую |
| `bulkCharge_list` | `GET /bulkcharge` | `fetch_status` (эвристика 0.69) | `bulk_charge_list()` | ничего: в `Provider::BaseService` нет метода для такой роли, платформа зовёт этот метод напрямую |
| `bulkCharge_fetch` | `GET /bulkcharge/{code}` | `fetch_status` (эвристика 0.95) | `bulk_charge_fetch(operation)` | ничего: в `Provider::BaseService` нет метода для такой роли, платформа зовёт этот метод напрямую |
| `bulkCharge_charges` | `GET /bulkcharge/{code}/charges` | `fetch_status` (эвристика 0.58) | `bulk_charge_charges(operation)` | ничего: в `Provider::BaseService` нет метода для такой роли, платформа зовёт этот метод напрямую |
| `bulkCharge_pause` | `GET /bulkcharge/pause/{code}` | `fetch_status` (эвристика 0.77) | `bulk_charge_pause(operation)` | ничего: в `Provider::BaseService` нет метода для такой роли, платформа зовёт этот метод напрямую |
| `bulkCharge_resume` | `GET /bulkcharge/resume/{code}` | `fetch_status` (эвристика 0.77) | `bulk_charge_resume(operation)` | ничего: в `Provider::BaseService` нет метода для такой роли, платформа зовёт этот метод напрямую |
| `integration_fetchPaymentSessionTimeout` | `GET /integration/payment_session_timeout` | `fetch_status` (эвристика 0.95) | `integration_fetch_payment_session_timeout()` | ничего: в `Provider::BaseService` нет метода для такой роли, платформа зовёт этот метод напрямую |
| `integration_updatePaymentSessionTimeout` | `PUT /integration/payment_session_timeout` | не распознана (unmapped) | `integration_update_payment_session_timeout(operation)` | добавьте синоним пути или operationId в `rules/operations.yml` и перегенерируйте; расширения `x-specgen-role` для операции в модели нет (docs/IR.md, таблица расширений) |
| `refund_create` | `POST /refund` | `refund` (эвристика 0.92) | `refund(operation)` | ничего: в `Provider::BaseService` нет метода для такой роли, платформа зовёт этот метод напрямую |
| `refund_list` | `GET /refund` | не распознана (unmapped) | `refund_list()` | добавьте синоним пути или operationId в `rules/operations.yml` и перегенерируйте; расширения `x-specgen-role` для операции в модели нет (docs/IR.md, таблица расширений) |
| `refund_fetch` | `GET /refund/{id}` | не распознана (unmapped) | `refund_fetch(operation)` | добавьте синоним пути или operationId в `rules/operations.yml` и перегенерируйте; расширения `x-specgen-role` для операции в модели нет (docs/IR.md, таблица расширений) |
| `dispute_list` | `GET /dispute` | не распознана (unmapped) | `dispute_list()` | добавьте синоним пути или operationId в `rules/operations.yml` и перегенерируйте; расширения `x-specgen-role` для операции в модели нет (docs/IR.md, таблица расширений) |
| `dispute_fetch` | `GET /dispute/{id}` | не распознана (unmapped) | `dispute_fetch(operation)` | добавьте синоним пути или operationId в `rules/operations.yml` и перегенерируйте; расширения `x-specgen-role` для операции в модели нет (docs/IR.md, таблица расширений) |
| `dispute_update` | `PUT /dispute/{id}` | не распознана (unmapped) | `dispute_update(operation)` | добавьте синоним пути или operationId в `rules/operations.yml` и перегенерируйте; расширения `x-specgen-role` для операции в модели нет (docs/IR.md, таблица расширений) |
| `dispute_uploadUrl` | `GET /dispute/{id}/upload_url` | не распознана (unmapped) | `dispute_upload_url(operation)` | добавьте синоним пути или operationId в `rules/operations.yml` и перегенерируйте; расширения `x-specgen-role` для операции в модели нет (docs/IR.md, таблица расширений) |
| `dispute_download` | `GET /dispute/export` | не распознана (unmapped) | `dispute_download()` | добавьте синоним пути или operationId в `rules/operations.yml` и перегенерируйте; расширения `x-specgen-role` для операции в модели нет (docs/IR.md, таблица расширений) |
| `dispute_transaction` | `GET /dispute/transaction/{id}` | `fetch_status` (эвристика 0.81) | `dispute_transaction(operation)` | ничего: в `Provider::BaseService` нет метода для такой роли, платформа зовёт этот метод напрямую |
| `dispute_resolve` | `PUT /dispute/{id}/resolve` | не распознана (unmapped) | `dispute_resolve(operation)` | добавьте синоним пути или operationId в `rules/operations.yml` и перегенерируйте; расширения `x-specgen-role` для операции в модели нет (docs/IR.md, таблица расширений) |
| `dispute_evidence` | `POST /dispute/{id}/evidence` | не распознана (unmapped) | `dispute_evidence(operation)` | добавьте синоним пути или operationId в `rules/operations.yml` и перегенерируйте; расширения `x-specgen-role` для операции в модели нет (docs/IR.md, таблица расширений) |
| `verification_bvnMatch` | `POST /bvn/match` | не распознана (unmapped) | `verification_bvn_match(operation)` | добавьте синоним пути или operationId в `rules/operations.yml` и перегенерируйте; расширения `x-specgen-role` для операции в модели нет (docs/IR.md, таблица расширений) |
| `verification_resolveBvn` | `GET /bank/resolve_bvn/{bvn}` | не распознана (unmapped) | `verification_resolve_bvn(operation)` | добавьте синоним пути или operationId в `rules/operations.yml` и перегенерируйте; расширения `x-specgen-role` для операции в модели нет (docs/IR.md, таблица расширений) |
| `verification_resolveAccountNumber` | `GET /bank/resolve` | `balance` (эвристика 0.69) | `verification_resolve_account_number()` | ничего: в `Provider::BaseService` нет метода для такой роли, платформа зовёт этот метод напрямую |
| `verification_resolveCardBin` | `GET /decision/bin/{bin}` | не распознана (unmapped) | `verification_resolve_card_bin(operation)` | добавьте синоним пути или operationId в `rules/operations.yml` и перегенерируйте; расширения `x-specgen-role` для операции в модели нет (docs/IR.md, таблица расширений) |
| `verification_listCountries` | `GET /country` | не распознана (unmapped) | `verification_list_countries()` | добавьте синоним пути или operationId в `rules/operations.yml` и перегенерируйте; расширения `x-specgen-role` для операции в модели нет (docs/IR.md, таблица расширений) |
| `verification_fetchBanks` | `GET /bank` | не распознана (unmapped) | `verification_fetch_banks()` | добавьте синоним пути или operationId в `rules/operations.yml` и перегенерируйте; расширения `x-specgen-role` для операции в модели нет (docs/IR.md, таблица расширений) |
| `verification_avs` | `GET /address_verification/states` | не распознана (unmapped) | `verification_avs()` | добавьте синоним пути или operationId в `rules/operations.yml` и перегенерируйте; расширения `x-specgen-role` для операции в модели нет (docs/IR.md, таблица расширений) |

## 5. Противоречия в самой спецификации

Спецификация расходится сама с собой или со своими соседями: enum против
примеров, коды ответов одной операции против другой, проза против структуры.
Инструмент выбрал, чему верить, и продолжил; правится это правкой
спецификации, а не настройкой инструмента.

### `field_role_conflict` — 4

Что сделал инструмент: роль оставлена полю с большей уверенностью, второе получило следующего кандидата

- **`$.paths['/paymentrequest'].post.requestBody.content['application/json'].schema.properties.customer`** — обязательное поле `customer`: роль external_id (0.21) уже у `invoice_number` (0.90) в той же схеме; взята следующая роль recipient_phone (0.21) — проверьте оба поля и закрепите роли фрагментом ниже
- **`$.paths['/refund'].post.requestBody.content['application/json'].schema.properties.transaction`** — обязательное поле `transaction`: роль currency (0.21) уже у `currency` (0.90) в той же схеме; взята следующая роль provider_operation_id (0.21) — проверьте оба поля и закрепите роли фрагментом ниже
- **`$.paths['/transfer'].post.requestBody.content['application/json'].schema.properties.source`** — обязательное поле `source`: роль currency (0.50) уже у `currency` (0.90) в той же схеме; других кандидатов нет, роль не выведена — задайте её фрагментом ниже
- **`$.paths['/paymentrequest/{id}'].put.requestBody.content['application/json'].schema.properties.customer`** — необязательное поле `customer`: роль external_id (0.21) уже у `invoice_number` (0.90) в той же схеме; взята следующая роль recipient_phone (0.21) — проверьте оба поля и закрепите роли фрагментом ниже

### `undeclared_status_code` — 46

Что сделал инструмент: для кода достроено общее правило ERROR_MAP по HTTP-коду

- **`$.paths['/bulkcharge'].post`** — операция bulkCharge_initiate не объявляет 404, объявленные у соседних операций (transaction_verify); для них достроены общие правила
- **`$.paths['/bvn/match'].post`** — операция verification_bvnMatch не объявляет 404, объявленные у соседних операций (transaction_verify); для них достроены общие правила
- **`$.paths['/charge'].post`** — операция charge_create не объявляет 404, объявленные у соседних операций (transaction_verify); для них достроены общие правила
- **`$.paths['/charge/submit_address'].post`** — операция charge_submitAddress не объявляет 404, объявленные у соседних операций (transaction_verify); для них достроены общие правила
- **`$.paths['/charge/submit_birthday'].post`** — операция charge_submitBirthday не объявляет 404, объявленные у соседних операций (transaction_verify); для них достроены общие правила
- **`$.paths['/charge/submit_otp'].post`** — операция charge_submitOtp не объявляет 404, объявленные у соседних операций (transaction_verify); для них достроены общие правила
- **`$.paths['/charge/submit_phone'].post`** — операция charge_submitPhone не объявляет 404, объявленные у соседних операций (transaction_verify); для них достроены общие правила
- **`$.paths['/charge/submit_pin'].post`** — операция charge_submitPin не объявляет 404, объявленные у соседних операций (transaction_verify); для них достроены общие правила
- **`$.paths['/customer'].post`** — операция customer_create не объявляет 404, объявленные у соседних операций (transaction_verify); для них достроены общие правила
- **`$.paths['/customer/deactivate_authorization'].post`** — операция customer_deactivateAuthorization не объявляет 404, объявленные у соседних операций (transaction_verify); для них достроены общие правила
- **`$.paths['/customer/set_risk_action'].post`** — операция customer_riskAction не объявляет 404, объявленные у соседних операций (transaction_verify); для них достроены общие правила
- **`$.paths['/customer/{code}/identification'].post`** — операция customer_validatte не объявляет 404, объявленные у соседних операций (transaction_verify); для них достроены общие правила
- **`$.paths['/dedicated_account'].post`** — операция dedicatedAccount_create не объявляет 404, объявленные у соседних операций (transaction_verify); для них достроены общие правила
- **`$.paths['/dedicated_account/split'].post`** — операция dedicatedAccount_addSplit не объявляет 404, объявленные у соседних операций (transaction_verify); для них достроены общие правила
- **`$.paths['/dispute/{id}/evidence'].post`** — операция dispute_evidence не объявляет 404, объявленные у соседних операций (transaction_verify); для них достроены общие правила
- **`$.paths['/page'].post`** — операция page_create не объявляет 404, объявленные у соседних операций (transaction_verify); для них достроены общие правила
- **`$.paths['/page/{id}/product'].post`** — операция page_addProducts не объявляет 404, объявленные у соседних операций (transaction_verify); для них достроены общие правила
- **`$.paths['/paymentrequest'].post`** — операция paymentRequest_create не объявляет 404, объявленные у соседних операций (transaction_verify); для них достроены общие правила
- **`$.paths['/paymentrequest/archive/{id}'].post`** — операция paymentRequest_archive не объявляет 404, объявленные у соседних операций (transaction_verify); для них достроены общие правила
- **`$.paths['/paymentrequest/finalize/{id}'].post`** — операция paymentRequest_finalize не объявляет 404, объявленные у соседних операций (transaction_verify); для них достроены общие правила
- и ещё 26 с тем же кодом

## 6. Справки

Факты, о которых читателю стоит знать; решения за человека инструмент здесь не
принимал. Списки сокращены до первых 5 элементов в группе — полный набор
виден в `./integrate analyze --spec paystack_v1.yaml`.

**`field_role_unknown`** — 212

- `$.components.schemas.Customer.properties.first_name` — необязательное поле `first_name` (string): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; в запрос оно не попадёт; если оно нужно, задайте роль фрагментом ниже
- `$.components.schemas.Customer.properties.last_name` — необязательное поле `last_name` (string): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; в запрос оно не попадёт; если оно нужно, задайте роль фрагментом ниже
- `$.components.schemas.Customer.properties.metadata` — необязательное поле `metadata` (string): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; в запрос оно не попадёт; если оно нужно, задайте роль фрагментом ниже
- `$.components.schemas.Customer.properties.risk_action` — необязательное поле `risk_action` (string, enum ["default", "allow", "deny"]): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; в запрос оно не попадёт; если оно нужно, задайте роль фрагментом ниже
- `$.paths['/address_verification/states'].get.parameters[1]` — необязательный параметр `country` (query) (string): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; в запрос оно не попадёт; если оно нужно, задайте роль фрагментом ниже
- и ещё 207 с тем же кодом

**`operation_unmapped`** — 74, подробности в разделе 4

- `$.paths['/address_verification/states'].get` — в спецификации слишком мало признаков того, для чего эта операция, поэтому роль не присвоена (fetch_status 3.0, balance 3.0, cancel 1.0 из 3.0 поданных голосов); задайте роль в overlay
- `$.paths['/bvn/match'].post` — в спецификации слишком мало признаков того, для чего эта операция, поэтому роль не присвоена (create_payout 3.0, create_deposit 3.0, webhook 3.0 из 3.0 поданных голосов); задайте роль в overlay
- `$.paths['/country'].get` — в спецификации слишком мало признаков того, для чего эта операция, поэтому роль не присвоена (fetch_status 3.0, balance 3.0, cancel 1.0 из 3.0 поданных голосов); задайте роль в overlay
- `$.paths['/customer'].get` — в спецификации слишком мало признаков того, для чего эта операция, поэтому роль не присвоена (fetch_status 3.0, balance 3.0, cancel 1.0 из 3.0 поданных голосов); задайте роль в overlay
- `$.paths['/customer/deactivate_authorization'].post` — в спецификации слишком мало признаков того, для чего эта операция, поэтому роль не присвоена (create_payout 3.0, create_deposit 3.0, webhook 3.0 из 3.0 поданных голосов); задайте роль в overlay
- и ещё 69 с тем же кодом

**`server_environment_unknown`** — 1

- `$.servers[0]` — ни описание, ни хост не говорят, песочница это или продакшен; запросы могут уйти не туда

## 7. Что доделать руками

1. Заполните обязательное поле `source` в build_payload: роль не выведена (роль currency отдана `currency` (0.90); ) — добавьте синоним в `rules/roles.yml` или задайте `x-specgen-role` в overlay
2. Проверьте поле `recipient` в build_payload: роль `recipient_type` присвоена с уверенностью ниже порога (эвристика 0.21, композитное сопоставление: name 2.0 (общие токены с синонимом `recipient_type`: recipient (50%)), type 1.0 (type string допустим для роли) = 3.0 из 14.0; следующая recipient_phone 0.21)
3. Задайте валюту запроса: платформа её не сообщает, а спецификация не назвала единственного значения — константа `CURRENCY` не сгенерирована; укажите код валюты через x-specgen-currency в overlay
4. Допишите тело метода `split_create` (операция `split_create`): роль не распознана, запрос собирается пустым
5. Допишите тело метода `split_list` (операция `split_list`): роль не распознана, запрос собирается пустым
6. Допишите тело метода `split_fetch` (операция `split_fetch`): роль не распознана, запрос собирается пустым
7. Допишите тело метода `split_update` (операция `split_update`): роль не распознана, запрос собирается пустым
8. Допишите тело метода `split_add_subaccount` (операция `split_addSubaccount`): роль не распознана, запрос собирается пустым
9. Допишите тело метода `split_remove_subaccount` (операция `split_removeSubaccount`): роль не распознана, запрос собирается пустым
10. Допишите тело метода `customer_create` (операция `customer_create`): роль не распознана, запрос собирается пустым
11. Допишите тело метода `customer_list` (операция `customer_list`): роль не распознана, запрос собирается пустым
12. Допишите тело метода `customer_fetch` (операция `customer_fetch`): роль не распознана, запрос собирается пустым
13. Допишите тело метода `customer_update` (операция `customer_update`): роль не распознана, запрос собирается пустым
14. Допишите тело метода `customer_risk_action` (операция `customer_riskAction`): роль не распознана, запрос собирается пустым
15. Допишите тело метода `customer_deactivate_authorization` (операция `customer_deactivateAuthorization`): роль не распознана, запрос собирается пустым
16. Допишите тело метода `customer_validatte` (операция `customer_validatte`): роль не распознана, запрос собирается пустым
17. Допишите тело метода `dedicated_account_create` (операция `dedicatedAccount_create`): роль не распознана, запрос собирается пустым
18. Допишите тело метода `dedicated_account_deactivate` (операция `dedicatedAccount_deactivate`): роль не распознана, запрос собирается пустым
19. Допишите тело метода `dedicated_account_add_split` (операция `dedicatedAccount_addSplit`): роль не распознана, запрос собирается пустым
20. Допишите тело метода `subaccount_create` (операция `subaccount_create`): роль не распознана, запрос собирается пустым
21. Допишите тело метода `subaccount_list` (операция `subaccount_list`): роль не распознана, запрос собирается пустым
22. Допишите тело метода `subaccount_fetch` (операция `subaccount_fetch`): роль не распознана, запрос собирается пустым
23. Допишите тело метода `subaccount_update` (операция `subaccount_update`): роль не распознана, запрос собирается пустым
24. Допишите тело метода `plan_create` (операция `plan_create`): роль не распознана, запрос собирается пустым
25. Допишите тело метода `plan_list` (операция `plan_list`): роль не распознана, запрос собирается пустым
26. Допишите тело метода `plan_fetch` (операция `plan_fetch`): роль не распознана, запрос собирается пустым
27. Допишите тело метода `plan_update` (операция `plan_update`): роль не распознана, запрос собирается пустым
28. Допишите тело метода `subscription_create` (операция `subscription_create`): роль не распознана, запрос собирается пустым
29. Допишите тело метода `subscription_list` (операция `subscription_list`): роль не распознана, запрос собирается пустым
30. Допишите тело метода `subscription_fetch` (операция `subscription_fetch`): роль не распознана, запрос собирается пустым
31. Допишите тело метода `subscription_disable` (операция `subscription_disable`): роль не распознана, запрос собирается пустым
32. Допишите тело метода `subscription_enable` (операция `subscription_enable`): роль не распознана, запрос собирается пустым
33. Допишите тело метода `subscription_manage_link` (операция `subscription_manageLink`): роль не распознана, запрос собирается пустым
34. Допишите тело метода `subscription_manage_email` (операция `subscription_manageEmail`): роль не распознана, запрос собирается пустым
35. Допишите тело метода `product_create` (операция `product_create`): роль не распознана, запрос собирается пустым
36. Допишите тело метода `product_list` (операция `product_list`): роль не распознана, запрос собирается пустым
37. Допишите тело метода `product_fetch` (операция `product_fetch`): роль не распознана, запрос собирается пустым
38. Допишите тело метода `product_update` (операция `product_update`): роль не распознана, запрос собирается пустым
39. Допишите тело метода `product_delete` (операция `product_delete`): роль не распознана, запрос собирается пустым
40. Допишите тело метода `page_create` (операция `page_create`): роль не распознана, запрос собирается пустым
41. Допишите тело метода `page_list` (операция `page_list`): роль не распознана, запрос собирается пустым
42. Допишите тело метода `page_fetch` (операция `page_fetch`): роль не распознана, запрос собирается пустым
43. Допишите тело метода `page_update` (операция `page_update`): роль не распознана, запрос собирается пустым
44. Допишите тело метода `page_check_slug_availability` (операция `page_checkSlugAvailability`): роль не распознана, запрос собирается пустым
45. Допишите тело метода `page_add_products` (операция `page_addProducts`): роль не распознана, запрос собирается пустым
46. Допишите тело метода `payment_request_update` (операция `paymentRequest_update`): роль не распознана, запрос собирается пустым
47. Допишите тело метода `settlements_fetch` (операция `settlements_fetch`): роль не распознана, запрос собирается пустым
48. Допишите тело метода `put_transferrecipient_code` (операция `put_transferrecipient_code`): роль не распознана, запрос собирается пустым
49. Допишите тело метода `integration_update_payment_session_timeout` (операция `integration_updatePaymentSessionTimeout`): роль не распознана, запрос собирается пустым
50. Допишите тело метода `refund_list` (операция `refund_list`): роль не распознана, запрос собирается пустым
51. Допишите тело метода `refund_fetch` (операция `refund_fetch`): роль не распознана, запрос собирается пустым
52. Допишите тело метода `dispute_list` (операция `dispute_list`): роль не распознана, запрос собирается пустым
53. Допишите тело метода `dispute_fetch` (операция `dispute_fetch`): роль не распознана, запрос собирается пустым
54. Допишите тело метода `dispute_update` (операция `dispute_update`): роль не распознана, запрос собирается пустым
55. Допишите тело метода `dispute_upload_url` (операция `dispute_uploadUrl`): роль не распознана, запрос собирается пустым
56. Допишите тело метода `dispute_download` (операция `dispute_download`): роль не распознана, запрос собирается пустым
57. Допишите тело метода `dispute_resolve` (операция `dispute_resolve`): роль не распознана, запрос собирается пустым
58. Допишите тело метода `dispute_evidence` (операция `dispute_evidence`): роль не распознана, запрос собирается пустым
59. Допишите тело метода `verification_bvn_match` (операция `verification_bvnMatch`): роль не распознана, запрос собирается пустым
60. Допишите тело метода `verification_resolve_bvn` (операция `verification_resolveBvn`): роль не распознана, запрос собирается пустым
61. Допишите тело метода `verification_resolve_card_bin` (операция `verification_resolveCardBin`): роль не распознана, запрос собирается пустым
62. Допишите тело метода `verification_list_countries` (операция `verification_listCountries`): роль не распознана, запрос собирается пустым
63. Допишите тело метода `verification_fetch_banks` (операция `verification_fetchBanks`): роль не распознана, запрос собирается пустым
64. Допишите тело метода `verification_avs` (операция `verification_avs`): роль не распознана, запрос собирается пустым
65. Решите судьбу необязательного поля `callback_url`: роли нет, в payload оно не попало
66. Решите судьбу необязательного поля `plan`: роли нет, в payload оно не попало
67. Решите судьбу необязательного поля `invoice_limit`: роли нет, в payload оно не попало
68. Решите судьбу необязательного поля `metadata`: роли нет, в payload оно не попало
69. Решите судьбу необязательного поля `channels`: роли нет, в payload оно не попало
70. Решите судьбу необязательного поля `split_code`: роли нет, в payload оно не попало
71. Решите судьбу необязательного поля `subaccount`: роли нет, в payload оно не попало
72. Решите судьбу необязательного поля `transaction_charge`: роли нет, в payload оно не попало
73. Решите судьбу необязательного поля `metadata`: роли нет, в payload оно не попало
74. Решите судьбу необязательного поля `split_code`: роли нет, в payload оно не попало
75. Решите судьбу необязательного поля `subaccount`: роли нет, в payload оно не попало
76. Решите судьбу необязательного поля `transaction_charge`: роли нет, в payload оно не попало
77. Решите судьбу необязательного поля `queue`: роли нет, в payload оно не попало
78. Решите судьбу необязательного поля `authorization_code`: роли нет, в payload оно не попало
79. Решите судьбу необязательного поля `at_least`: роли нет, в payload оно не попало
80. Решите судьбу необязательного поля `bearer_type`: роли нет, в payload оно не попало
81. Решите судьбу необязательного поля `bearer_subaccount`: роли нет, в payload оно не попало
82. Решите судьбу необязательного поля `name`: роли нет, в payload оно не попало
83. Решите судьбу необязательного поля `active`: роли нет, в payload оно не попало
84. Решите судьбу необязательного поля `bearer_type`: роли нет, в payload оно не попало
85. И ещё 95 однотипных пунктов — полный список в разделах 3 и 6
86. Проверьте значения фикстуры `transaction_initialize`: тело собрано не из примеров спецификации (`synthesized`)
87. Проверьте значения фикстуры `transaction_chargeAuthorization`: тело собрано не из примеров спецификации (`synthesized`)
88. Проверьте значения фикстуры `transaction_checkAuthorization`: тело собрано не из примеров спецификации (`synthesized`)
89. Проверьте значения фикстуры `transaction_partialDebit`: тело собрано не из примеров спецификации (`synthesized`)
90. Проверьте значения фикстуры `split_create`: тело собрано не из примеров спецификации (`synthesized`)
91. Проверьте значения фикстуры `split_update`: тело собрано не из примеров спецификации (`schema_example`)
92. Проверьте значения фикстуры `split_addSubaccount`: тело собрано не из примеров спецификации (`synthesized`)
93. Проверьте значения фикстуры `split_removeSubaccount`: тело собрано не из примеров спецификации (`synthesized`)
94. Проверьте значения фикстуры `customer_create`: тело собрано не из примеров спецификации (`synthesized`)
95. Проверьте значения фикстуры `customer_update`: тело собрано не из примеров спецификации (`synthesized`)
96. Проверьте значения фикстуры `customer_riskAction`: тело собрано не из примеров спецификации (`synthesized`)
97. Проверьте значения фикстуры `customer_deactivateAuthorization`: тело собрано не из примеров спецификации (`synthesized`)
98. Проверьте значения фикстуры `customer_validatte`: тело собрано не из примеров спецификации (`synthesized`)
99. Проверьте значения фикстуры `dedicatedAccount_create`: тело собрано не из примеров спецификации (`synthesized`)
100. Проверьте значения фикстуры `dedicatedAccount_addSplit`: тело собрано не из примеров спецификации (`synthesized`)
101. Проверьте значения фикстуры `subaccount_create`: тело собрано не из примеров спецификации (`synthesized`)
102. Проверьте значения фикстуры `subaccount_update`: тело собрано не из примеров спецификации (`synthesized`)
103. Проверьте значения фикстуры `plan_create`: тело собрано не из примеров спецификации (`synthesized`)
104. Проверьте значения фикстуры `plan_update`: тело собрано не из примеров спецификации (`synthesized`)
105. Проверьте значения фикстуры `subscription_create`: тело собрано не из примеров спецификации (`synthesized`)
106. И ещё 464 однотипных пунктов — полный список в разделах 3 и 6
107. Подключите вторую операцию создания `transaction_initialize` вручную: контракт даёт один метод создания
108. Подключите вторую операцию создания `transaction_chargeAuthorization` вручную: контракт даёт один метод создания
109. Подключите вторую операцию создания `transaction_checkAuthorization` вручную: контракт даёт один метод создания
110. Подключите вторую операцию создания `transaction_partialDebit` вручную: контракт даёт один метод создания
111. Подключите вторую операцию создания `paymentRequest_create` вручную: контракт даёт один метод создания
112. Подключите вторую операцию создания `transferrecipient_create` вручную: контракт даёт один метод создания
113. Подключите вторую операцию создания `transferrecipient_bulk` вручную: контракт даёт один метод создания
114. Подключите вторую операцию создания `transfer_finalize` вручную: контракт даёт один метод создания
115. Подключите вторую операцию создания `transfer_bulk` вручную: контракт даёт один метод создания
116. Подключите вторую операцию создания `transfer_resendOtp` вручную: контракт даёт один метод создания
117. Подключите вторую операцию создания `transfer_disableOtpFinalize` вручную: контракт даёт один метод создания
118. Подключите вторую операцию создания `charge_create` вручную: контракт даёт один метод создания
119. Подключите вторую операцию создания `charge_submitPin` вручную: контракт даёт один метод создания
120. Подключите вторую операцию создания `charge_submitOtp` вручную: контракт даёт один метод создания
121. Подключите вторую операцию создания `charge_submitPhone` вручную: контракт даёт один метод создания
122. Подключите вторую операцию создания `charge_submitBirthday` вручную: контракт даёт один метод создания
123. Подключите вторую операцию создания `charge_submitAddress` вручную: контракт даёт один метод создания
124. Подключите вторую операцию создания `bulkCharge_initiate` вручную: контракт даёт один метод создания

Итого: 124 пункта.
