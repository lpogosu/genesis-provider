# Отчёт о разборе спецификации «GOV.UK Pay API»

| | |
|---|---|
| Провайдер | `govuk_pay_v1` |
| Спецификация | `govuk_pay_v1.json`, версия 1.0.3, OpenAPI 3.0.1 |
| Класс сервиса | `Provider::GovukPayV1Service` |
| Файл сервиса | `govuk_pay_v1_service.rb` |

Отчёт сгенерирован инструментом integrate из той же модели провайдера, что и
сервис: всё, о чём здесь сказано, лежит в сгенерированных файлах рядом.
Каждая строка ниже — действие, а не констатация: если элемент спецификации
попал в отчёт, к нему приложено, что сделал инструмент и чем это закрыть.
Генерация не блокируется никогда, поэтому отчёт описывает готовые файлы, а не
причину отказа.

## 1. Сводка

| Показатель | Значение |
|---|---|
| Операции | всего 16: отображено на контракт 6, вне контракта 4, без роли (unmapped) 6 |
| Схемы и поля | схем 46, полей 242: скалярных 164, контейнеров 78 |
| Роли полей | 63 из 164 скалярных: по справочнику 44, эвристика выше порога 2, эвристика ниже порога 17 |
| Поля без роли | 101: обязательных 6, необязательных 95 |
| Статусы | 7: сопоставлено 5, не сопоставлено 2 |
| События вебхука | 0: сопоставлено 0, не сопоставлено 0 |
| Коды ошибок | кодов провайдера 0: в enum 0, только в примерах 0; общих правил по HTTP-коду 8 |
| Условия взаимодействия | 22: из структуры 22, из прозы описаний 0 |
| Предупреждения | 203: ошибок 0, предупреждений 34, справок 169 |

Сгенерированные артефакты:

| Файл | Что это | Строк |
|---|---|---|
| `govuk_pay_v1_service.rb` | сервис по контракту базового класса | 671 |
| `INTEGRATION.md` | документация интеграции | 256 |
| `fixtures.json` | примеры запросов, ответов и уведомлений | 1609 |
| `report.md` | этот отчёт | считается в момент записи |

### Сверка сгенерированного со спецификацией

Тела из `fixtures.json` проверены схемами той же спецификации, из которой они
выведены: запрос — схемой тела своей операции, ответ — схемой своего кода
ответа, уведомление — схемой тела вебхука. Это замыкает круг: спецификация →
разбор → генерация → обратно к спецификации. Тела, которых спецификация не
обещала (операция без `requestBody`, ответ `204`), в счёт не идут — проверять
там нечего.

**Сверено тел: 89; прошли схему: 69; не прошли: 0; синтезированы и схему не проходят: 3; сверить не с чем: 17.**

**Синтезированы и схему не проходят — 3** — значение собрал генератор по типу поля либо фикстура негативна намеренно, поэтому расхождение с `pattern` или `enum` законно и ошибкой прогона не считается

- **запрос Create a payment** — поле `metadata` не проходит `object`; место: `$.paths['/v1/payments'].post.requestBody.content['application/json'].schema`
- **ответ Create a payment 201** — поле `metadata` не проходит `object`; место: `$.paths['/v1/payments'].post.responses['201'].content['application/json'].schema`
- **ответ Get a payment 200** — поле `metadata` не проходит `object`; место: `$.paths['/v1/payments/{paymentId}'].get.responses['200'].content['application/json'].schema`

**Сверить не с чем — 17** — схемы в спецификации нет, сверять не с чем — это пробел спецификации, а не итог проверки

- **ответ Search agreements 401** — спецификация обещала тело, но не описала его — сверить нечего; место: `$.paths['/v1/agreements'].get.responses['401']`
- **ответ Create an agreement 401** — спецификация обещала тело, но не описала его — сверить нечего; место: `$.paths['/v1/agreements'].post.responses['401']`
- **ответ Get an agreement 401** — спецификация обещала тело, но не описала его — сверить нечего; место: `$.paths['/v1/agreements/{agreementId}'].get.responses['401']`
- **ответ Cancel an agreement 401** — спецификация обещала тело, но не описала его — сверить нечего; место: `$.paths['/v1/agreements/{agreementId}/cancel'].post.responses['401']`
- **ответ Search disputes 401** — спецификация обещала тело, но не описала его — сверить нечего; место: `$.paths['/v1/disputes'].get.responses['401']`
- **ответ Search payments 401** — спецификация обещала тело, но не описала его — сверить нечего; место: `$.paths['/v1/payments'].get.responses['401']`
- **ответ Create a payment 401** — спецификация обещала тело, но не описала его — сверить нечего; место: `$.paths['/v1/payments'].post.responses['401']`
- **ответ Get a payment 401** — спецификация обещала тело, но не описала его — сверить нечего; место: `$.paths['/v1/payments/{paymentId}'].get.responses['401']`
- и ещё 9 того же вида

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

**Проверок: 32; прошло: 29; не прошло: 1; не проверено: 2.**

**Не прошло — 1** — класс сделал не то, что обещают фикстуры и таблицы INTEGRATION.md: это расхождение сгенерированного кода с сгенерированной документацией, и его надо прочитать глазами

- **прогон: create_request — тело запроса** — значение `reference`: ожидалось "12345", отправлено "hu20sqlact5260q2nanm0q8u93"

**Не проверено — 2** — вызывать было нечем или незачем: спецификация не описала операции, фикстура не даёт данных либо инструмент сам оставил в этом месте TODO — пробел уже назван в разделах ниже

- **прогон: check_conditions — сумма ниже минимума (—)** — минимальная сумма — 0: ниже неё суммы не бывает, и отказа тоже
- **прогон: process_callback — уведомление —** — спецификация не описывает вебхуков — уведомление проверить нечем

## 2. Покрытие спецификации

**Покрытие: 36 % (144 из 395 элементов). В границах контракта: 89 % (144 из 162).**

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

Знаменатель второй цифры меньше первого на 233 элемента, и вот они все, по
видам:

- **Поля тел запросов** — 17: необязательные поля без роли — в payload они не идут намеренно (docs/PRINCIPLES.md, раздел «Что генерируем при неполной спеке»), а не по недосмотру
- **Поля тел ответов и уведомлений** — 216: роль поля не входит в читаемые сервисом или не выведена вовсе — методам контракта такое поле прочитать некуда

Больше не вычтено ничего: коды ответов, статусы, события вебхука, условия
взаимодействия, обязательные поля тел запросов и поля запросов с выведенной
ролью остаются в знаменателе второй цифры целиком — даже когда не покрыты,
потому что их непокрытие — пробел интеграции, а не свойство контракта.
Вычтенное не спрятано: каждый вычтенный элемент назван ниже, в «Что не покрыто
и почему», со своей причиной и своей корзиной.

| Измерение | Найдено | Покрыто | Покрытие |
|---|---|---|---|
| Операции | 16 | 10 | 63 % |
| Поля тел запросов | 29 | 4 | 14 % |
| Поля тел ответов и уведомлений | 232 | 16 | 7 % |
| Коды ответов | 89 | 89 | 100 % |
| Статусы | 7 | 5 | 71 % |
| События вебхука | 0 | 0 | нечего покрывать |
| Условия взаимодействия | 22 | 20 | 91 % |

### Что не покрыто и почему

Непокрыто 251: вне контракта 104, структурных исключений 140, требует ручной
работы 7. Корзина каждого элемента вычислена из его причины, таблица причин —
Generators::Report::Gap::BUCKETS.

**Требует ручной работы — 7.** Единственная корзина, адресованная человеку:
здесь спецификация описала то, что контракт умеет использовать, а интеграция
этого не взяла. Перечислена целиком, поимённо и первой — это и есть список
того, что стоит доделать руками.

**Поля тел запросов** — не покрыто 3

- `Create a payment: agreement_payment_type` — роль recipient_type выведена, но выражения платформы для неё нет ни в accessors, ни в requisites (rules/contract.yml, раздел platform) — добавьте его туда или заполните поле вручную
- `Create a payment: description` — обязательное поле без роли: в payload попало с TODO и значением по умолчанию, значение подставит человек
- `Create a payment: return_url` — обязательное поле без роли: в payload попало с TODO и значением по умолчанию, значение подставит человек

**Статусы** — не покрыто 2

- `active` — нет пары среди внутренних статусов: в STATUS_MAP nil
- `inactive` — нет пары среди внутренних статусов: в STATUS_MAP nil

**Условия взаимодействия** — не покрыто 2

- `field_max_length card_number` — проверка не сгенерирована: у платформы нет выражения для поля card_number
- `min_amount amount` — проверка не сгенерирована: у платформы нет выражения для поля amount

**Вне контракта — 104.** Ресурсы спецификации, которых методы контракта не
касаются вовсе: чужие операции и их поля, коды и схемы. Контракт про выплаты;
считать пробелом интеграции отсутствие в ней подписок, споров или хранения
карт — то же самое, что считать пробелом отсутствие метода для чужого API.
Свёрнуто числом с примерами.

- **Операции** — 6, например: `Search agreements`, `Create an agreement`, `Get an agreement`
- **Поля тел запросов** — 8, например: `Create an agreement: description`, `Create an agreement: user_identifier`, `Authorise a MOTO payment: card_number`
- **Поля тел ответов и уведомлений** — 90, например: `AgreementSearchResults._links.first_page.href`, `AgreementSearchResults._links.first_page.method`, `AgreementSearchResults._links.last_page.href`

**Структурные исключения метрики — 140.** Элементы, которым в методах
контракта нет места по построению: поле входящего тела засчитывается, только
когда его роль читает один из четырёх методов; необязательное поле без роли в
payload не идёт намеренно; код, объявленный диапазоном, ветки не даёт. Это
устройство метрики и контракта, а не пропуск разбора. Свёрнуто числом с
примерами.

- **Поля тел запросов** — 14, например: `Create a payment: agreement_id`, `Create a payment: authorisation_mode`, `Create a payment: delayed_capture`
- **Поля тел ответов и уведомлений** — 126, например: `RequestError.description`, `RequestError.field`, `RequestError.header`

## 3. Неоднозначности

Элементы, о которых спецификация говорит недостаточно, чтобы решение было
однозначным. Инструмент решил сам — что именно, сказано под каждым кодом; от
человека нужна проверка, а не заполнение пропуска.

### `currency_unknown` — 1

Что сделал инструмент: валюта не подставлена, множитель суммы по умолчанию

- **`$.components.schemas.CreateCardPaymentRequest.properties.amount`** — валюта суммы не выведена (поле `method` совпало с ролью currency, но его пример `GET` не код ISO 4217 — кандидат отвергнут); без кода валюты экспоненту ISO 4217 определить нельзя — задайте валюту в overlay

  ```yaml
  - target: "$.components.schemas.CreateCardPaymentRequest.properties.amount"
    update:
      x-specgen-currency: RUB  # код ISO 4217
  ```

### `field_role_low_confidence` — 20

Что сделал инструмент: роль присвоена лучшему кандидату, в коде рядом с полем — комментарий с уверенностью

- **`$.components.schemas.CreateCardPaymentRequest.properties.reference`** — обязательное поле `reference`: роль provider_operation_id выведена с низкой уверенностью 0.50 (порог 0.60); кандидаты: provider_operation_id 0.50, external_id 0.21; без него запрос не уйдёт, поэтому в код оно попадёт как provider_operation_id с TODO — проверьте роль и закрепите её фрагментом ниже

  ```yaml
  - target: "$.components.schemas.CreateCardPaymentRequest.properties.reference"
    update:
      x-specgen-role: provider_operation_id  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.Agreement.properties.reference`** — необязательное поле `reference`: роль external_id выведена с низкой уверенностью 0.21 (порог 0.60); кандидаты: external_id 0.21, provider_operation_id 0.21; в коде оно будет помечено TODO — проверьте роль и закрепите её фрагментом ниже

  ```yaml
  - target: "$.components.schemas.Agreement.properties.reference"
    update:
      x-specgen-role: external_id  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.CardDetails.properties.card_type`** — необязательное поле `card_type`: роль card_number выведена с низкой уверенностью 0.50 (порог 0.60); кандидаты: card_number 0.50; в коде оно будет помечено TODO — проверьте роль и закрепите её фрагментом ниже

  ```yaml
  - target: "$.components.schemas.CardDetails.properties.card_type"
    update:
      x-specgen-role: card_number  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.CardDetailsFromResponse.properties.card_type`** — необязательное поле `card_type`: роль card_number выведена с низкой уверенностью 0.50 (порог 0.60); кандидаты: card_number 0.50; в коде оно будет помечено TODO — проверьте роль и закрепите её фрагментом ниже

  ```yaml
  - target: "$.components.schemas.CardDetailsFromResponse.properties.card_type"
    update:
      x-specgen-role: card_number  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.CreateAgreementRequest.properties.reference`** — необязательное поле `reference`: роль external_id выведена с низкой уверенностью 0.21 (порог 0.60); кандидаты: external_id 0.21, provider_operation_id 0.21; в коде оно будет помечено TODO — проверьте роль и закрепите её фрагментом ниже

  ```yaml
  - target: "$.components.schemas.CreateAgreementRequest.properties.reference"
    update:
      x-specgen-role: external_id  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.CreateCardPaymentRequest.properties.agreement_payment_type`** — необязательное поле `agreement_payment_type`: роль recipient_type выведена с низкой уверенностью 0.21 (порог 0.60); кандидаты: recipient_type 0.21; в коде оно будет помечено TODO — проверьте роль и закрепите её фрагментом ниже

  ```yaml
  - target: "$.components.schemas.CreateCardPaymentRequest.properties.agreement_payment_type"
    update:
      x-specgen-role: recipient_type  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.Exemption.properties.requested`** — необязательное поле `requested`: роль created_at выведена с низкой уверенностью 0.14 (порог 0.60); кандидаты: created_at 0.14, idempotency_key 0.14; в коде оно будет помечено TODO — проверьте роль и закрепите её фрагментом ниже

  ```yaml
  - target: "$.components.schemas.Exemption.properties.requested"
    update:
      x-specgen-role: created_at  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.Link.properties.method`** — необязательное поле `method`: роль currency выведена с низкой уверенностью 0.24 (порог 0.60); кандидаты: currency 0.24; в коде оно будет помечено TODO — проверьте роль и закрепите её фрагментом ниже

  ```yaml
  - target: "$.components.schemas.Link.properties.method"
    update:
      x-specgen-role: currency  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.PaymentDetailForSearch.properties.agreement_payment_type`** — необязательное поле `agreement_payment_type`: роль recipient_type выведена с низкой уверенностью 0.21 (порог 0.60); кандидаты: recipient_type 0.21; в коде оно будет помечено TODO — проверьте роль и закрепите её фрагментом ниже

  ```yaml
  - target: "$.components.schemas.PaymentDetailForSearch.properties.agreement_payment_type"
    update:
      x-specgen-role: recipient_type  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.PaymentDetailForSearch.properties.card_brand`** — необязательное поле `card_brand`: роль card_number выведена с низкой уверенностью 0.21 (порог 0.60); кандидаты: card_number 0.21; в коде оно будет помечено TODO — проверьте роль и закрепите её фрагментом ниже

  ```yaml
  - target: "$.components.schemas.PaymentDetailForSearch.properties.card_brand"
    update:
      x-specgen-role: card_number  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.PaymentState.properties.finished`** — необязательное поле `finished`: роль completed_at выведена с низкой уверенностью 0.14 (порог 0.60); кандидаты: completed_at 0.14; в коде оно будет помечено TODO — проверьте роль и закрепите её фрагментом ниже

  ```yaml
  - target: "$.components.schemas.PaymentState.properties.finished"
    update:
      x-specgen-role: completed_at  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.PaymentWithAllLinks.properties.agreement_payment_type`** — необязательное поле `agreement_payment_type`: роль recipient_type выведена с низкой уверенностью 0.21 (порог 0.60); кандидаты: recipient_type 0.21; в коде оно будет помечено TODO — проверьте роль и закрепите её фрагментом ниже

  ```yaml
  - target: "$.components.schemas.PaymentWithAllLinks.properties.agreement_payment_type"
    update:
      x-specgen-role: recipient_type  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.PaymentWithAllLinks.properties.card_brand`** — необязательное поле `card_brand`: роль card_number выведена с низкой уверенностью 0.21 (порог 0.60); кандидаты: card_number 0.21; в коде оно будет помечено TODO — проверьте роль и закрепите её фрагментом ниже

  ```yaml
  - target: "$.components.schemas.PaymentWithAllLinks.properties.card_brand"
    update:
      x-specgen-role: card_number  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.RefundSummary.properties.amount_available`** — необязательное поле `amount_available`: роль amount выведена с низкой уверенностью 0.21 (порог 0.60); кандидаты: amount 0.21; в коде оно будет помечено TODO — проверьте роль и закрепите её фрагментом ниже

  ```yaml
  - target: "$.components.schemas.RefundSummary.properties.amount_available"
    update:
      x-specgen-role: amount  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.paths['/v1/agreements'].get.parameters[0]`** — необязательный параметр `reference` (query): роль external_id выведена с низкой уверенностью 0.21 (порог 0.60); кандидаты: external_id 0.21, provider_operation_id 0.21; в коде оно будет помечено TODO — проверьте роль и закрепите её фрагментом ниже

  ```yaml
  - target: "$.paths['/v1/agreements'].get.parameters[0]"
    update:
      x-specgen-role: external_id  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.paths['/v1/disputes'].get.parameters[3]`** — необязательный параметр `to_settled_date` (query): роль completed_at выведена с низкой уверенностью 0.26 (порог 0.60); кандидаты: completed_at 0.26; в коде оно будет помечено TODO — проверьте роль и закрепите её фрагментом ниже

  ```yaml
  - target: "$.paths['/v1/disputes'].get.parameters[3]"
    update:
      x-specgen-role: completed_at  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.paths['/v1/payments'].get.parameters[0]`** — необязательный параметр `reference` (query): роль external_id выведена с низкой уверенностью 0.21 (порог 0.60); кандидаты: external_id 0.21, provider_operation_id 0.21; в коде оно будет помечено TODO — проверьте роль и закрепите её фрагментом ниже

  ```yaml
  - target: "$.paths['/v1/payments'].get.parameters[0]"
    update:
      x-specgen-role: external_id  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.paths['/v1/payments'].get.parameters[12]`** — необязательный параметр `to_settled_date` (query): роль completed_at выведена с низкой уверенностью 0.26 (порог 0.60); кандидаты: completed_at 0.26; в коде оно будет помечено TODO — проверьте роль и закрепите её фрагментом ниже

  ```yaml
  - target: "$.paths['/v1/payments'].get.parameters[12]"
    update:
      x-specgen-role: completed_at  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.paths['/v1/payments'].get.parameters[3]`** — необязательный параметр `card_brand` (query): роль card_number выведена с низкой уверенностью 0.21 (порог 0.60); кандидаты: card_number 0.21; в коде оно будет помечено TODO — проверьте роль и закрепите её фрагментом ниже

  ```yaml
  - target: "$.paths['/v1/payments'].get.parameters[3]"
    update:
      x-specgen-role: card_number  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.paths['/v1/refunds'].get.parameters[3]`** — необязательный параметр `to_settled_date` (query): роль completed_at выведена с низкой уверенностью 0.26 (порог 0.60); кандидаты: completed_at 0.26; в коде оно будет помечено TODO — проверьте роль и закрепите её фрагментом ниже

  ```yaml
  - target: "$.paths['/v1/refunds'].get.parameters[3]"
    update:
      x-specgen-role: completed_at  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```

### `idempotency_dedup_unclear` — 1

Что сделал инструмент: ветка дедупликации не сгенерирована: ответ с кодом конфликта пойдёт как ошибка

- **`$.paths['/v1/payments'].post`** — заголовок Idempotency-Key объявлен, но ни одна операция не описывает ответ 409 со схемой успешного ответа; при повторе сервис не отличит дубль от ошибки — уточните у провайдера или опишите ответ в overlay

  ```yaml
  - target: "$.paths['/v1/payments'].post.responses"
    update:
      '409':
        description: Duplicate idempotency key, previous result returned
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/CreatePaymentResult'
  ```

### `operation_role_ambiguous` — 1

Что сделал инструмент: взят лучший кандидат роли, метод сгенерирован по нему

- **`$.paths['/v1/payments/{paymentId}/refunds'].post`** — две роли подходят этой операции почти одинаково; взята первая, но выбор стоит подтвердить (refund 12.0, create_payout 11.0, cancel 7.5 из 14.0 поданных голосов); переопределить — в overlay
  готового overlay-фрагмента нет: закрепляется записью в `rules/operations.yml` или правкой спецификации

### `operation_tie` — 2

Что сделал инструмент: ничья разрешена связью с ресурсом, а где её нет — порядком объявления

- **`$.paths['/v1/payments/{paymentId}'].get`** — на роль fetch_status претендует несколько операций с одинаковой уверенностью 0.95 (Get a payment (GET /v1/payments/{paymentId}), Get a payment refund (GET /v1/payments/{paymentId}/refunds/{refundId})); взята Get a payment: её связывает с Create a payment общий контейнер ресурса `payments`, путь продолжает путь создания
  готового overlay-фрагмента нет: исправляется правкой спецификации
- **`$.paths['/v1/payments/{paymentId}/cancel'].post`** — на роль cancel претендует несколько операций с одинаковой уверенностью 0.95 (Cancel an agreement (POST /v1/agreements/{agreementId}/cancel), Cancel a payment (POST /v1/payments/{paymentId}/cancel)); взята Cancel a payment: её связывает с Create a payment общий контейнер ресурса `payments`, путь продолжает путь создания
  готового overlay-фрагмента нет: исправляется правкой спецификации

### `required_field_role_unknown` — 8

Что сделал инструмент: в исходящем теле поле включено в payload со значением примера или nil и TODO рядом; во входящем — ищется структурно

- **`$.components.schemas.AuthorisationRequest.properties.cardholder_name`** — обязательное поле `cardholder_name` (string, min_length 0, max_length 255): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; без него запрос не уйдёт, поэтому в код оно попадёт с TODO — задайте роль фрагментом ниже или добавьте синоним в rules/roles.yml

  ```yaml
  - target: "$.components.schemas.AuthorisationRequest.properties.cardholder_name"
    update:
      x-specgen-role: TODO  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.AuthorisationRequest.properties.cvc`** — обязательное поле `cvc` (string, min_length 3, max_length 4): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; без него запрос не уйдёт, поэтому в код оно попадёт с TODO — задайте роль фрагментом ниже или добавьте синоним в rules/roles.yml

  ```yaml
  - target: "$.components.schemas.AuthorisationRequest.properties.cvc"
    update:
      x-specgen-role: TODO  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.AuthorisationRequest.properties.expiry_date`** — обязательное поле `expiry_date` (string, min_length 5, max_length 5): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; без него запрос не уйдёт, поэтому в код оно попадёт с TODO — задайте роль фрагментом ниже или добавьте синоним в rules/roles.yml

  ```yaml
  - target: "$.components.schemas.AuthorisationRequest.properties.expiry_date"
    update:
      x-specgen-role: TODO  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.AuthorisationRequest.properties.one_time_token`** — обязательное поле `one_time_token` (string, min_length 1): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; без него запрос не уйдёт, поэтому в код оно попадёт с TODO — задайте роль фрагментом ниже или добавьте синоним в rules/roles.yml

  ```yaml
  - target: "$.components.schemas.AuthorisationRequest.properties.one_time_token"
    update:
      x-specgen-role: TODO  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.CreateCardPaymentRequest.properties.description`** — обязательное поле `description` (string, min_length 0, max_length 255): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; без него запрос не уйдёт, поэтому в код оно попадёт с TODO — задайте роль фрагментом ниже или добавьте синоним в rules/roles.yml

  ```yaml
  - target: "$.components.schemas.CreateCardPaymentRequest.properties.description"
    update:
      x-specgen-role: TODO  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.CreateCardPaymentRequest.properties.return_url`** — обязательное поле `return_url` (string, min_length 0, max_length 2000): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; без него запрос не уйдёт, поэтому в код оно попадёт с TODO — задайте роль фрагментом ниже или добавьте синоним в rules/roles.yml

  ```yaml
  - target: "$.components.schemas.CreateCardPaymentRequest.properties.return_url"
    update:
      x-specgen-role: TODO  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.paths['/v1/agreements/{agreementId}'].get.parameters[0]`** — обязательный параметр `agreementId` (путь) (string): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; без него запрос не уйдёт, поэтому в код оно попадёт с TODO — задайте роль фрагментом ниже или добавьте синоним в rules/roles.yml

  ```yaml
  - target: "$.paths['/v1/agreements/{agreementId}'].get.parameters[0]"
    update:
      x-specgen-role: TODO  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.paths['/v1/agreements/{agreementId}/cancel'].post.parameters[0]`** — обязательный параметр `agreementId` (путь) (string): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; без него запрос не уйдёт, поэтому в код оно попадёт с TODO — задайте роль фрагментом ниже или добавьте синоним в rules/roles.yml

  ```yaml
  - target: "$.paths['/v1/agreements/{agreementId}/cancel'].post.parameters[0]"
    update:
      x-specgen-role: TODO  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```

### `schema_unresolved` — 17

Что сделал инструмент: схема не разобрана: её поля в код не попали

- **`$.paths['/v1/agreements'].get.responses['401']`** — ответ 401 операции Search agreements объявлен одним описанием: `content` нет, поэтому нечему описывать тело — либо опишите схему, либо объявите ответ без тела кодом 204
  готового overlay-фрагмента нет: исправляется правкой спецификации
- **`$.paths['/v1/agreements'].post.responses['401']`** — ответ 401 операции Create an agreement объявлен одним описанием: `content` нет, поэтому нечему описывать тело — либо опишите схему, либо объявите ответ без тела кодом 204
  готового overlay-фрагмента нет: исправляется правкой спецификации
- **`$.paths['/v1/agreements/{agreementId}'].get.responses['401']`** — ответ 401 операции Get an agreement объявлен одним описанием: `content` нет, поэтому нечему описывать тело — либо опишите схему, либо объявите ответ без тела кодом 204
  готового overlay-фрагмента нет: исправляется правкой спецификации
- **`$.paths['/v1/agreements/{agreementId}/cancel'].post.responses['401']`** — ответ 401 операции Cancel an agreement объявлен одним описанием: `content` нет, поэтому нечему описывать тело — либо опишите схему, либо объявите ответ без тела кодом 204
  готового overlay-фрагмента нет: исправляется правкой спецификации
- **`$.paths['/v1/disputes'].get.responses['401']`** — ответ 401 операции Search disputes объявлен одним описанием: `content` нет, поэтому нечему описывать тело — либо опишите схему, либо объявите ответ без тела кодом 204
  готового overlay-фрагмента нет: исправляется правкой спецификации
- **`$.paths['/v1/payments'].get.responses['401']`** — ответ 401 операции Search payments объявлен одним описанием: `content` нет, поэтому нечему описывать тело — либо опишите схему, либо объявите ответ без тела кодом 204
  готового overlay-фрагмента нет: исправляется правкой спецификации
- **`$.paths['/v1/payments'].post.responses['401']`** — ответ 401 операции Create a payment объявлен одним описанием: `content` нет, поэтому нечему описывать тело — либо опишите схему, либо объявите ответ без тела кодом 204
  готового overlay-фрагмента нет: исправляется правкой спецификации
- **`$.paths['/v1/payments/{paymentId}'].get.responses['401']`** — ответ 401 операции Get a payment объявлен одним описанием: `content` нет, поэтому нечему описывать тело — либо опишите схему, либо объявите ответ без тела кодом 204
  готового overlay-фрагмента нет: исправляется правкой спецификации
- **`$.paths['/v1/payments/{paymentId}/cancel'].post.responses['401']`** — ответ 401 операции Cancel a payment объявлен одним описанием: `content` нет, поэтому нечему описывать тело — либо опишите схему, либо объявите ответ без тела кодом 204
  готового overlay-фрагмента нет: исправляется правкой спецификации
- **`$.paths['/v1/payments/{paymentId}/capture'].post.responses['401']`** — ответ 401 операции Capture a payment объявлен одним описанием: `content` нет, поэтому нечему описывать тело — либо опишите схему, либо объявите ответ без тела кодом 204
  готового overlay-фрагмента нет: исправляется правкой спецификации
- **`$.paths['/v1/payments/{paymentId}/events'].get.responses['401']`** — ответ 401 операции Get events for a payment объявлен одним описанием: `content` нет, поэтому нечему описывать тело — либо опишите схему, либо объявите ответ без тела кодом 204
  готового overlay-фрагмента нет: исправляется правкой спецификации
- **`$.paths['/v1/payments/{paymentId}/refunds'].get.responses['401']`** — ответ 401 операции Get all refunds for a payment объявлен одним описанием: `content` нет, поэтому нечему описывать тело — либо опишите схему, либо объявите ответ без тела кодом 204
  готового overlay-фрагмента нет: исправляется правкой спецификации
- **`$.paths['/v1/payments/{paymentId}/refunds'].post.responses['202']`** — ответ 202 операции Submit a refund for a payment объявлен одним описанием: `content` нет, поэтому нечему описывать тело — либо опишите схему, либо объявите ответ без тела кодом 204
  готового overlay-фрагмента нет: исправляется правкой спецификации
- **`$.paths['/v1/payments/{paymentId}/refunds'].post.responses['401']`** — ответ 401 операции Submit a refund for a payment объявлен одним описанием: `content` нет, поэтому нечему описывать тело — либо опишите схему, либо объявите ответ без тела кодом 204
  готового overlay-фрагмента нет: исправляется правкой спецификации
- **`$.paths['/v1/payments/{paymentId}/refunds'].post.responses['412']`** — ответ 412 операции Submit a refund for a payment объявлен одним описанием: `content` нет, поэтому нечему описывать тело — либо опишите схему, либо объявите ответ без тела кодом 204
  готового overlay-фрагмента нет: исправляется правкой спецификации
- **`$.paths['/v1/payments/{paymentId}/refunds/{refundId}'].get.responses['401']`** — ответ 401 операции Get a payment refund объявлен одним описанием: `content` нет, поэтому нечему описывать тело — либо опишите схему, либо объявите ответ без тела кодом 204
  готового overlay-фрагмента нет: исправляется правкой спецификации
- **`$.paths['/v1/refunds'].get.responses['401']`** — ответ 401 операции Search refunds объявлен одним описанием: `content` нет, поэтому нечему описывать тело — либо опишите схему, либо объявите ответ без тела кодом 204
  готового overlay-фрагмента нет: исправляется правкой спецификации

### `spec_element_unsupported` — 2

Что сделал инструмент: значение расширения отвергнуто, элемент разобран без него

- **`$.components.schemas.ExternalMetadata.properties.metadata`** — `metadata` — свободная карта (`additionalProperties` или объект без `properties`): ключи спецификацией не перечислены, поэтому значением поля остаётся хеш, который заполняют вручную
  готового overlay-фрагмента нет: исправляется правкой спецификации
- **`$.components.schemas.PostLink.properties.params`** — `params` — свободная карта (`additionalProperties` или объект без `properties`): ключи спецификацией не перечислены, поэтому значением поля остаётся хеш, который заполняют вручную
  готового overlay-фрагмента нет: исправляется правкой спецификации

### `status_unmapped` — 2

Что сделал инструмент: в STATUS_MAP значение nil и TODO: сервис вернёт отказ status_unknown

- **`$.components.schemas.Agreement.properties.status.enum[1]`** — статус active неоднозначен: состояние сущности (счёта, ключа, подписки), а не операции: у операции «активна» значит и «идёт», и «доступна к отмене»; выберите внутренний статус (in_progress | approved | rejected) в overlay

  ```yaml
  - target: "$.components.schemas.Agreement.properties.status"
    update:
      x-specgen-status-map:
        active: in_progress  # in_progress | approved | rejected
  ```
- **`$.components.schemas.Agreement.properties.status.enum[3]`** — статус inactive неоднозначен: состояние сущности, а не операции: обратное к active; выберите внутренний статус (in_progress | approved | rejected) в overlay

  ```yaml
  - target: "$.components.schemas.Agreement.properties.status"
    update:
      x-specgen-status-map:
        inactive: in_progress  # in_progress | approved | rejected
  ```

### `webhook_missing` — 1

Что сделал инструмент: process_callback отказывает webhooks_not_supported: статус только опросом

- **`$.paths`** — спецификация не описывает входящих уведомлений (нет операции с security: [] и нет секции webhooks); статус операции сервис узнает только опросом через fetch_status
  готового overlay-фрагмента нет: исправляется правкой спецификации

### Как собрать overlay

Фрагменты выше — действия одного документа OpenAPI Overlay 1.0.0
(<https://spec.openapis.org/overlay/v1.0.0.html>). Соберите файл
`govuk_pay_v1.overlay.yaml`, вставив их подряд под ключ `actions`,
замените значения `TODO` и перегенерируйте:

```yaml
overlay: 1.0.0
info:
  title: govuk_pay_v1 disambiguation
  version: 1.0.0
actions:
- target: "$..."
  update:
    x-specgen-role: ...
```

```sh
./integrate --spec govuk_pay_v1.json --provider govuk_pay_v1 --overlay govuk_pay_v1.overlay.yaml
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
| `Search agreements` | `GET /v1/agreements` | не распознана (unmapped) | `search_agreements()` | добавьте синоним пути или operationId в `rules/operations.yml` и перегенерируйте; расширения `x-specgen-role` для операции в модели нет (docs/IR.md, таблица расширений) |
| `Create an agreement` | `POST /v1/agreements` | не распознана (unmapped) | `create_an_agreement(operation)` | добавьте синоним пути или operationId в `rules/operations.yml` и перегенерируйте; расширения `x-specgen-role` для операции в модели нет (docs/IR.md, таблица расширений) |
| `Get an agreement` | `GET /v1/agreements/{agreementId}` | не распознана (unmapped) | `get_an_agreement(operation)` | добавьте синоним пути или operationId в `rules/operations.yml` и перегенерируйте; расширения `x-specgen-role` для операции в модели нет (docs/IR.md, таблица расширений) |
| `Cancel an agreement` | `POST /v1/agreements/{agreementId}/cancel` | `cancel` (эвристика 0.95) | `cancel(operation)` | ничего: в `Provider::BaseService` нет метода для такой роли, платформа зовёт этот метод напрямую |
| `Authorise a MOTO payment` | `POST /v1/auth` | `create_payout` (эвристика 0.72) | `authorise_a_moto_payment(operation)` | ничего: в `Provider::BaseService` нет метода для такой роли, платформа зовёт этот метод напрямую |
| `Search disputes` | `GET /v1/disputes` | не распознана (unmapped) | `search_disputes()` | добавьте синоним пути или operationId в `rules/operations.yml` и перегенерируйте; расширения `x-specgen-role` для операции в модели нет (docs/IR.md, таблица расширений) |
| `Search payments` | `GET /v1/payments` | не распознана (unmapped) | `search_payments()` | добавьте синоним пути или operationId в `rules/operations.yml` и перегенерируйте; расширения `x-specgen-role` для операции в модели нет (docs/IR.md, таблица расширений) |
| `Cancel a payment` | `POST /v1/payments/{paymentId}/cancel` | `cancel` (эвристика 0.95) | `cancel_a_payment(operation)` | ничего: в `Provider::BaseService` нет метода для такой роли, платформа зовёт этот метод напрямую |
| `Capture a payment` | `POST /v1/payments/{paymentId}/capture` | `confirm` (эвристика 0.86) | `confirm(operation)` | ничего: в `Provider::BaseService` нет метода для такой роли, платформа зовёт этот метод напрямую |
| `Get events for a payment` | `GET /v1/payments/{paymentId}/events` | `fetch_status` (эвристика 0.79) | `get_events_for_a_payment(operation)` | ничего: в `Provider::BaseService` нет метода для такой роли, платформа зовёт этот метод напрямую |
| `Get all refunds for a payment` | `GET /v1/payments/{paymentId}/refunds` | `fetch_status` (эвристика 0.79) | `get_all_refunds_for_a_payment(operation)` | ничего: в `Provider::BaseService` нет метода для такой роли, платформа зовёт этот метод напрямую |
| `Submit a refund for a payment` | `POST /v1/payments/{paymentId}/refunds` | `refund` (эвристика 0.86) | `refund(operation)` | ничего: в `Provider::BaseService` нет метода для такой роли, платформа зовёт этот метод напрямую |
| `Get a payment refund` | `GET /v1/payments/{paymentId}/refunds/{refundId}` | `fetch_status` (эвристика 0.95) | `get_a_payment_refund(operation)` | ничего: в `Provider::BaseService` нет метода для такой роли, платформа зовёт этот метод напрямую |
| `Search refunds` | `GET /v1/refunds` | не распознана (unmapped) | `search_refunds()` | добавьте синоним пути или operationId в `rules/operations.yml` и перегенерируйте; расширения `x-specgen-role` для операции в модели нет (docs/IR.md, таблица расширений) |

## 5. Противоречия в самой спецификации

Спецификация расходится сама с собой или со своими соседями: enum против
примеров, коды ответов одной операции против другой, проза против структуры.
Инструмент выбрал, чему верить, и продолжил; правится это правкой
спецификации, а не настройкой инструмента.

### `field_role_conflict` — 30

Что сделал инструмент: роль оставлена полю с большей уверенностью, второе получило следующего кандидата

- **`$.paths['/v1/payments/{paymentId}/refunds/{refundId}'].get.parameters[0]`** — обязательный параметр `paymentId` (путь): роль provider_operation_id (0.90) уже у `refundId` (0.90) в той же схеме; других кандидатов нет, роль не выведена — задайте её фрагментом ниже
- **`$.components.schemas.CardDetails.properties.card_brand`** — необязательное поле `card_brand`: роль card_number (0.50) уже у `card_type` (0.50) в той же схеме; других кандидатов нет, роль не выведена — задайте её фрагментом ниже
- **`$.components.schemas.CardDetails.properties.first_digits_card_number`** — необязательное поле `first_digits_card_number`: роль card_number (0.50) уже у `card_type` (0.50) в той же схеме; других кандидатов нет, роль не выведена — задайте её фрагментом ниже
- **`$.components.schemas.CardDetails.properties.last_digits_card_number`** — необязательное поле `last_digits_card_number`: роль card_number (0.50) уже у `card_type` (0.50) в той же схеме; других кандидатов нет, роль не выведена — задайте её фрагментом ниже
- **`$.components.schemas.CardDetailsFromResponse.properties.card_brand`** — необязательное поле `card_brand`: роль card_number (0.50) уже у `card_type` (0.50) в той же схеме; других кандидатов нет, роль не выведена — задайте её фрагментом ниже
- **`$.components.schemas.CardDetailsFromResponse.properties.first_digits_card_number`** — необязательное поле `first_digits_card_number`: роль card_number (0.50) уже у `card_type` (0.50) в той же схеме; других кандидатов нет, роль не выведена — задайте её фрагментом ниже
- **`$.components.schemas.CardDetailsFromResponse.properties.last_digits_card_number`** — необязательное поле `last_digits_card_number`: роль card_number (0.50) уже у `card_type` (0.50) в той же схеме; других кандидатов нет, роль не выведена — задайте её фрагментом ниже
- **`$.components.schemas.CreatePaymentResult.properties.payment_provider`** — необязательное поле `payment_provider`: роль provider_operation_id (0.55) уже у `payment_id` (0.90) в той же схеме; других кандидатов нет, роль не выведена — задайте её фрагментом ниже
- **`$.components.schemas.CreatePaymentResult.properties.provider_id`** — необязательное поле `provider_id`: роль provider_operation_id (0.55) уже у `payment_id` (0.90) в той же схеме; других кандидатов нет, роль не выведена — задайте её фрагментом ниже
- **`$.components.schemas.CreatePaymentResult.properties.reference`** — необязательное поле `reference`: роль provider_operation_id (0.50) уже у `payment_id` (0.90) в той же схеме; взята следующая роль external_id (0.21) — проверьте оба поля и закрепите роли фрагментом ниже
- **`$.components.schemas.DisputeDetailForSearch.properties.net_amount`** — необязательное поле `net_amount`: роль amount (0.21) уже у `amount` (0.90) в той же схеме; других кандидатов нет, роль не выведена — задайте её фрагментом ниже
- **`$.components.schemas.PaymentDetailForSearch.properties.net_amount`** — необязательное поле `net_amount`: роль amount (0.50) уже у `amount` (0.90) в той же схеме; других кандидатов нет, роль не выведена — задайте её фрагментом ниже
- **`$.components.schemas.PaymentDetailForSearch.properties.payment_provider`** — необязательное поле `payment_provider`: роль provider_operation_id (0.55) уже у `payment_id` (0.90) в той же схеме; других кандидатов нет, роль не выведена — задайте её фрагментом ниже
- **`$.components.schemas.PaymentDetailForSearch.properties.provider_id`** — необязательное поле `provider_id`: роль provider_operation_id (0.55) уже у `payment_id` (0.90) в той же схеме; других кандидатов нет, роль не выведена — задайте её фрагментом ниже
- **`$.components.schemas.PaymentDetailForSearch.properties.reference`** — необязательное поле `reference`: роль provider_operation_id (0.50) уже у `payment_id` (0.90) в той же схеме; взята следующая роль external_id (0.21) — проверьте оба поля и закрепите роли фрагментом ниже
- **`$.components.schemas.PaymentDetailForSearch.properties.total_amount`** — необязательное поле `total_amount`: роль amount (0.90) уже у `amount` (0.90) в той же схеме; других кандидатов нет, роль не выведена — задайте её фрагментом ниже
- **`$.components.schemas.PaymentSettlementSummary.properties.captured_date`** — необязательное поле `captured_date`: роль completed_at (0.22) уже у `settled_date` (0.90) в той же схеме; других кандидатов нет, роль не выведена — задайте её фрагментом ниже
- **`$.components.schemas.PaymentWithAllLinks.properties.net_amount`** — необязательное поле `net_amount`: роль amount (0.50) уже у `amount` (0.90) в той же схеме; других кандидатов нет, роль не выведена — задайте её фрагментом ниже
- **`$.components.schemas.PaymentWithAllLinks.properties.payment_provider`** — необязательное поле `payment_provider`: роль provider_operation_id (0.55) уже у `payment_id` (0.90) в той же схеме; других кандидатов нет, роль не выведена — задайте её фрагментом ниже
- **`$.components.schemas.PaymentWithAllLinks.properties.provider_id`** — необязательное поле `provider_id`: роль provider_operation_id (0.55) уже у `payment_id` (0.90) в той же схеме; других кандидатов нет, роль не выведена — задайте её фрагментом ниже
- и ещё 10 с тем же кодом

### `undeclared_status_code` — 16

Что сделал инструмент: для кода достроено общее правило ERROR_MAP по HTTP-коду

- **`$.paths['/v1/agreements'].get`** — операция Search agreements не объявляет 400, 402, 409, 412, объявленные у соседних операций (Create an agreement, Authorise a MOTO payment, Cancel a payment, Submit a refund for a payment); для них достроены общие правила
- **`$.paths['/v1/agreements'].post`** — операция Create an agreement не объявляет 402, 404, 409, 412, объявленные у соседних операций (Authorise a MOTO payment, Search agreements, Cancel a payment, Submit a refund for a payment); для них достроены общие правила
- **`$.paths['/v1/agreements/{agreementId}'].get`** — операция Get an agreement не объявляет 400, 402, 409, 412, 422, объявленные у соседних операций (Create an agreement, Authorise a MOTO payment, Cancel a payment, Submit a refund for a payment, Search agreements); для них достроены общие правила
- **`$.paths['/v1/agreements/{agreementId}/cancel'].post`** — операция Cancel an agreement не объявляет 402, 409, 412, 422, объявленные у соседних операций (Authorise a MOTO payment, Cancel a payment, Submit a refund for a payment, Search agreements); для них достроены общие правила
- **`$.paths['/v1/auth'].post`** — операция Authorise a MOTO payment не объявляет 401, 404, 409, 412, 429, объявленные у соседних операций (Search agreements, Cancel a payment, Submit a refund for a payment); для них достроены общие правила
- **`$.paths['/v1/disputes'].get`** — операция Search disputes не объявляет 400, 402, 404, 409, 412, объявленные у соседних операций (Create an agreement, Authorise a MOTO payment, Search agreements, Cancel a payment, Submit a refund for a payment); для них достроены общие правила
- **`$.paths['/v1/payments'].get`** — операция Search payments не объявляет 400, 402, 404, 409, 412, объявленные у соседних операций (Create an agreement, Authorise a MOTO payment, Search agreements, Cancel a payment, Submit a refund for a payment); для них достроены общие правила
- **`$.paths['/v1/payments'].post`** — операция Create a payment не объявляет 402, 404, 409, 412, объявленные у соседних операций (Authorise a MOTO payment, Search agreements, Cancel a payment, Submit a refund for a payment); для них достроены общие правила
- **`$.paths['/v1/payments/{paymentId}'].get`** — операция Get a payment не объявляет 400, 402, 409, 412, 422, объявленные у соседних операций (Create an agreement, Authorise a MOTO payment, Cancel a payment, Submit a refund for a payment, Search agreements); для них достроены общие правила
- **`$.paths['/v1/payments/{paymentId}/cancel'].post`** — операция Cancel a payment не объявляет 402, 412, 422, объявленные у соседних операций (Authorise a MOTO payment, Submit a refund for a payment, Search agreements); для них достроены общие правила
- **`$.paths['/v1/payments/{paymentId}/capture'].post`** — операция Capture a payment не объявляет 402, 412, 422, объявленные у соседних операций (Authorise a MOTO payment, Submit a refund for a payment, Search agreements); для них достроены общие правила
- **`$.paths['/v1/payments/{paymentId}/events'].get`** — операция Get events for a payment не объявляет 400, 402, 409, 412, 422, объявленные у соседних операций (Create an agreement, Authorise a MOTO payment, Cancel a payment, Submit a refund for a payment, Search agreements); для них достроены общие правила
- **`$.paths['/v1/payments/{paymentId}/refunds'].get`** — операция Get all refunds for a payment не объявляет 400, 402, 409, 412, 422, объявленные у соседних операций (Create an agreement, Authorise a MOTO payment, Cancel a payment, Submit a refund for a payment, Search agreements); для них достроены общие правила
- **`$.paths['/v1/payments/{paymentId}/refunds'].post`** — операция Submit a refund for a payment не объявляет 400, 402, 409, 422, объявленные у соседних операций (Create an agreement, Authorise a MOTO payment, Cancel a payment, Search agreements); для них достроены общие правила
- **`$.paths['/v1/payments/{paymentId}/refunds/{refundId}'].get`** — операция Get a payment refund не объявляет 400, 402, 409, 412, 422, объявленные у соседних операций (Create an agreement, Authorise a MOTO payment, Cancel a payment, Submit a refund for a payment, Search agreements); для них достроены общие правила
- **`$.paths['/v1/refunds'].get`** — операция Search refunds не объявляет 400, 402, 404, 409, 412, 429, объявленные у соседних операций (Create an agreement, Authorise a MOTO payment, Search agreements, Cancel a payment, Submit a refund for a payment); для них достроены общие правила

## 6. Справки

Факты, о которых читателю стоит знать; решения за человека инструмент здесь не
принимал. Списки сокращены до первых 5 элементов в группе — полный набор
виден в `./integrate analyze --spec govuk_pay_v1.json`.

**`field_role_unknown`** — 91

- `$.components.schemas.Address.properties.city` — необязательное поле `city` (string, min_length 0, max_length 255): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; в запрос оно не попадёт; если оно нужно, задайте роль фрагментом ниже
- `$.components.schemas.Address.properties.country` — необязательное поле `country` (string): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; в запрос оно не попадёт; если оно нужно, задайте роль фрагментом ниже
- `$.components.schemas.Address.properties.line1` — необязательное поле `line1` (string, min_length 0, max_length 255): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; в запрос оно не попадёт; если оно нужно, задайте роль фрагментом ниже
- `$.components.schemas.Address.properties.line2` — необязательное поле `line2` (string, min_length 0, max_length 255): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; в запрос оно не попадёт; если оно нужно, задайте роль фрагментом ниже
- `$.components.schemas.Address.properties.postcode` — необязательное поле `postcode` (string, min_length 0, max_length 25): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; в запрос оно не попадёт; если оно нужно, задайте роль фрагментом ниже
- и ещё 86 с тем же кодом

**`operation_unmapped`** — 10, подробности в разделе 4

- `$.paths['/v1/agreements'].get` — в спецификации слишком мало признаков того, для чего эта операция, поэтому роль не присвоена (fetch_status 3.0, balance 3.0, cancel 1.0 из 3.0 поданных голосов); задайте роль в overlay
- `$.paths['/v1/disputes'].get` — в спецификации слишком мало признаков того, для чего эта операция, поэтому роль не присвоена (fetch_status 3.0, balance 3.0, cancel 1.0 из 3.0 поданных голосов); задайте роль в overlay
- `$.paths['/v1/agreements'].post` — больше всех голосов набрала роль create_payout, но она отсечена по форме: ни в пути, ни в operationId нет ни одного платёжного существительного (vetoes.domain_nouns в rules/operations.yml); роль не присвоена, операция получает отдельный публичный метод
- `$.paths['/v1/agreements/{agreementId}'].get` — больше всех голосов набрала роль fetch_status, но она отсечена по форме: ни в пути, ни в operationId нет ни одного платёжного существительного (vetoes.domain_nouns в rules/operations.yml); роль не присвоена, операция получает отдельный публичный метод
- `$.paths['/v1/agreements/{agreementId}/cancel'].post` — распознана как cancel, но в Provider::BaseService нет метода для такой роли; она генерируется отдельным публичным методом и остаётся вне контракта
- и ещё 5 с тем же кодом

**`server_environment_unknown`** — 1

- `$.servers[0]` — ни описание, ни хост не говорят, песочница это или продакшен; запросы могут уйти не туда

## 7. Что доделать руками

1. Заполните обязательное поле `description` в build_payload: роль не выведена (ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml) — добавьте синоним в `rules/roles.yml` или задайте `x-specgen-role` в overlay
2. Проверьте поле `reference` в build_payload: роль `provider_operation_id` присвоена с уверенностью ниже порога (эвристика 0.50, композитное сопоставление: name 2.0 (общие токены с синонимом `acquirer_reference`: reference (50%)), structure 4.0 (родитель `CreateCardPaymentRequest` содержит токен `payment` из подсказок роли), type 1.0 (type string допустим для роли) = 7.0 из 14.0; следующая external_id 0.21)
3. Заполните обязательное поле `return_url` в build_payload: роль не выведена (ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml) — добавьте синоним в `rules/roles.yml` или задайте `x-specgen-role` в overlay
4. Допишите тело метода `search_agreements` (операция `Search agreements`): роль не распознана, запрос собирается пустым
5. Допишите тело метода `create_an_agreement` (операция `Create an agreement`): роль не распознана, запрос собирается пустым
6. Допишите тело метода `get_an_agreement` (операция `Get an agreement`): роль не распознана, запрос собирается пустым
7. Допишите тело метода `search_disputes` (операция `Search disputes`): роль не распознана, запрос собирается пустым
8. Допишите тело метода `search_payments` (операция `Search payments`): роль не распознана, запрос собирается пустым
9. Допишите тело метода `search_refunds` (операция `Search refunds`): роль не распознана, запрос собирается пустым
10. Решите судьбу необязательного поля `description`: роли нет, в payload оно не попало
11. Решите судьбу необязательного поля `user_identifier`: роли нет, в payload оно не попало
12. Решите судьбу необязательного поля `agreement_id`: роли нет, в payload оно не попало
13. Решите судьбу необязательного поля `authorisation_mode`: роли нет, в payload оно не попало
14. Решите судьбу необязательного поля `delayed_capture`: роли нет, в payload оно не попало
15. Решите судьбу необязательного поля `email`: роли нет, в payload оно не попало
16. Решите судьбу необязательного поля `language`: роли нет, в payload оно не попало
17. Решите судьбу необязательного поля `metadata.metadata`: роли нет, в payload оно не попало
18. Решите судьбу необязательного поля `moto`: роли нет, в payload оно не попало
19. Решите судьбу необязательного поля `prefilled_cardholder_details.billing_address.city`: роли нет, в payload оно не попало
20. Решите судьбу необязательного поля `prefilled_cardholder_details.billing_address.country`: роли нет, в payload оно не попало
21. Решите судьбу необязательного поля `prefilled_cardholder_details.billing_address.line1`: роли нет, в payload оно не попало
22. Решите судьбу необязательного поля `prefilled_cardholder_details.billing_address.line2`: роли нет, в payload оно не попало
23. Решите судьбу необязательного поля `prefilled_cardholder_details.billing_address.postcode`: роли нет, в payload оно не попало
24. Решите судьбу необязательного поля `prefilled_cardholder_details.cardholder_name`: роли нет, в payload оно не попало
25. Решите судьбу необязательного поля `set_up_agreement`: роли нет, в payload оно не попало
26. Решите судьбу необязательного поля `refund_amount_available`: роли нет, в payload оно не попало
27. Проверьте значения фикстуры `Create an agreement`: тело собрано не из примеров спецификации (`schema_example`)
28. Проверьте значения фикстуры `Authorise a MOTO payment`: тело собрано не из примеров спецификации (`schema_example`)
29. Проверьте значения фикстуры `Create a payment`: тело собрано не из примеров спецификации (`schema_example`)
30. Проверьте значения фикстуры `Submit a refund for a payment`: тело собрано не из примеров спецификации (`schema_example`)
31. Проверьте значения фикстуры `Search agreements 200`: тело собрано не из примеров спецификации (`schema_example`)
32. Проверьте значения фикстуры `Search agreements 401`: тело собрано не из примеров спецификации (`undeclared`)
33. Проверьте значения фикстуры `Search agreements 404`: тело собрано не из примеров спецификации (`schema_example`)
34. Проверьте значения фикстуры `Search agreements 422`: тело собрано не из примеров спецификации (`schema_example`)
35. Проверьте значения фикстуры `Search agreements 429`: тело собрано не из примеров спецификации (`schema_example`)
36. Проверьте значения фикстуры `Search agreements 500`: тело собрано не из примеров спецификации (`schema_example`)
37. Проверьте значения фикстуры `Create an agreement 201`: тело собрано не из примеров спецификации (`schema_example`)
38. Проверьте значения фикстуры `Create an agreement 400`: тело собрано не из примеров спецификации (`schema_example`)
39. Проверьте значения фикстуры `Create an agreement 401`: тело собрано не из примеров спецификации (`undeclared`)
40. Проверьте значения фикстуры `Create an agreement 422`: тело собрано не из примеров спецификации (`schema_example`)
41. Проверьте значения фикстуры `Create an agreement 429`: тело собрано не из примеров спецификации (`schema_example`)
42. Проверьте значения фикстуры `Create an agreement 500`: тело собрано не из примеров спецификации (`schema_example`)
43. Проверьте значения фикстуры `Get an agreement 200`: тело собрано не из примеров спецификации (`schema_example`)
44. Проверьте значения фикстуры `Get an agreement 401`: тело собрано не из примеров спецификации (`undeclared`)
45. Проверьте значения фикстуры `Get an agreement 404`: тело собрано не из примеров спецификации (`schema_example`)
46. Проверьте значения фикстуры `Get an agreement 429`: тело собрано не из примеров спецификации (`schema_example`)
47. И ещё 69 однотипных пунктов — полный список в разделах 3 и 6
48. Подключите вторую операцию создания `Authorise a MOTO payment` вручную: контракт даёт один метод создания

Итого: 48 пунктов.
