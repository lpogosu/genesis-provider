# Отчёт о разборе спецификации «Paygate API»

| | |
|---|---|
| Провайдер | `moov_paygate_v1` |
| Спецификация | `moov_paygate_v1.yaml`, версия v1, OpenAPI 3.0.2 |
| Класс сервиса | `Provider::MoovPaygateV1Service` |
| Файл сервиса | `moov_paygate_v1_service.rb` |

Отчёт сгенерирован инструментом integrate из той же модели провайдера, что и
сервис: всё, о чём здесь сказано, лежит в сгенерированных файлах рядом.
Каждая строка ниже — действие, а не констатация: если элемент спецификации
попал в отчёт, к нему приложено, что сделал инструмент и чем это закрыть.
Генерация не блокируется никогда, поэтому отчёт описывает готовые файлы, а не
причину отказа.

## 1. Сводка

| Показатель | Значение |
|---|---|
| Операции | всего 10: отображено на контракт 6, вне контракта 1, без роли (unmapped) 3 |
| Схемы и поля | схем 12, полей 35: скалярных 21, контейнеров 14 |
| Роли полей | 9 из 21 скалярных: по справочнику 7, эвристика ниже порога 2 |
| Поля без роли | 12: обязательных 11, необязательных 1 |
| Статусы | 5: сопоставлено 5, не сопоставлено 0 |
| События вебхука | 0: сопоставлено 0, не сопоставлено 0 |
| Коды ошибок | кодов провайдера 0: в enum 0, только в примерах 0; общих правил по HTTP-коду 3 |
| Условия взаимодействия | 4: из структуры 4, из прозы описаний 0 |
| Предупреждения | 55: ошибок 0, предупреждений 28, справок 27 |

Сгенерированные артефакты:

| Файл | Что это | Строк |
|---|---|---|
| `moov_paygate_v1_service.rb` | сервис по контракту базового класса | 499 |
| `INTEGRATION.md` | документация интеграции | 194 |
| `fixtures.json` | примеры запросов, ответов и уведомлений | 496 |
| `report.md` | этот отчёт | считается в момент записи |

### Сверка сгенерированного со спецификацией

Тела из `fixtures.json` проверены схемами той же спецификации, из которой они
выведены: запрос — схемой тела своей операции, ответ — схемой своего кода
ответа, уведомление — схемой тела вебхука. Это замыкает круг: спецификация →
разбор → генерация → обратно к спецификации. Тела, которых спецификация не
обещала (операция без `requestBody`, ответ `204`), в счёт не идут — проверять
там нечего.

**Сверено тел: 24; прошли схему: 15; не прошли: 0; синтезированы и схему не проходят: 6; сверить не с чем: 3.**

**Синтезированы и схему не проходят — 6** — значение собрал генератор по типу поля либо фикстура негативна намеренно, поэтому расхождение с `pattern` или `enum` законно и ошибкой прогона не считается

- **ответ initiateMicroDeposits 200** — поле `created` не проходит `format`; место: `$.paths['/micro-deposits'].post.responses['200'].content['application/json'].schema`
- **ответ getMicroDeposits 200** — поле `created` не проходит `format`; место: `$.paths['/micro-deposits/{microDepositID}'].get.responses['200'].content['application/json'].schema`
- **ответ getAccountMicroDeposits 200** — поле `created` не проходит `format`; место: `$.paths['/accounts/{accountID}/micro-deposits'].get.responses['200'].content['application/json'].schema`
- **ответ getTransfers 200** — поле `тело целиком` не проходит `array`; место: `$.paths['/transfers'].get.responses['200'].content['application/json'].schema`
- **ответ addTransfer 201** — поле `created` не проходит `format`; место: `$.paths['/transfers'].post.responses['201'].content['application/json'].schema`
- **ответ getTransferByID 200** — поле `created` не проходит `format`; место: `$.paths['/transfers/{transferID}'].get.responses['200'].content['application/json'].schema`

**Сверить не с чем — 3** — схемы в спецификации нет, сверять не с чем — это пробел спецификации, а не итог проверки

- **ответ ping 200** — спецификация обещала тело, но не описала его — сверить нечего; место: `$.paths['/ping'].get.responses['200']`
- **ответ deleteTransferByID 200** — спецификация обещала тело, но не описала его — сверить нечего; место: `$.paths['/transfers/{transferID}'].delete.responses['200']`
- **ответ getTransferByID 404** — спецификация обещала тело, но не описала его — сверить нечего; место: `$.paths['/transfers/{transferID}'].get.responses['404']`

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

**Проверок: 19; прошло: 17; не прошло: 0; не проверено: 2.**

**Не проверено — 2** — вызывать было нечем или незачем: спецификация не описала операции, фикстура не даёт данных либо инструмент сам оставил в этом месте TODO — пробел уже назван в разделах ниже

- **прогон: check_conditions — сумма ниже минимума (—)** — спецификация не задаёт минимальной суммы — проверять нечего
- **прогон: process_callback — уведомление —** — спецификация не описывает вебхуков — уведомление проверить нечем

## 2. Покрытие спецификации

**Покрытие: 56 % (42 из 75 элементов). В границах контракта: 79 % (42 из 53).**

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

Знаменатель второй цифры меньше первого на 22 элемента, и вот они все, по
видам:

- **Поля тел запросов** — 1: необязательные поля без роли — в payload они не идут намеренно (docs/PRINCIPLES.md, раздел «Что генерируем при неполной спеке»), а не по недосмотру
- **Поля тел ответов и уведомлений** — 21: роль поля не входит в читаемые сервисом или не выведена вовсе — методам контракта такое поле прочитать некуда

Больше не вычтено ничего: коды ответов, статусы, события вебхука, условия
взаимодействия, обязательные поля тел запросов и поля запросов с выведенной
ролью остаются в знаменателе второй цифры целиком — даже когда не покрыты,
потому что их непокрытие — пробел интеграции, а не свойство контракта.
Вычтенное не спрятано: каждый вычтенный элемент назван ниже, в «Что не покрыто
и почему», со своей причиной и своей корзиной.

| Измерение | Найдено | Покрыто | Покрытие |
|---|---|---|---|
| Операции | 10 | 7 | 70 % |
| Поля тел запросов | 11 | 2 | 18 % |
| Поля тел ответов и уведомлений | 24 | 3 | 13 % |
| Коды ответов | 21 | 21 | 100 % |
| Статусы | 5 | 5 | 100 % |
| События вебхука | 0 | 0 | нечего покрывать |
| Условия взаимодействия | 4 | 4 | 100 % |

### Что не покрыто и почему

Непокрыто 33: вне контракта 13, структурных исключений 15, требует ручной
работы 5. Корзина каждого элемента вычислена из его причины, таблица причин —
Generators::Report::Gap::BUCKETS.

**Требует ручной работы — 5.** Единственная корзина, адресованная человеку:
здесь спецификация описала то, что контракт умеет использовать, а интеграция
этого не взяла. Перечислена целиком, поимённо и первой — это и есть список
того, что стоит доделать руками.

**Поля тел запросов** — не покрыто 5

- `addTransfer: source.customerID` — обязательное поле без роли: в payload попало с TODO и значением по умолчанию, значение подставит человек
- `addTransfer: source.accountID` — обязательное поле без роли: в payload попало с TODO и значением по умолчанию, значение подставит человек
- `addTransfer: destination.customerID` — обязательное поле без роли: в payload попало с TODO и значением по умолчанию, значение подставит человек
- `addTransfer: destination.accountID` — обязательное поле без роли: в payload попало с TODO и значением по умолчанию, значение подставит человек
- `addTransfer: description` — обязательное поле без роли: в payload попало с TODO и значением по умолчанию, значение подставит человек

**Вне контракта — 13.** Ресурсы спецификации, которых методы контракта не
касаются вовсе: чужие операции и их поля, коды и схемы. Контракт про выплаты;
считать пробелом интеграции отсутствие в ней подписок, споров или хранения
карт — то же самое, что считать пробелом отсутствие метода для чужого API.
Свёрнуто числом с примерами.

- **Операции** — 3: `ping`, `updateTransferConfiguration`, `getTransfers`
- **Поля тел запросов** — 3: `updateTransferConfiguration: companyIdentification`, `initiateMicroDeposits: destination.customerID`, `initiateMicroDeposits: destination.accountID`
- **Поля тел ответов и уведомлений** — 7, например: `OrganizationConfiguration.companyIdentification`, `MicroDeposits.transferIDs`, `MicroDeposits.destination.customerID`

**Структурные исключения метрики — 15.** Элементы, которым в методах контракта
нет места по построению: поле входящего тела засчитывается, только когда его
роль читает один из четырёх методов; необязательное поле без роли в payload не
идёт намеренно; код, объявленный диапазоном, ветки не даёт. Это устройство
метрики и контракта, а не пропуск разбора. Свёрнуто числом с примерами.

- **Поля тел запросов** — 1: `addTransfer: sameDay`
- **Поля тел ответов и уведомлений** — 14, например: `Transfer.amount.currency`, `Transfer.amount.value`, `Transfer.source.customerID`

## 3. Неоднозначности

Элементы, о которых спецификация говорит недостаточно, чтобы решение было
однозначным. Инструмент решил сам — что именно, сказано под каждым кодом; от
человека нужна проверка, а не заполнение пропуска.

### `field_role_low_confidence` — 3

Что сделал инструмент: роль присвоена лучшему кандидату, в коде рядом с полем — комментарий с уверенностью

- **`$.components.schemas.Error.properties.error`** — обязательное поле `error`: роль error_code выведена с низкой уверенностью 0.50 (порог 0.60); кандидаты: error_code 0.50, error_message 0.50; без него запрос не уйдёт, поэтому в код оно попадёт как error_code с TODO — проверьте роль и закрепите её фрагментом ниже

  ```yaml
  - target: "$.components.schemas.Error.properties.error"
    update:
      x-specgen-role: error_code  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.MicroDeposits.properties.microDepositID`** — обязательное поле `microDepositID`: роль provider_operation_id выведена с низкой уверенностью 0.26 (порог 0.60); кандидаты: provider_operation_id 0.26; без него запрос не уйдёт, поэтому в код оно попадёт как provider_operation_id с TODO — проверьте роль и закрепите её фрагментом ниже

  ```yaml
  - target: "$.components.schemas.MicroDeposits.properties.microDepositID"
    update:
      x-specgen-role: provider_operation_id  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.paths['/micro-deposits/{microDepositID}'].get.parameters[0]`** — обязательный параметр `microDepositID` (путь): роль provider_operation_id выведена с низкой уверенностью 0.55 (порог 0.60); кандидаты: provider_operation_id 0.55; без него запрос не уйдёт, поэтому в код оно попадёт как provider_operation_id с TODO — проверьте роль и закрепите её фрагментом ниже

  ```yaml
  - target: "$.paths['/micro-deposits/{microDepositID}'].get.parameters[0]"
    update:
      x-specgen-role: provider_operation_id  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```

### `idempotency_dedup_unclear` — 1

Что сделал инструмент: ветка дедупликации не сгенерирована: ответ с кодом конфликта пойдёт как ошибка

- **`$.paths['/transfers'].post`** — заголовок X-Idempotency-Key объявлен, но ни одна операция не описывает ответ 409 со схемой успешного ответа; при повторе сервис не отличит дубль от ошибки — уточните у провайдера или опишите ответ в overlay

  ```yaml
  - target: "$.paths['/transfers'].post.responses"
    update:
      '409':
        description: Duplicate idempotency key, previous result returned
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/Transfer'
  ```

### `idempotency_header_ambiguous` — 1

Что сделал инструмент: выбран один из нескольких объявленных заголовков идемпотентности

- **`$.paths['/transfers'].post.parameters[0]`** — спецификация объявляет несколько известных заголовков идемпотентности; выбран X-Idempotency-Key по списку priority в rules/idempotency.yml, отклонены: X-Request-ID
  готового overlay-фрагмента нет: закрепляется записью в `rules/idempotency.yml` или правкой спецификации

### `operation_role_ambiguous` — 1

Что сделал инструмент: взят лучший кандидат роли, метод сгенерирован по нему

- **`$.paths['/accounts/{accountID}/micro-deposits'].get`** — две роли подходят этой операции почти одинаково; взята первая, но выбор стоит подтвердить (fetch_status 10.0, balance 10.0 из 13.0 поданных голосов); переопределить — в overlay
  готового overlay-фрагмента нет: закрепляется записью в `rules/operations.yml` или правкой спецификации

### `operation_tie` — 1

Что сделал инструмент: ничья разрешена связью с ресурсом, а где её нет — порядком объявления

- **`$.paths['/transfers/{transferID}'].get`** — на роль fetch_status претендует несколько операций с одинаковой уверенностью 0.95 (getMicroDeposits (GET /micro-deposits/{microDepositID}), getTransferByID (GET /transfers/{transferID})); взята getTransferByID: её связывает с addTransfer общий контейнер ресурса `transfers`, путь продолжает путь создания, общая схема успешного ответа Transfer
  готового overlay-фрагмента нет: исправляется правкой спецификации

### `required_field_role_unknown` — 19

Что сделал инструмент: в исходящем теле поле включено в payload со значением примера или nil и TODO рядом; во входящем — ищется структурно

- **`$.components.schemas.CreateTransfer.properties.description`** — обязательное поле `description` (string, min_length 1, max_length 10): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; без него запрос не уйдёт, поэтому в код оно попадёт с TODO — задайте роль фрагментом ниже или добавьте синоним в rules/roles.yml

  ```yaml
  - target: "$.components.schemas.CreateTransfer.properties.description"
    update:
      x-specgen-role: TODO  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.Destination.properties.accountID`** — обязательное поле `accountID` (string): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; без него запрос не уйдёт, поэтому в код оно попадёт с TODO — задайте роль фрагментом ниже или добавьте синоним в rules/roles.yml

  ```yaml
  - target: "$.components.schemas.Destination.properties.accountID"
    update:
      x-specgen-role: TODO  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.Destination.properties.customerID`** — обязательное поле `customerID` (string): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; без него запрос не уйдёт, поэтому в код оно попадёт с TODO — задайте роль фрагментом ниже или добавьте синоним в rules/roles.yml

  ```yaml
  - target: "$.components.schemas.Destination.properties.customerID"
    update:
      x-specgen-role: TODO  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.OrganizationConfiguration.properties.companyIdentification`** — обязательное поле `companyIdentification` (string): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; без него запрос не уйдёт, поэтому в код оно попадёт с TODO — задайте роль фрагментом ниже или добавьте синоним в rules/roles.yml

  ```yaml
  - target: "$.components.schemas.OrganizationConfiguration.properties.companyIdentification"
    update:
      x-specgen-role: TODO  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.ReturnCode.properties.code`** — обязательное поле `code` (string): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; без него запрос не уйдёт, поэтому в код оно попадёт с TODO — задайте роль фрагментом ниже или добавьте синоним в rules/roles.yml

  ```yaml
  - target: "$.components.schemas.ReturnCode.properties.code"
    update:
      x-specgen-role: TODO  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.ReturnCode.properties.description`** — обязательное поле `description` (string): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; без него запрос не уйдёт, поэтому в код оно попадёт с TODO — задайте роль фрагментом ниже или добавьте синоним в rules/roles.yml

  ```yaml
  - target: "$.components.schemas.ReturnCode.properties.description"
    update:
      x-specgen-role: TODO  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.ReturnCode.properties.reason`** — обязательное поле `reason` (string): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; без него запрос не уйдёт, поэтому в код оно попадёт с TODO — задайте роль фрагментом ниже или добавьте синоним в rules/roles.yml

  ```yaml
  - target: "$.components.schemas.ReturnCode.properties.reason"
    update:
      x-specgen-role: TODO  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.Source.properties.accountID`** — обязательное поле `accountID` (string): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; без него запрос не уйдёт, поэтому в код оно попадёт с TODO — задайте роль фрагментом ниже или добавьте синоним в rules/roles.yml

  ```yaml
  - target: "$.components.schemas.Source.properties.accountID"
    update:
      x-specgen-role: TODO  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.Source.properties.customerID`** — обязательное поле `customerID` (string): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; без него запрос не уйдёт, поэтому в код оно попадёт с TODO — задайте роль фрагментом ниже или добавьте синоним в rules/roles.yml

  ```yaml
  - target: "$.components.schemas.Source.properties.customerID"
    update:
      x-specgen-role: TODO  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.Transfer.properties.description`** — обязательное поле `description` (string, min_length 1, max_length 10): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; без него запрос не уйдёт, поэтому в код оно попадёт с TODO — задайте роль фрагментом ниже или добавьте синоним в rules/roles.yml

  ```yaml
  - target: "$.components.schemas.Transfer.properties.description"
    update:
      x-specgen-role: TODO  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.Transfer.properties.sameDay`** — обязательное поле `sameDay` (boolean, default false): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; без него запрос не уйдёт, поэтому в код оно попадёт с TODO — задайте роль фрагментом ниже или добавьте синоним в rules/roles.yml

  ```yaml
  - target: "$.components.schemas.Transfer.properties.sameDay"
    update:
      x-specgen-role: TODO  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.paths['/accounts/{accountID}/micro-deposits'].get.parameters[0]`** — обязательный параметр `accountID` (путь) (string): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; без него запрос не уйдёт, поэтому в код оно попадёт с TODO — задайте роль фрагментом ниже или добавьте синоним в rules/roles.yml

  ```yaml
  - target: "$.paths['/accounts/{accountID}/micro-deposits'].get.parameters[0]"
    update:
      x-specgen-role: TODO  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.paths['/accounts/{accountID}/micro-deposits'].get.parameters[1]`** — обязательный параметр `X-Organization` (заголовок) (string): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; без него запрос не уйдёт, поэтому в код оно попадёт с TODO — задайте роль фрагментом ниже или добавьте синоним в rules/roles.yml

  ```yaml
  - target: "$.paths['/accounts/{accountID}/micro-deposits'].get.parameters[1]"
    update:
      x-specgen-role: TODO  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.paths['/micro-deposits'].post.parameters[0]`** — обязательный параметр `X-Organization` (заголовок) (string): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; без него запрос не уйдёт, поэтому в код оно попадёт с TODO — задайте роль фрагментом ниже или добавьте синоним в rules/roles.yml

  ```yaml
  - target: "$.paths['/micro-deposits'].post.parameters[0]"
    update:
      x-specgen-role: TODO  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.paths['/micro-deposits/{microDepositID}'].get.parameters[1]`** — обязательный параметр `X-Organization` (заголовок) (string): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; без него запрос не уйдёт, поэтому в код оно попадёт с TODO — задайте роль фрагментом ниже или добавьте синоним в rules/roles.yml

  ```yaml
  - target: "$.paths['/micro-deposits/{microDepositID}'].get.parameters[1]"
    update:
      x-specgen-role: TODO  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.paths['/transfers'].get.parameters[8]`** — обязательный параметр `X-Organization` (заголовок) (string): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; без него запрос не уйдёт, поэтому в код оно попадёт с TODO — задайте роль фрагментом ниже или добавьте синоним в rules/roles.yml

  ```yaml
  - target: "$.paths['/transfers'].get.parameters[8]"
    update:
      x-specgen-role: TODO  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.paths['/transfers'].post.parameters[2]`** — обязательный параметр `X-Organization` (заголовок) (string): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; без него запрос не уйдёт, поэтому в код оно попадёт с TODO — задайте роль фрагментом ниже или добавьте синоним в rules/roles.yml

  ```yaml
  - target: "$.paths['/transfers'].post.parameters[2]"
    update:
      x-specgen-role: TODO  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.paths['/transfers/{transferID}'].delete.parameters[2]`** — обязательный параметр `X-Organization` (заголовок) (string): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; без него запрос не уйдёт, поэтому в код оно попадёт с TODO — задайте роль фрагментом ниже или добавьте синоним в rules/roles.yml

  ```yaml
  - target: "$.paths['/transfers/{transferID}'].delete.parameters[2]"
    update:
      x-specgen-role: TODO  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.paths['/transfers/{transferID}'].get.parameters[2]`** — обязательный параметр `X-Organization` (заголовок) (string): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; без него запрос не уйдёт, поэтому в код оно попадёт с TODO — задайте роль фрагментом ниже или добавьте синоним в rules/roles.yml

  ```yaml
  - target: "$.paths['/transfers/{transferID}'].get.parameters[2]"
    update:
      x-specgen-role: TODO  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```

### `schema_unresolved` — 3

Что сделал инструмент: схема не разобрана: её поля в код не попали

- **`$.paths['/ping'].get.responses['200']`** — ответ 200 операции ping объявлен одним описанием: `content` нет, поэтому нечему описывать тело — либо опишите схему, либо объявите ответ без тела кодом 204
  готового overlay-фрагмента нет: исправляется правкой спецификации
- **`$.paths['/transfers/{transferID}'].delete.responses['200']`** — ответ 200 операции deleteTransferByID объявлен одним описанием: `content` нет, поэтому нечему описывать тело — либо опишите схему, либо объявите ответ без тела кодом 204
  готового overlay-фрагмента нет: исправляется правкой спецификации
- **`$.paths['/transfers/{transferID}'].get.responses['404']`** — ответ 404 операции getTransferByID объявлен одним описанием: `content` нет, поэтому нечему описывать тело — либо опишите схему, либо объявите ответ без тела кодом 204
  готового overlay-фрагмента нет: исправляется правкой спецификации

### `webhook_missing` — 1

Что сделал инструмент: process_callback отказывает webhooks_not_supported: статус только опросом

- **`$.paths`** — спецификация не описывает входящих уведомлений (нет операции с security: [] и нет секции webhooks); статус операции сервис узнает только опросом через fetch_status
  готового overlay-фрагмента нет: исправляется правкой спецификации

### Как собрать overlay

Фрагменты выше — действия одного документа OpenAPI Overlay 1.0.0
(<https://spec.openapis.org/overlay/v1.0.0.html>). Соберите файл
`moov_paygate_v1.overlay.yaml`, вставив их подряд под ключ `actions`,
замените значения `TODO` и перегенерируйте:

```yaml
overlay: 1.0.0
info:
  title: moov_paygate_v1 disambiguation
  version: 1.0.0
actions:
- target: "$..."
  update:
    x-specgen-role: ...
```

```sh
./integrate --spec moov_paygate_v1.yaml --provider moov_paygate_v1 --overlay moov_paygate_v1.overlay.yaml
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
| `ping` | `GET /ping` | не распознана (unmapped) | `ping()` | добавьте синоним пути или operationId в `rules/operations.yml` и перегенерируйте; расширения `x-specgen-role` для операции в модели нет (docs/IR.md, таблица расширений) |
| `getTransferConfiguration` | `GET /configuration/transfers` | `fetch_status` (эвристика 0.77) | `transfer_configuration()` | ничего: в `Provider::BaseService` нет метода для такой роли, платформа зовёт этот метод напрямую |
| `updateTransferConfiguration` | `PUT /configuration/transfers` | не распознана (unmapped) | `update_transfer_configuration(operation)` | добавьте синоним пути или operationId в `rules/operations.yml` и перегенерируйте; расширения `x-specgen-role` для операции в модели нет (docs/IR.md, таблица расширений) |
| `initiateMicroDeposits` | `POST /micro-deposits` | `create_deposit` (эвристика 0.95) | `initiate_micro_deposits(operation)` | ничего: в `Provider::BaseService` нет метода для такой роли, платформа зовёт этот метод напрямую |
| `getMicroDeposits` | `GET /micro-deposits/{microDepositID}` | `fetch_status` (эвристика 0.95) | `get_micro_deposits(operation)` | ничего: в `Provider::BaseService` нет метода для такой роли, платформа зовёт этот метод напрямую |
| `getAccountMicroDeposits` | `GET /accounts/{accountID}/micro-deposits` | `fetch_status` (эвристика 0.77) | `get_account_micro_deposits(operation)` | ничего: в `Provider::BaseService` нет метода для такой роли, платформа зовёт этот метод напрямую |
| `getTransfers` | `GET /transfers` | не распознана (unmapped) | `transfers()` | добавьте синоним пути или operationId в `rules/operations.yml` и перегенерируйте; расширения `x-specgen-role` для операции в модели нет (docs/IR.md, таблица расширений) |
| `deleteTransferByID` | `DELETE /transfers/{transferID}` | `cancel` (эвристика 0.79) | `cancel(operation)` | ничего: в `Provider::BaseService` нет метода для такой роли, платформа зовёт этот метод напрямую |

## 5. Противоречия в самой спецификации

Спецификация расходится сама с собой или со своими соседями: enum против
примеров, коды ответов одной операции против другой, проза против структуры.
Инструмент выбрал, чему верить, и продолжил; правится это правкой
спецификации, а не настройкой инструмента.

### `field_role_conflict` — 1

Что сделал инструмент: роль оставлена полю с большей уверенностью, второе получило следующего кандидата

- **`$.paths['/transfers'].post.parameters[0]`** — необязательный параметр `X-Idempotency-Key` (заголовок): роль idempotency_key (0.90) уже у `X-Request-ID` (0.90) в той же схеме; других кандидатов нет, роль не выведена — задайте её фрагментом ниже

### `undeclared_status_code` — 10

Что сделал инструмент: для кода достроено общее правило ERROR_MAP по HTTP-коду

- **`$.paths['/accounts/{accountID}/micro-deposits'].get`** — операция getAccountMicroDeposits не объявляет 404, 412, объявленные у соседних операций (getTransferByID, updateTransferConfiguration); для них достроены общие правила
- **`$.paths['/configuration/transfers'].get`** — операция getTransferConfiguration не объявляет 400, 404, 412, объявленные у соседних операций (updateTransferConfiguration, getTransferByID); для них достроены общие правила
- **`$.paths['/configuration/transfers'].put`** — операция updateTransferConfiguration не объявляет 404, объявленные у соседних операций (getTransferByID); для них достроены общие правила
- **`$.paths['/micro-deposits'].post`** — операция initiateMicroDeposits не объявляет 404, объявленные у соседних операций (getTransferByID); для них достроены общие правила
- **`$.paths['/micro-deposits/{microDepositID}'].get`** — операция getMicroDeposits не объявляет 404, 412, объявленные у соседних операций (getTransferByID, updateTransferConfiguration); для них достроены общие правила
- **`$.paths['/ping'].get`** — операция ping не объявляет 400, 404, 412, объявленные у соседних операций (updateTransferConfiguration, getTransferByID); для них достроены общие правила
- **`$.paths['/transfers'].get`** — операция getTransfers не объявляет 404, 412, объявленные у соседних операций (getTransferByID, updateTransferConfiguration); для них достроены общие правила
- **`$.paths['/transfers'].post`** — операция addTransfer не объявляет 404, объявленные у соседних операций (getTransferByID); для них достроены общие правила
- **`$.paths['/transfers/{transferID}'].delete`** — операция deleteTransferByID не объявляет 404, 412, объявленные у соседних операций (getTransferByID, updateTransferConfiguration); для них достроены общие правила
- **`$.paths['/transfers/{transferID}'].get`** — операция getTransferByID не объявляет 400, 412, объявленные у соседних операций (updateTransferConfiguration); для них достроены общие правила

## 6. Справки

Факты, о которых читателю стоит знать; решения за человека инструмент здесь не
принимал. Списки сокращены до первых 5 элементов в группе — полный набор
виден в `./integrate analyze --spec moov_paygate_v1.yaml`.

**`auth_absent`** — 1

- `$.components.securitySchemes` — спецификация вообще не объявляет авторизацию, поэтому сгенерированные запросы идут без учётных данных; для платёжного API это необычно, сверьтесь с контрактом

**`field_role_unknown`** — 9

- `$.components.schemas.CreateTransfer.properties.sameDay` — необязательное поле `sameDay` (boolean, default false): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; в запрос оно не попадёт; если оно нужно, задайте роль фрагментом ниже
- `$.paths['/configuration/transfers'].get.parameters[0]` — необязательный параметр `X-Organization` (заголовок) (string): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; в запрос оно не попадёт; если оно нужно, задайте роль фрагментом ниже
- `$.paths['/configuration/transfers'].put.parameters[0]` — необязательный параметр `X-Organization` (заголовок) (string): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; в запрос оно не попадёт; если оно нужно, задайте роль фрагментом ниже
- `$.paths['/transfers'].get.parameters[0]` — необязательный параметр `skip` (query) (integer, minimum 0, default 0): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; в запрос оно не попадёт; если оно нужно, задайте роль фрагментом ниже
- `$.paths['/transfers'].get.parameters[1]` — необязательный параметр `count` (query) (integer, minimum 0, maximum 100, default 25): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; в запрос оно не попадёт; если оно нужно, задайте роль фрагментом ниже
- и ещё 4 с тем же кодом

**`operation_unmapped`** — 4, подробности в разделе 4

- `$.paths['/ping'].get` — в спецификации слишком мало признаков того, для чего эта операция, поэтому роль не присвоена (fetch_status 3.0, balance 3.0, cancel 1.0 из 3.0 поданных голосов); задайте роль в overlay
- `$.paths['/configuration/transfers'].put` — больше всех голосов набрала роль create_payout, но она отсечена по форме: HTTP-метод операции не из тех, которыми выражается эта роль (vetoes.http_method в rules/operations.yml); роль не присвоена, операция получает отдельный публичный метод
- `$.paths['/transfers'].get` — больше всех голосов набрала роль fetch_status, но она отсечена по форме: успешный ответ — список, то есть листинг ресурса, а не чтение одного экземпляра (vetoes.list_response в rules/operations.yml); роль не присвоена, операция получает отдельный публичный метод
- `$.paths['/transfers/{transferID}'].delete` — распознана как cancel, но в Provider::BaseService нет метода для такой роли; она генерируется отдельным публичным методом и остаётся вне контракта

## 7. Что доделать руками

1. Заполните обязательное поле `source.customerID` в build_payload: роль не выведена (ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml) — добавьте синоним в `rules/roles.yml` или задайте `x-specgen-role` в overlay
2. Заполните обязательное поле `source.accountID` в build_payload: роль не выведена (ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml) — добавьте синоним в `rules/roles.yml` или задайте `x-specgen-role` в overlay
3. Заполните обязательное поле `destination.customerID` в build_payload: роль не выведена (ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml) — добавьте синоним в `rules/roles.yml` или задайте `x-specgen-role` в overlay
4. Заполните обязательное поле `destination.accountID` в build_payload: роль не выведена (ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml) — добавьте синоним в `rules/roles.yml` или задайте `x-specgen-role` в overlay
5. Заполните обязательное поле `description` в build_payload: роль не выведена (ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml) — добавьте синоним в `rules/roles.yml` или задайте `x-specgen-role` в overlay
6. Допишите тело метода `ping` (операция `ping`): роль не распознана, запрос собирается пустым
7. Допишите тело метода `update_transfer_configuration` (операция `updateTransferConfiguration`): роль не распознана, запрос собирается пустым
8. Допишите тело метода `transfers` (операция `getTransfers`): роль не распознана, запрос собирается пустым
9. Решите судьбу необязательного поля `sameDay`: роли нет, в payload оно не попало
10. Проверьте значения фикстуры `updateTransferConfiguration`: тело собрано не из примеров спецификации (`schema_example`)
11. Проверьте значения фикстуры `initiateMicroDeposits`: тело собрано не из примеров спецификации (`schema_example`)
12. Проверьте значения фикстуры `addTransfer`: тело собрано не из примеров спецификации (`schema_example`)
13. Проверьте значения фикстуры `ping 200`: тело собрано не из примеров спецификации (`undeclared`)
14. Проверьте значения фикстуры `getTransferConfiguration 200`: тело собрано не из примеров спецификации (`schema_example`)
15. Проверьте значения фикстуры `updateTransferConfiguration 200`: тело собрано не из примеров спецификации (`schema_example`)
16. Проверьте значения фикстуры `updateTransferConfiguration 400`: тело собрано не из примеров спецификации (`schema_example`)
17. Проверьте значения фикстуры `updateTransferConfiguration 412`: тело собрано не из примеров спецификации (`schema_example`)
18. Проверьте значения фикстуры `initiateMicroDeposits 200`: тело собрано не из примеров спецификации (`synthesized`)
19. Проверьте значения фикстуры `initiateMicroDeposits 400`: тело собрано не из примеров спецификации (`schema_example`)
20. Проверьте значения фикстуры `initiateMicroDeposits 412`: тело собрано не из примеров спецификации (`schema_example`)
21. Проверьте значения фикстуры `getMicroDeposits 200`: тело собрано не из примеров спецификации (`synthesized`)
22. Проверьте значения фикстуры `getMicroDeposits 400`: тело собрано не из примеров спецификации (`schema_example`)
23. Проверьте значения фикстуры `getAccountMicroDeposits 200`: тело собрано не из примеров спецификации (`synthesized`)
24. Проверьте значения фикстуры `getAccountMicroDeposits 400`: тело собрано не из примеров спецификации (`schema_example`)
25. Проверьте значения фикстуры `getTransfers 200`: тело собрано не из примеров спецификации (`schema_example`)
26. Проверьте значения фикстуры `getTransfers 400`: тело собрано не из примеров спецификации (`schema_example`)
27. Проверьте значения фикстуры `addTransfer 201`: тело собрано не из примеров спецификации (`synthesized`)
28. Проверьте значения фикстуры `addTransfer 400`: тело собрано не из примеров спецификации (`schema_example`)
29. Проверьте значения фикстуры `addTransfer 412`: тело собрано не из примеров спецификации (`schema_example`)
30. И ещё 4 однотипных пунктов — полный список в разделах 3 и 6
31. Подключите вторую операцию создания `initiateMicroDeposits` вручную: контракт даёт один метод создания

Итого: 31 пункт.
