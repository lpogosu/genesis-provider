# Отчёт о разборе спецификации «Transfers API»

| | |
|---|---|
| Провайдер | `adyen_transfers_v4` |
| Спецификация | `adyen_transfers_v4.yaml`, версия 4, OpenAPI 3.1.0 |
| Класс сервиса | `Provider::AdyenTransfersV4Service` |
| Файл сервиса | `adyen_transfers_v4_service.rb` |

Отчёт сгенерирован инструментом integrate из той же модели провайдера, что и
сервис: всё, о чём здесь сказано, лежит в сгенерированных файлах рядом.
Каждая строка ниже — действие, а не констатация: если элемент спецификации
попал в отчёт, к нему приложено, что сделал инструмент и чем это закрыть.
Генерация не блокируется никогда, поэтому отчёт описывает готовые файлы, а не
причину отказа.

## 1. Сводка

| Показатель | Значение |
|---|---|
| Операции | всего 12: отображено на контракт 4, вне контракта 3, без роли (unmapped) 5 |
| Схемы и поля | схем 108, полей 518: скалярных 393, контейнеров 125 |
| Роли полей | 166 из 393 скалярных: по справочнику 107, эвристика выше порога 4, эвристика ниже порога 55 |
| Поля без роли | 227: обязательных 58, необязательных 169 |
| Статусы | 79: сопоставлено 45, не сопоставлено 34 |
| События вебхука | 0: сопоставлено 0, не сопоставлено 0 |
| Коды ошибок | кодов провайдера 0: в enum 0, только в примерах 0; общих правил по HTTP-коду 3 |
| Условия взаимодействия | 23: из структуры 23, из прозы описаний 0 |
| Предупреждения | 377: ошибок 0, предупреждений 93, справок 284 |

Сгенерированные артефакты:

| Файл | Что это | Строк |
|---|---|---|
| `adyen_transfers_v4_service.rb` | сервис по контракту базового класса | 1077 |
| `INTEGRATION.md` | документация интеграции | 428 |
| `fixtures.json` | примеры запросов, ответов и уведомлений | 2395 |
| `report.md` | этот отчёт | считается в момент записи |

### Сверка сгенерированного со спецификацией

Тела из `fixtures.json` проверены схемами той же спецификации, из которой они
выведены: запрос — схемой тела своей операции, ответ — схемой своего кода
ответа, уведомление — схемой тела вебхука. Это замыкает круг: спецификация →
разбор → генерация → обратно к спецификации. Тела, которых спецификация не
обещала (операция без `requestBody`, ответ `204`), в счёт не идут — проверять
там нечего.

**Сверено тел: 83; прошли схему: 80; не прошли: 0; синтезированы и схему не проходят: 1; сверить не с чем: 2.**

**Синтезированы и схему не проходят — 1** — значение собрал генератор по типу поля либо фикстура негативна намеренно, поэтому расхождение с `pattern` или `enum` законно и ошибкой прогона не считается

- **ответ post-transfers 200** — поле `counterparty.bankAccount.accountIdentification.accountType` не проходит `schema` (и ещё расхождений: 49); место: `$.paths['/transfers'].post.responses['200'].content['application/json'].schema`

**Сверить не с чем — 2** — схемы в спецификации нет, сверять не с чем — это пробел спецификации, а не итог проверки

- **ответ post-transfers-approve 200 (transfers-approve)** — схема тела в спецификации не объявлена — сверить не с чем; место: `$.paths['/transfers/approve'].post.responses['200']`
- **ответ post-transfers-cancel 200 (transfers-cancel)** — схема тела в спецификации не объявлена — сверить не с чем; место: `$.paths['/transfers/cancel'].post.responses['200']`

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

**Проверок: 73; прошло: 69; не прошло: 1; не проверено: 3.**

**Не прошло — 1** — класс сделал не то, что обещают фикстуры и таблицы INTEGRATION.md: это расхождение сгенерированного кода с сгенерированной документацией, и его надо прочитать глазами

- **прогон: create_request — тело запроса** — в теле запроса нет ключа `amount.currency`

**Не проверено — 3** — вызывать было нечем или незачем: спецификация не описала операции, фикстура не даёт данных либо инструмент сам оставил в этом месте TODO — пробел уже назван в разделах ниже

- **прогон: check_conditions — сумма ниже минимума (—)** — спецификация не задаёт минимальной суммы — проверять нечего
- **прогон: create_request — идентификатор операции в результате** — в схеме успешного ответа нет поля с ролью provider_operation_id
- **прогон: process_callback — уведомление —** — спецификация не описывает вебхуков — уведомление проверить нечем

## 2. Покрытие спецификации

**Покрытие: 32 % (227 из 700 элементов). В границах контракта: 74 % (227 из 308).**

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

Знаменатель второй цифры меньше первого на 392 элемента, и вот они все, по
видам:

- **Поля тел запросов** — 66: необязательные поля без роли — в payload они не идут намеренно (docs/PRINCIPLES.md, раздел «Что генерируем при неполной спеке»), а не по недосмотру
- **Поля тел ответов и уведомлений** — 326: роль поля не входит в читаемые сервисом или не выведена вовсе — методам контракта такое поле прочитать некуда

Больше не вычтено ничего: коды ответов, статусы, события вебхука, условия
взаимодействия, обязательные поля тел запросов и поля запросов с выведенной
ролью остаются в знаменателе второй цифры целиком — даже когда не покрыты,
потому что их непокрытие — пробел интеграции, а не свойство контракта.
Вычтенное не спрятано: каждый вычтенный элемент назван ниже, в «Что не покрыто
и почему», со своей причиной и своей корзиной.

| Измерение | Найдено | Покрыто | Покрытие |
|---|---|---|---|
| Операции | 12 | 7 | 58 % |
| Поля тел запросов | 113 | 18 | 16 % |
| Поля тел ответов и уведомлений | 403 | 77 | 19 % |
| Коды ответов | 70 | 70 | 100 % |
| Статусы | 79 | 45 | 57 % |
| События вебхука | 0 | 0 | нечего покрывать |
| Условия взаимодействия | 23 | 10 | 43 % |

### Что не покрыто и почему

Непокрыто 473: вне контракта 86, структурных исключений 317, требует ручной
работы 70. Корзина каждого элемента вычислена из его причины, таблица причин —
Generators::Report::Gap::BUCKETS.

**Требует ручной работы — 70.** Единственная корзина, адресованная человеку:
здесь спецификация описала то, что контракт умеет использовать, а интеграция
этого не взяла. Перечислена целиком, поимённо и первой — это и есть список
того, что стоит доделать руками.

**Поля тел запросов** — не покрыто 23

- `post-transfers: amount.currency` — роль currency выведена, но выражения платформы для неё нет ни в accessors, ни в requisites (rules/contract.yml, раздел platform) — добавьте его туда или заполните поле вручную
- `post-transfers: category` — обязательное поле без роли: в payload попало с TODO и значением по умолчанию, значение подставит человек
- `post-transfers: counterparty.bankAccount.accountHolder.address.country` — обязательное поле без роли: в payload попало с TODO и значением по умолчанию, значение подставит человек
- `post-transfers: counterparty.bankAccount.accountHolder.type` — роль recipient_type выведена, но выражения платформы для неё нет ни в accessors, ни в requisites (rules/contract.yml, раздел platform) — добавьте его туда или заполните поле вручную
- `post-transfers: counterparty.bankAccount.accountIdentification.accountNumber` — обязательное поле без роли: в payload попало с TODO и значением по умолчанию, значение подставит человек
- `post-transfers: counterparty.bankAccount.accountIdentification.bsbCode` — обязательное поле без роли: в payload попало с TODO и значением по умолчанию, значение подставит человек
- `post-transfers: counterparty.bankAccount.accountIdentification.type` — роль recipient_type выведена, но выражения платформы для неё нет ни в accessors, ни в requisites (rules/contract.yml, раздел platform) — добавьте его туда или заполните поле вручную
- `post-transfers: counterparty.bankAccount.accountIdentification.bankCode` — обязательное поле без роли: в payload попало с TODO и значением по умолчанию, значение подставит человек
- `post-transfers: counterparty.bankAccount.accountIdentification.branchNumber` — обязательное поле без роли: в payload попало с TODO и значением по умолчанию, значение подставит человек
- `post-transfers: counterparty.bankAccount.accountIdentification.institutionNumber` — обязательное поле без роли: в payload попало с TODO и значением по умолчанию, значение подставит человек
- `post-transfers: counterparty.bankAccount.accountIdentification.transitNumber` — обязательное поле без роли: в payload попало с TODO и значением по умолчанию, значение подставит человек
- `post-transfers: counterparty.bankAccount.accountIdentification.clearingCode` — обязательное поле без роли: в payload попало с TODO и значением по умолчанию, значение подставит человек
- `post-transfers: counterparty.bankAccount.accountIdentification.bic` — роль bank_code выведена, но выражения платформы для неё нет ни в accessors, ни в requisites (rules/contract.yml, раздел platform) — добавьте его туда или заполните поле вручную
- `post-transfers: counterparty.bankAccount.accountIdentification.iban` — обязательное поле без роли: в payload попало с TODO и значением по умолчанию, значение подставит человек
- `post-transfers: counterparty.bankAccount.accountIdentification.additionalBankIdentification.type` — роль recipient_type выведена, но выражения платформы для неё нет ни в accessors, ни в requisites (rules/contract.yml, раздел platform) — добавьте его туда или заполните поле вручную
- `post-transfers: counterparty.bankAccount.accountIdentification.clearingNumber` — обязательное поле без роли: в payload попало с TODO и значением по умолчанию, значение подставит человек
- `post-transfers: counterparty.bankAccount.accountIdentification.sortCode` — обязательное поле без роли: в payload попало с TODO и значением по умолчанию, значение подставит человек
- `post-transfers: counterparty.bankAccount.accountIdentification.routingNumber` — обязательное поле без роли: в payload попало с TODO и значением по умолчанию, значение подставит человек
- `post-transfers: counterparty.card.cardHolder.address.country` — обязательное поле без роли: в payload попало с TODO и значением по умолчанию, значение подставит человек
- `post-transfers: counterparty.card.cardHolder.type` — роль recipient_type выведена, но выражения платформы для неё нет ни в accessors, ни в requisites (rules/contract.yml, раздел platform) — добавьте его туда или заполните поле вручную
- `post-transfers: type` — роль recipient_type выведена, но выражения платформы для неё нет ни в accessors, ни в requisites (rules/contract.yml, раздел platform) — добавьте его туда или заполните поле вручную
- `post-transfers: ultimateParty.address.country` — обязательное поле без роли: в payload попало с TODO и значением по умолчанию, значение подставит человек
- `post-transfers: ultimateParty.type` — роль recipient_type выведена, но выражения платформы для неё нет ни в accessors, ни в requisites (rules/contract.yml, раздел platform) — добавьте его туда или заполните поле вручную

**Статусы** — не покрыто 34

- `Active` — нет пары среди внутренних статусов: в STATUS_MAP nil
- `Authorised` — нет пары среди внутренних статусов: в STATUS_MAP nil
- `Repaid` — нет пары среди внутренних статусов: в STATUS_MAP nil
- `WrittenOff` — нет пары среди внутренних статусов: в STATUS_MAP nil
- `atmWithdrawal` — нет пары среди внутренних статусов: в STATUS_MAP nil
- `atmWithdrawalReversed` — нет пары среди внутренних статусов: в STATUS_MAP nil
- `authAdjustmentAuthorised` — нет пары среди внутренних статусов: в STATUS_MAP nil
- `authorised` — нет пары среди внутренних статусов: в STATUS_MAP nil
- `bankTransfer` — нет пары среди внутренних статусов: в STATUS_MAP nil
- `captureReversed` — нет пары среди внутренних статусов: в STATUS_MAP nil
- `chargeback` — нет пары среди внутренних статусов: в STATUS_MAP nil
- `chargebackExternally` — нет пары среди внутренних статусов: в STATUS_MAP nil
- `chargebackReversed` — нет пары среди внутренних статусов: в STATUS_MAP nil
- `depositCorrection` — нет пары среди внутренних статусов: в STATUS_MAP nil
- `dispute` — нет пары среди внутренних статусов: в STATUS_MAP nil
- `disputeClosed` — нет пары среди внутренних статусов: в STATUS_MAP nil
- `disputeNeedsReview` — нет пары среди внутренних статусов: в STATUS_MAP nil
- `fee` — нет пары среди внутренних статусов: в STATUS_MAP nil
- `interchangeAdjusted` — нет пары среди внутренних статусов: в STATUS_MAP nil
- `internalTransfer` — нет пары среди внутренних статусов: в STATUS_MAP nil
- `invoiceDeduction` — нет пары среди внутренних статусов: в STATUS_MAP nil
- `manuallyCorrected` — нет пары среди внутренних статусов: в STATUS_MAP nil
- `matchedStatement` — нет пары среди внутренних статусов: в STATUS_MAP nil
- `merchantPayin` — нет пары среди внутренних статусов: в STATUS_MAP nil
- `merchantPayinReversed` — нет пары среди внутренних статусов: в STATUS_MAP nil
- `miscCost` — нет пары среди внутренних статусов: в STATUS_MAP nil
- `paymentCost` — нет пары среди внутренних статусов: в STATUS_MAP nil
- `refundReversed` — нет пары среди внутренних статусов: в STATUS_MAP nil
- `refunded` — нет пары среди внутренних статусов: в STATUS_MAP nil
- `refundedExternally` — нет пары среди внутренних статусов: в STATUS_MAP nil
- `reserveAdjustment` — нет пары среди внутренних статусов: в STATUS_MAP nil
- `reversed` — нет пары среди внутренних статусов: в STATUS_MAP nil
- `secondChargeback` — нет пары среди внутренних статусов: в STATUS_MAP nil
- `undefined` — нет пары среди внутренних статусов: в STATUS_MAP nil

**Условия взаимодействия** — не покрыто 13

- `field_enum type` — проверка не сгенерирована: у платформы нет выражения для поля type
- `field_max_length bsbCode` — проверка не сгенерирована: у платформы нет выражения для поля bsbCode
- `field_enum type` — проверка не сгенерирована: у платформы нет выражения для поля type
- `field_max_length bankCode` — проверка не сгенерирована: у платформы нет выражения для поля bankCode
- `field_enum accountType` — проверка не сгенерирована: у платформы нет выражения для поля accountType
- `field_max_length institutionNumber` — проверка не сгенерирована: у платформы нет выражения для поля institutionNumber
- `field_max_length clearingCode` — проверка не сгенерирована: у платформы нет выражения для поля clearingCode
- `field_enum type` — проверка не сгенерирована: у платформы нет выражения для поля type
- `field_max_length clearingNumber` — проверка не сгенерирована: у платформы нет выражения для поля clearingNumber
- `field_max_length sortCode` — проверка не сгенерирована: у платформы нет выражения для поля sortCode
- `field_max_length routingNumber` — проверка не сгенерирована: у платформы нет выражения для поля routingNumber
- `field_enum type` — проверка не сгенерирована: у платформы нет выражения для поля type
- `field_enum type` — проверка не сгенерирована: у платформы нет выражения для поля type

**Вне контракта — 86.** Ресурсы спецификации, которых методы контракта не
касаются вовсе: чужие операции и их поля, коды и схемы. Контракт про выплаты;
считать пробелом интеграции отсутствие в ней подписок, споров или хранения
карт — то же самое, что считать пробелом отсутствие метода для чужого API.
Свёрнуто числом с примерами.

- **Операции** — 5, например: `get-grants`, `post-grants`, `get-grants-id`
- **Поля тел запросов** — 11, например: `post-grants: counterparty.balanceAccountId`, `post-grants: grantAccountId`, `post-grants: grantOfferId`
- **Поля тел ответов и уведомлений** — 70, например: `CapitalGrants.grants`, `RestServiceError.detail`, `RestServiceError.instance`

**Структурные исключения метрики — 317.** Элементы, которым в методах
контракта нет места по построению: поле входящего тела засчитывается, только
когда его роль читает один из четырёх методов; необязательное поле без роли в
payload не идёт намеренно; код, объявленный диапазоном, ветки не даёт. Это
устройство метрики и контракта, а не пропуск разбора. Свёрнуто числом с
примерами.

- **Поля тел запросов** — 61, например: `post-transfers: balanceAccountId`, `post-transfers: counterparty.balanceAccountId`, `post-transfers: counterparty.bankAccount.accountHolder.address.city`
- **Поля тел ответов и уведомлений** — 256, например: `TransferServiceRestServiceError.detail`, `TransferServiceRestServiceError.instance`, `TransferServiceRestServiceError.invalidFields`

## 3. Неоднозначности

Элементы, о которых спецификация говорит недостаточно, чтобы решение было
однозначным. Инструмент решил сам — что именно, сказано под каждым кодом; от
человека нужна проверка, а не заполнение пропуска.

### `auth_multiple_schemes` — 1

Что сделал инструмент: взята первая схема авторизации спецификации

- **`$.components.securitySchemes`** — схем авторизации в спецификации: 3; выбрана ApiKeyAuth, её требуют 11 операций; не используются: BasicAuth ($.components.securitySchemes.BasicAuth), clientKey ($.components.securitySchemes.clientKey)
  готового overlay-фрагмента нет: закрепляется записью в `rules/auth.yml` или правкой спецификации

### `currency_unknown` — 1

Что сделал инструмент: валюта не подставлена, множитель суммы по умолчанию

- **`$.components.schemas.Amount.properties.value`** — валюта суммы не выведена (поле `currency` совпало с ролью currency, но не задаёт ни enum, ни default, ни example); без кода валюты экспоненту ISO 4217 определить нельзя — задайте валюту в overlay

  ```yaml
  - target: "$.components.schemas.Amount.properties.value"
    update:
      x-specgen-currency: RUB  # код ISO 4217
  ```

### `field_role_low_confidence` — 50

Что сделал инструмент: роль присвоена лучшему кандидату, в коде рядом с полем — комментарий с уверенностью

- **`$.components.schemas.RestServiceError.properties.type`** — обязательное поле `type`: роль recipient_type выведена с низкой уверенностью 0.25 (порог 0.60); кандидаты: recipient_type 0.25; без него запрос не уйдёт, поэтому в код оно попадёт как recipient_type с TODO — проверьте роль и закрепите её фрагментом ниже

  ```yaml
  - target: "$.components.schemas.RestServiceError.properties.type"
    update:
      x-specgen-role: recipient_type  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.TransferEvent.properties.eventsData.items.properties.type`** — обязательное поле `type`: роль recipient_type выведена с низкой уверенностью 0.25 (порог 0.60); кандидаты: recipient_type 0.25; без него запрос не уйдёт, поэтому в код оно попадёт как recipient_type с TODO — проверьте роль и закрепите её фрагментом ниже

  ```yaml
  - target: "$.components.schemas.TransferEvent.properties.eventsData.items.properties.type"
    update:
      x-specgen-role: recipient_type  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.TransferEvent.properties.tracingData.properties.type`** — обязательное поле `type`: роль recipient_type выведена с низкой уверенностью 0.25 (порог 0.60); кандидаты: recipient_type 0.25; без него запрос не уйдёт, поэтому в код оно попадёт как recipient_type с TODO — проверьте роль и закрепите её фрагментом ниже

  ```yaml
  - target: "$.components.schemas.TransferEvent.properties.tracingData.properties.type"
    update:
      x-specgen-role: recipient_type  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.TransferEvent.properties.trackingData.properties.type`** — обязательное поле `type`: роль recipient_type выведена с низкой уверенностью 0.25 (порог 0.60); кандидаты: recipient_type 0.25; без него запрос не уйдёт, поэтому в код оно попадёт как recipient_type с TODO — проверьте роль и закрепите её фрагментом ниже

  ```yaml
  - target: "$.components.schemas.TransferEvent.properties.trackingData.properties.type"
    update:
      x-specgen-role: recipient_type  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.TransferServiceRestServiceError.properties.type`** — обязательное поле `type`: роль recipient_type выведена с низкой уверенностью 0.25 (порог 0.60); кандидаты: recipient_type 0.25; без него запрос не уйдёт, поэтому в код оно попадёт как recipient_type с TODO — проверьте роль и закрепите её фрагментом ниже

  ```yaml
  - target: "$.components.schemas.TransferServiceRestServiceError.properties.type"
    update:
      x-specgen-role: recipient_type  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.paths['/transactions'].get.parameters[5]`** — обязательный параметр `createdSince` (query): роль created_at выведена с низкой уверенностью 0.21 (порог 0.60); кандидаты: created_at 0.21; без него запрос не уйдёт, поэтому в код оно попадёт как created_at с TODO — проверьте роль и закрепите её фрагментом ниже

  ```yaml
  - target: "$.paths['/transactions'].get.parameters[5]"
    update:
      x-specgen-role: created_at  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.paths['/transfers'].get.parameters[6]`** — обязательный параметр `createdSince` (query): роль created_at выведена с низкой уверенностью 0.21 (порог 0.60); кандидаты: created_at 0.21; без него запрос не уйдёт, поэтому в код оно попадёт как created_at с TODO — проверьте роль и закрепите её фрагментом ниже

  ```yaml
  - target: "$.paths['/transfers'].get.parameters[6]"
    update:
      x-specgen-role: created_at  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.BankAccountV3.properties.storedPaymentMethodId`** — необязательное поле `storedPaymentMethodId`: роль provider_operation_id выведена с низкой уверенностью 0.21 (порог 0.60); кандидаты: provider_operation_id 0.21, recipient_type 0.21; в коде оно будет помечено TODO — проверьте роль и закрепите её фрагментом ниже

  ```yaml
  - target: "$.components.schemas.BankAccountV3.properties.storedPaymentMethodId"
    update:
      x-specgen-role: provider_operation_id  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.CardIdentification.properties.storedPaymentMethodId`** — необязательное поле `storedPaymentMethodId`: роль provider_operation_id выведена с низкой уверенностью 0.21 (порог 0.60); кандидаты: provider_operation_id 0.21, recipient_type 0.21; в коде оно будет помечено TODO — проверьте роль и закрепите её фрагментом ниже

  ```yaml
  - target: "$.components.schemas.CardIdentification.properties.storedPaymentMethodId"
    update:
      x-specgen-role: provider_operation_id  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.CashOutInfoCounterparty.properties.transferInstrumentId`** — необязательное поле `transferInstrumentId`: роль provider_operation_id выведена с низкой уверенностью 0.26 (порог 0.60); кандидаты: provider_operation_id 0.26; в коде оно будет помечено TODO — проверьте роль и закрепите её фрагментом ниже

  ```yaml
  - target: "$.components.schemas.CashOutInfoCounterparty.properties.transferInstrumentId"
    update:
      x-specgen-role: provider_operation_id  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.CounterpartyInfoV3.properties.transferInstrumentId`** — необязательное поле `transferInstrumentId`: роль provider_operation_id выведена с низкой уверенностью 0.26 (порог 0.60); кандидаты: provider_operation_id 0.26; в коде оно будет помечено TODO — проверьте роль и закрепите её фрагментом ниже

  ```yaml
  - target: "$.components.schemas.CounterpartyInfoV3.properties.transferInstrumentId"
    update:
      x-specgen-role: provider_operation_id  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.CounterpartyV3.properties.transferInstrumentId`** — необязательное поле `transferInstrumentId`: роль provider_operation_id выведена с низкой уверенностью 0.26 (порог 0.60); кандидаты: provider_operation_id 0.26; в коде оно будет помечено TODO — проверьте роль и закрепите её фрагментом ниже

  ```yaml
  - target: "$.components.schemas.CounterpartyV3.properties.transferInstrumentId"
    update:
      x-specgen-role: provider_operation_id  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.DefaultErrorResponseEntity.properties.type`** — необязательное поле `type`: роль recipient_type выведена с низкой уверенностью 0.25 (порог 0.60); кандидаты: recipient_type 0.25; в коде оно будет помечено TODO — проверьте роль и закрепите её фрагментом ниже

  ```yaml
  - target: "$.components.schemas.DefaultErrorResponseEntity.properties.type"
    update:
      x-specgen-role: recipient_type  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.DirectDebitInformation.properties.dateOfSignature`** — необязательное поле `dateOfSignature`: роль signature выведена с низкой уверенностью 0.43 (порог 0.60); кандидаты: signature 0.43; в коде оно будет помечено TODO — проверьте роль и закрепите её фрагментом ниже

  ```yaml
  - target: "$.components.schemas.DirectDebitInformation.properties.dateOfSignature"
    update:
      x-specgen-role: signature  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.FundingInstrument.properties.reference`** — необязательное поле `reference`: роль external_id выведена с низкой уверенностью 0.21 (порог 0.60); кандидаты: external_id 0.21, provider_operation_id 0.21; в коде оно будет помечено TODO — проверьте роль и закрепите её фрагментом ниже

  ```yaml
  - target: "$.components.schemas.FundingInstrument.properties.reference"
    update:
      x-specgen-role: external_id  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.GrantCounterparty.properties.transferInstrumentId`** — необязательное поле `transferInstrumentId`: роль provider_operation_id выведена с низкой уверенностью 0.26 (порог 0.60); кандидаты: provider_operation_id 0.26; в коде оно будет помечено TODO — проверьте роль и закрепите её фрагментом ниже

  ```yaml
  - target: "$.components.schemas.GrantCounterparty.properties.transferInstrumentId"
    update:
      x-specgen-role: provider_operation_id  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.GrantInfoCounterparty.properties.transferInstrumentId`** — необязательное поле `transferInstrumentId`: роль provider_operation_id выведена с низкой уверенностью 0.26 (порог 0.60); кандидаты: provider_operation_id 0.26; в коде оно будет помечено TODO — проверьте роль и закрепите её фрагментом ниже

  ```yaml
  - target: "$.components.schemas.GrantInfoCounterparty.properties.transferInstrumentId"
    update:
      x-specgen-role: provider_operation_id  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.InternalCategoryData.properties.modificationMerchantReference`** — необязательное поле `modificationMerchantReference`: роль external_id выведена с низкой уверенностью 0.26 (порог 0.60); кандидаты: external_id 0.26; в коде оно будет помечено TODO — проверьте роль и закрепите её фрагментом ниже

  ```yaml
  - target: "$.components.schemas.InternalCategoryData.properties.modificationMerchantReference"
    update:
      x-specgen-role: external_id  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.InternalCategoryData.properties.modificationPspReference`** — необязательное поле `modificationPspReference`: роль provider_operation_id выведена с низкой уверенностью 0.26 (порог 0.60); кандидаты: provider_operation_id 0.26; в коде оно будет помечено TODO — проверьте роль и закрепите её фрагментом ниже

  ```yaml
  - target: "$.components.schemas.InternalCategoryData.properties.modificationPspReference"
    update:
      x-specgen-role: provider_operation_id  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.IssuedCard.properties.schemeUniqueTransactionId`** — необязательное поле `schemeUniqueTransactionId`: роль idempotency_key выведена с низкой уверенностью 0.24 (порог 0.60); кандидаты: idempotency_key 0.24, provider_operation_id 0.21; в коде оно будет помечено TODO — проверьте роль и закрепите её фрагментом ниже

  ```yaml
  - target: "$.components.schemas.IssuedCard.properties.schemeUniqueTransactionId"
    update:
      x-specgen-role: idempotency_key  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- и ещё 30 с тем же кодом

### `idempotency_dedup_unclear` — 1

Что сделал инструмент: ветка дедупликации не сгенерирована: ответ с кодом конфликта пойдёт как ошибка

- **`$.paths['/grants'].post`** — заголовок Idempotency-Key объявлен, но ни одна операция не описывает ответ 409 со схемой успешного ответа; при повторе сервис не отличит дубль от ошибки — уточните у провайдера или опишите ответ в overlay

  ```yaml
  - target: "$.paths['/grants'].post.responses"
    update:
      '409':
        description: Duplicate idempotency key, previous result returned
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/CapitalGrant'
  ```

### `operation_role_ambiguous` — 1

Что сделал инструмент: взят лучший кандидат роли, метод сгенерирован по нему

- **`$.paths['/transfers/{transferId}/returns'].post`** — две роли подходят этой операции почти одинаково; взята первая, но выбор стоит подтвердить (refund 9.5, create_payout 8.5, cancel 7.5 из 14.0 поданных голосов); переопределить — в overlay
  готового overlay-фрагмента нет: закрепляется записью в `rules/operations.yml` или правкой спецификации

### `operation_tie` — 1

Что сделал инструмент: ничья разрешена связью с ресурсом, а где её нет — порядком объявления

- **`$.paths['/transfers/{id}'].get`** — на роль fetch_status претендует несколько операций с одинаковой уверенностью 0.95 (get-transactions-id (GET /transactions/{id}), get-transfers-id (GET /transfers/{id})); взята get-transfers-id: её связывает с post-transfers общий контейнер ресурса `transfers`, путь продолжает путь создания
  готового overlay-фрагмента нет: исправляется правкой спецификации

### `required_field_role_unknown` — 41

Что сделал инструмент: в исходящем теле поле включено в payload со значением примера или nil и TODO рядом; во входящем — ищется структурно

- **`$.components.schemas.AULocalAccountIdentification.properties.accountNumber`** — обязательное поле `accountNumber` (string, min_length 5, max_length 9): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; без него запрос не уйдёт, поэтому в код оно попадёт с TODO — задайте роль фрагментом ниже или добавьте синоним в rules/roles.yml

  ```yaml
  - target: "$.components.schemas.AULocalAccountIdentification.properties.accountNumber"
    update:
      x-specgen-role: TODO  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.Address.properties.country`** — обязательное поле `country` (string): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; без него запрос не уйдёт, поэтому в код оно попадёт с TODO — задайте роль фрагментом ниже или добавьте синоним в rules/roles.yml

  ```yaml
  - target: "$.components.schemas.Address.properties.country"
    update:
      x-specgen-role: TODO  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.BRLocalAccountIdentification.properties.accountNumber`** — обязательное поле `accountNumber` (string, min_length 1, max_length 10): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; без него запрос не уйдёт, поэтому в код оно попадёт с TODO — задайте роль фрагментом ниже или добавьте синоним в rules/roles.yml

  ```yaml
  - target: "$.components.schemas.BRLocalAccountIdentification.properties.accountNumber"
    update:
      x-specgen-role: TODO  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.BRLocalAccountIdentification.properties.branchNumber`** — обязательное поле `branchNumber` (string, min_length 1, max_length 4): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; без него запрос не уйдёт, поэтому в код оно попадёт с TODO — задайте роль фрагментом ниже или добавьте синоним в rules/roles.yml

  ```yaml
  - target: "$.components.schemas.BRLocalAccountIdentification.properties.branchNumber"
    update:
      x-specgen-role: TODO  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.CALocalAccountIdentification.properties.accountNumber`** — обязательное поле `accountNumber` (string, min_length 5, max_length 12): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; без него запрос не уйдёт, поэтому в код оно попадёт с TODO — задайте роль фрагментом ниже или добавьте синоним в rules/roles.yml

  ```yaml
  - target: "$.components.schemas.CALocalAccountIdentification.properties.accountNumber"
    update:
      x-specgen-role: TODO  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.CALocalAccountIdentification.properties.transitNumber`** — обязательное поле `transitNumber` (string, min_length 5, max_length 5): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; без него запрос не уйдёт, поэтому в код оно попадёт с TODO — задайте роль фрагментом ниже или добавьте синоним в rules/roles.yml

  ```yaml
  - target: "$.components.schemas.CALocalAccountIdentification.properties.transitNumber"
    update:
      x-specgen-role: TODO  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.CZLocalAccountIdentification.properties.accountNumber`** — обязательное поле `accountNumber` (string, min_length 2, max_length 17): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; без него запрос не уйдёт, поэтому в код оно попадёт с TODO — задайте роль фрагментом ниже или добавьте синоним в rules/roles.yml

  ```yaml
  - target: "$.components.schemas.CZLocalAccountIdentification.properties.accountNumber"
    update:
      x-specgen-role: TODO  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.CapitalBalance.properties.fee`** — обязательное поле `fee` (integer, format int64): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; без него запрос не уйдёт, поэтому в код оно попадёт с TODO — задайте роль фрагментом ниже или добавьте синоним в rules/roles.yml

  ```yaml
  - target: "$.components.schemas.CapitalBalance.properties.fee"
    update:
      x-specgen-role: TODO  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.CapitalBalance.properties.principal`** — обязательное поле `principal` (integer, format int64): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; без него запрос не уйдёт, поэтому в код оно попадёт с TODO — задайте роль фрагментом ниже или добавьте синоним в rules/roles.yml

  ```yaml
  - target: "$.components.schemas.CapitalBalance.properties.principal"
    update:
      x-specgen-role: TODO  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.CapitalGrant.properties.grantAccountId`** — обязательное поле `grantAccountId` (string): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; без него запрос не уйдёт, поэтому в код оно попадёт с TODO — задайте роль фрагментом ниже или добавьте синоним в rules/roles.yml

  ```yaml
  - target: "$.components.schemas.CapitalGrant.properties.grantAccountId"
    update:
      x-specgen-role: TODO  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.CapitalGrant.properties.grantOfferId`** — обязательное поле `grantOfferId` (string): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; без него запрос не уйдёт, поэтому в код оно попадёт с TODO — задайте роль фрагментом ниже или добавьте синоним в rules/roles.yml

  ```yaml
  - target: "$.components.schemas.CapitalGrant.properties.grantOfferId"
    update:
      x-specgen-role: TODO  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.CapitalGrantInfo.properties.grantAccountId`** — обязательное поле `grantAccountId` (string): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; без него запрос не уйдёт, поэтому в код оно попадёт с TODO — задайте роль фрагментом ниже или добавьте синоним в rules/roles.yml

  ```yaml
  - target: "$.components.schemas.CapitalGrantInfo.properties.grantAccountId"
    update:
      x-specgen-role: TODO  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.CapitalGrantInfo.properties.grantOfferId`** — обязательное поле `grantOfferId` (string): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; без него запрос не уйдёт, поэтому в код оно попадёт с TODO — задайте роль фрагментом ниже или добавьте синоним в rules/roles.yml

  ```yaml
  - target: "$.components.schemas.CapitalGrantInfo.properties.grantOfferId"
    update:
      x-specgen-role: TODO  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.CashOut.properties.instructingBalanceAccountId`** — обязательное поле `instructingBalanceAccountId` (string): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; без него запрос не уйдёт, поэтому в код оно попадёт с TODO — задайте роль фрагментом ниже или добавьте синоним в rules/roles.yml

  ```yaml
  - target: "$.components.schemas.CashOut.properties.instructingBalanceAccountId"
    update:
      x-specgen-role: TODO  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.CashOutInfo.properties.instructingBalanceAccountId`** — обязательное поле `instructingBalanceAccountId` (string): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; без него запрос не уйдёт, поэтому в код оно попадёт с TODO — задайте роль фрагментом ниже или добавьте синоним в rules/roles.yml

  ```yaml
  - target: "$.components.schemas.CashOutInfo.properties.instructingBalanceAccountId"
    update:
      x-specgen-role: TODO  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.DKLocalAccountIdentification.properties.accountNumber`** — обязательное поле `accountNumber` (string, min_length 4, max_length 10): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; без него запрос не уйдёт, поэтому в код оно попадёт с TODO — задайте роль фрагментом ниже или добавьте синоним в rules/roles.yml

  ```yaml
  - target: "$.components.schemas.DKLocalAccountIdentification.properties.accountNumber"
    update:
      x-specgen-role: TODO  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.EstimationTrackingData.properties.estimatedArrivalTime`** — обязательное поле `estimatedArrivalTime` (string, format date-time): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; без него запрос не уйдёт, поэтому в код оно попадёт с TODO — задайте роль фрагментом ниже или добавьте синоним в rules/roles.yml

  ```yaml
  - target: "$.components.schemas.EstimationTrackingData.properties.estimatedArrivalTime"
    update:
      x-specgen-role: TODO  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.HKLocalAccountIdentification.properties.accountNumber`** — обязательное поле `accountNumber` (string, min_length 9, max_length 17): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; без него запрос не уйдёт, поэтому в код оно попадёт с TODO — задайте роль фрагментом ниже или добавьте синоним в rules/roles.yml

  ```yaml
  - target: "$.components.schemas.HKLocalAccountIdentification.properties.accountNumber"
    update:
      x-specgen-role: TODO  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.HULocalAccountIdentification.properties.accountNumber`** — обязательное поле `accountNumber` (string, min_length 24, max_length 24): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; без него запрос не уйдёт, поэтому в код оно попадёт с TODO — задайте роль фрагментом ниже или добавьте синоним в rules/roles.yml

  ```yaml
  - target: "$.components.schemas.HULocalAccountIdentification.properties.accountNumber"
    update:
      x-specgen-role: TODO  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.IbanAccountIdentification.properties.iban`** — обязательное поле `iban` (string): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; без него запрос не уйдёт, поэтому в код оно попадёт с TODO — задайте роль фрагментом ниже или добавьте синоним в rules/roles.yml

  ```yaml
  - target: "$.components.schemas.IbanAccountIdentification.properties.iban"
    update:
      x-specgen-role: TODO  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- и ещё 21 с тем же кодом

### `schema_unresolved` — 2

Что сделал инструмент: схема не разобрана: её поля в код не попали

- **`$.paths['/transfers/approve'].post.responses['200'].content['application/json'].schema`** — у тела post-transfers-approve не объявлено читаемой схемы, поэтому ничто не описывает, что оно переносит
  готового overlay-фрагмента нет: исправляется правкой спецификации
- **`$.paths['/transfers/cancel'].post.responses['200'].content['application/json'].schema`** — у тела post-transfers-cancel не объявлено читаемой схемы, поэтому ничто не описывает, что оно переносит
  готового overlay-фрагмента нет: исправляется правкой спецификации

### `spec_element_unsupported` — 11

Что сделал инструмент: значение расширения отвергнуто, элемент разобран без него

- **`$.components.schemas.JSONObject`** — схема объявлена объектом, но не объявляет свойств, поэтому собрать из неё нечего
  готового overlay-фрагмента нет: исправляется правкой спецификации
- **`$.components.schemas.BankAccountV3.properties.accountIdentification`** — `oneOf` из 16 вариантов выбирается полем `type` (значения: auLocal, brLocal, caLocal, czLocal, dkLocal, hkLocal, huLocal, iban, noLocal, nzLocal, numberAndBic, plLocal, seLocal, sgLocal, ukLocal, usLocal): `discriminator` назвал и поле, и то, какие поля обязательны при каждом его значении
  готового overlay-фрагмента нет: исправляется правкой спецификации
- **`$.components.schemas.RelayedAuthorisationData.properties.metadata`** — `metadata` — свободная карта (`additionalProperties` или объект без `properties`): ключи спецификацией не перечислены, поэтому значением поля остаётся хеш, который заполняют вручную
  готового overlay-фрагмента нет: исправляется правкой спецификации
- **`$.components.schemas.Transfer.properties.categoryData`** — `oneOf` из 4 вариантов (bank, internal, issuedCard, platformPayment) разложен: свойства всех вариантов есть в IR и помечены своим вариантом, но обязательным не стало ни одно — какой вариант отправлять, спецификация не говорит
  готового overlay-фрагмента нет: исправляется правкой спецификации
- **`$.components.schemas.TransferData.properties.categoryData`** — `oneOf` из 4 вариантов (bank, internal, issuedCard, platformPayment) разложен: свойства всех вариантов есть в IR и помечены своим вариантом, но обязательным не стало ни одно — какой вариант отправлять, спецификация не говорит
  готового overlay-фрагмента нет: исправляется правкой спецификации
- **`$.components.schemas.TransferData.properties.tracing`** — `oneOf` из 2 вариантов выбирается полем `type` (значения: ukFps, usAch): `discriminator` назвал и поле, и то, какие поля обязательны при каждом его значении
  готового overlay-фрагмента нет: исправляется правкой спецификации
- **`$.components.schemas.TransferData.properties.tracking`** — `oneOf` из 3 вариантов выбирается полем `type` (значения: confirmation, estimation, internalReview): `discriminator` назвал и поле, и то, какие поля обязательны при каждом его значении
  готового overlay-фрагмента нет: исправляется правкой спецификации
- **`$.components.schemas.TransferEvent.properties.eventsData.items`** — `oneOf` из 3 вариантов (interchangeData, issuingTransactionData, merchantPurchaseData) разложен: свойства всех вариантов есть в IR и помечены своим вариантом, но обязательным не стало ни одно — какой вариант отправлять, спецификация не говорит
  готового overlay-фрагмента нет: исправляется правкой спецификации
- **`$.components.schemas.TransferEvent.properties.tracingData`** — `oneOf` из 2 вариантов выбирается полем `type` (значения: ukFps, usAch): `discriminator` назвал и поле, и то, какие поля обязательны при каждом его значении
  готового overlay-фрагмента нет: исправляется правкой спецификации
- **`$.components.schemas.TransferEvent.properties.trackingData`** — `oneOf` из 3 вариантов выбирается полем `type` (значения: confirmation, estimation, internalReview): `discriminator` назвал и поле, и то, какие поля обязательны при каждом его значении
  готового overlay-фрагмента нет: исправляется правкой спецификации
- **`$.components.schemas.TransferView.properties.categoryData`** — `oneOf` из 4 вариантов (bank, internal, issuedCard, platformPayment) разложен: свойства всех вариантов есть в IR и помечены своим вариантом, но обязательным не стало ни одно — какой вариант отправлять, спецификация не говорит
  готового overlay-фрагмента нет: исправляется правкой спецификации

### `status_unmapped` — 34

Что сделал инструмент: в STATUS_MAP значение nil и TODO: сервис вернёт отказ status_unknown

- **`$.components.schemas.CapitalGrant.properties.status.enum[1]`** — статус active неоднозначен: состояние сущности (счёта, ключа, подписки), а не операции: у операции «активна» значит и «идёт», и «доступна к отмене»; выберите внутренний статус (in_progress | approved | rejected) в overlay

  ```yaml
  - target: "$.components.schemas.CapitalGrant.properties.status"
    update:
      x-specgen-status-map:
        Active: in_progress  # in_progress | approved | rejected
  ```
- **`$.components.schemas.CapitalGrant.properties.status.enum[2]`** — статус Repaid не найден ни в каноне, ни среди синонимов rules/statuses.yml; выберите внутренний статус в overlay или добавьте синоним в справочник

  ```yaml
  - target: "$.components.schemas.CapitalGrant.properties.status"
    update:
      x-specgen-status-map:
        Repaid: in_progress  # in_progress | approved | rejected
  ```
- **`$.components.schemas.CapitalGrant.properties.status.enum[4]`** — статус WrittenOff не найден ни в каноне, ни среди синонимов rules/statuses.yml; выберите внутренний статус в overlay или добавьте синоним в справочник

  ```yaml
  - target: "$.components.schemas.CapitalGrant.properties.status"
    update:
      x-specgen-status-map:
        WrittenOff: in_progress  # in_progress | approved | rejected
  ```
- **`$.components.schemas.ReturnTransferResponse.properties.status.enum[0]`** — статус authorised неоднозначен: британское написание authorized; у Adyen это «средства зарезервированы», у других — «списаны»; выберите внутренний статус (in_progress | approved | rejected) в overlay

  ```yaml
  - target: "$.components.schemas.ReturnTransferResponse.properties.status"
    update:
      x-specgen-status-map:
        Authorised: in_progress  # in_progress | approved | rejected
  ```
- **`$.components.schemas.TransferData.properties.status.enum[15]`** — событие captureReversed читается как статус reversed; статус reversed неоднозначен: успешная операция, затем развёрнута провайдером; выберите внутренний статус (in_progress | approved | rejected) в overlay

  ```yaml
  - target: "$.components.schemas.TransferData.properties.status"
    update:
      x-specgen-status-map:
        captureReversed: in_progress  # in_progress | approved | rejected
  ```
- **`$.components.schemas.TransferData.properties.status.enum[18]`** — статус chargeback неоднозначен: успешная операция, деньги отозваны держателем карты; выберите внутренний статус (in_progress | approved | rejected) в overlay

  ```yaml
  - target: "$.components.schemas.TransferData.properties.status"
    update:
      x-specgen-status-map:
        chargeback: in_progress  # in_progress | approved | rejected
  ```
- **`$.components.schemas.TransferData.properties.status.enum[19]`** — событие chargebackExternally читается как статус chargeback; статус chargeback неоднозначен: успешная операция, деньги отозваны держателем карты; выберите внутренний статус (in_progress | approved | rejected) в overlay

  ```yaml
  - target: "$.components.schemas.TransferData.properties.status"
    update:
      x-specgen-status-map:
        chargebackExternally: in_progress  # in_progress | approved | rejected
  ```
- **`$.components.schemas.TransferData.properties.status.enum[1]`** — значение atmWithdrawal называет тип операции, а не её исход: слово `withdrawal` из not_status_words rules/statuses.yml; похоже, что в одном enum смешаны статусы и виды проводки; проверьте enum: если это всё-таки статусы, задайте их в overlay, иначе поле статусом не является

  ```yaml
  - target: "$.components.schemas.TransferData.properties.status"
    update:
      x-specgen-status-map:
        atmWithdrawal: in_progress  # in_progress | approved | rejected
  ```
- **`$.components.schemas.TransferData.properties.status.enum[22]`** — событие chargebackReversed читается как статус reversed; статус reversed неоднозначен: успешная операция, затем развёрнута провайдером; выберите внутренний статус (in_progress | approved | rejected) в overlay

  ```yaml
  - target: "$.components.schemas.TransferData.properties.status"
    update:
      x-specgen-status-map:
        chargebackReversed: in_progress  # in_progress | approved | rejected
  ```
- **`$.components.schemas.TransferData.properties.status.enum[24]`** — значение depositCorrection называет тип операции, а не её исход: слово `correction` из not_status_words rules/statuses.yml; похоже, что в одном enum смешаны статусы и виды проводки; проверьте enum: если это всё-таки статусы, задайте их в overlay, иначе поле статусом не является

  ```yaml
  - target: "$.components.schemas.TransferData.properties.status"
    update:
      x-specgen-status-map:
        depositCorrection: in_progress  # in_progress | approved | rejected
  ```
- **`$.components.schemas.TransferData.properties.status.enum[26]`** — значение dispute называет тип операции, а не её исход: слово `dispute` из not_status_words rules/statuses.yml; похоже, что в одном enum смешаны статусы и виды проводки; проверьте enum: если это всё-таки статусы, задайте их в overlay, иначе поле статусом не является

  ```yaml
  - target: "$.components.schemas.TransferData.properties.status"
    update:
      x-specgen-status-map:
        dispute: in_progress  # in_progress | approved | rejected
  ```
- **`$.components.schemas.TransferData.properties.status.enum[27]`** — событие disputeClosed читается как статус closed; статус closed неоднозначен: закрыт спор, счёт или сессия — исход самой операции этим словом не назван; выберите внутренний статус (in_progress | approved | rejected) в overlay

  ```yaml
  - target: "$.components.schemas.TransferData.properties.status"
    update:
      x-specgen-status-map:
        disputeClosed: in_progress  # in_progress | approved | rejected
  ```
- **`$.components.schemas.TransferData.properties.status.enum[29]`** — значение disputeNeedsReview называет тип операции, а не её исход: слово `dispute` из not_status_words rules/statuses.yml; похоже, что в одном enum смешаны статусы и виды проводки; проверьте enum: если это всё-таки статусы, задайте их в overlay, иначе поле статусом не является

  ```yaml
  - target: "$.components.schemas.TransferData.properties.status"
    update:
      x-specgen-status-map:
        disputeNeedsReview: in_progress  # in_progress | approved | rejected
  ```
- **`$.components.schemas.TransferData.properties.status.enum[33]`** — значение fee называет тип операции, а не её исход: слово `fee` из not_status_words rules/statuses.yml; похоже, что в одном enum смешаны статусы и виды проводки; проверьте enum: если это всё-таки статусы, задайте их в overlay, иначе поле статусом не является

  ```yaml
  - target: "$.components.schemas.TransferData.properties.status"
    update:
      x-specgen-status-map:
        fee: in_progress  # in_progress | approved | rejected
  ```
- **`$.components.schemas.TransferData.properties.status.enum[35]`** — значение interchangeAdjusted называет тип операции, а не её исход: слово `adjusted` из not_status_words rules/statuses.yml; похоже, что в одном enum смешаны статусы и виды проводки; проверьте enum: если это всё-таки статусы, задайте их в overlay, иначе поле статусом не является

  ```yaml
  - target: "$.components.schemas.TransferData.properties.status"
    update:
      x-specgen-status-map:
        interchangeAdjusted: in_progress  # in_progress | approved | rejected
  ```
- **`$.components.schemas.TransferData.properties.status.enum[36]`** — значение internalTransfer называет тип операции, а не её исход: слово `transfer` из not_status_words rules/statuses.yml; похоже, что в одном enum смешаны статусы и виды проводки; проверьте enum: если это всё-таки статусы, задайте их в overlay, иначе поле статусом не является

  ```yaml
  - target: "$.components.schemas.TransferData.properties.status"
    update:
      x-specgen-status-map:
        internalTransfer: in_progress  # in_progress | approved | rejected
  ```
- **`$.components.schemas.TransferData.properties.status.enum[38]`** — значение invoiceDeduction называет тип операции, а не её исход: слово `deduction` из not_status_words rules/statuses.yml; похоже, что в одном enum смешаны статусы и виды проводки; проверьте enum: если это всё-таки статусы, задайте их в overlay, иначе поле статусом не является

  ```yaml
  - target: "$.components.schemas.TransferData.properties.status"
    update:
      x-specgen-status-map:
        invoiceDeduction: in_progress  # in_progress | approved | rejected
  ```
- **`$.components.schemas.TransferData.properties.status.enum[3]`** — событие atmWithdrawalReversed читается как статус reversed; статус reversed неоднозначен: успешная операция, затем развёрнута провайдером; выберите внутренний статус (in_progress | approved | rejected) в overlay

  ```yaml
  - target: "$.components.schemas.TransferData.properties.status"
    update:
      x-specgen-status-map:
        atmWithdrawalReversed: in_progress  # in_progress | approved | rejected
  ```
- **`$.components.schemas.TransferData.properties.status.enum[41]`** — значение manuallyCorrected называет тип операции, а не её исход: слово `corrected` из not_status_words rules/statuses.yml; похоже, что в одном enum смешаны статусы и виды проводки; проверьте enum: если это всё-таки статусы, задайте их в overlay, иначе поле статусом не является

  ```yaml
  - target: "$.components.schemas.TransferData.properties.status"
    update:
      x-specgen-status-map:
        manuallyCorrected: in_progress  # in_progress | approved | rejected
  ```
- **`$.components.schemas.TransferData.properties.status.enum[42]`** — значение matchedStatement называет тип операции, а не её исход: слово `statement` из not_status_words rules/statuses.yml; похоже, что в одном enum смешаны статусы и виды проводки; проверьте enum: если это всё-таки статусы, задайте их в overlay, иначе поле статусом не является

  ```yaml
  - target: "$.components.schemas.TransferData.properties.status"
    update:
      x-specgen-status-map:
        matchedStatement: in_progress  # in_progress | approved | rejected
  ```
- и ещё 14 с тем же кодом

### `webhook_missing` — 1

Что сделал инструмент: process_callback отказывает webhooks_not_supported: статус только опросом

- **`$.paths`** — спецификация не описывает входящих уведомлений (нет операции с security: [] и нет секции webhooks); статус операции сервис узнает только опросом через fetch_status
  готового overlay-фрагмента нет: исправляется правкой спецификации

### Как собрать overlay

Фрагменты выше — действия одного документа OpenAPI Overlay 1.0.0
(<https://spec.openapis.org/overlay/v1.0.0.html>). Соберите файл
`adyen_transfers_v4.overlay.yaml`, вставив их подряд под ключ `actions`,
замените значения `TODO` и перегенерируйте:

```yaml
overlay: 1.0.0
info:
  title: adyen_transfers_v4 disambiguation
  version: 1.0.0
actions:
- target: "$..."
  update:
    x-specgen-role: ...
```

```sh
./integrate --spec adyen_transfers_v4.yaml --provider adyen_transfers_v4 --overlay adyen_transfers_v4.overlay.yaml
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
| `get-grants` | `GET /grants` | не распознана (unmapped) | `grants()` | добавьте синоним пути или operationId в `rules/operations.yml` и перегенерируйте; расширения `x-specgen-role` для операции в модели нет (docs/IR.md, таблица расширений) |
| `post-grants` | `POST /grants` | не распознана (unmapped) | `post_grants(operation)` | добавьте синоним пути или operationId в `rules/operations.yml` и перегенерируйте; расширения `x-specgen-role` для операции в модели нет (docs/IR.md, таблица расширений) |
| `get-grants-id` | `GET /grants/{id}` | не распознана (unmapped) | `get_grants_id(operation)` | добавьте синоним пути или operationId в `rules/operations.yml` и перегенерируйте; расширения `x-specgen-role` для операции в модели нет (docs/IR.md, таблица расширений) |
| `get-transactions` | `GET /transactions` | не распознана (unmapped) | `transactions()` | добавьте синоним пути или operationId в `rules/operations.yml` и перегенерируйте; расширения `x-specgen-role` для операции в модели нет (docs/IR.md, таблица расширений) |
| `get-transactions-id` | `GET /transactions/{id}` | `fetch_status` (эвристика 0.95) | `get_transactions_id(operation)` | ничего: в `Provider::BaseService` нет метода для такой роли, платформа зовёт этот метод напрямую |
| `get-transfers` | `GET /transfers` | не распознана (unmapped) | `transfers()` | добавьте синоним пути или operationId в `rules/operations.yml` и перегенерируйте; расширения `x-specgen-role` для операции в модели нет (docs/IR.md, таблица расширений) |
| `post-transfers-approve` | `POST /transfers/approve` | `confirm` (эвристика 0.86) | `confirm(operation)` | ничего: в `Provider::BaseService` нет метода для такой роли, платформа зовёт этот метод напрямую |
| `post-transfers-cancel` | `POST /transfers/cancel` | `cancel` (эвристика 0.93) | `cancel(operation)` | ничего: в `Provider::BaseService` нет метода для такой роли, платформа зовёт этот метод напрямую |
| `post-transfers-transferId-returns` | `POST /transfers/{transferId}/returns` | `refund` (эвристика 0.68) | `refund(operation)` | ничего: в `Provider::BaseService` нет метода для такой роли, платформа зовёт этот метод напрямую |
| `post-cashouts` | `POST /cashouts` | `create_payout` (эвристика 0.81) | `post_cashouts(operation)` | ничего: в `Provider::BaseService` нет метода для такой роли, платформа зовёт этот метод напрямую |

## 5. Противоречия в самой спецификации

Спецификация расходится сама с собой или со своими соседями: enum против
примеров, коды ответов одной операции против другой, проза против структуры.
Инструмент выбрал, чему верить, и продолжил; правится это правкой
спецификации, а не настройкой инструмента.

### `field_role_conflict` — 40

Что сделал инструмент: роль оставлена полю с большей уверенностью, второе получило следующего кандидата

- **`$.components.schemas.TransferView.properties.reference`** — обязательное поле `reference`: роль provider_operation_id (0.50) уже у `id` (0.90) в той же схеме; взята следующая роль external_id (0.21) — проверьте оба поля и закрепите роли фрагментом ниже
- **`$.paths['/transactions'].get.parameters[6]`** — обязательный параметр `createdUntil` (query): роль created_at (0.21) уже у `createdSince` (0.21) в той же схеме; других кандидатов нет, роль не выведена — задайте её фрагментом ниже
- **`$.paths['/transfers'].get.parameters[7]`** — обязательный параметр `createdUntil` (query): роль created_at (0.21) уже у `createdSince` (0.21) в той же схеме; других кандидатов нет, роль не выведена — задайте её фрагментом ниже
- **`$.components.schemas.BankAccountV3.properties.accountIdentification.properties.accountType`** — необязательное поле `accountType`: роль recipient_type (0.90) уже у `type` (0.90) в той же схеме; других кандидатов нет, роль не выведена — задайте её фрагментом ниже
- **`$.components.schemas.BankAccountV3.properties.accountIdentification.properties.bankCode`** — необязательное поле `bankCode`: роль bank_code (0.90) уже у `bsbCode` (0.90) в той же схеме; других кандидатов нет, роль не выведена — задайте её фрагментом ниже
- **`$.components.schemas.BankAccountV3.properties.accountIdentification.properties.bsbCode`** — необязательное поле `bsbCode`: роль bank_code (0.90) уже у `bic` (0.90) в той же схеме; других кандидатов нет, роль не выведена — задайте её фрагментом ниже
- **`$.components.schemas.BankAccountV3.properties.accountIdentification.properties.clearingCode`** — необязательное поле `clearingCode`: роль bank_code (0.90) уже у `bsbCode` (0.90) в той же схеме; других кандидатов нет, роль не выведена — задайте её фрагментом ниже
- **`$.components.schemas.BankAccountV3.properties.accountIdentification.properties.clearingNumber`** — необязательное поле `clearingNumber`: роль bank_code (0.90) уже у `bic` (0.90) в той же схеме; других кандидатов нет, роль не выведена — задайте её фрагментом ниже
- **`$.components.schemas.BankAccountV3.properties.accountIdentification.properties.institutionNumber`** — необязательное поле `institutionNumber`: роль bank_code (0.90) уже у `bsbCode` (0.90) в той же схеме; других кандидатов нет, роль не выведена — задайте её фрагментом ниже
- **`$.components.schemas.BankAccountV3.properties.accountIdentification.properties.routingNumber`** — необязательное поле `routingNumber`: роль bank_code (0.90) уже у `bic` (0.90) в той же схеме; других кандидатов нет, роль не выведена — задайте её фрагментом ниже
- **`$.components.schemas.BankAccountV3.properties.accountIdentification.properties.sortCode`** — необязательное поле `sortCode`: роль bank_code (0.90) уже у `bic` (0.90) в той же схеме; других кандидатов нет, роль не выведена — задайте её фрагментом ниже
- **`$.components.schemas.CALocalAccountIdentification.properties.accountType`** — необязательное поле `accountType`: роль recipient_type (0.90) уже у `type` (0.90) в той же схеме; других кандидатов нет, роль не выведена — задайте её фрагментом ниже
- **`$.components.schemas.CashOut.properties.transferInstrumentId`** — необязательное поле `transferInstrumentId`: роль provider_operation_id (0.26) уже у `id` (0.90) в той же схеме; других кандидатов нет, роль не выведена — задайте её фрагментом ниже
- **`$.components.schemas.CashOutInfo.properties.transferInstrumentId`** — необязательное поле `transferInstrumentId`: роль provider_operation_id (0.26) уже у `id` (0.90) в той же схеме; других кандидатов нет, роль не выведена — задайте её фрагментом ниже
- **`$.components.schemas.PaymentInstrument.properties.reference`** — необязательное поле `reference`: роль provider_operation_id (0.50) уже у `id` (0.90) в той же схеме; взята следующая роль external_id (0.21) — проверьте оба поля и закрепите роли фрагментом ниже
- **`$.components.schemas.PlatformPayment.properties.modificationMerchantReference`** — необязательное поле `modificationMerchantReference`: роль external_id (0.26) уже у `paymentMerchantReference` (0.26) в той же схеме; других кандидатов нет, роль не выведена — задайте её фрагментом ниже
- **`$.components.schemas.PlatformPayment.properties.modificationPspReference`** — необязательное поле `modificationPspReference`: роль provider_operation_id (0.55) уже у `pspPaymentReference` (0.55) в той же схеме; других кандидатов нет, роль не выведена — задайте её фрагментом ниже
- **`$.components.schemas.PlatformPayment.properties.platformPaymentType`** — необязательное поле `platformPaymentType`: роль recipient_type (0.21) уже у `type` (0.90) в той же схеме; других кандидатов нет, роль не выведена — задайте её фрагментом ниже
- **`$.components.schemas.ReturnTransferResponse.properties.reference`** — необязательное поле `reference`: роль provider_operation_id (0.50) уже у `id` (0.90) в той же схеме; взята следующая роль external_id (0.21) — проверьте оба поля и закрепите роли фрагментом ниже
- **`$.components.schemas.ReturnTransferResponse.properties.transferId`** — необязательное поле `transferId`: роль provider_operation_id (0.90) уже у `id` (0.90) в той же схеме; других кандидатов нет, роль не выведена — задайте её фрагментом ниже
- и ещё 20 с тем же кодом

### `undeclared_status_code` — 11

Что сделал инструмент: для кода достроено общее правило ERROR_MAP по HTTP-коду

- **`$.paths['/grants'].get`** — операция get-grants не объявляет 429, объявленные у соседних операций (post-cashouts); для них достроены общие правила
- **`$.paths['/grants'].post`** — операция post-grants не объявляет 429, объявленные у соседних операций (post-cashouts); для них достроены общие правила
- **`$.paths['/grants/{id}'].get`** — операция get-grants-id не объявляет 429, объявленные у соседних операций (post-cashouts); для них достроены общие правила
- **`$.paths['/transactions'].get`** — операция get-transactions не объявляет 400, 404, 429, объявленные у соседних операций (get-grants, post-cashouts); для них достроены общие правила
- **`$.paths['/transactions/{id}'].get`** — операция get-transactions-id не объявляет 400, 404, 429, объявленные у соседних операций (get-grants, post-cashouts); для них достроены общие правила
- **`$.paths['/transfers'].get`** — операция get-transfers не объявляет 400, 404, 429, объявленные у соседних операций (get-grants, post-cashouts); для них достроены общие правила
- **`$.paths['/transfers'].post`** — операция post-transfers не объявляет 400, 404, 429, объявленные у соседних операций (get-grants, post-cashouts); для них достроены общие правила
- **`$.paths['/transfers/approve'].post`** — операция post-transfers-approve не объявляет 400, 404, 429, объявленные у соседних операций (get-grants, post-cashouts); для них достроены общие правила
- **`$.paths['/transfers/cancel'].post`** — операция post-transfers-cancel не объявляет 400, 404, 429, объявленные у соседних операций (get-grants, post-cashouts); для них достроены общие правила
- **`$.paths['/transfers/{id}'].get`** — операция get-transfers-id не объявляет 400, 404, 429, объявленные у соседних операций (get-grants, post-cashouts); для них достроены общие правила
- **`$.paths['/transfers/{transferId}/returns'].post`** — операция post-transfers-transferId-returns не объявляет 400, 404, 429, объявленные у соседних операций (get-grants, post-cashouts); для них достроены общие правила

## 6. Справки

Факты, о которых читателю стоит знать; решения за человека инструмент здесь не
принимал. Списки сокращены до первых 5 элементов в группе — полный набор
виден в `./integrate analyze --spec adyen_transfers_v4.yaml`.

**`field_role_unknown`** — 174

- `$.components.schemas.AdditionalBankIdentification.properties.code` — необязательное поле `code` (string): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; в запрос оно не попадёт; если оно нужно, задайте роль фрагментом ниже
- `$.components.schemas.Address.properties.city` — необязательное поле `city` (string, min_length 3): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; в запрос оно не попадёт; если оно нужно, задайте роль фрагментом ниже
- `$.components.schemas.Address.properties.line1` — необязательное поле `line1` (string): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; в запрос оно не попадёт; если оно нужно, задайте роль фрагментом ниже
- `$.components.schemas.Address.properties.line2` — необязательное поле `line2` (string): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; в запрос оно не попадёт; если оно нужно, задайте роль фрагментом ниже
- `$.components.schemas.Address.properties.postalCode` — необязательное поле `postalCode` (string, min_length 3): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; в запрос оно не попадёт; если оно нужно, задайте роль фрагментом ниже
- и ещё 169 с тем же кодом

**`operation_unmapped`** — 8, подробности в разделе 4

- `$.paths['/grants'].post` — в спецификации слишком мало признаков того, для чего эта операция, поэтому роль не присвоена (create_payout 3.0, create_deposit 3.0, webhook 3.0 из 3.0 поданных голосов); задайте роль в overlay
- `$.paths['/grants'].get` — больше всех голосов набрала роль fetch_status, но она отсечена по форме: ни в пути, ни в operationId нет ни одного платёжного существительного (vetoes.domain_nouns в rules/operations.yml); роль не присвоена, операция получает отдельный публичный метод
- `$.paths['/grants/{id}'].get` — больше всех голосов набрала роль fetch_status, но она отсечена по форме: ни в пути, ни в operationId нет ни одного платёжного существительного (vetoes.domain_nouns в rules/operations.yml); роль не присвоена, операция получает отдельный публичный метод
- `$.paths['/transactions'].get` — больше всех голосов набрала роль fetch_status, но она отсечена по форме: успешный ответ — список, то есть листинг ресурса, а не чтение одного экземпляра (vetoes.list_response в rules/operations.yml); роль не присвоена, операция получает отдельный публичный метод
- `$.paths['/transfers'].get` — больше всех голосов набрала роль fetch_status, но она отсечена по форме: успешный ответ — список, то есть листинг ресурса, а не чтение одного экземпляра (vetoes.list_response в rules/operations.yml); роль не присвоена, операция получает отдельный публичный метод
- и ещё 3 с тем же кодом

## 7. Что доделать руками

1. Заполните обязательное поле `category` в build_payload: роль не выведена (ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml) — добавьте синоним в `rules/roles.yml` или задайте `x-specgen-role` в overlay
2. Заполните обязательное поле `counterparty.bankAccount.accountHolder.address.country` в build_payload: роль не выведена (ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml) — добавьте синоним в `rules/roles.yml` или задайте `x-specgen-role` в overlay
3. Заполните обязательное поле `counterparty.bankAccount.accountIdentification.accountNumber` в build_payload: роль не выведена (ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml) — добавьте синоним в `rules/roles.yml` или задайте `x-specgen-role` в overlay
4. Заполните обязательное поле `counterparty.bankAccount.accountIdentification.bsbCode` в build_payload: роль не выведена (роль bank_code отдана `bic` (0.90); ) — добавьте синоним в `rules/roles.yml` или задайте `x-specgen-role` в overlay
5. Заполните обязательное поле `counterparty.bankAccount.accountIdentification.bankCode` в build_payload: роль не выведена (роль bank_code отдана `bsbCode` (0.90); ) — добавьте синоним в `rules/roles.yml` или задайте `x-specgen-role` в overlay
6. Заполните обязательное поле `counterparty.bankAccount.accountIdentification.branchNumber` в build_payload: роль не выведена (ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml) — добавьте синоним в `rules/roles.yml` или задайте `x-specgen-role` в overlay
7. Заполните обязательное поле `counterparty.bankAccount.accountIdentification.institutionNumber` в build_payload: роль не выведена (роль bank_code отдана `bsbCode` (0.90); ) — добавьте синоним в `rules/roles.yml` или задайте `x-specgen-role` в overlay
8. Заполните обязательное поле `counterparty.bankAccount.accountIdentification.transitNumber` в build_payload: роль не выведена (ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml) — добавьте синоним в `rules/roles.yml` или задайте `x-specgen-role` в overlay
9. Заполните обязательное поле `counterparty.bankAccount.accountIdentification.clearingCode` в build_payload: роль не выведена (роль bank_code отдана `bsbCode` (0.90); ) — добавьте синоним в `rules/roles.yml` или задайте `x-specgen-role` в overlay
10. Заполните обязательное поле `counterparty.bankAccount.accountIdentification.iban` в build_payload: роль не выведена (ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml) — добавьте синоним в `rules/roles.yml` или задайте `x-specgen-role` в overlay
11. Заполните обязательное поле `counterparty.bankAccount.accountIdentification.clearingNumber` в build_payload: роль не выведена (роль bank_code отдана `bic` (0.90); ) — добавьте синоним в `rules/roles.yml` или задайте `x-specgen-role` в overlay
12. Заполните обязательное поле `counterparty.bankAccount.accountIdentification.sortCode` в build_payload: роль не выведена (роль bank_code отдана `bic` (0.90); ) — добавьте синоним в `rules/roles.yml` или задайте `x-specgen-role` в overlay
13. Заполните обязательное поле `counterparty.bankAccount.accountIdentification.routingNumber` в build_payload: роль не выведена (роль bank_code отдана `bic` (0.90); ) — добавьте синоним в `rules/roles.yml` или задайте `x-specgen-role` в overlay
14. Заполните обязательное поле `counterparty.card.cardHolder.address.country` в build_payload: роль не выведена (ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml) — добавьте синоним в `rules/roles.yml` или задайте `x-specgen-role` в overlay
15. Заполните обязательное поле `ultimateParty.address.country` в build_payload: роль не выведена (ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml) — добавьте синоним в `rules/roles.yml` или задайте `x-specgen-role` в overlay
16. Задайте валюту запроса: платформа её не сообщает, а спецификация не назвала единственного значения — константа `CURRENCY` не сгенерирована; укажите код валюты через x-specgen-currency в overlay
17. Допишите тело метода `grants` (операция `get-grants`): роль не распознана, запрос собирается пустым
18. Допишите тело метода `post_grants` (операция `post-grants`): роль не распознана, запрос собирается пустым
19. Допишите тело метода `get_grants_id` (операция `get-grants-id`): роль не распознана, запрос собирается пустым
20. Допишите тело метода `transactions` (операция `get-transactions`): роль не распознана, запрос собирается пустым
21. Допишите тело метода `transfers` (операция `get-transfers`): роль не распознана, запрос собирается пустым
22. Решите судьбу необязательного поля `counterparty.balanceAccountId`: роли нет, в payload оно не попало
23. Решите судьбу необязательного поля `balanceAccountId`: роли нет, в payload оно не попало
24. Решите судьбу необязательного поля `counterparty.balanceAccountId`: роли нет, в payload оно не попало
25. Решите судьбу необязательного поля `counterparty.bankAccount.accountHolder.address.city`: роли нет, в payload оно не попало
26. Решите судьбу необязательного поля `counterparty.bankAccount.accountHolder.address.line1`: роли нет, в payload оно не попало
27. Решите судьбу необязательного поля `counterparty.bankAccount.accountHolder.address.line2`: роли нет, в payload оно не попало
28. Решите судьбу необязательного поля `counterparty.bankAccount.accountHolder.address.postalCode`: роли нет, в payload оно не попало
29. Решите судьбу необязательного поля `counterparty.bankAccount.accountHolder.address.stateOrProvince`: роли нет, в payload оно не попало
30. Решите судьбу необязательного поля `counterparty.bankAccount.accountHolder.dateOfBirth`: роли нет, в payload оно не попало
31. Решите судьбу необязательного поля `counterparty.bankAccount.accountHolder.email`: роли нет, в payload оно не попало
32. Решите судьбу необязательного поля `counterparty.bankAccount.accountHolder.firstName`: роли нет, в payload оно не попало
33. Решите судьбу необязательного поля `counterparty.bankAccount.accountHolder.fullName`: роли нет, в payload оно не попало
34. Решите судьбу необязательного поля `counterparty.bankAccount.accountHolder.lastName`: роли нет, в payload оно не попало
35. Решите судьбу необязательного поля `counterparty.bankAccount.accountHolder.url`: роли нет, в payload оно не попало
36. Решите судьбу необязательного поля `counterparty.bankAccount.accountIdentification.ispb`: роли нет, в payload оно не попало
37. Решите судьбу необязательного поля `counterparty.bankAccount.accountIdentification.accountType`: роли нет, в payload оно не попало
38. Решите судьбу необязательного поля `counterparty.bankAccount.accountIdentification.additionalBankIdentification.code`: роли нет, в payload оно не попало
39. Решите судьбу необязательного поля `counterparty.card.cardHolder.address.city`: роли нет, в payload оно не попало
40. Решите судьбу необязательного поля `counterparty.card.cardHolder.address.line1`: роли нет, в payload оно не попало
41. Решите судьбу необязательного поля `counterparty.card.cardHolder.address.line2`: роли нет, в payload оно не попало
42. И ещё 46 однотипных пунктов — полный список в разделах 3 и 6
43. Проверьте значения фикстуры `get-grants 200`: тело собрано не из примеров спецификации (`synthesized`)
44. Проверьте значения фикстуры `get-grants 400`: тело собрано не из примеров спецификации (`synthesized`)
45. Проверьте значения фикстуры `get-grants 401`: тело собрано не из примеров спецификации (`synthesized`)
46. Проверьте значения фикстуры `get-grants 403`: тело собрано не из примеров спецификации (`synthesized`)
47. Проверьте значения фикстуры `get-grants 404`: тело собрано не из примеров спецификации (`synthesized`)
48. Проверьте значения фикстуры `get-grants 422`: тело собрано не из примеров спецификации (`synthesized`)
49. Проверьте значения фикстуры `get-grants 500`: тело собрано не из примеров спецификации (`synthesized`)
50. Проверьте значения фикстуры `post-grants 400`: тело собрано не из примеров спецификации (`synthesized`)
51. Проверьте значения фикстуры `post-grants 401`: тело собрано не из примеров спецификации (`synthesized`)
52. Проверьте значения фикстуры `post-grants 403`: тело собрано не из примеров спецификации (`synthesized`)
53. Проверьте значения фикстуры `post-grants 404`: тело собрано не из примеров спецификации (`synthesized`)
54. Проверьте значения фикстуры `post-grants 422`: тело собрано не из примеров спецификации (`synthesized`)
55. Проверьте значения фикстуры `post-grants 500`: тело собрано не из примеров спецификации (`synthesized`)
56. Проверьте значения фикстуры `get-grants-id 200`: тело собрано не из примеров спецификации (`synthesized`)
57. Проверьте значения фикстуры `get-grants-id 400`: тело собрано не из примеров спецификации (`synthesized`)
58. Проверьте значения фикстуры `get-grants-id 401`: тело собрано не из примеров спецификации (`synthesized`)
59. Проверьте значения фикстуры `get-grants-id 403`: тело собрано не из примеров спецификации (`synthesized`)
60. Проверьте значения фикстуры `get-grants-id 404`: тело собрано не из примеров спецификации (`synthesized`)
61. Проверьте значения фикстуры `get-grants-id 422`: тело собрано не из примеров спецификации (`synthesized`)
62. Проверьте значения фикстуры `get-grants-id 500`: тело собрано не из примеров спецификации (`synthesized`)
63. И ещё 40 однотипных пунктов — полный список в разделах 3 и 6
64. Подключите вторую операцию создания `post-cashouts` вручную: контракт даёт один метод создания
65. Уберите повтор в check_conditions: условие `field_max_length` на роль `external_id` пришло от двух полей (`reference`)
66. Уберите повтор в check_conditions: условие `field_enum` на роль `recipient_type` пришло от двух полей (`type`)
67. Уберите повтор в check_conditions: условие `field_max_length` на роль `bank_code` пришло от двух полей (`bsbCode`, `bankCode`, `clearingNumber`, `routingNumber`)

Итого: 67 пунктов.
