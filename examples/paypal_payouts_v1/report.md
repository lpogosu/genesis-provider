# Отчёт о разборе спецификации «Payouts»

| | |
|---|---|
| Провайдер | `paypal_payouts_v1` |
| Спецификация | `paypal_payouts_v1.json`, версия 1.9, OpenAPI 3.0.3 |
| Класс сервиса | `Provider::PaypalPayoutsV1Service` |
| Файл сервиса | `paypal_payouts_v1_service.rb` |

Отчёт сгенерирован инструментом integrate из той же модели провайдера, что и
сервис: всё, о чём здесь сказано, лежит в сгенерированных файлах рядом.
Каждая строка ниже — действие, а не констатация: если элемент спецификации
попал в отчёт, к нему приложено, что сделал инструмент и чем это закрыть.
Генерация не блокируется никогда, поэтому отчёт описывает готовые файлы, а не
причину отказа.

## 1. Сводка

| Показатель | Значение |
|---|---|
| Операции | всего 4: отображено на контракт 3, вне контракта 1, без роли (unmapped) 0 |
| Схемы и поля | схем 52, полей 161: скалярных 100, контейнеров 61 |
| Роли полей | 32 из 100 скалярных: по справочнику 31, эвристика ниже порога 1 |
| Поля без роли | 68: обязательных 14, необязательных 54 |
| Статусы | 9: сопоставлено 5, не сопоставлено 4 |
| События вебхука | 0: сопоставлено 0, не сопоставлено 0 |
| Коды ошибок | кодов провайдера 0: в enum 0, только в примерах 0; общих правил по HTTP-коду 3 |
| Условия взаимодействия | 9: из структуры 9, из прозы описаний 0 |
| Предупреждения | 88: ошибок 0, предупреждений 21, справок 67 |

Сгенерированные артефакты:

| Файл | Что это | Строк |
|---|---|---|
| `paypal_payouts_v1_service.rb` | сервис по контракту базового класса | 361 |
| `INTEGRATION.md` | документация интеграции | 207 |
| `fixtures.json` | примеры запросов, ответов и уведомлений | 444 |
| `report.md` | этот отчёт | считается в момент записи |

### Сверка сгенерированного со спецификацией

Тела из `fixtures.json` проверены схемами той же спецификации, из которой они
выведены: запрос — схемой тела своей операции, ответ — схемой своего кода
ответа, уведомление — схемой тела вебхука. Это замыкает круг: спецификация →
разбор → генерация → обратно к спецификации. Тела, которых спецификация не
обещала (операция без `requestBody`, ответ `204`), в счёт не идут — проверять
там нечего.

**Сверено тел: 19; прошли схему: 15; не прошли: 0; синтезированы и схему не проходят: 0; сверить не с чем: 4.**

**Сверить не с чем — 4** — схемы в спецификации нет, сверять не с чем — это пробел спецификации, а не итог проверки

- **ответ payouts.post default** — схему не удалось проверить: /components/schemas/error; место: `$.paths['/v1/payments/payouts'].post.responses.default.content['application/json'].schema`
- **ответ payouts.get default** — схему не удалось проверить: /components/schemas/error; место: `$.paths['/v1/payments/payouts/{id}'].get.responses.default.content['application/json'].schema`
- **ответ payouts-item.get default** — схему не удалось проверить: /components/schemas/error; место: `$.paths['/v1/payments/payouts-item/{payout_item_id}'].get.responses.default.content['application/json'].schema`
- **ответ payouts-item.cancel default** — схему не удалось проверить: /components/schemas/error; место: `$.paths['/v1/payments/payouts-item/{payout_item_id}/cancel'].post.responses.default.content['application/json'].schema`

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

**Проверок: 18; прошло: 14; не прошло: 1; не проверено: 3.**

**Не прошло — 1** — класс сделал не то, что обещают фикстуры и таблицы INTEGRATION.md: это расхождение сгенерированного кода с сгенерированной документацией, и его надо прочитать глазами

- **прогон: create_request — тело запроса** — значение `items`: ожидалось [{"recipient_type":"EMAIL","amount":{"value":"9.87","currenc…, отправлено []

**Не проверено — 3** — вызывать было нечем или незачем: спецификация не описала операции, фикстура не даёт данных либо инструмент сам оставил в этом месте TODO — пробел уже назван в разделах ниже

- **прогон: check_conditions — сумма ниже минимума (—)** — спецификация не задаёт минимальной суммы — проверять нечего
- **прогон: create_request — заголовок авторизации Authorization** — значение заголовка вычисляет сам класс (access_token), и этот метод генератор оставил человеку: в прогоне он отвечает заглушкой, а в фикстуре стоит раскрытая часть выражения
- **прогон: process_callback — уведомление —** — спецификация не описывает вебхуков — уведомление проверить нечем

## 2. Покрытие спецификации

**Покрытие: 34 % (36 из 105 элементов). В границах контракта: 72 % (36 из 50).**

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

Знаменатель второй цифры меньше первого на 55 элементов, и вот они все, по
видам:

- **Поля тел запросов** — 3: необязательные поля без роли — в payload они не идут намеренно (docs/PRINCIPLES.md, раздел «Что генерируем при неполной спеке»), а не по недосмотру
- **Поля тел ответов и уведомлений** — 52: роль поля не входит в читаемые сервисом или не выведена вовсе — методам контракта такое поле прочитать некуда

Больше не вычтено ничего: коды ответов, статусы, события вебхука, условия
взаимодействия, обязательные поля тел запросов и поля запросов с выведенной
ролью остаются в знаменателе второй цифры целиком — даже когда не покрыты,
потому что их непокрытие — пробел интеграции, а не свойство контракта.
Вычтенное не спрятано: каждый вычтенный элемент назван ниже, в «Что не покрыто
и почему», со своей причиной и своей корзиной.

| Измерение | Найдено | Покрыто | Покрытие |
|---|---|---|---|
| Операции | 4 | 4 | 100 % |
| Поля тел запросов | 6 | 1 | 17 % |
| Поля тел ответов и уведомлений | 59 | 7 | 12 % |
| Коды ответов | 18 | 14 | 78 % |
| Статусы | 9 | 5 | 56 % |
| События вебхука | 0 | 0 | нечего покрывать |
| Условия взаимодействия | 9 | 5 | 56 % |

### Что не покрыто и почему

Непокрыто 69: вне контракта 1, структурных исключений 58, требует ручной
работы 10. Корзина каждого элемента вычислена из его причины, таблица причин —
Generators::Report::Gap::BUCKETS.

**Требует ручной работы — 10.** Единственная корзина, адресованная человеку:
здесь спецификация описала то, что контракт умеет использовать, а интеграция
этого не взяла. Перечислена целиком, поимённо и первой — это и есть список
того, что стоит доделать руками.

**Поля тел запросов** — не покрыто 2

- `payouts.post: sender_batch_header.recipient_type` — роль recipient_type выведена, но выражения платформы для неё нет ни в accessors, ни в requisites (rules/contract.yml, раздел platform) — добавьте его туда или заполните поле вручную
- `payouts.post: items` — обязательное поле без роли: в payload попало с TODO и значением по умолчанию, значение подставит человек

**Статусы** — не покрыто 4

- `BLOCKED` — нет пары среди внутренних статусов: в STATUS_MAP nil
- `ONHOLD` — нет пары среди внутренних статусов: в STATUS_MAP nil
- `REFUNDED` — нет пары среди внутренних статусов: в STATUS_MAP nil
- `REVERSED` — нет пары среди внутренних статусов: в STATUS_MAP nil

**Условия взаимодействия** — не покрыто 4

- `field_pattern recipient_type` — проверка не сгенерирована: у платформы нет выражения для поля recipient_type
- `field_max_length recipient_type` — проверка не сгенерирована: у платформы нет выражения для поля recipient_type
- `field_pattern recipient_type` — проверка не сгенерирована: у платформы нет выражения для поля recipient_type
- `field_max_length recipient_type` — проверка не сгенерирована: у платформы нет выражения для поля recipient_type

**Вне контракта — 1.** Ресурсы спецификации, которых методы контракта не
касаются вовсе: чужие операции и их поля, коды и схемы. Контракт про выплаты;
считать пробелом интеграции отсутствие в ней подписок, споров или хранения
карт — то же самое, что считать пробелом отсутствие метода для чужого API.
Свёрнуто числом с примерами.

- **Коды ответов** — 1: `payouts-item.get default`

**Структурные исключения метрики — 58.** Элементы, которым в методах контракта
нет места по построению: поле входящего тела засчитывается, только когда его
роль читает один из четырёх методов; необязательное поле без роли в payload не
идёт намеренно; код, объявленный диапазоном, ветки не даёт. Это устройство
метрики и контракта, а не пропуск разбора. Свёрнуто числом с примерами.

- **Поля тел запросов** — 3: `payouts.post: sender_batch_header.email_subject`, `payouts.post: sender_batch_header.email_message`, `payouts.post: sender_batch_header.note`
- **Поля тел ответов и уведомлений** — 52, например: `payout.batch_header.time_created`, `payout.batch_header.sender_batch_header.email_subject`, `payout.batch_header.sender_batch_header.email_message`
- **Коды ответов** — 3: `payouts.post default`, `payouts.get default`, `payouts-item.cancel default`

## 3. Неоднозначности

Элементы, о которых спецификация говорит недостаточно, чтобы решение было
однозначным. Инструмент решил сам — что именно, сказано под каждым кодом; от
человека нужна проверка, а не заполнение пропуска.

### `currency_unknown` — 1

Что сделал инструмент: валюта не подставлена, множитель суммы по умолчанию

- **`$.components.schemas.payout_item_request.properties.amount`** — валюта суммы не выведена (поле `currency` совпало с ролью currency, но не задаёт ни enum, ни default, ни example); без кода валюты экспоненту ISO 4217 определить нельзя — задайте валюту в overlay

  ```yaml
  - target: "$.components.schemas.payout_item_request.properties.amount"
    update:
      x-specgen-currency: RUB  # код ISO 4217
  ```

### `field_role_low_confidence` — 2

Что сделал инструмент: роль присвоена лучшему кандидату, в коде рядом с полем — комментарий с уверенностью

- **`$.components.schemas.payout_batch.properties.total_items`** — необязательное поле `total_items`: роль amount выведена с низкой уверенностью 0.59 (порог 0.60); кандидаты: amount 0.59; в коде оно будет помечено TODO — проверьте роль и закрепите её фрагментом ниже

  ```yaml
  - target: "$.components.schemas.payout_batch.properties.total_items"
    update:
      x-specgen-role: amount  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.paths['/v1/payments/payouts/{id}'].get.parameters[4]`** — необязательный параметр `total_required` (query): роль amount выведена с низкой уверенностью 0.14 (порог 0.60); кандидаты: amount 0.14; в коде оно будет помечено TODO — проверьте роль и закрепите её фрагментом ниже

  ```yaml
  - target: "$.paths['/v1/payments/payouts/{id}'].get.parameters[4]"
    update:
      x-specgen-role: amount  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```

### `idempotency_dedup_unclear` — 1

Что сделал инструмент: ветка дедупликации не сгенерирована: ответ с кодом конфликта пойдёт как ошибка

- **`$.paths['/v1/payments/payouts'].post`** — заголовок PayPal-Request-Id объявлен, но ни одна операция не описывает ответ 409 со схемой успешного ответа; при повторе сервис не отличит дубль от ошибки — уточните у провайдера или опишите ответ в overlay

  ```yaml
  - target: "$.paths['/v1/payments/payouts'].post.responses"
    update:
      '409':
        description: Duplicate idempotency key, previous result returned
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/payout'
  ```

### `operation_tie` — 1

Что сделал инструмент: ничья разрешена связью с ресурсом, а где её нет — порядком объявления

- **`$.paths['/v1/payments/payouts/{id}'].get`** — на роль fetch_status претендует несколько операций с одинаковой уверенностью 0.95 (payouts.get (GET /v1/payments/payouts/{id}), payouts-item.get (GET /v1/payments/payouts-item/{payout_item_id})); взята payouts.get: её связывает с payouts.post общий контейнер ресурса `payouts`, путь продолжает путь создания
  готового overlay-фрагмента нет: исправляется правкой спецификации

### `required_field_role_unknown` — 12

Что сделал инструмент: в исходящем теле поле включено в payload со значением примера или nil и TODO рядом; во входящем — ищется структурно

- **`$.components.schemas.error.properties.debug_id`** — обязательное поле `debug_id` (string): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; без него запрос не уйдёт, поэтому в код оно попадёт с TODO — задайте роль фрагментом ниже или добавьте синоним в rules/roles.yml

  ```yaml
  - target: "$.components.schemas.error.properties.debug_id"
    update:
      x-specgen-role: TODO  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.error.properties.name`** — обязательное поле `name` (string): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; без него запрос не уйдёт, поэтому в код оно попадёт с TODO — задайте роль фрагментом ниже или добавьте синоним в rules/roles.yml

  ```yaml
  - target: "$.components.schemas.error.properties.name"
    update:
      x-specgen-role: TODO  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.error_details.properties.issue`** — обязательное поле `issue` (string): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; без него запрос не уйдёт, поэтому в код оно попадёт с TODO — задайте роль фрагментом ниже или добавьте синоним в rules/roles.yml

  ```yaml
  - target: "$.components.schemas.error_details.properties.issue"
    update:
      x-specgen-role: TODO  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.error_link_description.properties.href`** — обязательное поле `href` (string, pattern "^.*$", min_length 0, max_length 20000): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; без него запрос не уйдёт, поэтому в код оно попадёт с TODO — задайте роль фрагментом ниже или добавьте синоним в rules/roles.yml

  ```yaml
  - target: "$.components.schemas.error_link_description.properties.href"
    update:
      x-specgen-role: TODO  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.error_link_description.properties.rel`** — обязательное поле `rel` (string, pattern "^.*$", min_length 0, max_length 100): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; без него запрос не уйдёт, поэтому в код оно попадёт с TODO — задайте роль фрагментом ниже или добавьте синоним в rules/roles.yml

  ```yaml
  - target: "$.components.schemas.error_link_description.properties.rel"
    update:
      x-specgen-role: TODO  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.link_description.properties.href`** — обязательное поле `href` (string): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; без него запрос не уйдёт, поэтому в код оно попадёт с TODO — задайте роль фрагментом ниже или добавьте синоним в rules/roles.yml

  ```yaml
  - target: "$.components.schemas.link_description.properties.href"
    update:
      x-specgen-role: TODO  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.link_description.properties.rel`** — обязательное поле `rel` (string): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; без него запрос не уйдёт, поэтому в код оно попадёт с TODO — задайте роль фрагментом ниже или добавьте синоним в rules/roles.yml

  ```yaml
  - target: "$.components.schemas.link_description.properties.rel"
    update:
      x-specgen-role: TODO  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.payout_item_detail.properties.receiver`** — обязательное поле `receiver` (string, pattern "^.*$", min_length 0, max_length 127): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; без него запрос не уйдёт, поэтому в код оно попадёт с TODO — задайте роль фрагментом ниже или добавьте синоним в rules/roles.yml

  ```yaml
  - target: "$.components.schemas.payout_item_detail.properties.receiver"
    update:
      x-specgen-role: TODO  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.payout_item_request.properties.receiver`** — обязательное поле `receiver` (string, pattern "^.*$", min_length 0, max_length 127): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; без него запрос не уйдёт, поэтому в код оно попадёт с TODO — задайте роль фрагментом ниже или добавьте синоним в rules/roles.yml

  ```yaml
  - target: "$.components.schemas.payout_item_request.properties.receiver"
    update:
      x-specgen-role: TODO  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.phone.properties.country_code`** — обязательное поле `country_code` (string, pattern "^[0-9]{1,3}?$", min_length 1, max_length 3): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; без него запрос не уйдёт, поэтому в код оно попадёт с TODO — задайте роль фрагментом ниже или добавьте синоним в rules/roles.yml

  ```yaml
  - target: "$.components.schemas.phone.properties.country_code"
    update:
      x-specgen-role: TODO  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.phone.properties.national_number`** — обязательное поле `national_number` (string, pattern "^[0-9]{1,14}?$", min_length 1, max_length 14): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; без него запрос не уйдёт, поэтому в код оно попадёт с TODO — задайте роль фрагментом ниже или добавьте синоним в rules/roles.yml

  ```yaml
  - target: "$.components.schemas.phone.properties.national_number"
    update:
      x-specgen-role: TODO  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas['error_details-2'].properties.issue`** — обязательное поле `issue` (string): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; без него запрос не уйдёт, поэтому в код оно попадёт с TODO — задайте роль фрагментом ниже или добавьте синоним в rules/roles.yml

  ```yaml
  - target: "$.components.schemas['error_details-2'].properties.issue"
    update:
      x-specgen-role: TODO  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```

### `spec_element_unsupported` — 1

Что сделал инструмент: значение расширения отвергнуто, элемент разобран без него

- **`$.components.schemas.error_default`** — `oneOf` из 9 вариантов (error_400, error_401, error_403, error_404, error_409, error_415, error_422, error_500, error_503) разложен: свойства всех вариантов есть в IR и помечены своим вариантом, но обязательным не стало ни одно — какой вариант отправлять, спецификация не говорит
  готового overlay-фрагмента нет: исправляется правкой спецификации

### `status_unmapped` — 4

Что сделал инструмент: в STATUS_MAP значение nil и TODO: сервис вернёт отказ status_unknown

- **`$.components.schemas.payout_batch_items.properties.transaction_status.enum[5]`** — статус onhold неоднозначен: то же, что on_hold, слитное написание; выберите внутренний статус (in_progress | approved | rejected) в overlay

  ```yaml
  - target: "$.components.schemas.payout_batch_items.properties.transaction_status"
    update:
      x-specgen-status-map:
        ONHOLD: in_progress  # in_progress | approved | rejected
  ```
- **`$.components.schemas.payout_batch_items.properties.transaction_status.enum[6]`** — статус blocked неоднозначен: блокировка комплаенсом бывает и временной, и окончательной; выберите внутренний статус (in_progress | approved | rejected) в overlay

  ```yaml
  - target: "$.components.schemas.payout_batch_items.properties.transaction_status"
    update:
      x-specgen-status-map:
        BLOCKED: in_progress  # in_progress | approved | rejected
  ```
- **`$.components.schemas.payout_batch_items.properties.transaction_status.enum[7]`** — статус refunded неоднозначен: успешная операция, деньги затем возвращены; выберите внутренний статус (in_progress | approved | rejected) в overlay

  ```yaml
  - target: "$.components.schemas.payout_batch_items.properties.transaction_status"
    update:
      x-specgen-status-map:
        REFUNDED: in_progress  # in_progress | approved | rejected
  ```
- **`$.components.schemas.payout_batch_items.properties.transaction_status.enum[8]`** — статус reversed неоднозначен: успешная операция, затем развёрнута провайдером; выберите внутренний статус (in_progress | approved | rejected) в overlay

  ```yaml
  - target: "$.components.schemas.payout_batch_items.properties.transaction_status"
    update:
      x-specgen-status-map:
        REVERSED: in_progress  # in_progress | approved | rejected
  ```

### `units_unknown` — 1

Что сделал инструмент: AMOUNT_MULTIPLIER = 1 и TODO: сумма уходит без пересчёта

- **`$.components.schemas.payout_item_request.properties.amount`** — единицы суммы у поля `amount` не выведены (type: object, дробного example нет); без множителя сервис не соберёт запрос — задайте единицы в overlay

  ```yaml
  - target: "$.components.schemas.payout_item_request.properties.amount"
    update:
      x-specgen-amount-unit: minor  # minor | major
      x-specgen-exponent: 2  # экспонента минорной единицы ISO 4217
  ```

### `webhook_missing` — 1

Что сделал инструмент: process_callback отказывает webhooks_not_supported: статус только опросом

- **`$.paths`** — спецификация не описывает входящих уведомлений (нет операции с security: [] и нет секции webhooks); статус операции сервис узнает только опросом через fetch_status
  готового overlay-фрагмента нет: исправляется правкой спецификации

### Как собрать overlay

Фрагменты выше — действия одного документа OpenAPI Overlay 1.0.0
(<https://spec.openapis.org/overlay/v1.0.0.html>). Соберите файл
`paypal_payouts_v1.overlay.yaml`, вставив их подряд под ключ `actions`,
замените значения `TODO` и перегенерируйте:

```yaml
overlay: 1.0.0
info:
  title: paypal_payouts_v1 disambiguation
  version: 1.0.0
actions:
- target: "$..."
  update:
    x-specgen-role: ...
```

```sh
./integrate --spec paypal_payouts_v1.json --provider paypal_payouts_v1 --overlay paypal_payouts_v1.overlay.yaml
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
| `payouts-item.get` | `GET /v1/payments/payouts-item/{payout_item_id}` | `fetch_status` (эвристика 0.95) | `payouts_item_get(operation)` | ничего: в `Provider::BaseService` нет метода для такой роли, платформа зовёт этот метод напрямую |
| `payouts-item.cancel` | `POST /v1/payments/payouts-item/{payout_item_id}/cancel` | `cancel` (эвристика 0.95) | `cancel(operation)` | ничего: в `Provider::BaseService` нет метода для такой роли, платформа зовёт этот метод напрямую |

## 5. Противоречия в самой спецификации

Спецификация расходится сама с собой или со своими соседями: enum против
примеров, коды ответов одной операции против другой, проза против структуры.
Инструмент выбрал, чему верить, и продолжил; правится это правкой
спецификации, а не настройкой инструмента.

### `field_role_conflict` — 5

Что сделал инструмент: роль оставлена полю с большей уверенностью, второе получило следующего кандидата

- **`$.components.schemas.payout_batch_items.properties.payout_batch_id`** — обязательное поле `payout_batch_id`: роль provider_operation_id (0.90) уже у `payout_item_id` (0.90) в той же схеме; других кандидатов нет, роль не выведена — задайте её фрагментом ниже
- **`$.components.schemas.payout_item.properties.payout_batch_id`** — обязательное поле `payout_batch_id`: роль provider_operation_id (0.90) уже у `payout_item_id` (0.90) в той же схеме; других кандидатов нет, роль не выведена — задайте её фрагментом ниже
- **`$.components.schemas.payout_batch.properties.total_pages`** — необязательное поле `total_pages`: роль amount (0.59) уже у `total_items` (0.59) в той же схеме; других кандидатов нет, роль не выведена — задайте её фрагментом ниже
- **`$.components.schemas.payout_batch_items.properties.transaction_id`** — необязательное поле `transaction_id`: роль provider_operation_id (0.90) уже у `payout_item_id` (0.90) в той же схеме; других кандидатов нет, роль не выведена — задайте её фрагментом ниже
- **`$.components.schemas.payout_item.properties.transaction_id`** — необязательное поле `transaction_id`: роль provider_operation_id (0.90) уже у `payout_item_id` (0.90) в той же схеме; других кандидатов нет, роль не выведена — задайте её фрагментом ниже

### `undeclared_status_code` — 4

Что сделал инструмент: для кода достроено общее правило ERROR_MAP по HTTP-коду

- **`$.paths['/v1/payments/payouts'].post`** — операция payouts.post не объявляет 404, объявленные у соседних операций (payouts.get); для них достроены общие правила
- **`$.paths['/v1/payments/payouts-item/{payout_item_id}'].get`** — операция payouts-item.get не объявляет 400, 403, объявленные у соседних операций (payouts.post); для них достроены общие правила
- **`$.paths['/v1/payments/payouts-item/{payout_item_id}/cancel'].post`** — операция payouts-item.cancel не объявляет 403, объявленные у соседних операций (payouts.post); для них достроены общие правила
- **`$.paths['/v1/payments/payouts/{id}'].get`** — операция payouts.get не объявляет 400, 403, объявленные у соседних операций (payouts.post); для них достроены общие правила

## 6. Справки

Факты, о которых читателю стоит знать; решения за человека инструмент здесь не
принимал. Списки сокращены до первых 5 элементов в группе — полный набор
виден в `./integrate analyze --spec paypal_payouts_v1.json`.

**`field_role_unknown`** — 54

- `$.components.schemas.application_context.properties.holler_url` — необязательное поле `holler_url` (string, format uri, min_length 1, max_length 1000): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; в запрос оно не попадёт; если оно нужно, задайте роль фрагментом ниже
- `$.components.schemas.application_context.properties.logo_url` — необязательное поле `logo_url` (string, format uri, min_length 0, max_length 1000): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; в запрос оно не попадёт; если оно нужно, задайте роль фрагментом ниже
- `$.components.schemas.application_context.properties.social_feed_privacy` — необязательное поле `social_feed_privacy` (string, pattern "^.*$", min_length 1, max_length 15, default "PRIVATE"): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; в запрос оно не попадёт; если оно нужно, задайте роль фрагментом ниже
- `$.components.schemas.error.properties.information_link` — необязательное поле `information_link` (string): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; в запрос оно не попадёт; если оно нужно, задайте роль фрагментом ниже
- `$.components.schemas.error_400.properties.debug_id` — необязательное поле `debug_id` (string): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; в запрос оно не попадёт; если оно нужно, задайте роль фрагментом ниже
- и ещё 49 с тем же кодом

**`operation_unmapped`** — 1, подробности в разделе 4

- `$.paths['/v1/payments/payouts-item/{payout_item_id}/cancel'].post` — распознана как cancel, но в Provider::BaseService нет метода для такой роли; она генерируется отдельным публичным методом и остаётся вне контракта

## 7. Что доделать руками

1. Заполните обязательное поле `items` в build_payload: роль не выведена (поле-контейнер (array): роли получают его вложенные поля, а не оно само) — добавьте синоним в `rules/roles.yml` или задайте `x-specgen-role` в overlay
2. Решите судьбу необязательного поля `sender_batch_header.email_subject`: роли нет, в payload оно не попало
3. Решите судьбу необязательного поля `sender_batch_header.email_message`: роли нет, в payload оно не попало
4. Решите судьбу необязательного поля `sender_batch_header.note`: роли нет, в payload оно не попало
5. Проверьте значения фикстуры `payouts.post 201`: тело собрано не из примеров спецификации (`synthesized`)
6. Проверьте значения фикстуры `payouts.post 400`: тело собрано не из примеров спецификации (`synthesized`)
7. Проверьте значения фикстуры `payouts.post 403`: тело собрано не из примеров спецификации (`synthesized`)
8. Проверьте значения фикстуры `payouts.post 500`: тело собрано не из примеров спецификации (`synthesized`)
9. Проверьте значения фикстуры `payouts.post default`: тело собрано не из примеров спецификации (`schema_example`)
10. Проверьте значения фикстуры `payouts.get 200`: тело собрано не из примеров спецификации (`synthesized`)
11. Проверьте значения фикстуры `payouts.get 404`: тело собрано не из примеров спецификации (`synthesized`)
12. Проверьте значения фикстуры `payouts.get 500`: тело собрано не из примеров спецификации (`synthesized`)
13. Проверьте значения фикстуры `payouts.get default`: тело собрано не из примеров спецификации (`schema_example`)
14. Проверьте значения фикстуры `payouts-item.get 200`: тело собрано не из примеров спецификации (`synthesized`)
15. Проверьте значения фикстуры `payouts-item.get 404`: тело собрано не из примеров спецификации (`synthesized`)
16. Проверьте значения фикстуры `payouts-item.get 500`: тело собрано не из примеров спецификации (`synthesized`)
17. Проверьте значения фикстуры `payouts-item.get default`: тело собрано не из примеров спецификации (`schema_example`)
18. Проверьте значения фикстуры `payouts-item.cancel 200`: тело собрано не из примеров спецификации (`synthesized`)
19. Проверьте значения фикстуры `payouts-item.cancel 400`: тело собрано не из примеров спецификации (`synthesized`)
20. Проверьте значения фикстуры `payouts-item.cancel 404`: тело собрано не из примеров спецификации (`synthesized`)
21. Проверьте значения фикстуры `payouts-item.cancel 500`: тело собрано не из примеров спецификации (`synthesized`)
22. Проверьте значения фикстуры `payouts-item.cancel default`: тело собрано не из примеров спецификации (`schema_example`)
23. Уберите повтор в check_conditions: условие `field_max_length` на роль `external_id` пришло от двух полей (`sender_batch_id`, `sender_item_id`)

Итого: 23 пункта.
