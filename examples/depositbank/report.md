# Отчёт о разборе спецификации «DepositBank Collection API»

| | |
|---|---|
| Провайдер | `depositbank` |
| Спецификация | `depositbank.yaml`, версия 1.2.0, OpenAPI 3.1.0 |
| Класс сервиса | `Provider::DepositbankService` |
| Файл сервиса | `depositbank_service.rb` |

Отчёт сгенерирован инструментом integrate из той же модели провайдера, что и
сервис: всё, о чём здесь сказано, лежит в сгенерированных файлах рядом.
Каждая строка ниже — действие, а не констатация: если элемент спецификации
попал в отчёт, к нему приложено, что сделал инструмент и чем это закрыть.
Генерация не блокируется никогда, поэтому отчёт описывает готовые файлы, а не
причину отказа.

## 1. Сводка

| Показатель | Значение |
|---|---|
| Операции | всего 6: отображено на контракт 2, вне контракта 2, без роли (unmapped) 2 |
| Схемы и поля | схем 10, полей 42: скалярных 37, контейнеров 5 |
| Роли полей | 20 из 37 скалярных: по справочнику 19, эвристика ниже порога 1 |
| Поля без роли | 17: обязательных 8, необязательных 9 |
| Статусы | 5: сопоставлено 5, не сопоставлено 0 |
| События вебхука | 0: сопоставлено 0, не сопоставлено 0 |
| Коды ошибок | кодов провайдера 13: в enum 12, только в примерах 1; общих правил по HTTP-коду 8 |
| Условия взаимодействия | 10: из структуры 10, из прозы описаний 0 |
| Предупреждения | 43: ошибок 0, предупреждений 10, справок 33 |

Сгенерированные артефакты:

| Файл | Что это | Строк |
|---|---|---|
| `depositbank_service.rb` | сервис по контракту базового класса | 460 |
| `INTEGRATION.md` | документация интеграции | 231 |
| `fixtures.json` | примеры запросов, ответов и уведомлений | 587 |
| `report.md` | этот отчёт | считается в момент записи |

### Сверка сгенерированного со спецификацией

Тела из `fixtures.json` проверены схемами той же спецификации, из которой они
выведены: запрос — схемой тела своей операции, ответ — схемой своего кода
ответа, уведомление — схемой тела вебхука. Это замыкает круг: спецификация →
разбор → генерация → обратно к спецификации. Тела, которых спецификация не
обещала (операция без `requestBody`, ответ `204`), в счёт не идут — проверять
там нечего.

**Сверено тел: 28; прошли схему: 27; не прошли: 1; синтезированы и схему не проходят: 0; сверить не с чем: 0.**

**Не прошли схему — 1** — тело взято из примеров спецификации дословно и не проходит её же схему: спорят спецификация и её собственная схема, и это надо прочитать глазами

- **ответ createDeposit 422** — поле `error_code` не проходит `enum`; место: `$.paths['/deposits'].post.responses['422'].content['application/json'].schema`

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

**Проверок: 25; прошло: 23; не прошло: 0; не проверено: 2.**

**Не проверено — 2** — вызывать было нечем или незачем: спецификация не описала операции, фикстура не даёт данных либо инструмент сам оставил в этом месте TODO — пробел уже назван в разделах ниже

- **прогон: create_request — заголовок авторизации Authorization** — значение заголовка вычисляет сам класс (access_token), и этот метод генератор оставил человеку: в прогоне он отвечает заглушкой, а в фикстуре стоит раскрытая часть выражения
- **прогон: process_callback — уведомление —** — спецификация не описывает вебхуков — уведомление проверить нечем

## 2. Покрытие спецификации

**Покрытие: 60 % (52 из 87 элементов). В границах контракта: 87 % (52 из 60).**

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

Знаменатель второй цифры меньше первого на 27 элементов, и вот они все, по
видам:

- **Поля тел запросов** — 3: необязательные поля без роли — в payload они не идут намеренно (docs/PRINCIPLES.md, раздел «Что генерируем при неполной спеке»), а не по недосмотру
- **Поля тел ответов и уведомлений** — 24: роль поля не входит в читаемые сервисом или не выведена вовсе — методам контракта такое поле прочитать некуда

Больше не вычтено ничего: коды ответов, статусы, события вебхука, условия
взаимодействия, обязательные поля тел запросов и поля запросов с выведенной
ролью остаются в знаменателе второй цифры целиком — даже когда не покрыты,
потому что их непокрытие — пробел интеграции, а не свойство контракта.
Вычтенное не спрятано: каждый вычтенный элемент назван ниже, в «Что не покрыто
и почему», со своей причиной и своей корзиной.

| Измерение | Найдено | Покрыто | Покрытие |
|---|---|---|---|
| Операции | 6 | 4 | 67 % |
| Поля тел запросов | 12 | 4 | 33 % |
| Поля тел ответов и уведомлений | 29 | 5 | 17 % |
| Коды ответов | 25 | 25 | 100 % |
| Статусы | 5 | 5 | 100 % |
| События вебхука | 0 | 0 | нечего покрывать |
| Условия взаимодействия | 10 | 9 | 90 % |

### Что не покрыто и почему

Непокрыто 35: вне контракта 9, структурных исключений 20, требует ручной
работы 6. Корзина каждого элемента вычислена из его причины, таблица причин —
Generators::Report::Gap::BUCKETS.

**Требует ручной работы — 6.** Единственная корзина, адресованная человеку:
здесь спецификация описала то, что контракт умеет использовать, а интеграция
этого не взяла. Перечислена целиком, поимённо и первой — это и есть список
того, что стоит доделать руками.

**Поля тел запросов** — не покрыто 5

- `createDeposit: remitter.zengin_bank_code` — обязательное поле без роли: в payload попало с TODO и значением по умолчанию, значение подставит человек
- `createDeposit: remitter.branch_code` — обязательное поле без роли: в payload попало с TODO и значением по умолчанию, значение подставит человек
- `createDeposit: remitter.account_number` — обязательное поле без роли: в payload попало с TODO и значением по умолчанию, значение подставит человек
- `createDeposit: remitter.account_holder_kana` — обязательное поле без роли: в payload попало с TODO и значением по умолчанию, значение подставит человек
- `createDeposit: remitter.swift_bic` — роль bank_code выведена, но выражения платформы для неё нет ни в accessors, ни в requisites (rules/contract.yml, раздел platform) — добавьте его туда или заполните поле вручную

**Условия взаимодействия** — не покрыто 1

- `field_pattern swift_bic` — проверка не сгенерирована: значение поля swift_bic зависит от способа выплаты и собирается в remitter_requisites

**Вне контракта — 9.** Ресурсы спецификации, которых методы контракта не
касаются вовсе: чужие операции и их поля, коды и схемы. Контракт про выплаты;
считать пробелом интеграции отсутствие в ней подписок, споров или хранения
карт — то же самое, что считать пробелом отсутствие метода для чужого API.
Свёрнуто числом с примерами.

- **Операции** — 2: `listDeposits`, `listBankCodes`
- **Поля тел ответов и уведомлений** — 7, например: `DepositPage.items`, `DepositPage.next_cursor`, `AccountBalance.account_id`

**Структурные исключения метрики — 20.** Элементы, которым в методах контракта
нет места по построению: поле входящего тела засчитывается, только когда его
роль читает один из четырёх методов; необязательное поле без роли в payload не
идёт намеренно; код, объявленный диапазоном, ветки не даёт. Это устройство
метрики и контракта, а не пропуск разбора. Свёрнуто числом с примерами.

- **Поля тел запросов** — 3: `createDeposit: remitter.intermediary_swift`, `createDeposit: purpose_code`, `createDeposit: value_date`
- **Поля тел ответов и уведомлений** — 17, например: `DepositResource.deposit_amount`, `DepositResource.currency_code`, `DepositResource.remitter.settlement_type`

## 3. Неоднозначности

Элементы, о которых спецификация говорит недостаточно, чтобы решение было
однозначным. Инструмент решил сам — что именно, сказано под каждым кодом; от
человека нужна проверка, а не заполнение пропуска.

### `error_action_unknown` — 1

Что сделал инструмент: взято действие по умолчанию из rules/errors.yml

- **`$.components.schemas.ErrorBody.properties.error_code.enum[4]`** — для кода deposit_not_confirmable нет правила в rules/errors.yml; взято действие по умолчанию reject с уверенностью 0.30 — задайте действие в overlay или добавьте шаблон в справочник

  ```yaml
  - target: "$.components.schemas.DepositRejection.properties.rejection_code"
    update:
      x-specgen-error-actions:
        deposit_not_confirmable: reject  # reject | retry | retry_backoff | alert | escalate
  ```

### `field_role_low_confidence` — 2

Что сделал инструмент: роль присвоена лучшему кандидату, в коде рядом с полем — комментарий с уверенностью

- **`$.components.schemas.DepositResource.properties.bank_reference`** — необязательное поле `bank_reference`: роль bank_name выведена с низкой уверенностью 0.21 (порог 0.60); кандидаты: bank_name 0.21; в коде оно будет помечено TODO — проверьте роль и закрепите её фрагментом ниже

  ```yaml
  - target: "$.components.schemas.DepositResource.properties.bank_reference"
    update:
      x-specgen-role: bank_name  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.paths['/deposits'].get.parameters[1]`** — необязательный параметр `created_to` (query): роль created_at выведена с низкой уверенностью 0.21 (порог 0.60); кандидаты: created_at 0.21; в коде оно будет помечено TODO — проверьте роль и закрепите её фрагментом ниже

  ```yaml
  - target: "$.paths['/deposits'].get.parameters[1]"
    update:
      x-specgen-role: created_at  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```

### `idempotency_dedup_unclear` — 1

Что сделал инструмент: ветка дедупликации не сгенерирована: ответ с кодом конфликта пойдёт как ошибка

- **`$.paths['/deposits'].post`** — заголовок Idempotence-Key объявлен, но ни одна операция не описывает ответ 409 со схемой успешного ответа; при повторе сервис не отличит дубль от ошибки — уточните у провайдера или опишите ответ в overlay

  ```yaml
  - target: "$.paths['/deposits'].post.responses"
    update:
      '409':
        description: Duplicate idempotency key, previous result returned
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/DepositResource'
  ```

### `required_field_role_unknown` — 6

Что сделал инструмент: в исходящем теле поле включено в payload со значением примера или nil и TODO рядом; во входящем — ищется структурно

- **`$.components.schemas.AccountBalance.properties.account_id`** — обязательное поле `account_id` (string): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; без него запрос не уйдёт, поэтому в код оно попадёт с TODO — задайте роль фрагментом ниже или добавьте синоним в rules/roles.yml

  ```yaml
  - target: "$.components.schemas.AccountBalance.properties.account_id"
    update:
      x-specgen-role: TODO  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.AccountBalance.properties.as_of`** — обязательное поле `as_of` (string, format date-time): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; без него запрос не уйдёт, поэтому в код оно попадёт с TODO — задайте роль фрагментом ниже или добавьте синоним в rules/roles.yml

  ```yaml
  - target: "$.components.schemas.AccountBalance.properties.as_of"
    update:
      x-specgen-role: TODO  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.AccountBalance.properties.available_balance`** — обязательное поле `available_balance` (number, format double): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; без него запрос не уйдёт, поэтому в код оно попадёт с TODO — задайте роль фрагментом ниже или добавьте синоним в rules/roles.yml

  ```yaml
  - target: "$.components.schemas.AccountBalance.properties.available_balance"
    update:
      x-specgen-role: TODO  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.AccountBalance.properties.reserved_balance`** — обязательное поле `reserved_balance` (number, format double): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; без него запрос не уйдёт, поэтому в код оно попадёт с TODO — задайте роль фрагментом ниже или добавьте синоним в rules/roles.yml

  ```yaml
  - target: "$.components.schemas.AccountBalance.properties.reserved_balance"
    update:
      x-specgen-role: TODO  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.Remitter.properties.account_holder_kana`** — обязательное поле `account_holder_kana` (string, max_length 48): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; без него запрос не уйдёт, поэтому в код оно попадёт с TODO — задайте роль фрагментом ниже или добавьте синоним в rules/roles.yml

  ```yaml
  - target: "$.components.schemas.Remitter.properties.account_holder_kana"
    update:
      x-specgen-role: TODO  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.paths['/accounts/{account_id}/balance'].get.parameters[0]`** — обязательный параметр `account_id` (путь) (string): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; без него запрос не уйдёт, поэтому в код оно попадёт с TODO — задайте роль фрагментом ниже или добавьте синоним в rules/roles.yml

  ```yaml
  - target: "$.paths['/accounts/{account_id}/balance'].get.parameters[0]"
    update:
      x-specgen-role: TODO  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```

### `webhook_missing` — 1

Что сделал инструмент: process_callback отказывает webhooks_not_supported: статус только опросом

- **`$.paths`** — спецификация не описывает входящих уведомлений (нет операции с security: [] и нет секции webhooks); статус операции сервис узнает только опросом через fetch_status
  готового overlay-фрагмента нет: исправляется правкой спецификации

### Как собрать overlay

Фрагменты выше — действия одного документа OpenAPI Overlay 1.0.0
(<https://spec.openapis.org/overlay/v1.0.0.html>). Соберите файл
`depositbank.overlay.yaml`, вставив их подряд под ключ `actions`,
замените значения `TODO` и перегенерируйте:

```yaml
overlay: 1.0.0
info:
  title: depositbank disambiguation
  version: 1.0.0
actions:
- target: "$..."
  update:
    x-specgen-role: ...
```

```sh
./integrate --spec depositbank.yaml --provider depositbank --overlay depositbank.overlay.yaml
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
| `listDeposits` | `GET /deposits` | не распознана (unmapped) | `list_deposits()` | добавьте синоним пути или operationId в `rules/operations.yml` и перегенерируйте; расширения `x-specgen-role` для операции в модели нет (docs/IR.md, таблица расширений) |
| `confirmDeposit` | `POST /deposits/{deposit_id}/confirm` | `confirm` (эвристика 0.86) | `confirm(operation)` | ничего: в `Provider::BaseService` нет метода для такой роли, платформа зовёт этот метод напрямую |
| `getAccountBalance` | `GET /accounts/{account_id}/balance` | `balance` (эвристика 0.95) | `balance(operation)` | ничего: в `Provider::BaseService` нет метода для такой роли, платформа зовёт этот метод напрямую |
| `listBankCodes` | `GET /reference/banks` | не распознана (unmapped) | `list_bank_codes()` | добавьте синоним пути или operationId в `rules/operations.yml` и перегенерируйте; расширения `x-specgen-role` для операции в модели нет (docs/IR.md, таблица расширений) |

## 5. Противоречия в самой спецификации

Спецификация расходится сама с собой или со своими соседями: enum против
примеров, коды ответов одной операции против другой, проза против структуры.
Инструмент выбрал, чему верить, и продолжил; правится это правкой
спецификации, а не настройкой инструмента.

### `error_code_undeclared` — 1

Что сделал инструмент: код добавлен в ERROR_MAP: карта строится как объединение enum и примеров

- **`$.paths['/deposits'].post.responses['422'].content['application/json'].example.error_code`** — код value_date_invalid встречается в примере, но не объявлен в enum поля кода ошибки ($.components.schemas.DepositRejection.properties.rejection_code); карта ошибок строится как объединение enum и примеров, спецификацию стоит поправить

### `error_code_unused` — 5

Что сделал инструмент: правило для кода построено по rules/errors.yml, в примерах его проверить нечем

- **`$.components.schemas.DepositRejection.properties.rejection_code.enum[2]`** — код amount_limit_exceeded объявлен в enum, но не встречается ни в одном примере; правило обработки построено по справочнику
- **`$.components.schemas.DepositRejection.properties.rejection_code.enum[3]`** — код compliance_hold объявлен в enum, но не встречается ни в одном примере; правило обработки построено по справочнику
- **`$.components.schemas.DepositRejection.properties.rejection_code.enum[4]`** — код duplicate_reference объявлен в enum, но не встречается ни в одном примере; правило обработки построено по справочнику
- **`$.components.schemas.DepositRejection.properties.rejection_code.enum[5]`** — код bank_unavailable объявлен в enum, но не встречается ни в одном примере; правило обработки построено по справочнику
- **`$.components.schemas.ErrorBody.properties.error_code.enum[3]`** — код validation_failed объявлен в enum, но не встречается ни в одном примере; правило обработки построено по справочнику

### `field_role_conflict` — 4

Что сделал инструмент: роль оставлена полю с большей уверенностью, второе получило следующего кандидата

- **`$.components.schemas.BankDirectoryEntry.properties.bank_name_kana`** — необязательное поле `bank_name_kana`: роль bank_name (0.55) уже у `bank_name` (0.90) в той же схеме; других кандидатов нет, роль не выведена — задайте её фрагментом ниже
- **`$.components.schemas.Remitter.properties.intermediary_swift`** — необязательное поле `intermediary_swift`: роль bank_code (0.50) уже у `swift_bic` (0.90) в той же схеме; других кандидатов нет, роль не выведена — задайте её фрагментом ниже
- **`$.components.schemas.Remitter.properties.zengin_bank_code`** — необязательное поле `zengin_bank_code`: роль bank_code (0.26) уже у `swift_bic` (0.90) в той же схеме; других кандидатов нет, роль не выведена — задайте её фрагментом ниже
- **`$.paths['/deposits'].get.parameters[0]`** — необязательный параметр `created_from` (query): роль created_at (0.21) уже у `created_to` (0.21) в той же схеме; других кандидатов нет, роль не выведена — задайте её фрагментом ниже

### `undeclared_status_code` — 6

Что сделал инструмент: для кода достроено общее правило ERROR_MAP по HTTP-коду

- **`$.paths['/accounts/{account_id}/balance'].get`** — операция getAccountBalance не объявляет 400, 409, 422, 503, объявленные у соседних операций (createDeposit, confirmDeposit); для них достроены общие правила
- **`$.paths['/deposits'].get`** — операция listDeposits не объявляет 404, 409, 422, 503, объявленные у соседних операций (getDepositStatus, confirmDeposit, createDeposit); для них достроены общие правила
- **`$.paths['/deposits'].post`** — операция createDeposit не объявляет 404, 409, 429, 500, объявленные у соседних операций (getDepositStatus, confirmDeposit, listDeposits); для них достроены общие правила
- **`$.paths['/deposits/{deposit_id}'].get`** — операция getDepositStatus не объявляет 400, 409, 422, 429, 500, 503, объявленные у соседних операций (createDeposit, confirmDeposit, listDeposits); для них достроены общие правила
- **`$.paths['/deposits/{deposit_id}/confirm'].post`** — операция confirmDeposit не объявляет 400, 401, 422, 429, 500, 503, объявленные у соседних операций (createDeposit, listDeposits); для них достроены общие правила
- **`$.paths['/reference/banks'].get`** — операция listBankCodes не объявляет 400, 404, 409, 422, 429, 503, объявленные у соседних операций (createDeposit, getDepositStatus, confirmDeposit, listDeposits); для них достроены общие правила

## 6. Справки

Факты, о которых читателю стоит знать; решения за человека инструмент здесь не
принимал. Списки сокращены до первых 5 элементов в группе — полный набор
виден в `./integrate analyze --spec depositbank.yaml`.

**`field_role_unknown`** — 12

- `$.components.schemas.CreateDepositRequest.properties.purpose_code` — необязательное поле `purpose_code` (string, enum ["trade_settlement", "services", "salary", "securities", "other"]): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; в запрос оно не попадёт; если оно нужно, задайте роль фрагментом ниже
- `$.components.schemas.CreateDepositRequest.properties.value_date` — необязательное поле `value_date` (string, format date): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; в запрос оно не попадёт; если оно нужно, задайте роль фрагментом ниже
- `$.components.schemas.DepositPage.properties.next_cursor` — необязательное поле `next_cursor` (string, nullable true): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; в запрос оно не попадёт; если оно нужно, задайте роль фрагментом ниже
- `$.components.schemas.DepositRejection.properties.rejected_at` — необязательное поле `rejected_at` (string, format date-time): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; в запрос оно не попадёт; если оно нужно, задайте роль фрагментом ниже
- `$.components.schemas.ErrorBody.properties.error_details.items.properties.field` — необязательное поле `field` (string): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; в запрос оно не попадёт; если оно нужно, задайте роль фрагментом ниже
- и ещё 7 с тем же кодом

**`operation_unmapped`** — 4, подробности в разделе 4

- `$.paths['/reference/banks'].get` — в спецификации слишком мало признаков того, для чего эта операция, поэтому роль не присвоена (fetch_status 3.0, balance 3.0, cancel 1.0 из 3.0 поданных голосов); задайте роль в overlay
- `$.paths['/accounts/{account_id}/balance'].get` — распознана как balance, но в Provider::BaseService нет метода для такой роли; она генерируется отдельным публичным методом и остаётся вне контракта
- `$.paths['/deposits'].get` — больше всех голосов набрала роль create_deposit, но она отсечена по форме: HTTP-метод операции не из тех, которыми выражается эта роль (vetoes.http_method в rules/operations.yml); роль не присвоена, операция получает отдельный публичный метод
- `$.paths['/deposits/{deposit_id}/confirm'].post` — распознана как confirm, но в Provider::BaseService нет метода для такой роли; она генерируется отдельным публичным методом и остаётся вне контракта

## 7. Что доделать руками

1. Заполните обязательное поле `remitter.zengin_bank_code` в build_payload: роль не выведена (роль bank_code отдана `swift_bic` (0.90); ) — добавьте синоним в `rules/roles.yml` или задайте `x-specgen-role` в overlay
2. Заполните обязательное поле `remitter.branch_code` в build_payload: роль не выведена (ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml) — добавьте синоним в `rules/roles.yml` или задайте `x-specgen-role` в overlay
3. Заполните обязательное поле `remitter.account_number` в build_payload: роль не выведена (ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml) — добавьте синоним в `rules/roles.yml` или задайте `x-specgen-role` в overlay
4. Заполните обязательное поле `remitter.account_holder_kana` в build_payload: роль не выведена (ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml) — добавьте синоним в `rules/roles.yml` или задайте `x-specgen-role` в overlay
5. Заполните реквизит `zengin_bank_code` для способа выплаты `domestic`: выражения платформы для него нет, добавьте его в rules/contract.yml (platform.requisites) или подставьте значение из `operation.payout_requisite` вручную
6. Заполните реквизит `branch_code` для способа выплаты `domestic`: выражения платформы для него нет, добавьте его в rules/contract.yml (platform.requisites) или подставьте значение из `operation.payout_requisite` вручную
7. Заполните реквизит `account_number` для способа выплаты `domestic`: выражения платформы для него нет, добавьте его в rules/contract.yml (platform.requisites) или подставьте значение из `operation.payout_requisite` вручную
8. Заполните реквизит `account_holder_kana` для способа выплаты `domestic`: выражения платформы для него нет, добавьте его в rules/contract.yml (platform.requisites) или подставьте значение из `operation.payout_requisite` вручную
9. Заполните реквизит `swift_bic` для способа выплаты `domestic`: выражения платформы для него нет, добавьте его в rules/contract.yml (platform.requisites) или подставьте значение из `operation.payout_requisite` вручную
10. Заполните реквизит `intermediary_swift` для способа выплаты `domestic`: выражения платформы для него нет, добавьте его в rules/contract.yml (platform.requisites) или подставьте значение из `operation.payout_requisite` вручную
11. Заполните реквизит `account_holder_kana` для способа выплаты `international`: выражения платформы для него нет, добавьте его в rules/contract.yml (platform.requisites) или подставьте значение из `operation.payout_requisite` вручную
12. Заполните реквизит `swift_bic` для способа выплаты `international`: выражения платформы для него нет, добавьте его в rules/contract.yml (platform.requisites) или подставьте значение из `operation.payout_requisite` вручную
13. Заполните реквизит `intermediary_swift` для способа выплаты `international`: выражения платформы для него нет, добавьте его в rules/contract.yml (platform.requisites) или подставьте значение из `operation.payout_requisite` вручную
14. Допишите тело метода `list_deposits` (операция `listDeposits`): роль не распознана, запрос собирается пустым
15. Допишите тело метода `list_bank_codes` (операция `listBankCodes`): роль не распознана, запрос собирается пустым
16. Решите судьбу необязательного поля `remitter.intermediary_swift`: роли нет, в payload оно не попало
17. Решите судьбу необязательного поля `purpose_code`: роли нет, в payload оно не попало
18. Решите судьбу необязательного поля `value_date`: роли нет, в payload оно не попало

Итого: 18 пунктов.
