# Отчёт о разборе спецификации «Payment Gateway»

| | |
|---|---|
| Провайдер | `broken` |
| Спецификация | `broken.yaml`, версия 0.1, OpenAPI 3.0.3 |
| Класс сервиса | `Provider::BrokenService` |
| Файл сервиса | `broken_service.rb` |

Отчёт сгенерирован инструментом integrate из той же модели провайдера, что и
сервис: всё, о чём здесь сказано, лежит в сгенерированных файлах рядом.
Каждая строка ниже — действие, а не констатация: если элемент спецификации
попал в отчёт, к нему приложено, что сделал инструмент и чем это закрыть.
Генерация не блокируется никогда, поэтому отчёт описывает готовые файлы, а не
причину отказа.

## 1. Сводка

| Показатель | Значение |
|---|---|
| Операции | всего 6: отображено на контракт 3, вне контракта 2, без роли (unmapped) 1 |
| Схемы и поля | схем 7, полей 24: скалярных 22, контейнеров 2 |
| Роли полей | 6 из 22 скалярных: эвристика ниже порога 6 |
| Поля без роли | 16: обязательных 5, необязательных 11 |
| Статусы | 5: сопоставлено 2, не сопоставлено 3 |
| События вебхука | 5: сопоставлено 2, не сопоставлено 3 |
| Коды ошибок | кодов провайдера 5: в enum 4, только в примерах 1; общих правил по HTTP-коду 1 |
| Условия взаимодействия | 0: из структуры 0, из прозы описаний 0 |
| Предупреждения | 64: ошибок 0, предупреждений 31, справок 33 |

Сгенерированные артефакты:

| Файл | Что это | Строк |
|---|---|---|
| `broken_service.rb` | сервис по контракту базового класса | 443 |
| `INTEGRATION.md` | документация интеграции | 253 |
| `fixtures.json` | примеры запросов, ответов и уведомлений | 301 |
| `report.md` | этот отчёт | считается в момент записи |

### Сверка сгенерированного со спецификацией

Тела из `fixtures.json` проверены схемами той же спецификации, из которой они
выведены: запрос — схемой тела своей операции, ответ — схемой своего кода
ответа, уведомление — схемой тела вебхука. Это замыкает круг: спецификация →
разбор → генерация → обратно к спецификации. Тела, которых спецификация не
обещала (операция без `requestBody`, ответ `204`), в счёт не идут — проверять
там нечего.

**Сверено тел: 15; прошли схему: 5; не прошли: 4; синтезированы и схему не проходят: 4; сверить не с чем: 2.**

**Не прошли схему — 4** — тело взято из примеров спецификации дословно и не проходит её же схему: спорят спецификация и её собственная схема, и это надо прочитать глазами

- **запрос post_notify** — поле `st` не проходит `enum`; место: `$.paths['/notify'].post.requestBody.content['application/json'].schema`
- **ответ post_transactions 400** — поле `err` не проходит `enum`; место: `$.paths['/transactions'].post.responses['400'].content['application/json'].schema`
- **уведомление webhook IN_REVIEW** — поле `st` не проходит `enum`; место: `$.paths['/notify'].post.requestBody.content['application/json'].schema`
- **уведомление webhook PART_DONE** — поле `st` не проходит `enum`; место: `$.paths['/notify'].post.requestBody.content['application/json'].schema`

**Синтезированы и схему не проходят — 4** — значение собрал генератор по типу поля либо фикстура негативна намеренно, поэтому расхождение с `pattern` или `enum` законно и ошибкой прогона не считается

- **уведомление webhook DONE** — поле `st` не проходит `enum`; место: `$.paths['/notify'].post.requestBody.content['application/json'].schema`
- **уведомление webhook NOTOK** — поле `st` не проходит `enum`; место: `$.paths['/notify'].post.requestBody.content['application/json'].schema`
- **уведомление webhook WAITING** — поле `st` не проходит `enum`; место: `$.paths['/notify'].post.requestBody.content['application/json'].schema`
- **уведомление webhook unknown_event** — поле `st` не проходит `enum`; место: `$.paths['/notify'].post.requestBody.content['application/json'].schema`

**Сверить не с чем — 2** — схемы в спецификации нет, сверять не с чем — это пробел спецификации, а не итог проверки

- **ответ post_transactions_ref_void 200** — спецификация обещала тело, но не описала его — сверить нечего; место: `$.paths['/transactions/{ref}/void'].post.responses['200']`
- **ответ get_reports_daily 200** — спецификация обещала тело, но не описала его — сверить нечего; место: `$.paths['/reports/daily'].get.responses['200']`

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

**Проверок: 26; прошло: 11; не прошло: 1; не проверено: 14.**

**Не прошло — 1** — класс сделал не то, что обещают фикстуры и таблицы INTEGRATION.md: это расхождение сгенерированного кода с сгенерированной документацией, и его надо прочитать глазами

- **прогон: create_request — тело запроса** — в теле запроса нет ключа `cur`

**Не проверено — 14** — вызывать было нечем или незачем: спецификация не описала операции, фикстура не даёт данных либо инструмент сам оставил в этом месте TODO — пробел уже назван в разделах ниже

- **прогон: check_conditions — сумма ниже минимума (—)** — спецификация не задаёт минимальной суммы — проверять нечего
- **прогон: create_request — идентификатор операции в результате** — в схеме успешного ответа нет поля с ролью provider_operation_id
- **прогон: verify_webhook_signature — подпись уведомления webhook DONE** — профиль подписи не выведен, в коде на этом месте TODO
- **прогон: verify_webhook_signature — подпись уведомления webhook IN_REVIEW** — профиль подписи не выведен, в коде на этом месте TODO
- **прогон: verify_webhook_signature — подпись уведомления webhook NOTOK** — профиль подписи не выведен, в коде на этом месте TODO
- **прогон: verify_webhook_signature — подпись уведомления webhook PART_DONE** — профиль подписи не выведен, в коде на этом месте TODO
- **прогон: verify_webhook_signature — подпись уведомления webhook WAITING** — профиль подписи не выведен, в коде на этом месте TODO
- **прогон: verify_webhook_signature — подпись уведомления webhook unknown_event** — профиль подписи не выведен, в коде на этом месте TODO
- и ещё 6 того же вида

## 2. Покрытие спецификации

**Покрытие: 43 % (20 из 46 элементов). В границах контракта: 65 % (20 из 31).**

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

Знаменатель второй цифры меньше первого на 15 элементов, и вот они все, по
видам:

- **Поля тел запросов** — 2: необязательные поля без роли — в payload они не идут намеренно (docs/PRINCIPLES.md, раздел «Что генерируем при неполной спеке»), а не по недосмотру
- **Поля тел ответов и уведомлений** — 13: роль поля не входит в читаемые сервисом или не выведена вовсе — методам контракта такое поле прочитать некуда

Больше не вычтено ничего: коды ответов, статусы, события вебхука, условия
взаимодействия, обязательные поля тел запросов и поля запросов с выведенной
ролью остаются в знаменателе второй цифры целиком — даже когда не покрыты,
потому что их непокрытие — пробел интеграции, а не свойство контракта.
Вычтенное не спрятано: каждый вычтенный элемент назван ниже, в «Что не покрыто
и почему», со своей причиной и своей корзиной.

| Измерение | Найдено | Покрыто | Покрытие |
|---|---|---|---|
| Операции | 6 | 5 | 83 % |
| Поля тел запросов | 7 | 1 | 14 % |
| Поля тел ответов и уведомлений | 17 | 4 | 24 % |
| Коды ответов | 6 | 6 | 100 % |
| Статусы | 5 | 2 | 40 % |
| События вебхука | 5 | 2 | 40 % |
| Условия взаимодействия | 0 | 0 | нечего покрывать |

### Что не покрыто и почему

Непокрыто 26: вне контракта 4, структурных исключений 12, требует ручной
работы 10. Корзина каждого элемента вычислена из его причины, таблица причин —
Generators::Report::Gap::BUCKETS.

**Требует ручной работы — 10.** Единственная корзина, адресованная человеку:
здесь спецификация описала то, что контракт умеет использовать, а интеграция
этого не взяла. Перечислена целиком, поимённо и первой — это и есть список
того, что стоит доделать руками.

**Поля тел запросов** — не покрыто 4

- `post_transactions: cur` — обязательное поле без роли: в payload попало с TODO и значением по умолчанию, значение подставит человек
- `post_transactions: xref_tag_9` — обязательное поле без роли: в payload попало с TODO и значением по умолчанию, значение подставит человек
- `post_transactions: party.kind` — обязательное поле без роли: в payload попало с TODO и значением по умолчанию, значение подставит человек
- `post_transactions: party.acct` — обязательное поле без роли: в payload попало с TODO и значением по умолчанию, значение подставит человек

**Статусы** — не покрыто 3

- `IN_REVIEW` — нет пары среди внутренних статусов: в STATUS_MAP nil
- `NOTOK` — нет пары среди внутренних статусов: в STATUS_MAP nil
- `PART_DONE` — нет пары среди внутренних статусов: в STATUS_MAP nil

**События вебхука** — не покрыто 3

- `IN_REVIEW` — нет пары среди внутренних статусов: в EVENT_MAP nil
- `NOTOK` — нет пары среди внутренних статусов: в EVENT_MAP nil
- `PART_DONE` — нет пары среди внутренних статусов: в EVENT_MAP nil

**Вне контракта — 4.** Ресурсы спецификации, которых методы контракта не
касаются вовсе: чужие операции и их поля, коды и схемы. Контракт про выплаты;
считать пробелом интеграции отсутствие в ней подписок, споров или хранения
карт — то же самое, что считать пробелом отсутствие метода для чужого API.
Свёрнуто числом с примерами.

- **Операции** — 1: `get_reports_daily`
- **Поля тел ответов и уведомлений** — 3: `Limits.min_amt`, `Limits.max_amt`, `Limits.cur`

**Структурные исключения метрики — 12.** Элементы, которым в методах контракта
нет места по построению: поле входящего тела засчитывается, только когда его
роль читает один из четырёх методов; необязательное поле без роли в payload не
идёт намеренно; код, объявленный диапазоном, ветки не даёт. Это устройство
метрики и контракта, а не пропуск разбора. Свёрнуто числом с примерами.

- **Поля тел запросов** — 2: `post_transactions: aux_flag_b`, `post_transactions: party.nm`
- **Поля тел ответов и уведомлений** — 10, например: `Txn.ref`, `Txn.amt`, `Txn.cur`

## 3. Неоднозначности

Элементы, о которых спецификация говорит недостаточно, чтобы решение было
однозначным. Инструмент решил сам — что именно, сказано под каждым кодом; от
человека нужна проверка, а не заполнение пропуска.

### `currency_unknown` — 1

Что сделал инструмент: валюта не подставлена, множитель суммы по умолчанию

- **`$.components.schemas.TxnCreate.properties.amt`** — валюта суммы не выведена (ни одно поле не совпало с синонимами роли currency в rules/roles.yml); без кода валюты экспоненту ISO 4217 определить нельзя — задайте валюту в overlay

  ```yaml
  - target: "$.components.schemas.TxnCreate.properties.amt"
    update:
      x-specgen-currency: RUB  # код ISO 4217
  ```

### `error_action_unknown` — 5

Что сделал инструмент: взято действие по умолчанию из rules/errors.yml

- **`$.components.schemas.Err.properties.err.enum[0]`** — для кода E100 нет правила в rules/errors.yml; взято действие по умолчанию reject с уверенностью 0.30 — задайте действие в overlay или добавьте шаблон в справочник

  ```yaml
  - target: "$.components.schemas.Err.properties.err"
    update:
      x-specgen-error-actions:
        E100: reject  # reject | retry | retry_backoff | alert | escalate
  ```
- **`$.components.schemas.Err.properties.err.enum[1]`** — для кода E200 нет правила в rules/errors.yml; взято действие по умолчанию reject с уверенностью 0.30 — задайте действие в overlay или добавьте шаблон в справочник

  ```yaml
  - target: "$.components.schemas.Err.properties.err"
    update:
      x-specgen-error-actions:
        E200: reject  # reject | retry | retry_backoff | alert | escalate
  ```
- **`$.components.schemas.Err.properties.err.enum[2]`** — для кода E300 нет правила в rules/errors.yml; взято действие по умолчанию reject с уверенностью 0.30 — задайте действие в overlay или добавьте шаблон в справочник

  ```yaml
  - target: "$.components.schemas.Err.properties.err"
    update:
      x-specgen-error-actions:
        E300: reject  # reject | retry | retry_backoff | alert | escalate
  ```
- **`$.components.schemas.Err.properties.err.enum[3]`** — для кода E999 нет правила в rules/errors.yml; взято действие по умолчанию reject с уверенностью 0.30 — задайте действие в overlay или добавьте шаблон в справочник

  ```yaml
  - target: "$.components.schemas.Err.properties.err"
    update:
      x-specgen-error-actions:
        E999: reject  # reject | retry | retry_backoff | alert | escalate
  ```
- **`$.paths['/transactions'].post.responses['400'].content['application/json'].example.err`** — для кода E777 нет правила в rules/errors.yml; взято действие по умолчанию reject с уверенностью 0.30 — задайте действие в overlay или добавьте шаблон в справочник

  ```yaml
  - target: "$.components.schemas.Err.properties.err"
    update:
      x-specgen-error-actions:
        E777: reject  # reject | retry | retry_backoff | alert | escalate
  ```

### `field_role_low_confidence` — 6

Что сделал инструмент: роль присвоена лучшему кандидату, в коде рядом с полем — комментарий с уверенностью

- **`$.components.schemas.Notice.properties.st`** — обязательное поле `st`: роль status выведена с низкой уверенностью 0.26 (порог 0.60); кандидаты: status 0.26; без него запрос не уйдёт, поэтому в код оно попадёт как status с TODO — проверьте роль и закрепите её фрагментом ниже

  ```yaml
  - target: "$.components.schemas.Notice.properties.st"
    update:
      x-specgen-role: status  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.TxnCreate.properties.amt`** — обязательное поле `amt`: роль amount выведена с низкой уверенностью 0.43 (порог 0.60); кандидаты: amount 0.43; без него запрос не уйдёт, поэтому в код оно попадёт как amount с TODO — проверьте роль и закрепите её фрагментом ниже

  ```yaml
  - target: "$.components.schemas.TxnCreate.properties.amt"
    update:
      x-specgen-role: amount  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.Err.properties.err`** — необязательное поле `err`: роль error_code выведена с низкой уверенностью 0.21 (порог 0.60); кандидаты: error_code 0.21; в коде оно будет помечено TODO — проверьте роль и закрепите её фрагментом ниже

  ```yaml
  - target: "$.components.schemas.Err.properties.err"
    update:
      x-specgen-role: error_code  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.Limits.properties.min_amt`** — необязательное поле `min_amt`: роль amount выведена с низкой уверенностью 0.43 (порог 0.60); кандидаты: amount 0.43; в коде оно будет помечено TODO — проверьте роль и закрепите её фрагментом ниже

  ```yaml
  - target: "$.components.schemas.Limits.properties.min_amt"
    update:
      x-specgen-role: amount  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.Txn.properties.amt`** — необязательное поле `amt`: роль amount выведена с низкой уверенностью 0.43 (порог 0.60); кандидаты: amount 0.43; в коде оно будет помечено TODO — проверьте роль и закрепите её фрагментом ниже

  ```yaml
  - target: "$.components.schemas.Txn.properties.amt"
    update:
      x-specgen-role: amount  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.Txn.properties.st`** — необязательное поле `st`: роль status выведена с низкой уверенностью 0.26 (порог 0.60); кандидаты: status 0.26; в коде оно будет помечено TODO — проверьте роль и закрепите её фрагментом ниже

  ```yaml
  - target: "$.components.schemas.Txn.properties.st"
    update:
      x-specgen-role: status  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```

### `idempotency_header_missing` — 1

Что сделал инструмент: ключ идемпотентности не отправляется

- **`$.paths['/transactions'].post`** — ни одна операция не объявляет заголовок идемпотентности (алиасы rules/idempotency.yml: Idempotence-Key, Idempotency-Key, PayPal-Request-Id, X-Idempotency-Key, X-Request-Id, X-Unique-Transaction-Id); повтор запроса после сетевого сбоя создаст вторую выплату — уточните у провайдера или объявите заголовок в overlay

  ```yaml
  - target: "$.paths['/transactions'].post"
    update:
      parameters:
        - name: Idempotency-Key
          in: header
          required: false
          schema:
            type: string
            format: uuid
  ```

### `operation_id_missing` — 6

Что сделал инструмент: ключом операции стала пара «HTTP-метод и путь»

- **`$.paths['/limits'].get`** — операция не объявляет operationId; в этом отчёте и в сгенерированном коде она названа "get_limits"
  готового overlay-фрагмента нет: исправляется правкой спецификации
- **`$.paths['/notify'].post`** — операция не объявляет operationId; в этом отчёте и в сгенерированном коде она названа "post_notify"
  готового overlay-фрагмента нет: исправляется правкой спецификации
- **`$.paths['/reports/daily'].get`** — операция не объявляет operationId; в этом отчёте и в сгенерированном коде она названа "get_reports_daily"
  готового overlay-фрагмента нет: исправляется правкой спецификации
- **`$.paths['/transactions'].post`** — операция не объявляет operationId; в этом отчёте и в сгенерированном коде она названа "post_transactions"
  готового overlay-фрагмента нет: исправляется правкой спецификации
- **`$.paths['/transactions/{ref}'].get`** — операция не объявляет operationId; в этом отчёте и в сгенерированном коде она названа "get_transactions_ref"
  готового overlay-фрагмента нет: исправляется правкой спецификации
- **`$.paths['/transactions/{ref}/void'].post`** — операция не объявляет operationId; в этом отчёте и в сгенерированном коде она названа "post_transactions_ref_void"
  готового overlay-фрагмента нет: исправляется правкой спецификации

### `required_field_role_unknown` — 7

Что сделал инструмент: в исходящем теле поле включено в payload со значением примера или nil и TODO рядом; во входящем — ищется структурно

- **`$.components.schemas.Notice.properties.ref`** — обязательное поле `ref` (string): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; без него запрос не уйдёт, поэтому в код оно попадёт с TODO — задайте роль фрагментом ниже или добавьте синоним в rules/roles.yml

  ```yaml
  - target: "$.components.schemas.Notice.properties.ref"
    update:
      x-specgen-role: TODO  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.Party.properties.acct`** — обязательное поле `acct` (string, max_length 34): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; без него запрос не уйдёт, поэтому в код оно попадёт с TODO — задайте роль фрагментом ниже или добавьте синоним в rules/roles.yml

  ```yaml
  - target: "$.components.schemas.Party.properties.acct"
    update:
      x-specgen-role: TODO  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.Party.properties.kind`** — обязательное поле `kind` (string, enum ["P2P", "CARD", "ACC"]): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; без него запрос не уйдёт, поэтому в код оно попадёт с TODO — задайте роль фрагментом ниже или добавьте синоним в rules/roles.yml

  ```yaml
  - target: "$.components.schemas.Party.properties.kind"
    update:
      x-specgen-role: TODO  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.TxnCreate.properties.cur`** — обязательное поле `cur` (string): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; без него запрос не уйдёт, поэтому в код оно попадёт с TODO — задайте роль фрагментом ниже или добавьте синоним в rules/roles.yml

  ```yaml
  - target: "$.components.schemas.TxnCreate.properties.cur"
    update:
      x-specgen-role: TODO  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.TxnCreate.properties.xref_tag_9`** — обязательное поле `xref_tag_9` (string, max_length 32): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; без него запрос не уйдёт, поэтому в код оно попадёт с TODO — задайте роль фрагментом ниже или добавьте синоним в rules/roles.yml

  ```yaml
  - target: "$.components.schemas.TxnCreate.properties.xref_tag_9"
    update:
      x-specgen-role: TODO  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.paths['/transactions/{ref}'].get.parameters[0]`** — обязательный параметр `ref` (путь) (string): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; без него запрос не уйдёт, поэтому в код оно попадёт с TODO — задайте роль фрагментом ниже или добавьте синоним в rules/roles.yml

  ```yaml
  - target: "$.paths['/transactions/{ref}'].get.parameters[0]"
    update:
      x-specgen-role: TODO  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.paths['/transactions/{ref}/void'].post.parameters[0]`** — обязательный параметр `ref` (путь) (string): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; без него запрос не уйдёт, поэтому в код оно попадёт с TODO — задайте роль фрагментом ниже или добавьте синоним в rules/roles.yml

  ```yaml
  - target: "$.paths['/transactions/{ref}/void'].post.parameters[0]"
    update:
      x-specgen-role: TODO  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```

### `schema_unresolved` — 2

Что сделал инструмент: схема не разобрана: её поля в код не попали

- **`$.paths['/reports/daily'].get.responses['200'].content['application/json'].schema`** — у тела get_reports_daily не объявлено читаемой схемы, поэтому ничто не описывает, что оно переносит
  готового overlay-фрагмента нет: исправляется правкой спецификации
- **`$.paths['/transactions/{ref}/void'].post.responses['200']`** — ответ 200 операции post_transactions_ref_void объявлен одним описанием: `content` нет, поэтому нечему описывать тело — либо опишите схему, либо объявите ответ без тела кодом 204
  готового overlay-фрагмента нет: исправляется правкой спецификации

### `signature_profile_incomplete` — 1

Что сделал инструмент: недостающие параметры подписи взяты по умолчанию из rules/signatures.yml

- **`$.paths['/notify'].post`** — вебхук post_notify не объявляет заголовок подписи (header_names rules/signatures.yml); подлинность уведомлений проверить нечем — задайте профиль подписи в overlay

  ```yaml
  - target: "$.paths['/notify'].post"
    update:
      x-specgen-signature:
        profile: custom
        header: X-Signature
        algorithm: hmac_sha256  # hmac_sha256 | hmac_sha512 | hmac_sha1
        encoding: hex  # hex | base64
        payload: raw_body  # raw_body | id_timestamp_body
        secret_key: webhook_secret
  ```

### `status_unmapped` — 3

Что сделал инструмент: в STATUS_MAP значение nil и TODO: сервис вернёт отказ status_unknown

- **`$.components.schemas.Txn.properties.st.enum[2]`** — статус NOTOK не найден ни в каноне, ни среди синонимов rules/statuses.yml; выберите внутренний статус в overlay или добавьте синоним в справочник

  ```yaml
  - target: "$.components.schemas.Txn.properties.st"
    update:
      x-specgen-status-map:
        NOTOK: in_progress  # in_progress | approved | rejected
  ```
- **`$.paths['/notify'].post.requestBody.content['application/json'].examples.first.value.st`** — статус IN_REVIEW не найден ни в каноне, ни среди синонимов rules/statuses.yml; выберите внутренний статус в overlay или добавьте синоним в справочник

  ```yaml
  - target: "$.components.schemas.Txn.properties.st"
    update:
      x-specgen-status-map:
        IN_REVIEW: in_progress  # in_progress | approved | rejected
  ```
- **`$.paths['/notify'].post.requestBody.content['application/json'].examples.second.value.st`** — статус PART_DONE целиком не найден ни в каноне, ни среди синонимов rules/statuses.yml; как статус читается только хвост done (approved), но ведущее слово `part` меняет смысл (modifiers rules/statuses.yml) — снимать его нельзя; выберите внутренний статус в overlay — молча приравнять его к хвосту нельзя: частично проведённый платёж ушёл бы в платформу как выплаченный

  ```yaml
  - target: "$.components.schemas.Txn.properties.st"
    update:
      x-specgen-status-map:
        PART_DONE: in_progress  # in_progress | approved | rejected
  ```

### `webhook_event_unmapped` — 3

Что сделал инструмент: в EVENT_MAP значение nil и TODO

- **`$.components.schemas.Notice.properties.st.enum[2]`** — событие NOTOK не переведено во внутренний статус: поле события не найдено, событие читается по значению поля статуса `st`; статус NOTOK не найден ни в каноне, ни среди синонимов rules/statuses.yml; задайте статус в overlay

  ```yaml
  - target: "$.components.schemas.Notice.properties.st"
    update:
      x-specgen-status-map:
        NOTOK: in_progress  # in_progress | approved | rejected
  ```
- **`$.paths['/notify'].post.requestBody.content['application/json'].examples.first.value.st`** — событие IN_REVIEW не переведено во внутренний статус: поле события не найдено, событие читается по значению поля статуса `st`; статус IN_REVIEW не найден ни в каноне, ни среди синонимов rules/statuses.yml; задайте статус в overlay

  ```yaml
  - target: "$.components.schemas.Notice.properties.st"
    update:
      x-specgen-status-map:
        IN_REVIEW: in_progress  # in_progress | approved | rejected
  ```
- **`$.paths['/notify'].post.requestBody.content['application/json'].examples.second.value.st`** — событие PART_DONE не переведено во внутренний статус: поле события не найдено, событие читается по значению поля статуса `st`; статус PART_DONE целиком не найден ни в каноне, ни среди синонимов rules/statuses.yml; как статус читается только хвост done (approved), но ведущее слово `part` меняет смысл (modifiers rules/statuses.yml) — снимать его нельзя; задайте статус в overlay

  ```yaml
  - target: "$.components.schemas.Notice.properties.st"
    update:
      x-specgen-status-map:
        PART_DONE: in_progress  # in_progress | approved | rejected
  ```

### Как собрать overlay

Фрагменты выше — действия одного документа OpenAPI Overlay 1.0.0
(<https://spec.openapis.org/overlay/v1.0.0.html>). Соберите файл
`broken.overlay.yaml`, вставив их подряд под ключ `actions`,
замените значения `TODO` и перегенерируйте:

```yaml
overlay: 1.0.0
info:
  title: broken disambiguation
  version: 1.0.0
actions:
- target: "$..."
  update:
    x-specgen-role: ...
```

```sh
./integrate --spec broken.yaml --provider broken --overlay broken.overlay.yaml
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
| `post_transactions_ref_void` | `POST /transactions/{ref}/void` | `cancel` (эвристика 0.95) | `cancel(operation)` | ничего: в `Provider::BaseService` нет метода для такой роли, платформа зовёт этот метод напрямую |
| `get_reports_daily` | `GET /reports/daily` | не распознана (unmapped) | `reports_daily()` | добавьте синоним пути или operationId в `rules/operations.yml` и перегенерируйте; расширения `x-specgen-role` для операции в модели нет (docs/IR.md, таблица расширений) |
| `get_limits` | `GET /limits` | `balance` (эвристика 0.95) | `balance()` | ничего: в `Provider::BaseService` нет метода для такой роли, платформа зовёт этот метод напрямую |

## 5. Противоречия в самой спецификации

Спецификация расходится сама с собой или со своими соседями: enum против
примеров, коды ответов одной операции против другой, проза против структуры.
Инструмент выбрал, чему верить, и продолжил; правится это правкой
спецификации, а не настройкой инструмента.

### `error_code_undeclared` — 1

Что сделал инструмент: код добавлен в ERROR_MAP: карта строится как объединение enum и примеров

- **`$.paths['/transactions'].post.responses['400'].content['application/json'].example.err`** — код E777 встречается в примере, но не объявлен в enum поля кода ошибки ($.components.schemas.Err.properties.err); карта ошибок строится как объединение enum и примеров, спецификацию стоит поправить

### `error_code_unused` — 4

Что сделал инструмент: правило для кода построено по rules/errors.yml, в примерах его проверить нечем

- **`$.components.schemas.Err.properties.err.enum[0]`** — код E100 объявлен в enum, но не встречается ни в одном примере; правило обработки построено по справочнику
- **`$.components.schemas.Err.properties.err.enum[1]`** — код E200 объявлен в enum, но не встречается ни в одном примере; правило обработки построено по справочнику
- **`$.components.schemas.Err.properties.err.enum[2]`** — код E300 объявлен в enum, но не встречается ни в одном примере; правило обработки построено по справочнику
- **`$.components.schemas.Err.properties.err.enum[3]`** — код E999 объявлен в enum, но не встречается ни в одном примере; правило обработки построено по справочнику

### `field_role_conflict` — 2

Что сделал инструмент: роль оставлена полю с большей уверенностью, второе получило следующего кандидата

- **`$.components.schemas.Limits.properties.max_amt`** — необязательное поле `max_amt`: роль amount (0.43) уже у `min_amt` (0.43) в той же схеме; других кандидатов нет, роль не выведена — задайте её фрагментом ниже
- **`$.components.schemas.Txn.properties.ttl_amt`** — необязательное поле `ttl_amt`: роль amount (0.43) уже у `amt` (0.43) в той же схеме; других кандидатов нет, роль не выведена — задайте её фрагментом ниже

### `status_missing_from_enum` — 2

Что сделал инструмент: статус добавлен в STATUS_MAP: карта строится как объединение enum и примеров

- **`$.paths['/notify'].post.requestBody.content['application/json'].examples.first.value.st`** — статус IN_REVIEW встречается в примере, но его нет ни в одном enum поля статуса; карта статусов дополнена им, спецификацию стоит поправить
- **`$.paths['/notify'].post.requestBody.content['application/json'].examples.second.value.st`** — статус PART_DONE встречается в примере, но его нет ни в одном enum поля статуса; карта статусов дополнена им, спецификацию стоит поправить

### `undeclared_status_code` — 4

Что сделал инструмент: для кода достроено общее правило ERROR_MAP по HTTP-коду

- **`$.paths['/limits'].get`** — операция get_limits не объявляет 400, объявленные у соседних операций (post_transactions); для них достроены общие правила
- **`$.paths['/reports/daily'].get`** — операция get_reports_daily не объявляет 400, объявленные у соседних операций (post_transactions); для них достроены общие правила
- **`$.paths['/transactions/{ref}'].get`** — операция get_transactions_ref не объявляет 400, объявленные у соседних операций (post_transactions); для них достроены общие правила
- **`$.paths['/transactions/{ref}/void'].post`** — операция post_transactions_ref_void не объявляет 400, объявленные у соседних операций (post_transactions); для них достроены общие правила

### `webhook_event_undeclared` — 2

Что сделал инструмент: событие добавлено в EVENT_MAP из примера

- **`$.paths['/notify'].post.requestBody.content['application/json'].examples.first.value`** — событие IN_REVIEW встречается в примере first, но его нет в enum поля `st`; список событий дополнен им, спецификацию стоит поправить
- **`$.paths['/notify'].post.requestBody.content['application/json'].examples.second.value`** — событие PART_DONE встречается в примере second, но его нет в enum поля `st`; список событий дополнен им, спецификацию стоит поправить

## 6. Справки

Факты, о которых читателю стоит знать; решения за человека инструмент здесь не
принимал. Списки сокращены до первых 5 элементов в группе — полный набор
виден в `./integrate analyze --spec broken.yaml`.

**`field_role_unknown`** — 10

- `$.components.schemas.Err.properties.txt` — необязательное поле `txt` (string): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; в запрос оно не попадёт; если оно нужно, задайте роль фрагментом ниже
- `$.components.schemas.Limits.properties.cur` — необязательное поле `cur` (string): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; в запрос оно не попадёт; если оно нужно, задайте роль фрагментом ниже
- `$.components.schemas.Notice.properties.ts` — необязательное поле `ts` (integer): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; в запрос оно не попадёт; если оно нужно, задайте роль фрагментом ниже
- `$.components.schemas.Party.properties.nm` — необязательное поле `nm` (string): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; в запрос оно не попадёт; если оно нужно, задайте роль фрагментом ниже
- `$.components.schemas.Txn.properties.cur` — необязательное поле `cur` (string): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; в запрос оно не попадёт; если оно нужно, задайте роль фрагментом ниже
- и ещё 5 с тем же кодом

**`operation_unmapped`** — 3, подробности в разделе 4

- `$.paths['/reports/daily'].get` — в спецификации слишком мало признаков того, для чего эта операция, поэтому роль не присвоена (fetch_status 3.0, balance 3.0, cancel 1.0 из 3.0 поданных голосов); задайте роль в overlay
- `$.paths['/limits'].get` — распознана как balance, но в Provider::BaseService нет метода для такой роли; она генерируется отдельным публичным методом и остаётся вне контракта
- `$.paths['/transactions/{ref}/void'].post` — распознана как cancel, но в Provider::BaseService нет метода для такой роли; она генерируется отдельным публичным методом и остаётся вне контракта

**`server_environment_unknown`** — 1

- `$.servers[0]` — ни описание, ни хост не говорят, песочница это или продакшен; запросы могут уйти не туда

## 7. Что доделать руками

1. Проверьте поле `amt` в build_payload: роль `amount` присвоена с уверенностью ниже порога (эвристика 0.43, композитное сопоставление: name 5.0 (токен `amt` из подсказок роли amount (rules/roles.yml)), type 1.0 (type integer допустим для роли) = 6.0 из 14.0; других кандидатов нет)
2. Заполните обязательное поле `cur` в build_payload: роль не выведена (ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml) — добавьте синоним в `rules/roles.yml` или задайте `x-specgen-role` в overlay
3. Заполните обязательное поле `xref_tag_9` в build_payload: роль не выведена (ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml) — добавьте синоним в `rules/roles.yml` или задайте `x-specgen-role` в overlay
4. Заполните обязательное поле `party.kind` в build_payload: роль не выведена (ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml) — добавьте синоним в `rules/roles.yml` или задайте `x-specgen-role` в overlay
5. Заполните обязательное поле `party.acct` в build_payload: роль не выведена (ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml) — добавьте синоним в `rules/roles.yml` или задайте `x-specgen-role` в overlay
6. Допишите тело метода `reports_daily` (операция `get_reports_daily`): роль не распознана, запрос собирается пустым
7. Вызовите `verify_webhook_signature(raw_body, headers)` на маршруте вебхука до разбора JSON: `process_callback` получает уже разобранное тело, а HMAC считается по сырым байтам — либо кладите байты и заголовки в аргумент по выражениям rules/contract.yml
8. Решите судьбу необязательного поля `aux_flag_b`: роли нет, в payload оно не попало
9. Решите судьбу необязательного поля `party.nm`: роли нет, в payload оно не попало
10. Проверьте значения фикстуры `post_transactions`: тело собрано не из примеров спецификации (`synthesized`)
11. Проверьте значения фикстуры `post_transactions 200`: тело собрано не из примеров спецификации (`schema_example`)
12. Проверьте значения фикстуры `get_transactions_ref 200`: тело собрано не из примеров спецификации (`schema_example`)
13. Проверьте значения фикстуры `post_transactions_ref_void 200`: тело собрано не из примеров спецификации (`undeclared`)
14. Проверьте значения фикстуры `get_reports_daily 200`: тело собрано не из примеров спецификации (`undeclared`)
15. Проверьте значения фикстуры `post_notify 200`: тело собрано не из примеров спецификации (`synthesized`)
16. Проверьте значения фикстуры `get_limits 200`: тело собрано не из примеров спецификации (`synthesized`)
17. Проверьте значения фикстуры `webhook DONE`: тело собрано не из примеров спецификации (`schema_example`)
18. Проверьте значения фикстуры `webhook NOTOK`: тело собрано не из примеров спецификации (`schema_example`)
19. Проверьте значения фикстуры `webhook WAITING`: тело собрано не из примеров спецификации (`schema_example`)
20. Проверьте значения фикстуры `webhook unknown_event`: тело собрано не из примеров спецификации (`synthesized`)

Итого: 20 пунктов.
