# Отчёт о разборе спецификации «NovaPay Payout API»

| | |
|---|---|
| Провайдер | `novapay` |
| Спецификация | `novapay.yaml`, версия 1.0.0, OpenAPI 3.0.3 |
| Класс сервиса | `Provider::NovapayService` |
| Файл сервиса | `novapay_service.rb` |

Отчёт сгенерирован инструментом integrate из той же модели провайдера, что и
сервис: всё, о чём здесь сказано, лежит в сгенерированных файлах рядом.
Каждая строка ниже — действие, а не констатация: если элемент спецификации
попал в отчёт, к нему приложено, что сделал инструмент и чем это закрыть.
Генерация не блокируется никогда, поэтому отчёт описывает готовые файлы, а не
причину отказа.

## 1. Сводка

| Показатель | Значение |
|---|---|
| Операции | всего 5: отображено на контракт 3, вне контракта 2, без роли (unmapped) 0 |
| Схемы и поля | схем 8, полей 31: скалярных 26, контейнеров 5 |
| Роли полей | 22 из 26 скалярных: по справочнику 21, эвристика выше порога 1 |
| Поля без роли | 4: обязательных 1, необязательных 3 |
| Статусы | 5: сопоставлено 5, не сопоставлено 0 |
| События вебхука | 4: сопоставлено 4, не сопоставлено 0 |
| Коды ошибок | кодов провайдера 10: в enum 7, только в примерах 3; общих правил по HTTP-коду 8 |
| Условия взаимодействия | 9: из структуры 8, из прозы описаний 1 |
| Предупреждения | 18: ошибок 0, предупреждений 6, справок 12 |

Сгенерированные артефакты:

| Файл | Что это | Строк |
|---|---|---|
| `novapay_service.rb` | сервис по контракту базового класса | 389 |
| `INTEGRATION.md` | документация интеграции | 222 |
| `fixtures.json` | примеры запросов, ответов и уведомлений | 461 |
| `report.md` | этот отчёт | считается в момент записи |

## 2. Покрытие спецификации

**Покрытие: 76 % (55 из 72 элементов).**

Формула — доля покрытых элементов от всех: сумма покрытого по семи измерениям,
делённая на сумму найденного. Среднее по измерениям отброшено намеренно:
измерения разного размера, и четыре события вебхука не должны весить столько
же, сколько триста полей схем. Покрытым считается элемент, у которого в
сгенерированном коде есть ветка, выражение или строка таблицы; поля тел
запросов считаются по операциям, поля входящих тел — по схемам. Из входящего
тела сервис читает только поле события уведомления и поля с ролями
`status`, `provider_operation_id`, `error_code`, `external_id`; остальные в коде не участвуют,
и это честно видно в цифре.

| Измерение | Найдено | Покрыто | Покрытие |
|---|---|---|---|
| Операции | 5 | 5 | 100 % |
| Поля тел запросов | 8 | 8 | 100 % |
| Поля тел ответов и уведомлений | 27 | 10 | 37 % |
| Коды ответов | 14 | 14 | 100 % |
| Статусы | 5 | 5 | 100 % |
| События вебхука | 4 | 4 | 100 % |
| Условия взаимодействия | 9 | 9 | 100 % |

### Что не покрыто и почему

**Поля тел ответов и уведомлений** — не покрыто 17

- `PayoutResponse.amount` — не читается: роль `amount` выведена, но методам контракта `Provider::BaseService` она не нужна
- `PayoutResponse.currency` — не читается: роль `currency` выведена, но методам контракта `Provider::BaseService` она не нужна
- `PayoutResponse.recipient.type` — не читается: роль `recipient_type` выведена, но методам контракта `Provider::BaseService` она не нужна
- `PayoutResponse.recipient.phone` — не читается: роль `recipient_phone` выведена, но методам контракта `Provider::BaseService` она не нужна
- `PayoutResponse.recipient.bank_code` — не читается: роль `bank_code` выведена, но методам контракта `Provider::BaseService` она не нужна
- `PayoutResponse.recipient.bank_name` — не читается: роль `bank_name` выведена, но методам контракта `Provider::BaseService` она не нужна
- `PayoutResponse.recipient.card_number` — не читается: роль `card_number` выведена, но методам контракта `Provider::BaseService` она не нужна
- `PayoutResponse.error.message` — не читается: роль `error_message` выведена, но методам контракта `Provider::BaseService` она не нужна
- `PayoutResponse.created_at` — не читается: роль `created_at` выведена, но методам контракта `Provider::BaseService` она не нужна
- `PayoutResponse.completed_at` — не читается: роль `completed_at` выведена, но методам контракта `Provider::BaseService` она не нужна
- `ErrorResponse.error.message` — не читается: роль `error_message` выведена, но методам контракта `Provider::BaseService` она не нужна
- `payoutWebhook.responses.200.received` — не читается: роль не выведена
- `WebhookPayload.completed_at` — не читается: роль `completed_at` выведена, но методам контракта `Provider::BaseService` она не нужна
- `WebhookPayload.error.message` — не читается: роль `error_message` выведена, но методам контракта `Provider::BaseService` она не нужна
- `getBalance.responses.200.balance` — не читается: роль не выведена
- и ещё 2 в этом измерении

## 3. Неоднозначности

Элементы, о которых спецификация говорит недостаточно, чтобы решение было
однозначным. Инструмент решил сам — что именно, сказано под каждым кодом; от
человека нужна проверка, а не заполнение пропуска.

### `conditional_required_hint` — 2

Что сделал инструмент: поле помечено условно обязательным, условие вынесено в комментарий над записью payload

- **`$.components.schemas.Recipient`** — `card_number` выглядит условно обязательным (`type` = card), но схема не задаёт условия; фрагмент ниже задаёт его формально

  ```yaml
  - target: "$.components.schemas.Recipient"
    update:
      x-jsonschema-if:
        properties:
          type:
            const: card
      x-jsonschema-then:
        required: [card_number]
  ```
- **`$.components.schemas.Recipient`** — `bank_code` выглядит условно обязательным (`type` = sbp), но схема не задаёт условия; фрагмент ниже задаёт его формально

  ```yaml
  - target: "$.components.schemas.Recipient"
    update:
      x-jsonschema-if:
        properties:
          type:
            const: sbp
      x-jsonschema-then:
        required: [bank_code]
  ```

### `required_field_role_unknown` — 1

Что сделал инструмент: в исходящем теле поле включено в payload со значением примера или nil и TODO рядом; во входящем — ищется структурно

- **`$.components.schemas.WebhookPayload.properties.event`** — обязательное поле `event` (string, enum ["payout.completed", "payout.failed", "payout.processing", "payout.cancelled"]): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; без него запрос не уйдёт, поэтому в код оно попадёт с TODO — задайте роль фрагментом ниже или добавьте синоним в rules/roles.yml

  ```yaml
  - target: "$.components.schemas.WebhookPayload.properties.event"
    update:
      x-specgen-role: TODO  # одна из: amount, currency, external_id, provider_operation_id, recipient_type, recipient_phone, bank_code, bank_name, card_number, status, error_code, error_message, created_at, completed_at, idempotency_key, signature
  ```

### Как собрать overlay

Фрагменты выше — действия одного документа OpenAPI Overlay 1.0.0
(<https://spec.openapis.org/overlay/v1.0.0.html>). Соберите файл
`novapay.overlay.yaml`, вставив их подряд под ключ `actions`,
замените значения `TODO` и перегенерируйте:

```yaml
overlay: 1.0.0
info:
  title: novapay disambiguation
  version: 1.0.0
actions:
- target: "$..."
  update:
    x-specgen-role: ...
```

```sh
./integrate --spec novapay.yaml --provider novapay --overlay novapay.overlay.yaml
```

## 4. Операции вне контракта и без роли

Операция, которой нет места в контракте базового класса, не выбрасывается: для
неё генерируется отдельный публичный метод, и здесь сказано какой. Роль
операции закрепляется синонимом в `rules/operations.yml` — расширения
`x-specgen-role` для операции в модели нет (`docs/IR.md`, таблица расширений).

| Операция | HTTP-метод и путь | Роль | Что сгенерировано | Что сделать |
|---|---|---|---|---|
| `cancelPayout` | `POST /payouts/{payout_id}/cancel` | `cancel` (эвристика 0.95) | `cancel(operation)` | ничего: в `Provider::BaseService` нет метода для такой роли, платформа зовёт этот метод напрямую |
| `getBalance` | `GET /balance` | `balance` (эвристика 0.93) | `balance()` | ничего: в `Provider::BaseService` нет метода для такой роли, платформа зовёт этот метод напрямую |

## 5. Противоречия в самой спецификации

Спецификация расходится сама с собой или со своими соседями: enum против
примеров, коды ответов одной операции против другой, проза против структуры.
Инструмент выбрал, чему верить, и продолжил; правится это правкой
спецификации, а не настройкой инструмента.

### `error_code_undeclared` — 3

Что сделал инструмент: код добавлен в ERROR_MAP: карта строится как объединение enum и примеров

- **`$.paths['/payouts'].post.responses['401'].content['application/json'].example.error.code`** — код unauthorized встречается в примере, но не объявлен в enum поля кода ошибки ($.components.schemas.PayoutError.properties.code); карта ошибок строится как объединение enum и примеров, спецификацию стоит поправить
- **`$.paths['/payouts/{payout_id}'].get.responses['404'].content['application/json'].example.error.code`** — код not_found встречается в примере, но не объявлен в enum поля кода ошибки ($.components.schemas.PayoutError.properties.code); карта ошибок строится как объединение enum и примеров, спецификацию стоит поправить
- **`$.paths['/payouts/{payout_id}/cancel'].post.responses['409'].content['application/json'].example.error.code`** — код invalid_status встречается в примере, но не объявлен в enum поля кода ошибки ($.components.schemas.PayoutError.properties.code); карта ошибок строится как объединение enum и примеров, спецификацию стоит поправить

### `error_code_unused` — 3

Что сделал инструмент: правило для кода построено по rules/errors.yml, в примерах его проверить нечем

- **`$.components.schemas.PayoutError.properties.code.enum[3]`** — код bank_unavailable объявлен в enum, но не встречается ни в одном примере; правило обработки построено по справочнику
- **`$.components.schemas.PayoutError.properties.code.enum[4]`** — код amount_limit_exceeded объявлен в enum, но не встречается ни в одном примере; правило обработки построено по справочнику
- **`$.components.schemas.PayoutError.properties.code.enum[6]`** — код internal_error объявлен в enum, но не встречается ни в одном примере; правило обработки построено по справочнику

### `undeclared_status_code` — 4

Что сделал инструмент: для кода достроено общее правило ERROR_MAP по HTTP-коду

- **`$.paths['/balance'].get`** — операция getBalance не объявляет 400, 401, 402, 404, 409, 422, 429, 500, объявленные у соседних операций (createPayout, getPayoutStatus); для них достроены общие правила
- **`$.paths['/payouts'].post`** — операция createPayout не объявляет 404, объявленные у соседних операций (getPayoutStatus); для них достроены общие правила
- **`$.paths['/payouts/{payout_id}'].get`** — операция getPayoutStatus не объявляет 400, 402, 409, 422, 429, 500, объявленные у соседних операций (createPayout); для них достроены общие правила
- **`$.paths['/payouts/{payout_id}/cancel'].post`** — операция cancelPayout не объявляет 400, 401, 402, 404, 422, 429, 500, объявленные у соседних операций (createPayout, getPayoutStatus); для них достроены общие правила

## 6. Справки

Факты, о которых читателю стоит знать; решения за человека инструмент здесь не
принимал. Списки сокращены до первых 5 элементов в группе — полный набор
виден в `./integrate analyze --spec novapay.yaml`.

**`field_role_unknown`** — 3

- `$.paths['/balance'].get.responses['200'].content['application/json'].schema.properties.balance` — необязательное поле `balance` (integer): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; в запрос оно не попадёт; если оно нужно, задайте роль фрагментом ниже
- `$.paths['/balance'].get.responses['200'].content['application/json'].schema.properties.hold` — необязательное поле `hold` (integer): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; в запрос оно не попадёт; если оно нужно, задайте роль фрагментом ниже
- `$.paths['/webhooks/payout'].post.responses['200'].content['application/json'].schema.properties.received` — необязательное поле `received` (boolean): роль не выведена — ни имя, ни ограничения не совпали ни с одной ролью rules/roles.yml; в запрос оно не попадёт; если оно нужно, задайте роль фрагментом ниже

**`operation_unmapped`** — 2, подробности в разделе 4

- `$.paths['/balance'].get` — распознана как balance, но в Provider::BaseService нет метода для такой роли; она генерируется отдельным публичным методом и остаётся вне контракта
- `$.paths['/payouts/{payout_id}/cancel'].post` — распознана как cancel, но в Provider::BaseService нет метода для такой роли; она генерируется отдельным публичным методом и остаётся вне контракта

## 7. Что доделать руками

1. Вызовите `verify_webhook_signature(raw_body, headers)` на маршруте вебхука до разбора JSON: `process_callback` получает уже разобранное тело, а HMAC считается по сырым байтам — либо кладите байты и заголовки в аргумент по выражениям rules/contract.yml
2. Проверьте значения фикстуры `createPayout 400`: тело собрано не из примеров спецификации (`schema_example`)
3. Проверьте значения фикстуры `createPayout 409`: тело собрано не из примеров спецификации (`schema_example`)
4. Проверьте значения фикстуры `createPayout 500`: тело собрано не из примеров спецификации (`schema_example`)
5. Проверьте значения фикстуры `getPayoutStatus 200`: тело собрано не из примеров спецификации (`schema_example`)
6. Проверьте значения фикстуры `cancelPayout 200`: тело собрано не из примеров спецификации (`schema_example`)
7. Проверьте значения фикстуры `payoutWebhook 200`: тело собрано не из примеров спецификации (`schema_example`)
8. Проверьте значения фикстуры `getBalance 200`: тело собрано не из примеров спецификации (`schema_example`)
9. Проверьте значения фикстуры `webhook payout.cancelled`: тело собрано не из примеров спецификации (`schema_example`)
10. Проверьте значения фикстуры `webhook payout.processing`: тело собрано не из примеров спецификации (`schema_example`)
11. Проверьте значения фикстуры `webhook signature_invalid`: тело собрано не из примеров спецификации (`synthesized`)
12. Проверьте значения фикстуры `webhook unknown_event`: тело собрано не из примеров спецификации (`synthesized`)

Итого: 12 пунктов.
