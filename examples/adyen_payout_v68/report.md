# Отчёт о разборе спецификации «Adyen Payout API»

| | |
|---|---|
| Провайдер | `adyen_payout_v68` |
| Спецификация | `adyen_payout_v68.yaml`, версия 68, OpenAPI 3.1.0 |
| Класс сервиса | `Provider::AdyenPayoutV68Service` |
| Файл сервиса | `adyen_payout_v68_service.rb` |

Отчёт сгенерирован инструментом integrate из той же модели провайдера, что и
сервис: всё, о чём здесь сказано, лежит в сгенерированных файлах рядом.
Каждая строка ниже — действие, а не констатация: если элемент спецификации
попал в отчёт, к нему приложено, что сделал инструмент и чем это закрыть.
Генерация не блокируется никогда, поэтому отчёт описывает готовые файлы, а не
причину отказа.

## 1. Сводка

| Показатель | Значение |
|---|---|
| Операции | всего 6: отображено на контракт 1, вне контракта 1, без роли (unmapped) 4 |
| Схемы и поля | схем 31, полей 252: скалярных 214, контейнеров 38 |
| Роли полей | 34 из 214 скалярных: по справочнику 21, эвристика ниже порога 13 |
| Поля без роли | 180: обязательных 35, необязательных 145 |
| Статусы | 0: сопоставлено 0, не сопоставлено 0 |
| События вебхука | 0: сопоставлено 0, не сопоставлено 0 |
| Коды ошибок | кодов провайдера 1: в enum 0, только в примерах 1; общих правил по HTTP-коду 0 |
| Условия взаимодействия | 1: из структуры 1, из прозы описаний 0 |
| Предупреждения | 216: ошибок 0, предупреждений 45, справок 171 |

Сгенерированные артефакты:

| Файл | Что это | Строк |
|---|---|---|
| `adyen_payout_v68_service.rb` | сервис по контракту базового класса | 902 |
| `INTEGRATION.md` | документация интеграции | 263 |
| `fixtures.json` | примеры запросов, ответов и уведомлений | 810 |
| `report.md` | этот отчёт | считается в момент записи |

### Сверка сгенерированного со спецификацией

Тела из `fixtures.json` проверены схемами той же спецификации, из которой они
выведены: запрос — схемой тела своей операции, ответ — схемой своего кода
ответа, уведомление — схемой тела вебхука. Это замыкает круг: спецификация →
разбор → генерация → обратно к спецификации. Тела, которых спецификация не
обещала (операция без `requestBody`, ответ `204`), в счёт не идут — проверять
там нечего.

**Сверено тел: 42; прошли схему: 39; не прошли: 0; синтезированы и схему не проходят: 3; сверить не с чем: 0.**

**Синтезированы и схему не проходят — 3** — значение собрал генератор по типу поля либо фикстура негативна намеренно, поэтому расхождение с `pattern` или `enum` законно и ошибкой прогона не считается

- **запрос post-storeDetail** — поле `dateOfBirth` не проходит `format` (и ещё расхождений: 1); место: `$.paths['/storeDetail'].post.requestBody.content['application/json'].schema`
- **запрос post-storeDetailAndSubmitThirdParty** — поле `amount.currency` не проходит `maxLength` (и ещё расхождений: 2); место: `$.paths['/storeDetailAndSubmitThirdParty'].post.requestBody.content['application/json'].schema`
- **запрос post-submitThirdParty** — поле `amount.currency` не проходит `maxLength`; место: `$.paths['/submitThirdParty'].post.requestBody.content['application/json'].schema`

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

**Проверок: 19; прошло: 14; не прошло: 1; не проверено: 4.**

**Не прошло — 1** — класс сделал не то, что обещают фикстуры и таблицы INTEGRATION.md: это расхождение сгенерированного кода с сгенерированной документацией, и его надо прочитать глазами

- **прогон: create_request — тело запроса** — в теле запроса нет ключа `amount.currency`

**Не проверено — 4** — вызывать было нечем или незачем: спецификация не описала операции, фикстура не даёт данных либо инструмент сам оставил в этом месте TODO — пробел уже назван в разделах ниже

- **прогон: check_conditions — сумма ниже минимума (—)** — спецификация не задаёт минимальной суммы — проверять нечего
- **прогон: create_request — идентификатор операции в результате** — в схеме успешного ответа нет поля с ролью provider_operation_id
- **прогон: fetch_status — запрос к провайдеру** — спецификация не описывает операции опроса статуса — вызывать нечего
- **прогон: process_callback — уведомление —** — спецификация не описывает вебхуков — уведомление проверить нечем

## 2. Покрытие спецификации

**Покрытие: 23 % (55 из 240 элементов). В границах контракта: 45 % (55 из 122).**

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

Знаменатель второй цифры меньше первого на 118 элементов, и вот они все, по
видам:

- **Поля тел запросов** — 95: необязательные поля без роли — в payload они не идут намеренно (docs/PRINCIPLES.md, раздел «Что генерируем при неполной спеке»), а не по недосмотру
- **Поля тел ответов и уведомлений** — 23: роль поля не входит в читаемые сервисом или не выведена вовсе — методам контракта такое поле прочитать некуда

Больше не вычтено ничего: коды ответов, статусы, события вебхука, условия
взаимодействия, обязательные поля тел запросов и поля запросов с выведенной
ролью остаются в знаменателе второй цифры целиком — даже когда не покрыты,
потому что их непокрытие — пробел интеграции, а не свойство контракта.
Вычтенное не спрятано: каждый вычтенный элемент назван ниже, в «Что не покрыто
и почему», со своей причиной и своей корзиной.

| Измерение | Найдено | Покрыто | Покрытие |
|---|---|---|---|
| Операции | 6 | 2 | 33 % |
| Поля тел запросов | 163 | 6 | 4 % |
| Поля тел ответов и уведомлений | 34 | 11 | 32 % |
| Коды ответов | 36 | 36 | 100 % |
| Статусы | 0 | 0 | нечего покрывать |
| События вебхука | 0 | 0 | нечего покрывать |
| Условия взаимодействия | 1 | 0 | 0 % |

### Что не покрыто и почему

Непокрыто 185: вне контракта 122, структурных исключений 44, требует ручной
работы 19. Корзина каждого элемента вычислена из его причины, таблица причин —
Generators::Report::Gap::BUCKETS.

**Требует ручной работы — 19.** Единственная корзина, адресованная человеку:
здесь спецификация описала то, что контракт умеет использовать, а интеграция
этого не взяла. Перечислена целиком, поимённо и первой — это и есть список
того, что стоит доделать руками.

**Поля тел запросов** — не покрыто 18

- `post-payout: amount.currency` — роль currency выведена, но выражения платформы для неё нет ни в accessors, ни в requisites (rules/contract.yml, раздел platform) — добавьте его туда или заполните поле вручную
- `post-payout: billingAddress.city` — обязательное поле без роли: в payload попало с TODO и значением по умолчанию, значение подставит человек
- `post-payout: billingAddress.country` — обязательное поле без роли: в payload попало с TODO и значением по умолчанию, значение подставит человек
- `post-payout: billingAddress.houseNumberOrName` — обязательное поле без роли: в payload попало с TODO и значением по умолчанию, значение подставит человек
- `post-payout: billingAddress.postalCode` — обязательное поле без роли: в payload попало с TODO и значением по умолчанию, значение подставит человек
- `post-payout: billingAddress.street` — обязательное поле без роли: в payload попало с TODO и значением по умолчанию, значение подставит человек
- `post-payout: fundSource.billingAddress.city` — обязательное поле без роли: в payload попало с TODO и значением по умолчанию, значение подставит человек
- `post-payout: fundSource.billingAddress.country` — обязательное поле без роли: в payload попало с TODO и значением по умолчанию, значение подставит человек
- `post-payout: fundSource.billingAddress.houseNumberOrName` — обязательное поле без роли: в payload попало с TODO и значением по умолчанию, значение подставит человек
- `post-payout: fundSource.billingAddress.postalCode` — обязательное поле без роли: в payload попало с TODO и значением по умолчанию, значение подставит человек
- `post-payout: fundSource.billingAddress.street` — обязательное поле без роли: в payload попало с TODO и значением по умолчанию, значение подставит человек
- `post-payout: fundSource.shopperName.firstName` — обязательное поле без роли: в payload попало с TODO и значением по умолчанию, значение подставит человек
- `post-payout: fundSource.shopperName.lastName` — обязательное поле без роли: в payload попало с TODO и значением по умолчанию, значение подставит человек
- `post-payout: fundSource.telephoneNumber` — роль recipient_phone выведена, но выражения платформы для неё нет ни в accessors, ни в requisites (rules/contract.yml, раздел platform) — добавьте его туда или заполните поле вручную
- `post-payout: merchantAccount` — обязательное поле без роли: в payload попало с TODO и значением по умолчанию, значение подставит человек
- `post-payout: shopperName.firstName` — обязательное поле без роли: в payload попало с TODO и значением по умолчанию, значение подставит человек
- `post-payout: shopperName.lastName` — обязательное поле без роли: в payload попало с TODO и значением по умолчанию, значение подставит человек
- `post-payout: telephoneNumber` — роль recipient_phone выведена, но выражения платформы для неё нет ни в accessors, ни в requisites (rules/contract.yml, раздел platform) — добавьте его туда или заполните поле вручную

**Условия взаимодействия** — не покрыто 1

- `field_max_length currency` — проверка не сгенерирована: у платформы нет выражения для поля currency

**Вне контракта — 122.** Ресурсы спецификации, которых методы контракта не
касаются вовсе: чужие операции и их поля, коды и схемы. Контракт про выплаты;
считать пробелом интеграции отсутствие в ней подписок, споров или хранения
карт — то же самое, что считать пробелом отсутствие метода для чужого API.
Свёрнуто числом с примерами.

- **Операции** — 4, например: `post-declineThirdParty`, `post-storeDetail`, `post-storeDetailAndSubmitThirdParty`
- **Поля тел запросов** — 109, например: `post-confirmThirdParty: additionalData`, `post-confirmThirdParty: merchantAccount`, `post-confirmThirdParty: originalReference`
- **Поля тел ответов и уведомлений** — 9, например: `ModifyResponse.additionalData`, `ModifyResponse.response`, `StoreDetailResponse.additionalData`

**Структурные исключения метрики — 44.** Элементы, которым в методах контракта
нет места по построению: поле входящего тела засчитывается, только когда его
роль читает один из четырёх методов; необязательное поле без роли в payload не
идёт намеренно; код, объявленный диапазоном, ветки не даёт. Это устройство
метрики и контракта, а не пропуск разбора. Свёрнуто числом с примерами.

- **Поля тел запросов** — 30, например: `post-payout: billingAddress.stateOrProvince`, `post-payout: card.cvc`, `post-payout: card.expiryMonth`
- **Поля тел ответов и уведомлений** — 14, например: `ServiceError.additionalData`, `ServiceError.errorType`, `ServiceError.message`

## 3. Неоднозначности

Элементы, о которых спецификация говорит недостаточно, чтобы решение было
однозначным. Инструмент решил сам — что именно, сказано под каждым кодом; от
человека нужна проверка, а не заполнение пропуска.

### `auth_multiple_schemes` — 1

Что сделал инструмент: взята первая схема авторизации спецификации

- **`$.components.securitySchemes`** — схем авторизации в спецификации: 2; выбрана ApiKeyAuth, её требуют 6 операций; не используются: BasicAuth ($.components.securitySchemes.BasicAuth)
  готового overlay-фрагмента нет: закрепляется записью в `rules/auth.yml` или правкой спецификации

### `currency_unknown` — 1

Что сделал инструмент: валюта не подставлена, множитель суммы по умолчанию

- **`$.components.schemas.Amount.properties.value`** — валюта суммы не выведена (поле `currency` совпало с ролью currency, но не задаёт ни enum, ни default, ни example); без кода валюты экспоненту ISO 4217 определить нельзя — задайте валюту в overlay

  ```yaml
  - target: "$.components.schemas.Amount.properties.value"
    update:
      x-specgen-currency: RUB  # код ISO 4217
  ```

### `error_action_unknown` — 1

Что сделал инструмент: взято действие по умолчанию из rules/errors.yml

- **`$.paths['/confirmThirdParty'].post.responses['400'].content['application/json'].examples.generic.value.errorCode`** — для кода 702 нет правила в rules/errors.yml; взято действие по умолчанию reject с уверенностью 0.30 — задайте действие в overlay или добавьте шаблон в справочник
  готового overlay-фрагмента нет: закрепляется записью в `rules/errors.yml` или правкой спецификации

### `field_role_low_confidence` — 13

Что сделал инструмент: роль присвоена лучшему кандидату, в коде рядом с полем — комментарий с уверенностью

- **`$.components.schemas.PayoutRequest.properties.reference`** — обязательное поле `reference`: роль provider_operation_id выведена с низкой уверенностью 0.50 (порог 0.60); кандидаты: provider_operation_id 0.50, external_id 0.21; без него запрос не уйдёт, поэтому в код оно попадёт как provider_operation_id с TODO — проверьте роль и закрепите её фрагментом ниже

  ```yaml
  - target: "$.components.schemas.PayoutRequest.properties.reference"
    update:
      x-specgen-role: provider_operation_id  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.StoreDetailAndSubmitRequest.properties.reference`** — обязательное поле `reference`: роль external_id выведена с низкой уверенностью 0.21 (порог 0.60); кандидаты: external_id 0.21, provider_operation_id 0.21; без него запрос не уйдёт, поэтому в код оно попадёт как external_id с TODO — проверьте роль и закрепите её фрагментом ниже

  ```yaml
  - target: "$.components.schemas.StoreDetailAndSubmitRequest.properties.reference"
    update:
      x-specgen-role: external_id  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.SubmitRequest.properties.reference`** — обязательное поле `reference`: роль external_id выведена с низкой уверенностью 0.21 (порог 0.60); кандидаты: external_id 0.21, provider_operation_id 0.21; без него запрос не уйдёт, поэтому в код оно попадёт как external_id с TODO — проверьте роль и закрепите её фрагментом ниже

  ```yaml
  - target: "$.components.schemas.SubmitRequest.properties.reference"
    update:
      x-specgen-role: external_id  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.PayoutResponse.properties.dccSignature`** — необязательное поле `dccSignature`: роль signature выведена с низкой уверенностью 0.43 (порог 0.60); кандидаты: signature 0.43; в коде оно будет помечено TODO — проверьте роль и закрепите её фрагментом ниже

  ```yaml
  - target: "$.components.schemas.PayoutResponse.properties.dccSignature"
    update:
      x-specgen-role: signature  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.PayoutResponse.properties.refusalReason`** — необязательное поле `refusalReason`: роль error_code выведена с низкой уверенностью 0.26 (порог 0.60); кандидаты: error_code 0.26; в коде оно будет помечено TODO — проверьте роль и закрепите её фрагментом ниже

  ```yaml
  - target: "$.components.schemas.PayoutResponse.properties.refusalReason"
    update:
      x-specgen-role: error_code  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.ResponseAdditionalDataCard.properties.cardBin`** — необязательное поле `cardBin`: роль card_number выведена с низкой уверенностью 0.50 (порог 0.60); кандидаты: card_number 0.50; в коде оно будет помечено TODO — проверьте роль и закрепите её фрагментом ниже

  ```yaml
  - target: "$.components.schemas.ResponseAdditionalDataCard.properties.cardBin"
    update:
      x-specgen-role: card_number  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.ResponseAdditionalDataCard.properties.cardPaymentMethod`** — необязательное поле `cardPaymentMethod`: роль recipient_type выведена с низкой уверенностью 0.26 (порог 0.60); кандидаты: recipient_type 0.26; в коде оно будет помечено TODO — проверьте роль и закрепите её фрагментом ниже

  ```yaml
  - target: "$.components.schemas.ResponseAdditionalDataCard.properties.cardPaymentMethod"
    update:
      x-specgen-role: recipient_type  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.ResponseAdditionalDataCommon.properties.authorisedAmountValue`** — необязательное поле `authorisedAmountValue`: роль amount выведена с низкой уверенностью 0.26 (порог 0.60); кандидаты: amount 0.26; в коде оно будет помечено TODO — проверьте роль и закрепите её фрагментом ниже

  ```yaml
  - target: "$.components.schemas.ResponseAdditionalDataCommon.properties.authorisedAmountValue"
    update:
      x-specgen-role: amount  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.ResponseAdditionalDataCommon.properties.refusalReasonRaw`** — необязательное поле `refusalReasonRaw`: роль error_code выведена с низкой уверенностью 0.21 (порог 0.60); кандидаты: error_code 0.21; в коде оно будет помечено TODO — проверьте роль и закрепите её фрагментом ниже

  ```yaml
  - target: "$.components.schemas.ResponseAdditionalDataCommon.properties.refusalReasonRaw"
    update:
      x-specgen-role: error_code  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.ResponseAdditionalDataCommon.properties.requestCurrencyCode`** — необязательное поле `requestCurrencyCode`: роль currency выведена с низкой уверенностью 0.26 (порог 0.60); кандидаты: currency 0.26; в коде оно будет помечено TODO — проверьте роль и закрепите её фрагментом ниже

  ```yaml
  - target: "$.components.schemas.ResponseAdditionalDataCommon.properties.requestCurrencyCode"
    update:
      x-specgen-role: currency  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.ResponseAdditionalDataSepa.properties['sepadirectdebit.dateOfSignature']`** — необязательное поле `sepadirectdebit.dateOfSignature`: роль signature выведена с низкой уверенностью 0.43 (порог 0.60); кандидаты: signature 0.43; в коде оно будет помечено TODO — проверьте роль и закрепите её фрагментом ниже

  ```yaml
  - target: "$.components.schemas.ResponseAdditionalDataSepa.properties['sepadirectdebit.dateOfSignature']"
    update:
      x-specgen-role: signature  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.StoreDetailAndSubmitResponse.properties.refusalReason`** — необязательное поле `refusalReason`: роль error_code выведена с низкой уверенностью 0.26 (порог 0.60); кандидаты: error_code 0.26; в коде оно будет помечено TODO — проверьте роль и закрепите её фрагментом ниже

  ```yaml
  - target: "$.components.schemas.StoreDetailAndSubmitResponse.properties.refusalReason"
    update:
      x-specgen-role: error_code  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.SubmitResponse.properties.refusalReason`** — необязательное поле `refusalReason`: роль error_code выведена с низкой уверенностью 0.26 (порог 0.60); кандидаты: error_code 0.26; в коде оно будет помечено TODO — проверьте роль и закрепите её фрагментом ниже

  ```yaml
  - target: "$.components.schemas.SubmitResponse.properties.refusalReason"
    update:
      x-specgen-role: error_code  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```

### `idempotency_header_missing` — 1

Что сделал инструмент: ключ идемпотентности не отправляется

- **`$.paths['/payout'].post`** — ни одна операция не объявляет заголовок идемпотентности (алиасы rules/idempotency.yml: Idempotence-Key, Idempotency-Key, PayPal-Request-Id, X-Idempotency-Key, X-Request-Id, X-Unique-Transaction-Id); повтор запроса после сетевого сбоя создаст вторую выплату — уточните у провайдера или объявите заголовок в overlay

  ```yaml
  - target: "$.paths['/payout'].post"
    update:
      parameters:
        - name: Idempotency-Key
          in: header
          required: false
          schema:
            type: string
            format: uuid
  ```

### `operation_role_ambiguous` — 1

Что сделал инструмент: взят лучший кандидат роли, метод сгенерирован по нему

- **`$.paths['/payout'].post`** — две роли подходят этой операции почти одинаково; взята первая, но выбор стоит подтвердить (create_payout 8.5, cancel 7.5, confirm 6.5 из 11.0 поданных голосов); переопределить — в overlay
  готового overlay-фрагмента нет: закрепляется записью в `rules/operations.yml` или правкой спецификации

### `required_field_role_unknown` — 35

Что сделал инструмент: в исходящем теле поле включено в payload со значением примера или nil и TODO рядом; во входящем — ищется структурно

- **`$.components.schemas.Address.properties.city`** — обязательное поле `city` (string, max_length 3000): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; без него запрос не уйдёт, поэтому в код оно попадёт с TODO — задайте роль фрагментом ниже или добавьте синоним в rules/roles.yml

  ```yaml
  - target: "$.components.schemas.Address.properties.city"
    update:
      x-specgen-role: TODO  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.Address.properties.country`** — обязательное поле `country` (string): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; без него запрос не уйдёт, поэтому в код оно попадёт с TODO — задайте роль фрагментом ниже или добавьте синоним в rules/roles.yml

  ```yaml
  - target: "$.components.schemas.Address.properties.country"
    update:
      x-specgen-role: TODO  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.Address.properties.houseNumberOrName`** — обязательное поле `houseNumberOrName` (string, max_length 3000): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; без него запрос не уйдёт, поэтому в код оно попадёт с TODO — задайте роль фрагментом ниже или добавьте синоним в rules/roles.yml

  ```yaml
  - target: "$.components.schemas.Address.properties.houseNumberOrName"
    update:
      x-specgen-role: TODO  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.Address.properties.postalCode`** — обязательное поле `postalCode` (string): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; без него запрос не уйдёт, поэтому в код оно попадёт с TODO — задайте роль фрагментом ниже или добавьте синоним в rules/roles.yml

  ```yaml
  - target: "$.components.schemas.Address.properties.postalCode"
    update:
      x-specgen-role: TODO  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.Address.properties.street`** — обязательное поле `street` (string, max_length 3000): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; без него запрос не уйдёт, поэтому в код оно попадёт с TODO — задайте роль фрагментом ниже или добавьте синоним в rules/roles.yml

  ```yaml
  - target: "$.components.schemas.Address.properties.street"
    update:
      x-specgen-role: TODO  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.FraudCheckResult.properties.accountScore`** — обязательное поле `accountScore` (integer, format int32): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; без него запрос не уйдёт, поэтому в код оно попадёт с TODO — задайте роль фрагментом ниже или добавьте синоним в rules/roles.yml

  ```yaml
  - target: "$.components.schemas.FraudCheckResult.properties.accountScore"
    update:
      x-specgen-role: TODO  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.FraudCheckResult.properties.checkId`** — обязательное поле `checkId` (integer, format int32): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; без него запрос не уйдёт, поэтому в код оно попадёт с TODO — задайте роль фрагментом ниже или добавьте синоним в rules/roles.yml

  ```yaml
  - target: "$.components.schemas.FraudCheckResult.properties.checkId"
    update:
      x-specgen-role: TODO  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.FraudCheckResult.properties.name`** — обязательное поле `name` (string): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; без него запрос не уйдёт, поэтому в код оно попадёт с TODO — задайте роль фрагментом ниже или добавьте синоним в rules/roles.yml

  ```yaml
  - target: "$.components.schemas.FraudCheckResult.properties.name"
    update:
      x-specgen-role: TODO  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.FraudResult.properties.accountScore`** — обязательное поле `accountScore` (integer, format int32): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; без него запрос не уйдёт, поэтому в код оно попадёт с TODO — задайте роль фрагментом ниже или добавьте синоним в rules/roles.yml

  ```yaml
  - target: "$.components.schemas.FraudResult.properties.accountScore"
    update:
      x-specgen-role: TODO  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.ModifyRequest.properties.merchantAccount`** — обязательное поле `merchantAccount` (string): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; без него запрос не уйдёт, поэтому в код оно попадёт с TODO — задайте роль фрагментом ниже или добавьте синоним в rules/roles.yml

  ```yaml
  - target: "$.components.schemas.ModifyRequest.properties.merchantAccount"
    update:
      x-specgen-role: TODO  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.ModifyRequest.properties.originalReference`** — обязательное поле `originalReference` (string): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; без него запрос не уйдёт, поэтому в код оно попадёт с TODO — задайте роль фрагментом ниже или добавьте синоним в rules/roles.yml

  ```yaml
  - target: "$.components.schemas.ModifyRequest.properties.originalReference"
    update:
      x-specgen-role: TODO  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.ModifyResponse.properties.response`** — обязательное поле `response` (string): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; без него запрос не уйдёт, поэтому в код оно попадёт с TODO — задайте роль фрагментом ниже или добавьте синоним в rules/roles.yml

  ```yaml
  - target: "$.components.schemas.ModifyResponse.properties.response"
    update:
      x-specgen-role: TODO  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.Name.properties.firstName`** — обязательное поле `firstName` (string, max_length 80): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; без него запрос не уйдёт, поэтому в код оно попадёт с TODO — задайте роль фрагментом ниже или добавьте синоним в rules/roles.yml

  ```yaml
  - target: "$.components.schemas.Name.properties.firstName"
    update:
      x-specgen-role: TODO  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.Name.properties.lastName`** — обязательное поле `lastName` (string, max_length 80): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; без него запрос не уйдёт, поэтому в код оно попадёт с TODO — задайте роль фрагментом ниже или добавьте синоним в rules/roles.yml

  ```yaml
  - target: "$.components.schemas.Name.properties.lastName"
    update:
      x-specgen-role: TODO  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.PayoutRequest.properties.merchantAccount`** — обязательное поле `merchantAccount` (string): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; без него запрос не уйдёт, поэтому в код оно попадёт с TODO — задайте роль фрагментом ниже или добавьте синоним в rules/roles.yml

  ```yaml
  - target: "$.components.schemas.PayoutRequest.properties.merchantAccount"
    update:
      x-specgen-role: TODO  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.StoreDetailAndSubmitRequest.properties.dateOfBirth`** — обязательное поле `dateOfBirth` (string, format date): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; без него запрос не уйдёт, поэтому в код оно попадёт с TODO — задайте роль фрагментом ниже или добавьте синоним в rules/roles.yml

  ```yaml
  - target: "$.components.schemas.StoreDetailAndSubmitRequest.properties.dateOfBirth"
    update:
      x-specgen-role: TODO  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.StoreDetailAndSubmitRequest.properties.entityType`** — обязательное поле `entityType` (string, enum ["NaturalPerson", "Company"]): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; без него запрос не уйдёт, поэтому в код оно попадёт с TODO — задайте роль фрагментом ниже или добавьте синоним в rules/roles.yml

  ```yaml
  - target: "$.components.schemas.StoreDetailAndSubmitRequest.properties.entityType"
    update:
      x-specgen-role: TODO  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.StoreDetailAndSubmitRequest.properties.merchantAccount`** — обязательное поле `merchantAccount` (string): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; без него запрос не уйдёт, поэтому в код оно попадёт с TODO — задайте роль фрагментом ниже или добавьте синоним в rules/roles.yml

  ```yaml
  - target: "$.components.schemas.StoreDetailAndSubmitRequest.properties.merchantAccount"
    update:
      x-specgen-role: TODO  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.StoreDetailAndSubmitRequest.properties.nationality`** — обязательное поле `nationality` (string, max_length 2): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; без него запрос не уйдёт, поэтому в код оно попадёт с TODO — задайте роль фрагментом ниже или добавьте синоним в rules/roles.yml

  ```yaml
  - target: "$.components.schemas.StoreDetailAndSubmitRequest.properties.nationality"
    update:
      x-specgen-role: TODO  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- **`$.components.schemas.StoreDetailAndSubmitRequest.properties.shopperEmail`** — обязательное поле `shopperEmail` (string): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; без него запрос не уйдёт, поэтому в код оно попадёт с TODO — задайте роль фрагментом ниже или добавьте синоним в rules/roles.yml

  ```yaml
  - target: "$.components.schemas.StoreDetailAndSubmitRequest.properties.shopperEmail"
    update:
      x-specgen-role: TODO  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```
- и ещё 15 с тем же кодом

### `spec_element_unsupported` — 11

Что сделал инструмент: значение расширения отвергнуто, элемент разобран без него

- **`$.components.schemas.FundSource.properties.additionalData`** — `additionalData` — свободная карта (`additionalProperties` или объект без `properties`): ключи спецификацией не перечислены, поэтому значением поля остаётся хеш, который заполняют вручную
  готового overlay-фрагмента нет: исправляется правкой спецификации
- **`$.components.schemas.ModifyRequest.properties.additionalData`** — `additionalData` — свободная карта (`additionalProperties` или объект без `properties`): ключи спецификацией не перечислены, поэтому значением поля остаётся хеш, который заполняют вручную
  готового overlay-фрагмента нет: исправляется правкой спецификации
- **`$.components.schemas.ModifyResponse.properties.additionalData`** — `additionalData` — свободная карта (`additionalProperties` или объект без `properties`): ключи спецификацией не перечислены, поэтому значением поля остаётся хеш, который заполняют вручную
  готового overlay-фрагмента нет: исправляется правкой спецификации
- **`$.components.schemas.PayoutResponse.properties.additionalData`** — `additionalData` — свободная карта (`additionalProperties` или объект без `properties`): ключи спецификацией не перечислены, поэтому значением поля остаётся хеш, который заполняют вручную
  готового overlay-фрагмента нет: исправляется правкой спецификации
- **`$.components.schemas.ServiceError.properties.additionalData`** — `additionalData` — свободная карта (`additionalProperties` или объект без `properties`): ключи спецификацией не перечислены, поэтому значением поля остаётся хеш, который заполняют вручную
  готового overlay-фрагмента нет: исправляется правкой спецификации
- **`$.components.schemas.StoreDetailAndSubmitRequest.properties.additionalData`** — `additionalData` — свободная карта (`additionalProperties` или объект без `properties`): ключи спецификацией не перечислены, поэтому значением поля остаётся хеш, который заполняют вручную
  готового overlay-фрагмента нет: исправляется правкой спецификации
- **`$.components.schemas.StoreDetailAndSubmitResponse.properties.additionalData`** — `additionalData` — свободная карта (`additionalProperties` или объект без `properties`): ключи спецификацией не перечислены, поэтому значением поля остаётся хеш, который заполняют вручную
  готового overlay-фрагмента нет: исправляется правкой спецификации
- **`$.components.schemas.StoreDetailRequest.properties.additionalData`** — `additionalData` — свободная карта (`additionalProperties` или объект без `properties`): ключи спецификацией не перечислены, поэтому значением поля остаётся хеш, который заполняют вручную
  готового overlay-фрагмента нет: исправляется правкой спецификации
- **`$.components.schemas.StoreDetailResponse.properties.additionalData`** — `additionalData` — свободная карта (`additionalProperties` или объект без `properties`): ключи спецификацией не перечислены, поэтому значением поля остаётся хеш, который заполняют вручную
  готового overlay-фрагмента нет: исправляется правкой спецификации
- **`$.components.schemas.SubmitRequest.properties.additionalData`** — `additionalData` — свободная карта (`additionalProperties` или объект без `properties`): ключи спецификацией не перечислены, поэтому значением поля остаётся хеш, который заполняют вручную
  готового overlay-фрагмента нет: исправляется правкой спецификации
- **`$.components.schemas.SubmitResponse.properties.additionalData`** — `additionalData` — свободная карта (`additionalProperties` или объект без `properties`): ключи спецификацией не перечислены, поэтому значением поля остаётся хеш, который заполняют вручную
  готового overlay-фрагмента нет: исправляется правкой спецификации

### `webhook_missing` — 1

Что сделал инструмент: process_callback отказывает webhooks_not_supported: статус только опросом

- **`$.paths`** — спецификация не описывает входящих уведомлений (нет операции с security: [] и нет секции webhooks); статус операции сервис узнает только опросом через fetch_status
  готового overlay-фрагмента нет: исправляется правкой спецификации

### Как собрать overlay

Фрагменты выше — действия одного документа OpenAPI Overlay 1.0.0
(<https://spec.openapis.org/overlay/v1.0.0.html>). Соберите файл
`adyen_payout_v68.overlay.yaml`, вставив их подряд под ключ `actions`,
замените значения `TODO` и перегенерируйте:

```yaml
overlay: 1.0.0
info:
  title: adyen_payout_v68 disambiguation
  version: 1.0.0
actions:
- target: "$..."
  update:
    x-specgen-role: ...
```

```sh
./integrate --spec adyen_payout_v68.yaml --provider adyen_payout_v68 --overlay adyen_payout_v68.overlay.yaml
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
| `post-confirmThirdParty` | `POST /confirmThirdParty` | `confirm` (эвристика 0.68) | `confirm(operation)` | ничего: в `Provider::BaseService` нет метода для такой роли, платформа зовёт этот метод напрямую |
| `post-declineThirdParty` | `POST /declineThirdParty` | не распознана (unmapped) | `post_decline_third_party(operation)` | добавьте синоним пути или operationId в `rules/operations.yml` и перегенерируйте; расширения `x-specgen-role` для операции в модели нет (docs/IR.md, таблица расширений) |
| `post-storeDetail` | `POST /storeDetail` | не распознана (unmapped) | `post_store_detail(operation)` | добавьте синоним пути или operationId в `rules/operations.yml` и перегенерируйте; расширения `x-specgen-role` для операции в модели нет (docs/IR.md, таблица расширений) |
| `post-storeDetailAndSubmitThirdParty` | `POST /storeDetailAndSubmitThirdParty` | не распознана (unmapped) | `post_store_detail_and_submit_third_party(operation)` | добавьте синоним пути или operationId в `rules/operations.yml` и перегенерируйте; расширения `x-specgen-role` для операции в модели нет (docs/IR.md, таблица расширений) |
| `post-submitThirdParty` | `POST /submitThirdParty` | не распознана (unmapped) | `post_submit_third_party(operation)` | добавьте синоним пути или operationId в `rules/operations.yml` и перегенерируйте; расширения `x-specgen-role` для операции в модели нет (docs/IR.md, таблица расширений) |

## 5. Противоречия в самой спецификации

Спецификация расходится сама с собой или со своими соседями: enum против
примеров, коды ответов одной операции против другой, проза против структуры.
Инструмент выбрал, чему верить, и продолжил; правится это правкой
спецификации, а не настройкой инструмента.

### `error_code_undeclared` — 1

Что сделал инструмент: код добавлен в ERROR_MAP: карта строится как объединение enum и примеров

- **`$.paths['/confirmThirdParty'].post.responses['400'].content['application/json'].examples.generic.value.errorCode`** — код 702 встречается в примере, но не объявлен в enum поля кода ошибки; карта ошибок строится как объединение enum и примеров, спецификацию стоит поправить

### `field_role_conflict` — 9

Что сделал инструмент: роль оставлена полю с большей уверенностью, второе получило следующего кандидата

- **`$.components.schemas.BankAccount.properties.bankCity`** — необязательное поле `bankCity`: роль bank_name (0.50) уже у `bankName` (0.90) в той же схеме; других кандидатов нет, роль не выведена — задайте её фрагментом ниже
- **`$.components.schemas.BankAccount.properties.bankLocationId`** — необязательное поле `bankLocationId`: роль bank_code (0.55) уже у `bic` (0.90) в той же схеме; других кандидатов нет, роль не выведена — задайте её фрагментом ниже
- **`$.components.schemas.ResponseAdditionalDataCard.properties.cardSummary`** — необязательное поле `cardSummary`: роль card_number (0.50) уже у `cardBin` (0.50) в той же схеме; других кандидатов нет, роль не выведена — задайте её фрагментом ниже
- **`$.components.schemas.ResponseAdditionalDataCommon.properties.inferredRefusalReason`** — необязательное поле `inferredRefusalReason`: роль error_code (0.21) уже у `refusalReasonRaw` (0.21) в той же схеме; других кандидатов нет, роль не выведена — задайте её фрагментом ниже
- **`$.components.schemas.ResponseAdditionalDataCommon.properties.paymentMethodVariant`** — необязательное поле `paymentMethodVariant`: роль recipient_type (0.26) уже у `paymentMethod` (0.90) в той же схеме; других кандидатов нет, роль не выведена — задайте её фрагментом ниже
- **`$.components.schemas.ResponseAdditionalDataCommon.properties.requestAmount`** — необязательное поле `requestAmount`: роль amount (0.21) уже у `authorisedAmountValue` (0.26) в той же схеме; других кандидатов нет, роль не выведена — задайте её фрагментом ниже
- **`$.components.schemas.ResponseAdditionalDataCommon.properties.transactionLinkId`** — необязательное поле `transactionLinkId`: роль external_id (0.21) уже у `merchantReference` (0.90) в той же схеме; других кандидатов нет, роль не выведена — задайте её фрагментом ниже
- **`$.components.schemas.ResponseAdditionalDataCommon.properties.visaTransactionId`** — необязательное поле `visaTransactionId`: роль external_id (0.21) уже у `merchantReference` (0.90) в той же схеме; других кандидатов нет, роль не выведена — задайте её фрагментом ниже
- **`$.components.schemas.ResponseAdditionalDataCommon.properties['recurring.firstPspReference']`** — необязательное поле `recurring.firstPspReference`: роль provider_operation_id (0.21) уже у `acquirerReference` (0.90) в той же схеме; других кандидатов нет, роль не выведена — задайте её фрагментом ниже

## 6. Справки

Факты, о которых читателю стоит знать; решения за человека инструмент здесь не
принимал. Списки сокращены до первых 5 элементов в группе — полный набор
виден в `./integrate analyze --spec adyen_payout_v68.yaml`.

**`field_role_unknown`** — 136

- `$.components.schemas.Address.properties.stateOrProvince` — необязательное поле `stateOrProvince` (string): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; в запрос оно не попадёт; если оно нужно, задайте роль фрагментом ниже
- `$.components.schemas.BankAccount.properties.bankAccountNumber` — необязательное поле `bankAccountNumber` (string): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; в запрос оно не попадёт; если оно нужно, задайте роль фрагментом ниже
- `$.components.schemas.BankAccount.properties.countryCode` — необязательное поле `countryCode` (string): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; в запрос оно не попадёт; если оно нужно, задайте роль фрагментом ниже
- `$.components.schemas.BankAccount.properties.iban` — необязательное поле `iban` (string): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; в запрос оно не попадёт; если оно нужно, задайте роль фрагментом ниже
- `$.components.schemas.BankAccount.properties.ownerName` — необязательное поле `ownerName` (string): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; в запрос оно не попадёт; если оно нужно, задайте роль фрагментом ниже
- и ещё 131 с тем же кодом

**`operation_unmapped`** — 5, подробности в разделе 4

- `$.paths['/storeDetail'].post` — в спецификации слишком мало признаков того, для чего эта операция, поэтому роль не присвоена (create_payout 3.0, create_deposit 3.0, webhook 3.0 из 3.0 поданных голосов); задайте роль в overlay
- `$.paths['/confirmThirdParty'].post` — распознана как confirm, но в Provider::BaseService нет метода для такой роли; она генерируется отдельным публичным методом и остаётся вне контракта
- `$.paths['/declineThirdParty'].post` — больше всех голосов набрала роль cancel, но она отсечена по форме: ни в пути, ни в operationId нет ни одного платёжного существительного (vetoes.domain_nouns в rules/operations.yml); роль не присвоена, операция получает отдельный публичный метод
- `$.paths['/storeDetailAndSubmitThirdParty'].post` — больше всех голосов набрала роль create_payout, но она отсечена по форме: ни в пути, ни в operationId нет ни одного платёжного существительного (vetoes.domain_nouns в rules/operations.yml); роль не присвоена, операция получает отдельный публичный метод
- `$.paths['/submitThirdParty'].post` — больше всех голосов набрала роль create_payout, но она отсечена по форме: ни в пути, ни в operationId нет ни одного платёжного существительного (vetoes.domain_nouns в rules/operations.yml); роль не присвоена, операция получает отдельный публичный метод

## 7. Что доделать руками

1. Заполните обязательное поле `billingAddress.city` в build_payload: роль не выведена (ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml) — добавьте синоним в `rules/roles.yml` или задайте `x-specgen-role` в overlay
2. Заполните обязательное поле `billingAddress.country` в build_payload: роль не выведена (ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml) — добавьте синоним в `rules/roles.yml` или задайте `x-specgen-role` в overlay
3. Заполните обязательное поле `billingAddress.houseNumberOrName` в build_payload: роль не выведена (ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml) — добавьте синоним в `rules/roles.yml` или задайте `x-specgen-role` в overlay
4. Заполните обязательное поле `billingAddress.postalCode` в build_payload: роль не выведена (ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml) — добавьте синоним в `rules/roles.yml` или задайте `x-specgen-role` в overlay
5. Заполните обязательное поле `billingAddress.street` в build_payload: роль не выведена (ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml) — добавьте синоним в `rules/roles.yml` или задайте `x-specgen-role` в overlay
6. Заполните обязательное поле `fundSource.billingAddress.city` в build_payload: роль не выведена (ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml) — добавьте синоним в `rules/roles.yml` или задайте `x-specgen-role` в overlay
7. Заполните обязательное поле `fundSource.billingAddress.country` в build_payload: роль не выведена (ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml) — добавьте синоним в `rules/roles.yml` или задайте `x-specgen-role` в overlay
8. Заполните обязательное поле `fundSource.billingAddress.houseNumberOrName` в build_payload: роль не выведена (ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml) — добавьте синоним в `rules/roles.yml` или задайте `x-specgen-role` в overlay
9. Заполните обязательное поле `fundSource.billingAddress.postalCode` в build_payload: роль не выведена (ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml) — добавьте синоним в `rules/roles.yml` или задайте `x-specgen-role` в overlay
10. Заполните обязательное поле `fundSource.billingAddress.street` в build_payload: роль не выведена (ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml) — добавьте синоним в `rules/roles.yml` или задайте `x-specgen-role` в overlay
11. Заполните обязательное поле `fundSource.shopperName.firstName` в build_payload: роль не выведена (ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml) — добавьте синоним в `rules/roles.yml` или задайте `x-specgen-role` в overlay
12. Заполните обязательное поле `fundSource.shopperName.lastName` в build_payload: роль не выведена (ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml) — добавьте синоним в `rules/roles.yml` или задайте `x-specgen-role` в overlay
13. Заполните обязательное поле `merchantAccount` в build_payload: роль не выведена (ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml) — добавьте синоним в `rules/roles.yml` или задайте `x-specgen-role` в overlay
14. Проверьте поле `reference` в build_payload: роль `provider_operation_id` присвоена с уверенностью ниже порога (эвристика 0.50, композитное сопоставление: name 2.0 (общие токены с синонимом `acquirer_reference`: reference (50%)), structure 4.0 (родитель `PayoutRequest` содержит токен `payout` из подсказок роли), type 1.0 (type string допустим для роли) = 7.0 из 14.0; следующая external_id 0.21)
15. Заполните обязательное поле `shopperName.firstName` в build_payload: роль не выведена (ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml) — добавьте синоним в `rules/roles.yml` или задайте `x-specgen-role` в overlay
16. Заполните обязательное поле `shopperName.lastName` в build_payload: роль не выведена (ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml) — добавьте синоним в `rules/roles.yml` или задайте `x-specgen-role` в overlay
17. Задайте валюту запроса: платформа её не сообщает, а спецификация не назвала единственного значения — константа `CURRENCY` не сгенерирована; укажите код валюты через x-specgen-currency в overlay
18. Допишите тело метода `post_decline_third_party` (операция `post-declineThirdParty`): роль не распознана, запрос собирается пустым
19. Допишите тело метода `post_store_detail` (операция `post-storeDetail`): роль не распознана, запрос собирается пустым
20. Допишите тело метода `post_store_detail_and_submit_third_party` (операция `post-storeDetailAndSubmitThirdParty`): роль не распознана, запрос собирается пустым
21. Допишите тело метода `post_submit_third_party` (операция `post-submitThirdParty`): роль не распознана, запрос собирается пустым
22. Решите судьбу необязательного поля `additionalData`: роли нет, в payload оно не попало
23. Решите судьбу необязательного поля `additionalData`: роли нет, в payload оно не попало
24. Решите судьбу необязательного поля `billingAddress.stateOrProvince`: роли нет, в payload оно не попало
25. Решите судьбу необязательного поля `card.cvc`: роли нет, в payload оно не попало
26. Решите судьбу необязательного поля `card.expiryMonth`: роли нет, в payload оно не попало
27. Решите судьбу необязательного поля `card.expiryYear`: роли нет, в payload оно не попало
28. Решите судьбу необязательного поля `card.holderName`: роли нет, в payload оно не попало
29. Решите судьбу необязательного поля `card.issueNumber`: роли нет, в payload оно не попало
30. Решите судьбу необязательного поля `card.number`: роли нет, в payload оно не попало
31. Решите судьбу необязательного поля `card.startMonth`: роли нет, в payload оно не попало
32. Решите судьбу необязательного поля `card.startYear`: роли нет, в payload оно не попало
33. Решите судьбу необязательного поля `fraudOffset`: роли нет, в payload оно не попало
34. Решите судьбу необязательного поля `fundSource.additionalData`: роли нет, в payload оно не попало
35. Решите судьбу необязательного поля `fundSource.billingAddress.stateOrProvince`: роли нет, в payload оно не попало
36. Решите судьбу необязательного поля `fundSource.card.cvc`: роли нет, в payload оно не попало
37. Решите судьбу необязательного поля `fundSource.card.expiryMonth`: роли нет, в payload оно не попало
38. Решите судьбу необязательного поля `fundSource.card.expiryYear`: роли нет, в payload оно не попало
39. Решите судьбу необязательного поля `fundSource.card.holderName`: роли нет, в payload оно не попало
40. Решите судьбу необязательного поля `fundSource.card.issueNumber`: роли нет, в payload оно не попало
41. Решите судьбу необязательного поля `fundSource.card.number`: роли нет, в payload оно не попало
42. И ещё 75 однотипных пунктов — полный список в разделах 3 и 6
43. Проверьте значения фикстуры `post-storeDetail`: тело собрано не из примеров спецификации (`synthesized`)
44. Проверьте значения фикстуры `post-storeDetailAndSubmitThirdParty`: тело собрано не из примеров спецификации (`synthesized`)
45. Проверьте значения фикстуры `post-submitThirdParty`: тело собрано не из примеров спецификации (`synthesized`)
46. Проверьте значения фикстуры `post-confirmThirdParty 401`: тело собрано не из примеров спецификации (`synthesized`)
47. Проверьте значения фикстуры `post-confirmThirdParty 403`: тело собрано не из примеров спецификации (`synthesized`)
48. Проверьте значения фикстуры `post-confirmThirdParty 422`: тело собрано не из примеров спецификации (`synthesized`)
49. Проверьте значения фикстуры `post-confirmThirdParty 500`: тело собрано не из примеров спецификации (`synthesized`)
50. Проверьте значения фикстуры `post-declineThirdParty 401`: тело собрано не из примеров спецификации (`synthesized`)
51. Проверьте значения фикстуры `post-declineThirdParty 403`: тело собрано не из примеров спецификации (`synthesized`)
52. Проверьте значения фикстуры `post-declineThirdParty 422`: тело собрано не из примеров спецификации (`synthesized`)
53. Проверьте значения фикстуры `post-declineThirdParty 500`: тело собрано не из примеров спецификации (`synthesized`)
54. Проверьте значения фикстуры `post-payout 200`: тело собрано не из примеров спецификации (`schema_example`)
55. Проверьте значения фикстуры `post-payout 401`: тело собрано не из примеров спецификации (`synthesized`)
56. Проверьте значения фикстуры `post-payout 403`: тело собрано не из примеров спецификации (`synthesized`)
57. Проверьте значения фикстуры `post-payout 422`: тело собрано не из примеров спецификации (`synthesized`)
58. Проверьте значения фикстуры `post-payout 500`: тело собрано не из примеров спецификации (`synthesized`)
59. Проверьте значения фикстуры `post-storeDetail 401`: тело собрано не из примеров спецификации (`synthesized`)
60. Проверьте значения фикстуры `post-storeDetail 403`: тело собрано не из примеров спецификации (`synthesized`)
61. Проверьте значения фикстуры `post-storeDetail 422`: тело собрано не из примеров спецификации (`synthesized`)
62. Проверьте значения фикстуры `post-storeDetail 500`: тело собрано не из примеров спецификации (`synthesized`)
63. И ещё 10 однотипных пунктов — полный список в разделах 3 и 6

Итого: 63 пункта.
