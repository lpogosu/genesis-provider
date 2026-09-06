# Состояние конвейера

Что уже работает, как это проверить и что делать следующим. Файл для людей и
для агентов: читается после `CLAUDE.md`, обновляется в том же коммите, что
закрывает этап. Всё, что здесь написано, обязано воспроизводиться командой —
иначе это не состояние, а надежда.

Обновлено: 5 сентября 2026, после правки контракта по письменным ответам
экспертов (вопросы 18–25 в `docs/QUESTIONS.md`): сгенерированный сервис
читает `operation.id`, `operation.amount` и `operation.payout_requisite`, а
не плоские поля, которых у платформы нет. В каталоге семь спек: выданная,
три свои (`cardpay`, `depositbank`, `broken`) и три чужие настоящие; все семь
проходят `./integrate` без стектрейса одной командой.

---

## Стадии

```
SpecLoader → OverlayApplier → Analyzers + Matchers → IR → Generators → Validators → Reporter
  готов        готов          10 из 10     готов     готов   4 из 4       нет     Summary + report.md

Поверх конвейера: CLI (./integrate) и веб — Rack-API плюс собранный фронт,
обе точки входа зовут один и тот же Runner.
```

| Стадия | Состояние | Точка входа | Проверка |
|---|---|---|---|
| SpecLoader | готов | `SpecGen::SpecLoader.load(path, overlay: nil)` | `spec/unit/specgen/spec_loader/` — 18 видов плохого входа дают `SpecGen::Error` с файлом и JSONPath |
| OverlayApplier | готов: OpenAPI Overlay 1.0.0, `update` и `remove`, подмножество JSONPath то же, что печатает отчёт | `SpecGen::Overlay.apply(raw, file:)` через `SpecLoader.load(path, overlay:)`; флаги `--overlay` у `generate` и `analyze` | `./integrate --spec spec/fixtures/specs/novapay.yaml --overlay spec/fixtures/overlays/novapay.yaml` — два `conditional_required_hint` исчезают, условие читается как `dependentRequired` 1.00; `spec/unit/specgen/overlay/` — 58 примеров, в том числе полный цикл «отчёт → фрагмент → overlay → повторный прогон» |
| Rules (справочники) | готов, 11 книг | `SpecGen::Rules.load` | `rules/*.yml`; противоречие между книгами валит загрузку одним `RulesError` со всеми проблемами; одиннадцатая — `rules/assumptions.yml`, допущения проекта для INTEGRATION.md |
| IR | готов | `SpecGen::IR::ProviderProfile` | `docs/IR.md`; `to_h` детерминирован; новый тип `Condition`, у `Idempotency` новый член `conflict_status` |
| Analyzers, часть 1 | готов: Info, Auth, Operation, Schema | `SpecGen::Analyzers::Runner.call` | `./integrate analyze --spec ...` |
| Analyzers, часть 2 | готов: Units, Status, Error, Webhook, Idempotency, Conditions | `SpecGen::Analyzers::Runner.call` | `spec/unit/specgen/analyzers/*_spec.rb`, по одному файлу на анализатор; в каждом есть пример на неоднозначный вход, где ожидается предупреждение |
| Matchers (роли полей) | готов: Name, Type, Constraint, Structure, Composite, Assigner | `SpecGen::Matchers::Assigner.new(rules:).call(subjects)`; вызывается из SchemaReader и ParameterReader | `spec/unit/specgen/matchers/*_spec.rb`, стадия целиком — `spec/unit/specgen/analyzers/field_roles_spec.rb`; на выданной спеке 22 из 26 скалярных полей и все 3 параметра получают роль |
| Generators | готов: четыре артефакта из одной команды | `SpecGen::Generators.call(profile:, rules:, options:)` → `[Artifact]`; `./integrate --spec ... --provider ...` пишет `output/<provider>_service.rb`, `output/INTEGRATION.md` и `output/fixtures.json` | `ruby -c output/<provider>_service.rb`; `bundle exec rubocop --config config/rubocop_generated.yml output/<provider>_service.rb`; `grep '^## ' output/INTEGRATION.md` — ровно девять разделов; `ruby -rjson -e 'JSON.parse(File.read("output/fixtures.json"))'`; `grep '^## ' output/report.md` — ровно семь разделов; golden — `spec/golden/novapay_spec.rb` против `spec/fixtures/golden/novapay/` (все четыре файла); `spec/unit/specgen/generators/` |
| Пакетный прогон | готов | `SpecGen::Batch.new(dir:, rules:).call` → `[Row]`; `./integrate --all --specs <каталог>` | `spec/unit/specgen/batch_spec.rb`; сводка печатается `Reporter::BatchLines`, покрытие берётся из метрик артефакта `report.md` |
| Mock provider | не начат | — | промпт 8 |
| Validators | не начат | — | промпт 9 |
| Reporter | готов: `Summary` в консоли и `report.md` на диске | `SpecGen::Reporter::Summary`, `SpecGen::Generators::ReportGenerator` | `./integrate analyze --spec ... --explain`; `output/report.md` |
| Texts (язык) | готов: ru по умолчанию, en | `SpecGen::Texts.t`, `locales/<код>/*.yml` | `--locale en`; `spec/unit/specgen/texts_spec.rb` следит за полнотой ключей |
| Web (API и фронт) | готов: пять маршрутов, один конверт ошибки, статика из `public/` | `SpecGen::Web.app` через `config.ru`; сервер — `ruby bin/serve --port 9292` | `spec/unit/specgen/web/` — 23 примера; живьём: `curl localhost:9292/api/health`, `/api/specs`, `POST /api/generate {"spec_id":"novapay"}`; содержимое артефактов из API байт-в-байт совпадает с тем, что пишет `./integrate --all` |

---

## Язык

Правило — в `CLAUDE.md`, раздел «Язык»; термины — в `docs/GLOSSARY.md`.
Коротко: всё для человека по-русски, всё для машины по-английски. Тексты для
человека не пишутся строками в коде, а лежат в `locales/<код>/<стадия>.yml` и
читаются через `Texts.t('ключ', имя: значение)` и `Texts.plural(n, 'сущ')`.

Состояние перевода на 4 сентября 2026 — `lib/` переведён целиком:

| Что | Где тексты | Ключей |
|---|---|---|
| CLI, справка, экран `analyze` | `locales/*/cli.yml` | 120 (ru) / 113 (en) |
| Генерация: строки CLI об артефактах, комментарии, которые презентеры кладут в сгенерированный код, и пояснения `_todo` в фикстурах | `locales/*/generators.yml` | 101 (ru) / 100 (en) |
| Ошибки загрузчика спецификации, формат места ошибки | `locales/*/spec_loader.yml` | 26 |
| Ошибки загрузчика справочников | `locales/*/rules.yml` | 117 |
| Предупреждения и обоснования всех анализаторов, кроме схем | `locales/*/analyzers.yml` | 147 |
| Предупреждения и обоснования: схемы и условная обязательность | `locales/*/schemas.yml` | 21 |
| Обоснования голосов и решений матчеров полей, предупреждения о ролях | `locales/*/matchers.yml` | 42 |
| Комментарии во всём `lib/` | в коде, по `docs/GLOSSARY.md` | — |
| Описания примеров в тестах `it '...'` | остаются английскими намеренно | — |

Всего ключей: 499 в `ru`, 492 в `en` (разница — формы множественного числа).
Overlay-фрагменты в обеих локалях побайтово одинаковы: это текст для машины;
комментарии `#` внутри фрагмента — проза для человека, они переведены.

Известные хвосты:

- Справка `--help` следует `SPECGEN_LOCALE`, а не флагу `--locale`: Thor
  читает `desc` при загрузке класса. Записано в README.
- Сообщения самих библиотек (Psych, JSON, ошибки файловой системы)
  подставляются как есть, по-английски: это чужой текст внутри нашего.
- Строка экрана «dedup on 409» одинакова в обеих локалях намеренно: это
  термин черновика IETF, а не фраза.

Закрытый хвост: константа `UNDERIVED = 'не выведено'` в `ir/units.rb`,
`ir/idempotency.rb`, `ir/signature_profile.rb` убрана — члены-`Derived` этих
типов обязательны, обоснование приходит из анализаторов через `Texts`.

---

## Живая демонстрация на сегодня

```sh
./integrate --all                      # все семь спецификаций каталога, сводная таблица
./integrate --all --specs tmp/real-specs --output tmp/batch   # скачанные чужие спеки
./integrate --spec spec/fixtures/specs/cardpay.yaml --provider cardpay      # карта, Bearer, Standard Webhooks
./integrate --spec spec/fixtures/specs/depositbank.yaml --provider depositbank  # OAS 3.1, JPY, OAuth2, без вебхуков
./integrate --spec spec/fixtures/specs/broken.yaml --provider broken        # одиннадцать дыр, генерация не блокируется
./integrate --spec spec/fixtures/specs/novapay.yaml --provider novapay
./integrate --spec spec/fixtures/specs/novapay.yaml --overlay spec/fixtures/overlays/novapay.yaml  # условная обязательность становится dependentRequired 1.00
ruby -c output/novapay_service.rb
grep '^## ' output/report.md
bundle exec rubocop --config config/rubocop_generated.yml output/novapay_service.rb
ruby -rjson -e 'JSON.parse(File.read("output/fixtures.json")); puts "JSON OK"'
./integrate analyze --spec spec/fixtures/specs/novapay.yaml
./integrate analyze --spec spec/fixtures/specs/novapay.yaml --explain
./integrate analyze --spec spec/fixtures/specs/novapay.yaml --provider novapay
./integrate analyze --spec spec/fixtures/specs/novapay.yaml --locale en
```

Первая команда — экран с провайдером, серверами, авторизацией, единицами
суммы («minor, x100 (ISO 4217: экспонента RUB 2)»), пятью статусами, вебхуком
с четырьмя событиями и профилем подписи, идемпотентностью («dedup on 409»),
картой ошибок («7 в enum + 3 только в примерах; дедупликация 409 у
createPayout»), девятью условиями взаимодействия, пятью операциями с ролями
их параметров (`заголовок Idempotency-Key (необязательный)
role=idempotency_key`), восемью схемами со сводкой ролей («Роли полей: 22 из
26 скалярных (по справочнику 21, эвристика 1); не выведено 4; контейнеров 5»)
и ролью в строке каждого поля, и восемнадцатью предупреждениями (0 ошибок,
6 предупреждений, 12 справок). Вторая добавляет обоснование под каждым
выведенным значением — у роли поля это арифметика голосов («композитное
сопоставление: name 5.0 (…), structure 4.0 (…), type 1.0 (…) = 10.0 из
14.0») — и Overlay-фрагмент под каждым исправимым предупреждением.

Первая команда — генерация: `Генерация сервиса... ok (379 строк) ->
output/novapay_service.rb` и итог по предупреждениям. Файл проходит
`ruby -c` и RuboCop по `config/rubocop_generated.yml`. Внутри: четыре метода
контракта с именами из `rules/contract.yml`, `STATUS_MAP` / `ERROR_MAP` /
`RETRY_POLICY` / `EVENT_MAP` замороженными хешами с отсортированными
ключами, `check_conditions` с пятью проверками, пересчитанными в мажорные
единицы (`operation.amount < 1000` при `minimum: 100000`), ветка
`DEDUP_STATUS` для 409 со схемой успеха, `verify_signature!` с
`OpenSSL.fixed_length_secure_compare`, UUID v5 через `Digest::SHA1`,
`cancel` и `balance` отдельными публичными методами. Те же команды на
чужих спецификациях (`spec/fixtures/specs/real/`) дают `ruby -c`-валидные
и RuboCop-чистые файлы, полные TODO.

Та же первая команда второй строкой пишет `Генерация документации... ok
(218 строк) -> output/INTEGRATION.md`: девять нумерованных разделов
(авторизация и секрет, ENV, таблица методов с идемпотентностью, статусы и
события, ошибки с действиями и RETRY_POLICY словами, YAML-фрагмент
ProviderGateway с пересчётом `minimum: 100000` в `1000.00 RUB`, схема
подписи с примером вычисления без секрета, пошаговое подключение, принятые
допущения — восемь из `rules/assumptions.yml` плюс допущения прогона: два
намёка условной обязательности 0.50 и ограничение отмены 0.60). Таблицы
документа собираются из тех же презентеров, что константы сервиса
(`Service::Tables#status_mappings`, `#code_rules`, `#retry_policy`,
`Precheck#description`, `Signature#value`), поэтому совпадают с
`STATUS_MAP` / `ERROR_MAP` / `RETRY_POLICY` по построению. На чужих
спецификациях документ честно говорит «в спецификации не объявлено» и
перечисляет, что взято по умолчанию (PayPal — 8 строк допущений прогона,
Adyen Transfers — 60).

Та же команда третьей строкой пишет `Генерация фикстур... ok (461 строка)
-> output/fixtures.json`: все три вида, которых требует критерий T5.3, —
пять запросов (по одному на операцию, с заголовками авторизации,
`Content-Type` и ключом идемпотентности), пятнадцать ответов (у
`createPayout` все восемь объявленных кодов, включая 201, 409 и ошибки) и
шесть уведомлений (четыре события enum плюс две негативные: заведомо
неверная подпись и незнакомое событие). Подпись уведомлений настоящая:
64 шестнадцатеричных символа `HMAC-SHA256(raw_body, test_webhook_secret)`,
которые проверяет юнит-тест, а фикстура годится для `process_callback` как
есть. Каждая фикстура несёт `expected` (внутренний статус по `STATUS_MAP`,
действие по `ERROR_MAP`, `dedup` у кода конфликта) и `source`. На чужих
спецификациях файл остаётся разумного размера: Adyen Payout 24 КБ, Adyen
Transfers 73 КБ, PayPal Payouts 16 КБ.

Та же команда четвёртой строкой пишет `Генерация отчёта... ok (228 строк)
-> output/report.md`: семь разделов. Сводка таблицей (операции, схемы и
поля, роли по источникам, статусы, события, коды ошибок, условия,
предупреждения) и список записанных артефактов с числом строк — их отдаёт
`Runner`, отчёт идёт в `ORDER` последним. Покрытие спецификации одной
цифрой: у novapay 75 % (54 из 72 элементов), у PayPal Payouts 33 %, Adyen
Payout 21 %, Adyen Transfers 35 %, Mollie 27 %, ЮKassa 37 %. Дальше
неоднозначности по кодам с готовыми Overlay-фрагментами и инструкцией, как
склеить из них один файл; операции вне контракта таблицей (`cancelPayout` →
`cancel(operation)`, `getBalance` → `balance()`); противоречия самой
спецификации (три `error_code_undeclared`, три `error_code_unused`, четыре
`undeclared_status_code`); справки, сокращённые до пяти элементов в группе;
нумерованный чеклист ручной работы с итогом «11 пунктов». На чужих
спецификациях отчёт остаётся читаемым: Mollie с 1855 предупреждениями — 1208
строк, Adyen Transfers — 861.

Команда `analyze` доказывает разбор целиком (критерии экспертов E1.1,
E1.2, E1.3; техжюри T1.1–T1.5) и провайдер-нейтральность ядра (E4.2).

Сценарий первого чекпоинта — `docs/CHECKPOINT-1.md`.

---

## Что известно о `novapay.yaml` после разбора

Коротко, подробности в `docs/CHECKPOINT-1.md`, раздел 4.

- Пять операций, не шесть. Роли: `create_payout`, `fetch_status`, `cancel`,
  `webhook`, `balance`; две последние вне контракта `BaseService`.
- Единицы суммы: `type: integer` и `enum: [RUB]` в теле запроса дают минорные
  единицы с экспонентой 2 по ISO 4217; «Сумма в копейках» и `minimum:
  100000 = 1000.00 RUB` только подтверждают. Ни одного предупреждения.
- Пять статусов — все по канону кейса с уверенностью 1.0; один и тот же
  enum объявлен в `PayoutResponse` и `WebhookPayload`, записан один раз.
- `409` на `POST /payouts` возвращает `PayoutResponse` — путь дедупликации
  (действие `:dedup`, `Idempotency#conflict_status = 409`), а на
  `POST /payouts/{id}/cancel` — `ErrorResponse` (`reject`). Карту ошибок
  нельзя строить по HTTP-коду, только по коду вместе со схемой ответа.
- Коды `unauthorized`, `not_found`, `invalid_status` есть в примерах, но не в
  enum `PayoutError.code` — три `error_code_undeclared`; `bank_unavailable`,
  `amount_limit_exceeded`, `internal_error` есть в enum, но ни в одном
  примере — три `error_code_unused`. Карта ошибок — объединение, 10 кодов.
- У `GET /payouts/{payout_id}`, `POST /payouts/{id}/cancel` и `GET /balance`
  не объявлены коды, объявленные у соседей — четыре справки
  `undeclared_status_code` и общие правила для 400–500. Ответы входящего
  вебхука в карту не входят: их пишем мы.
- Вебхук: `security: []` — единственный маркер; поле события `event` найдено
  структурно (все четыре значения после снятия префикса читаются как
  статусы); подпись `X-NovaPay-Signature` совпала с профилем `novapay` из
  `rules/signatures.yml`, «HMAC-SHA256» из описания подтверждает алгоритм.
- `Idempotency-Key` объявлен `required: false` только у `createPayout`;
  отправляется всегда (`send_when_optional`).
- Девять условий взаимодействия: `Retry-After` и 429 у `createPayout`,
  необязательный ключ идемпотентности, `minimum: 100000` у суммы, `enum
  [RUB]` у валюты, `maxLength: 64` у `external_id`, `enum [sbp, card]` у типа
  получателя, `pattern` телефона и отмена только в `pending` и `processing`
  — последнее из прозы описания `cancelPayout`, эвристика 0.6.
- Условная обязательность `bank_code` / `card_number` есть только в прозе
  описания; вытянута с уверенностью 0.5 и Overlay-фрагментом.
- Роли полей: 31 поле = 5 контейнеров (`recipient`, `error` — роли получают
  их вложенные поля) + 26 скалярных, из них 21 по точному синониму
  `rules/roles.yml` (`:registry` 0.90), 1 эвристикой — `PayoutError.code`
  0.71 по слабому токену `code` вместе с родителем `PayoutError`, — и 4 без
  роли: `WebhookPayload.event` (обязательное, предупреждение; роли события в
  IR нет намеренно, событие читает WebhookAnalyzer), `balance`, `hold`,
  `received` (необязательные, справки). Все три параметра — по справочнику:
  `Idempotency-Key`, `payout_id` в пути, `X-NovaPay-Signature` через
  `header_names` `rules/signatures.yml`. Ни одного конфликта.

---

## Свои альтернативные спецификации

Балл за универсальность (E4.1, 7 баллов) нельзя получить, показав работу на
одной выданной спеке. `spec/fixtures/specs/` держит семь файлов: выданная,
три свои и три чужие настоящие. Одна команда, одна таблица:

```sh
./integrate --all
```

| Спецификация | Провайдер | Операций | С ролью | Покрытие | Замечаний | Файлов |
|---|---|---|---|---|---|---|
| `broken.yaml` | broken | 6 | 5/6 | 43 % | 64 | 4 |
| `cardpay.yaml` | cardpay | 6 | 6/6 | 66 % | 41 | 4 |
| `depositbank.yaml` | depositbank | 6 | 5/6 | 61 % | 43 | 4 |
| `novapay.yaml` | novapay | 5 | 5/5 | 75 % | 18 | 4 |
| `real/adyen_payout_v68.yaml` | adyen_payout_v68 | 6 | 5/6 | 21 % | 211 | 4 |
| `real/adyen_transfers_v4.yaml` | adyen_transfers_v4 | 12 | 11/12 | 35 % | 333 | 4 |
| `real/paypal_payouts_v1.json` | paypal_payouts_v1 | 4 | 4/4 | 33 % | 86 | 4 |

Смысл таблицы не в цифрах, а в том, что разница между провайдерами видна в
одном экране и среди них есть чужие. Что именно различается:

| | novapay | cardpay | depositbank | broken |
|---|---|---|---|---|
| Версия OAS | 3.0.3 | 3.0.3 | **3.1.0** | 3.0.3 |
| Авторизация | apiKey в заголовке | **http bearer** | **oauth2 clientCredentials** | apiKey в заголовке |
| Единицы | minor, x100 (RUB, экспонента 2) | minor, x100 (USD, экспонента 2) | **major, x1 (JPY, экспонента 0)** | **не выведены** |
| Тип суммы | `integer` | `integer` | **`number` с дробным примером** | `integer` без описания |
| Идемпотентность | `Idempotency-Key`, необязательный, dedup 409 | **`X-Request-Id`, обязательный**, dedup 409 | **`Idempotence-Key`, обязательный, без dedup** | **не объявлена** |
| Вебхук | кастомный `X-NovaPay-Signature`, hex | **Standard Webhooks**, base64, префикс `v1,` | **нет вообще, только опрос** | **есть, подписи нет** |
| Получатель | `recipient`: type / phone / bank_code | **`destination`: method / pan / expiry / holder** | **`remitter`: settlement_type / zengin / swift** | **`party`: kind / acct / nm** |
| Статусы | pending … cancelled | **queued / sending / succeeded / declined / returned** | **initiated / under_review / posted / returned / rejected** | **WAITING / DONE / NOTOK + два только в примерах** |
| Условная обязательность | проза, 0.50 | проза, 0.50 | **`dependentRequired` и `if/then/else`, 1.00** | нет |
| Общих имён полей с novapay | — | 6 из 35 | 3 из 37 | **0 из 19** |

Последняя строка — ответ на вопрос «а это не переименованный NovaPay?».
Общими остались только всеотраслевые слова (`currency`, `created_at`,
`code`, `message`, `error`, `received`); у `broken.yaml` нет и их.

### Что каждая проверяет

**`cardpay.yaml`** — выплата на карту (push-to-card) в долларах. Ветки,
которых у выданной спеки нет: наследование корневого `security` вместо
объявления у каждой операции, обязательный ключ идемпотентности, английская
лексика единиц (cents, minor units) в `unit_words`, профиль
`standard_webhooks` из `rules/signatures.yml` целиком (три заголовка,
подписываемая строка из идентификатора, метки времени и тела, base64,
префикс версии, допуск 300 секунд), роль `refund` у операции вне контракта.
Роль `recipient_type` выводится не по имени (`method` — слово из
`generic_tokens`), а по значениям enum вместе с родителем; `card_number` —
по токену `pan` и шаблону. Ограничение отмены вытянуто из английской прозы.

**`depositbank.yaml`** — приём депозитов в иенах, OpenAPI 3.1. Единственная
спека, где условная обязательность объявлена формально: `if/then/else` на
`settlement_type` и `dependentRequired` на `intermediary_swift` читаются
нативно с уверенностью 1.00 против 0.50 у прозы NovaPay. Единственная, где
вебхука нет вовсе: `process_callback` отказывает `webhooks_not_supported`, и
отчёт говорит почему, а не оставляет пустой метод. Единственная с обратным
направлением денег (`create_deposit`), с мажорными единицами и с валютой
нулевой экспоненты — множитель 1 берётся из таблицы ISO 4217 по коду
валюты, а не из слова в описании.

**`broken.yaml`** — главный экспонат: одиннадцать намеренных дыр,
пронумерованных в шапке файла, и по строке отчёта на каждую. Генерация не
блокируется ни на одной: четыре артефакта, `ruby -c` и RuboCop чистые.
Циклического `$ref` в файле нет намеренно — загрузчик отвергает его целиком
(так он ведёт себя на спецификации Stripe), и вместо полусотни осмысленных
строк отчёта получилась бы одна строка об ошибке загрузки; отказ загружать
цикл проверяется в `spec/unit/specgen/spec_loader/`.

| Дыра | Что видит человек в `report.md` |
|---|---|
| нет `operationId` у шести операций | `operation_id_missing` шесть раз: «в этом отчёте и в сгенерированном коде она названа `GET /limits`» |
| нет примеров | чеклист раздела 7: одиннадцать фикстур с источником `schema_example`, `synthesized` или `undeclared` |
| `xref_tag_9` обязательное, неопознаваемое | `required_field_role_unknown`, `xref_tag_9: nil` с TODO в payload, пункт 3 чеклиста |
| `aux_flag_b` необязательное | одна справка: «в payload не включено» |
| enum статусов против примеров | `status_missing_from_enum` дважды, `webhook_event_undeclared` дважды, `status_unmapped` трижды |
| `200` одним `description` | `schema_unresolved`: «либо опишите схему, либо объявите ответ без тела кодом 204» |
| `content` без `schema` | `schema_unresolved`: «не объявлено читаемой схемы» |
| сумма без единиц | `currency_unknown`, слот `x-specgen-currency`, `AMOUNT_MULTIPLIER = 1` с TODO |
| необъявленные коды ответов | `undeclared_status_code` четыре раза со ссылкой на соседнюю операцию |
| код в примере против enum | `error_code_undeclared` один раз и `error_code_unused` четыре раза |
| вебхук без подписи | `signature_profile_incomplete` и готовый фрагмент `x-specgen-signature` |
| `ref` двусмысленное | `required_field_role_unknown` и слот `x-specgen-role` |
| две суммы в одной схеме | `field_role_conflict` дважды, с баллами обоих полей |

Отдельно про `PART_DONE`. Значение из примера уведомления, которого нет в
enum. Снятие ведущего слова дало бы `DONE` в `approved` с уверенностью 0.90
— частично проведённый платёж ушёл бы в платформу как выплаченный. Вместо
этого вывода нет вовсе, а предупреждение называет отвергнутого кандидата и
объясняет отказ. Это единственное место, где инструмент осознанно не берёт
лучшего кандидата: направление ошибки запрещено, а названный near-miss —
не пустое место.

### Чем это лечилось

Всё, чего инструмент не узнал в новых спеках, закрыто строками в `rules/`,
ни одной ветки по провайдеру в `lib/`:

| Справочник | Что добавлено | Откуда |
|---|---|---|
| `rules/statuses.yml` | `sending` и `under_review` в синонимы `in_progress` | cardpay, depositbank |
| `rules/roles.yml` | `client_reference` в external_id, `posted_at` в completed_at, `settlement_type` в recipient_type, `reason_text` в error_message | depositbank, cardpay |
| `rules/operations.yml` | `transaction` и `transactions` в лексику `create_payout` | broken: `POST /transactions` выигрывал `cancel`, потому что этот ресурс был только у `fetch_status` и `cancel` |
| `rules/errors.yml` | правило `review` (комплаенс, KYC, санкции) в escalate; `closed` и `mismatch` в правило `rejected` | depositbank, cardpay |
| `rules/conditions.yml` | значение условия больше не захватывает точку предложения | cardpay: фраза «Required when method is card.» давала `const: card.` в предложенном overlay |

Четыре дефекта ядра, которые нашли новые спеки, чинились кодом, потому что
данными не выражаются: путь к коду ошибки брался из схемы успеха; `examples`
массивом на уровне схемы (законный в 3.1) не читался; сгенерированный код
ломал `Style/NumericLiterals` на любой границе суммы от 10 000 и
`Naming/VariableNumber` на любом поле вида `address_line_1`; фикстура ответа
без схемы выдавала несуществующий пример за пример спецификации. Подробности
— в соглашениях ниже.

---

## Соглашения, установленные в ходе работы над анализаторами

Не выводятся из кода при беглом чтении, поэтому записаны здесь.

**Каждый анализатор** наследует `Analyzers::Base`, получает `document`,
`profile`, `rules`, `options` и заполняет свою часть профиля. Всё выведенное —
`IR::Derived` с `evidence`, которое потом печатает отчёт. `Derived.unknown`
всегда сопровождается `profile.warn`: неизвестное без предупреждения — это
молчаливая дыра.

**Анализаторы независимы, общее — в reader'ах.** Ни один не читает то, что
записал другой. Всё, что нужно двоим, — общий reader в
`lib/specgen/analyzers/`, пересчитываемый от документа: `SchemaIndex`,
`RoleLookup`, `ExampleReader`, `StatusReader`, `DedupReader`, `Base#role_of`.
Список и назначение — в `docs/IR.md`, раздел «Границы слоёв».

**Роли полей и параметров проставляют SchemaAnalyzer и OperationAnalyzer**
в момент чтения схемы и операции — через общий компонент
`Matchers::Assigner`, так же как роль операции даёт общий `OperationRole`.
Отдельной стадии, которая читала бы уже собранные поля профиля, нет
намеренно: это нарушило бы правило «анализаторы не читают то, что записал
другой». Цена решения — SchemaReader и ParameterReader принимают
необязательный `assigner:`; анализаторы, которым роли не нужны (Units,
Status, Conditions, Webhook, Idempotency), читают параметры без него и
получают `Derived.unknown` с пометкой «роли проставляют матчеры». Поле
суммы, валюты, статуса они находят через `RoleLookup`. Код ошибки узнаётся
структурно (токен `code` под родителем-ошибкой) теми же проверками
`NameMatcher#token` и `StructureMatcher.parent_hit`.

**`RoleLookup` отвечает тем же, чем матчеры, и словарём вперёд.** Сначала
точный синоним `rules/roles.yml` (`NameMatcher#exact`). Если словарь молчит
об этой роли во всём документе, спрашивается `Matchers::Composite` — тот же
композит, который проставляет роли полей в IR, — по одному разу на каждое
имя документа, и ответом становится его лучший кандидат. Порога у reader'а
нет намеренно: роль ниже 0.6 уже присвоена полю и уже напечатана в отчёте с
баллами, и второе умолчание о том же поле — это молчаливая дыра, из-за
которой отчёт на `broken.yaml` на одной странице говорил «роль amount 0.43»,
а на соседней «поле суммы не найдено ни в одной схеме». Вместо порога
уверенность вывода понижается до уверенности роли (`RoleLookup#temper`):
единицы по полю `amt` — `heuristic 0.43`, а по полю `amount` — как были.
Роль, названную словарём хотя бы у одного поля документа, эвристике не
отдаём: если провайдер написал `amount`, множитель считается по нему, а не
по соседнему `amt`. Это же держит стоимость: композитный проход
запускается только там, где словарю сказать нечего (на novapay, cardpay,
depositbank и трёх чужих спеках он не запускается вовсе, на broken.yaml —
по 19 именам).

**Как считается роль поля.** Четыре матчера голосуют за роли баллом
в [0, 1]; балл роли = Σ вес × балл, уверенность = балл / сумма всех весов
(14: name 5, constraint 4, structure 4, type 1), потолок 0.95. Знаменатель
фиксирован намеренно: матчер, которому нечего сказать, снижает уверенность
— о поле без типа и ограничений известно меньше. Опознают роль только имя и
ограничения (pattern / example / enum); расположение, тип, `maxLength` и
числовые границы лишь подтверждают уже опознанную — иначе каждое строковое
поле под `recipient` получало бы пять кандидатов с равным баллом, а `page`
с `minimum: 1` становился суммой. Слабый токен из `generic_tokens` (`code`)
опознаёт роль только вместе с родителем: `error.code` — кандидат,
`countryCode` — нет. Частичное совпадение токенов, где общие слова — только
из `generic_tokens` (`debug_id` ~ `id`, `full_name` ~ `bank_name`), голоса
не даёт. Все веса, баллы, пороги и списки слов — секция `matchers`
`rules/roles.yml`; загрузчик отказывает, если один матчер в одиночку
достигает порога.

**`:registry` против `:heuristic` у роли поля.** Точный синоним из
`names` (или имя заголовка из `rules/signatures.yml` /
`rules/idempotency.yml`) — источник `:registry` с уверенностью справочника
0.90, остальные голоса лишь перечисляются как подтверждения; словарь
точнее любой арифметики. Всё остальное — `:heuristic` с насчитанной
уверенностью. Сильная эвристика может перевесить словарь по очкам
(`bank.id` с шаблоном БИК — `bank_code` 0.54, а не `provider_operation_id`),
и тогда решение эвристическое и попадает в отчёт.

**Порог 0.6 решает не «присваивать ли роль», а «попадёт ли решение в
отчёт»** (эксперты, чекпоинт 1). Ниже порога или при отрыве от второго
кандидата меньше `margin` 0.1 роль всё равно получает лучший кандидат, а
предупреждение `field_role_low_confidence` перечисляет баллы всех
кандидатов — для обязательного поля это `:warning` (оно войдёт в код с
TODO), для необязательного `:info`. Без роли поле остаётся только когда
никто не опознал (`required_field_role_unknown` / `field_role_unknown`) или
когда оно проиграло конфликт и следующего кандидата нет. Одна роль у двух
полей одной схемы — `field_role_conflict`: роль остаётся у поля с большей
уверенностью (при равенстве — у первого), второе получает следующего
кандидата или остаётся без роли; роли из overlay в конфликт не вступают,
`repeatable` в `rules/roles.yml` пуст намеренно. Единственный
`Derived.unknown` без предупреждения — поле-контейнер (объект или массив):
роли получают его вложенные поля, это устройство модели, а не пробел.

**Расширение `x-specgen-role`** на схеме свойства или на объекте параметра
читается как источник `:overlay` 1.0; значение вне `IR::Roles::FIELD`
отвергается с `spec_element_unsupported`. Ровно его предлагают
предупреждения о ролях; для поля без кандидата слот — `TODO`, которое
читатель расширения отвергнет, пока человек его не заменит.

**Префикс статуса снимается только по адресу события.** `payout.completed`
-> `completed` — молча и с прежней уверенностью: `.`, `:` и `/` разделяют
адрес события, а не имя статуса. Ведущие слова внутри самого имени решают
две секции `rules/statuses.yml`: `modifiers` — слова, меняющие смысл статуса
за ними (`PART_DONE` не читается как `DONE`: частично проведённый платёж не
выплачен, это запрещённое направление ошибки, и значение остаётся
невыведенным с предупреждением, называющим отвергнутого кандидата), а
`tail_confidence` 0.5 — уверенность всего остального
(`authAdjustmentRefused` -> `refused` у Adyen Transfers: читаем, но ниже
порога и с записью в допущения прогона, а не как синоним справочника с 0.90).

**Ответ, объявленный одним `description`.** Ветка «`content` есть, `schema`
нет» давала `body_schema_unreadable`, ветка «`content` нет вовсе» молчала.
Теперь обе дают `schema_unresolved`. Молчим только там, где тела нет по
смыслу: 1xx, 204, 205, 304, `default` (RFC 9110) и любые ответы входящего
вебхука — их пишем мы. На Mollie проверка нашла настоящий пробел:
`202` у `release-authorization` не описывает тело.

**Проза — только подтверждающий сигнал.** Слово «копейках», «HMAC-SHA256»,
«только в статусах …» никогда не первичный источник: единицы даёт тип и
ISO 4217, алгоритм — профиль справочника, статусы отмены — enum. Совпало —
попадает в обоснование; разошлось — `units_inconsistent`,
`signature_profile_conflict`, `condition_unclear`. Лексика для этого лежит в
`rules/*.yml` (`unit_words`, `algorithm_words`, `status_restriction`), не в
коде.

**Расширения overlay `x-specgen-*`** читаются анализаторами как источник
`:overlay`, и ровно они предлагаются в `suggested_overlay`. Таблица — в
`docs/IR.md`. Значение вне словаря IR отвергается с
`spec_element_unsupported`.

**Стадия overlay стоит между определением версии и проверкой структуры.**
До разрешения `$ref` — иначе `$.components.schemas.X` перестала бы быть
единственным местом и правка задела бы одну копию из нескольких. После
определения версии — файл, который вообще не OpenAPI, отвергается раньше,
чем к нему применяют поправки. Перед проверкой структуры — она контракт
загрузчика с остальным конвейером и обязана видеть тот документ, который
конвейер увидит, иначе overlay протащил бы схему с опечаткой в `type` прямо
в анализаторы. Анализаторы про overlay не знают ничего и не менялись.

**Подмножество JSONPath у целей overlay — ровно то, что печатает наш
отчёт.** `JsonPath.parse` — строгая обратная операция к `JsonPath.build`
(имя через точку, ключ в скобках в кавычках, индекс массива), и это
проверяется round-trip-тестом. Движок общего вида (`..`, `*`, фильтры) не
писан намеренно: цели мы предлагаем сами, а цель, адресующая несколько узлов
сразу, сделала бы ответ «что именно переопределено» непроверяемым.
Синтаксис вне подмножества — ошибка файла overlay, а не тихий пропуск.

**Битый overlay — `OverlayError`, ненайденная цель — предупреждение.**
Граница проходит по тому, известно ли намерение. Файл, который нельзя
прочитать как overlay (нет `overlay` или `actions`, действие без `target`,
действие сразу с `update` и `remove`), не даёт ни одного действия, о котором
человек просил, — прогон останавливается с именем файла и местом внутри
него. Цель, которой нет в спецификации, — расхождение версий: действие
пропускается, остальные применяются, а в профиль идёт
`overlay_target_missing`, потому что генерацию не блокирует ничто.

**Предупреждения стадии пишет сама стадия, а не анализатор.** Только
applier знает, что стояло в спецификации до слияния: после него документ
единый, и анализатор честно назвал бы переопределённое значение структурным.
`Overlay::Result#warn_into(profile)` вызывается из `Analyzers::Runner` одной
строкой до анализаторов; `overlay_conflict` рождается на каждом ключе,
который уже был и значил другое, и на каждом `remove`, а простое дополнение
спором со спецификацией не считается. Тот же вызов кладёт лог стадии в
`ProviderProfile#overlay` — единственный член профиля не про провайдера, а
про прогон. Из него раздел 1 отчёта печатает таблицу применённых действий:
переопределённое человеком видно там же, где сказано, из чего собран сервис.
Без overlay член равен nil, таблицы нет, и артефакты байт-в-байт прежние —
golden-эталон не обновлялся.

**Слияние — по тексту Action Object спецификации Overlay 1.0.0:** вложенные
объекты сливаются рекурсивно, скаляры и массивы заменяются целиком, цель-
массив получает `update` последним элементом. Это не JSON Merge Patch
(RFC 7386): `null` присваивается свойству, а не удаляет его — удаление в
Overlay выражается отдельным действием `remove`.

**Новый код предупреждения** добавляется в `IR::Warning::CODES` осознанно, с
комментарием над константой (комментарии внутри `%i[...]` становятся
символами). Ничего про запас. В промпте 5 добавлены три:
`signature_profile_conflict`, `webhook_event_undeclared`, `condition_unclear`;
в промпте 6 — два: `field_role_low_confidence`, `field_role_conflict`.

**Новые ключи справочника статусов** — `modifiers` и `tail_confidence`,
загружает `StatusesBook#modifier` / `#tail_confidence`; приёмка данных —
`spec/unit/specgen/rules/dictionaries_spec.rb` (в том числе проверка, что ни
один модификатор сам не является статусом).

**Новый справочник** — это четыре места сразу: файл `rules/<имя>.yml`, класс
`Rules::<Имя>Book < Book`, строка в `Rules::Registry::BOOKS` плюс
`attr_reader`, дефолт в `spec/support/rules_fixtures.rb` и приёмка данных в
`spec/unit/specgen/rules/dictionaries_spec.rb`. Загрузчик книги обязан падать
на противоречиях, а не брать первое совпадение. Десятая книга —
`rules/errors.yml`: политика действий по ошибкам; `dedup` она не выдаёт
намеренно — дедупликация структурна.

**Фикстурные справочники минимальны намеренно** (одни `names` у ролей плюс
секция `matchers` с теми же числами, что в поставке), и это значит, что
структурные эвристики — код ошибки под родителем, шаблон телефона,
образцы значений — на них не проверить. Такие тесты (ErrorAnalyzer,
OperationAnalyzer, SchemaAnalyzer, все `spec/unit/specgen/matchers/`,
`field_roles_spec`) гоняются на поставляемых `rules/`, и в шапке файла
сказано почему.

**Что показали чужие спецификации после матчеров** (5 сентября 2026,
`./integrate analyze`): PayPal Payouts — 31 роль из 97 скалярных полей,
Adyen Payout — 26 из 214, Adyen Transfers — 130 из 333, ЮKassa — 169 из
375, Mollie — 370 из 1538; ни одного стектрейса. Числа — после пополнения
словаря именами PayPal (`payout_batch_id`, `payout_item_id`,
`sender_batch_id`, `sender_item_id`, `time_created`, `time_completed`,
`time_processed`) и удаления `result_code` из синонимов кода ошибки: у
Adyen `resultCode` — исход авторизации, то есть статус, поэтому имя без
устойчивого смысла оставлено неопознанным (правило 4 шапки
`rules/roles.yml`), и Adyen Payout потерял четыре роли по справочнику
осознанно. `transferInstrumentId` в словарь не вошёл: это счёт получателя,
роли «счёт» в IR нет (см. `account/schet` там же). Роли по справочнику
преобладают везде (в ЮKassa 157 из 169), эвристика добавляет 10–20 % и все
её решения ниже порога попадают в отчёт. Отчёт на большой спеке
(Mollie: 1855 предупреждений, из них 1168 — необязательные поля без роли)
без группировки читать нельзя — задача промпта 11, не матчеров.

**Имена схем** — только через `Analyzers::SchemaNaming`. Компонентная схема
называется именем компонента (по маркеру `x-specgen-ref`, который оставляет
резолвер), инлайновая — `<operationKey>.responses.<status>` или
`<operationKey>.requestBody`. OperationAnalyzer, SchemaAnalyzer и SchemaIndex
обязаны называть одну схему одинаково.

**Пороги и веса** матчера ролей операций — в `rules/operations.yml`, не в
коде. Уверенности условий из прозы — там же, где лексика: 0.5 у условной
обязательности (ниже порога матчеров), 0.6 у ограничения по статусу (ровно
порог: совпадают значения enum, а не любые слова).

**Хелперы в спеках анализаторов** принимают фрагменты OpenAPI как хеши со
строковыми ключами без скобок. Хелпер с любым именованным параметром
превращает такой хеш в kwargs и падает «given 0, expected 1» на своей
строке; поэтому необязательные аргументы у них позиционные
(`def analyze(data, family = :oas30)`).

## Соглашения стадии генерации

**Один генератор — один класс и один шаблон.** `Generators::Runner::ORDER`
перечисляет классы-наследники `Generators::Base`; каждый объявляет
`TEMPLATE` (файл в `templates/`), `KIND` и отдаёт объект-представление.
Добавить артефакт (INTEGRATION.md, fixtures.json, report.md) — добавить
класс в `ORDER`, шаблон в `templates/` и представление; `Runner`, `Writer`,
`Naming` и CLI не меняются. `Base#render` оборачивает любую ошибку шаблона
в `GenerationError` с именем шаблона и местом ошибки.

**Шаблон видит только представление.** `templates/service.rb.erb` держит
разметку класса и таблицы; всё остальное — строки от презентеров
`Generators::Service::*` (`Payload`, `Tables`, `Precheck`, `Creation`,
`Polling`, `Callback`, `Signature`, `Authorization`, `Extras`, `Privates`),
собранных `Service::View`. Презентеры читают только IR и справочники через
`Service::Context`; имена методов контракта, хелперов, выражения платформы и
внутренние статусы — из `rules/contract.yml` (`ContractBook#method_for`,
`#helper`, `#helper_for_status`, `#platform`). В шаблоне и в `lib/` нет ни
одного литерала имени метода контракта. Комментарии в самом шаблоне — по-
русски прямо в ERB; комментарии, которые формируют презентеры, — через
`Texts.t('generators.service.*')`.

**Раздел `platform` в `rules/contract.yml`** — то, как сгенерированный
сервис разговаривает с платформой, и после ответов экспертов от 5 сентября
2026 (вопросы 18–25) он описывает не догадку, а форму объекта операции:
`accessors` — только гарантированные поля (`operation.id`,
`operation.amount`, `operation.provider_operation_key`, `operation.status`),
сумма сырая в мажорных единицах; `requisites` — реквизиты получателя из
JSONB-хеша `operation.payout_requisite`, где ключ верхнего уровня это
`payment_method` шлюза, он же `request_method`; `failure_codes` — коды
платформы для первого аргумента `failure` (`by_http`, `by_action`,
`validation`, `internal`); `lookup` и `writers` (с подстановкой `%{value}`,
оба пусты); `callback` (сырое тело и заголовки аргумента
`process_callback`); `result.success_predicate` и `result.create_success`.
Плоских полей `currency`, `recipient_phone`, `bank_code`, `card_number` в
`accessors` нет вовсе — их у операции не существует. Загружают
`Rules::PlatformBindings`, `Rules::RequisiteMap` и `Rules::FailureCodes`;
роль вне `IR::Roles::FIELD`, выражение без `%{value}` там, где оно
обязательно, и код отказа, не похожий на символ Ruby, — ошибки загрузки.
У хелперов `approve_operation` / `reject_operation` есть поле `status`:
по нему шаблон выбирает хелпер для внутреннего статуса.

**Условная обязательность становится веткой, а не комментарием.**
`Service::Requisites` ищет в теле запроса объект первого уровня
(`recipient`, `destination`, `remitter`), внутри которого есть поле роли
`recipient_type` с enum хотя бы из двух значений и хотя бы одно поле,
обязательное при одном из этих значений. Каждое значение enum становится
веткой `case request_method` в отдельном приватном методе
`<поле>_requisites`; ключ ветки — способ выплаты платформы, найденный по
нормализованному имени (`sbp`, `card`), а значение поля роли
`recipient_type` внутри ветки — литерал из спецификации, потому что
провайдер вправе называть способ иначе, чем платформа. Поле без условия
общее для всех веток. Роль без выражения в `requisites` даёт TODO и строку
таблицы «куда мапить» в INTEGRATION.md, а не выдуманный ключ хеша: догадка
о спецификации обязательна, догадка о платформе запрещена. Значение
поля с известной ролью, для которой выражения нет, — только `nil`:
правдоподобный пример из спецификации ушёл бы провайдеру как настоящий.
Ветка не генерируется, когда значений enum меньше двух, роли
`recipient_type` нет вовсе или спецификация не выразила условной
обязательности по этому enum: `case` с одинаковыми ветками хуже, чем его
отсутствие.

**Валюта — константа сервиса, а не поле операции.** Платформа валюту не
сообщает, поэтому `CURRENCY` берётся из того же кода ISO 4217, по которому
считается `AMOUNT_MULTIPLIER` (единственное значение `enum`, `const` или
`example` поля с ролью `currency`), и печатается с обоснованием. Не
выведена — константы нет, поле тела запроса получает TODO, а `report.md` —
пункт «задайте валюту». Предпроверка `currency` при этом не генерируется:
значение задано по построению, и лишний guard читался бы как настоящая
проверка.

**Презентеры сервиса — общие для всех артефактов.** `Service::View`
отдаёт наружу `context` и `parts` (payload, polling, callback, signature,
authorization, creation, precheck, extras, tables, http);
`Integration::View` строит `Service::View` и читает у него те же объекты.
Данные, из которых печатаются строки Ruby, открыты как данные:
`Tables#status_mappings` / `#events` / `#code_rules` / `#http_rules` /
`#specific_rules` / `#retry_policy`, `Precheck#description` / `#major_text`
/ `#amount` / `#role_of` / `#failure_code`, `Signature#value` / `#known?`,
`Authorization#type` / `#entry` / `#param_names` / `#credential_keys` /
`#stub_name`, `Extras#entries`, `Context#timeouts` / `#base_url_env` /
`#sandbox_url` / `#full_class_name` / `#error_code_path`. Правило: документ
никогда не пересчитывает то, что уже посчитал презентер сервиса, — иначе
таблица INTEGRATION.md совпадёт с константой по совпадению, а не по
построению. Презентеры документа (`Generators::Integration::*`) наследуют
`Integration::Base` (контекст, части, `t` под `generators.integration.*`,
Markdown-хелперы) и делятся по разделам: `Access` (1–2), `Methods` (3),
`Statuses` (4), `Errors` (5), `Gateway` (6), `SignatureDoc` (7),
`Assumptions` + `RunAssumptions` + `RunGaps` (9); проза разделов и раздел 8
целиком — в `templates/INTEGRATION.md.erb`.

**Допущения проекта — данные, не docs.** Раздел «Принятые допущения»
берёт текст из `rules/assumptions.yml` (`Rules::AssumptionsBook`: `all`,
`documented`, `find`; поля `id`, `text`, `source`, `affects`, `status`
active | withdrawn, `replaced_by`, `documented`), а не из
`docs/ASSUMPTIONS.md`: генератор не должен зависеть от документации
репозитория. Журнал для людей остаётся в `docs/`, правится тем же коммитом;
загрузчик отказывает на повторном `id` и на снятом допущении без
`replaced_by`. `documented: false` — допущение о ходе проекта, в
INTEGRATION.md не попадает. Допущения конкретного прогона генератор берёт
из IR: только `Derived` ниже порога и `Derived.unknown`, которые стали кодом
(роль поля, условная обязательность из прозы, условие из прозы, единицы,
члены профиля подписи, код конфликта, авторизация, статусы и события без
пары, действия по умолчанию, роли операций, песочница, параметры пути без
роли, поле статуса не по роли), а не все предупреждения.

**Параметр, который тело метода не использует, получает префикс `_`**
(`Service::Method#signature`): контракт требует `request_method` в
`create_request`, а `Lint/UnusedMethodArgument` — пометки; голый `super`
считается использованием всех аргументов.

**Отдельный RuboCop-конфиг для сгенерированного кода** —
`config/rubocop_generated.yml`: наследует основной, отключает
`Metrics/ClassLength` (сервис длиннее 150 строк по построению), поднимает
`MethodLength` до 30 с `AllowedMethods: [build_payload, check_conditions]`
(это таблицы, их не режут на хелперы), `AbcSize` 40, сложность 12. `Lint/*`,
`Security/*`, `Style/Documentation`, `Layout/EndOfLine` в силе. Все
переносы, `%w[]`/`%i[]`, `.freeze`, пустые строки после guard-блоков,
`rescue` на уровне `def` — забота `Generators::Ruby`, не ручных правок.

**Откуда берётся значение в fixtures.json и что значит `source`.** Тело,
взятое из `examples` спецификации дословно, — `spec_example`; собранное из
`example` / `const` / `enum[0]` / `default` свойств схемы —
`schema_example`; содержащее хоть одну заглушку по типу (`"string"`, `0`,
`true`) — `synthesized`; обещанное спецификацией, но не описанное ею —
`undeclared`. Придуманное значение никогда не выдаётся за пример
из спецификации, и у каждой фикстуры не-`spec_example` есть `_todo` —
единственный ключ с подчёркиванием и единственная русская проза в файле.
Схема, у которой ни одно поле не подсказало значение, собирается целиком
(`Fixtures::Values#object`): пустое тело в фикстуре бесполезнее заглушки.
Глубина вложенности ограничена `MAX_DEPTH` 4 — иначе Adyen Transfers даёт
мегабайты. Тело операции без `requestBody` — `null` с источником
`spec_example`: «тела нет» сказала сама спецификация; так же читается ответ
`204` и `304`, у которых тела не бывает по RFC 9110. А вот ответ с любым
другим кодом, у которого схемы нет (`description` без `content` либо
`content: application/json: {}`), — не пример, а пробел: источник
`undeclared`, тело `null`, `_todo` просит описать схему. Пустое тело нельзя
выдавать за пример там, где примера не существует. Действие в
`expected.action` считается по коду ошибки из тела только тогда, когда тело
— пример спецификации; код, подставленный нами из `enum`, о политике
ничего не говорит, и тогда действие определяет HTTP-код.

**Подпись уведомлений в фикстурах считается по-настоящему**
(`Fixtures::Signing`): HMAC от точных байтов `raw_body`
(`JSON.generate(body)`) секретом-заглушкой `test_<ключ credentials>` по
профилю `IR::SignatureProfile` — тем же, по которому сгенерирован
`verify_signature!`. У профиля Standard Webhooks подписывается
`{id}.{timestamp}.{body}` с фиксированными значениями
(`SPECGEN_TIMESTAMP` с дефолтом 1767225600), потому что `Time.now` в
генераторе запрещён. Негативная фикстура сохраняет длину и префикс
значения, заменяя саму подпись нулями. Ключ идемпотентности в фикстуре
считает `Generators::Uuid.v5` — тот же RFC 4122 §4.3, что печатает шаблон
сервиса, от `"<slug>:<external_id из примера>"`.

**Измерение покрытия, в котором нечего покрывать, не печатает 100 %.**
`Dimension#percent` у пустого измерения — `nil`, а в таблице отчёта стоит
«нечего покрывать» (`generators.report.coverage_empty`): круглая цифра там,
где нет данных, читается как достижение. На итоговую цифру это не влияет —
пустое измерение не добавляет ни к числителю, ни к знаменателю.

**Числовые литералы в сгенерированный Ruby печатает только `Ruby.number`**
(через него же идёт `Ruby.literal` для любого `Numeric`): целая часть от
пяти знаков разделяется подчёркиваниями по три разряда от конца, как того
требует `Style/NumericLiterals`. Иначе `maximum: 5000000` у CardPay даёт
`operation.amount > 50000` и офенс. Отключением правило не лечится:
сгенерированный класс читают глазами, и `50_000` читается лучше. Обратный
случай — `Naming/VariableNumber`: ключи payload это дословные имена полей
спецификации (`address_line_1`, `xref_tag_9`), переименовать их нельзя,
поэтому правило выключено в `config/rubocop_generated.yml`.

**Формула покрытия — доля покрытых элементов от всех**, а не среднее по
измерениям: сумма покрытого по семи измерениям (операции, поля тел запросов,
поля входящих тел, коды ответов, статусы, события, условия), делённая на
сумму найденного. Среднее отброшено намеренно: измерения разного размера, и
четыре события вебхука не должны весить столько же, сколько триста полей.
Покрытым считается элемент, у которого в сгенерированном коде есть ветка,
выражение или строка таблицы: операция — метод сервиса (роль `unmapped` не
считается), поле тела запроса — выражение платформы по роли, поле входящего
тела — одна из ролей `status`, `provider_operation_id`, `error_code`,
`external_id` либо поле события, код ответа — успех, `DEDUP_STATUS` или
правило `ERROR_MAP` по HTTP-коду (действие по умолчанию покрытием не
считается), статус и событие — пара в `STATUS_MAP` / `EVENT_MAP`, условие —
проверка в `check_conditions`, ограничение отмены или строка `RETRY_POLICY`.
Поля тел запросов считаются по операциям, поля входящих тел — по схемам.

**Цифр покрытия две, и формула первой не меняется.** Вторая — «в границах
контракта»: тот же числитель, но из знаменателя вычтено то, чему в методах
`Provider::BaseService` нет места по построению. Вычитается ровно три вида и
только из непокрытого: поля входящих тел, чья роль не входит в
`CoverageFields::READ_ROLES` (плюс поля без роли) — читать их некуда;
необязательные поля тел запросов без роли — по `CLAUDE.md` они намеренно не
идут в payload; операции без роли, которым не досталось даже отдельного
публичного метода (пока `Service::Extras` генерирует метод каждой, таких нет,
и правило остаётся проверкой, а не скидкой). Обязательные поля запросов без
роли не вычитаются: они уходят в payload с TODO, и это настоящий пробел.
Счётчик живёт в `Dimension#out_of_scope`, обе цифры — в `Artifact#metrics`
(`coverage_percent`, `contract_coverage_percent`, `contract_total`), в колонке
«В контракте» сводки `./integrate --all` и в ответе веб-API. В отчёте они
печатаются одной строкой и обязаны сопровождаться списком вычтенного по видам:
вторая цифра без списка читается как подкрутка. Первая отвечает «сколько
спецификации задействовано», вторая — «сколько не упущено из задействуемого».

**Раздел отчёта выбирается по коду предупреждения, а не по серьёзности.**
`Report::Warnings::CONTRADICTIONS` — спецификация против самой себя (enum
против примеров, коды соседей, проза против структуры, конфликты overlay и
ролей), `NOTES` — факты, где инструмент ничего не решал, всё остальное —
неоднозначности. Один код — ровно один раздел, иначе читатель искал бы одну
проблему в двух местах; это проверяет
`spec/unit/specgen/generators/report_generator_spec.rb`, там же — требование
собственного текста `action_<код>` в обеих локалях. У кода со своим разделом
(`operation_unmapped`, `contract_gap`) справка ссылается на раздел 4.

**Golden обновляется только явно:** `SPECGEN_UPDATE_GOLDEN=1 bundle exec
rspec spec/golden`; тест сравнивает каждый файл `spec/fixtures/golden/novapay/`
байт-в-байт и отдельно проверяет, что два прогона в разные каталоги дают
одинаковые байты. Файлы пишет `Generators::Writer` в бинарном режиме
(`File.binwrite`), LF, один `\n` в конце.

**UUID v5** в сгенерированном коде — `Digest::SHA1` по RFC 4122 §4.3, без
`SecureRandom`; пространство имён — DNS-namespace из
`rules/idempotency.yml`. Проверочный вектор: `uuid_v5(DNS, 'python.org') =
886313e1-3b8a-5372-9b90-0c9aee199e5d`.

**Чего не хватило в IR для фикстур** (заявки ir-architect и
rules-curator): `IR::Response` и `Operation` несут примеры, но ни один
элемент IR не помнит примеры на уровне свойств схемы иначе как
`Field#example` — сборка тела из схемы живёт в `Fixtures::Values`, хотя
это скорее свойство IR; `WebhookEvent#example` есть только у событий,
названных в примерах (у novapay — у двух из четырёх), остальным тело
одалживается у соседнего события с подстановкой enum; `rules/auth.yml`
хранит значение заголовка авторизации выражением Ruby, поэтому фикстура
раскрывает его текстом (`Basic`, `HMAC`, OAuth2 раскрыть нечем — заглушка
и строка в `_todo`). Кодов отказа `signature_invalid` и `unknown_event`
не было в одном месте: теперь это `Service::Signature::INVALID_CODE` и
`Service::Callback::UNKNOWN_EVENT_CODE`, их читают негативные фикстуры.

**Чего не хватило в IR для шаблонов** (заявки ir-architect):
`Webhook#event_field` (поле события угадывается по полю, чей `enum`
покрывает все имена событий); структурный список кандидатов роли с баллами
(сейчас — только текст `Derived#evidence` и сообщение
`field_role_low_confidence`, TODO в коде цитирует их); `value_prefix`
профиля Standard Webhooks в `SignatureProfile` (берётся из
`rules/signatures.yml`). Для INTEGRATION.md: у `ErrorRule` с
`provider_code` нет HTTP-кодов, при которых код встречается (в примерах
`unauthorized` лежит под 401, но правило этого не помнит — колонка
«HTTP-код» у кодов провайдера говорит «любой, читается из тела»);
`Condition` знает имя поля, но не схему, поэтому два поля `type` из разных
схем Adyen сливаются в одну запись `fields:` фрагмента шлюза (второе
условие уходит в комментарий); overlay-фрагмент подписи документ берёт из
`profile.warnings`, а не из IR вебхука.

**История коммитов** — по одному коммиту на этап, каждый самодостаточен:
`rspec` и `rubocop` зелёные на каждом. Общие файлы (`analyzers.rb`,
`warning.rb`, `registry.rb`, локали) входят в коммит промежуточным
состоянием, а не финальным. Сообщения на русском, тело объясняет решения,
которых не видно в diff.

---

## Окружение разработки на этой машине

- Ruby 3.4.10 в `C:\Ruby34-x64`. В каждой Git Bash-сессии перед командами:
  `export PATH="/c/Ruby34-x64/bin:$PATH"`.
- Репозиторий LF-only (`.gitattributes`). Ruby в текстовом режиме на Windows
  пишет CRLF: файлы писать в бинарном режиме или через инструменты
  редактирования, после массовых правок проверять `file`.
- Heredoc через Bash-инструмент агента может съесть обратные слэши: всё с
  регулярными выражениями писать через Write/Edit, потом проверять
  `grep -rlP '[\x00-\x08\x0b\x0c\x0e-\x1f]' lib/ rules/ spec/ locales/`.
- `\b` в Ruby различает только ASCII-буквы: граница русского слова в
  `rules/*.yml` пишется `(?<![[:alpha:]])`.

---

## Следующий шаг

Порядок после чекпоинта 2 (5 сентября 2026) — в `docs/PROMPTS.md`, раздел
«Актуальный порядок после чекпоинта 2»; ответы экспертов дословно в
`docs/QUESTIONS.md`, следствия в `docs/ASSUMPTIONS.md`.

Коротко: приоритет — чужие спецификации, потому что эксперты сказали это
прямо. Измеренное покрытие: NovaPay 75 % (54 из 72), ЮKassa 39 %
(34 операции, 22 с ролью), PayPal Payouts 33 %, Adyen Transfers 35 %,
Mollie 29 % (128 операций, 111 с ролью), Adyen Payout 21 %. Цифры ниже
прежних после перехода на `payout_requisite`: реквизит, для которого
выражения платформы нет, теперь честно не считается покрытым. Всё это одной командой: `./integrate --all --specs <каталог>`.

Что уже сделано из плана: роли операций больше не оставляют пустого места
(третий уровень доверия), добавлены роли `confirm` и `refund`, тело запроса
операций вне контракта собирается по ролям, статусы пополнены банковской
лексикой, есть пакетный прогон со сводкой. На Adyen Transfers роль получают
11 операций из 12 вместо 7, статусы 54 % вместо 48 %.

Где остался потолок и почему. Поля тел запросов — 21 %: оставшиеся поля либо
необязательные без роли (по CLAUDE.md в payload не идут), либо обязательные
без роли (идут с TODO). Поднять эту цифру можно только новыми ролями полей
(`account_number`, `iban`, `recipient_name`), а у каждой новой роли обязано
быть выражение платформы в `rules/contract.yml` — то есть ответ на вопрос 1,
заданный экспертам 5 сентября: какие поля вообще есть у `operation`. Пока
ответа нет, новые роли полей не добавляем: это была бы догадка о платформе,
а не о спецификации. Поля тел ответов — 19 %, и это по построению: методам
контракта нужны четыре роли из ответа (`status`, `provider_operation_id`,
`error_code`, `external_id`), остальные читать некуда.

Промпт 10 закрыт: в каталоге семь спецификаций, три свои и три чужие рядом с
выданной, все семь проходят одной командой (`./integrate --all`), цифры и
таблица различий — в разделе «Свои альтернативные спецификации» выше. Всё,
чего инструмент не узнал в новых спеках, вылечено строками в `rules/`; четыре
дефекта ядра, которые данными не выражаются, починены кодом.

Шаг 6 закрыт: OverlayApplier применяет OpenAPI Overlay 1.0.0 до анализа,
фрагменты из раздела 3 отчёта работают как есть, а `--overlay` больше не
печатает «игнорируется». Дальше по таблице порядка: шаг 7 — вторая цифра покрытия «из того, что контракту вообще
нужно», шаг 8 — репетиция живого прогона и README. Потом сверка сформированных
запросов со спекой и `--fix`, который соберёт overlay из фрагментов раздела 3
отчёта — инструкция по сборке уже напечатана в самом отчёте, а её формат
разбирает `YAML.safe_load` в юнит-тесте. Мок-провайдер остаётся в бонусе:
эксперты оценивают сгенерированный класс, а не живой трафик.

Хвосты, которые нашли новые спеки и которые сознательно оставлены:

- **Ограничение по статусу из прозы читается только у роли `cancel`.** Фраза
  «Confirmation is accepted only in status initiated or under_review» у
  `confirmDeposit` подходит под шаблон `only_in_status_en`, но до него не
  доходит: `ConditionsAnalyzer` спрашивает про ограничение только операцию
  отмены, а вид условия в IR называется `cancel_status_restriction`.
  Расширение на `confirm` и `refund` — изменение модели, а не справочника.
- **`ref` в `broken.yaml` не получает ни одного кандидата роли.** Имя короче
  `min_length` 4 и не делит ни одного токена с синонимами `external_id` и
  `provider_operation_id`, поэтому это `required_field_role_unknown`, а не
  «лучший кандидат с видимым отрывом», как задумывалось при написании спеки.
  Лечится словарём или порогом Левенштейна у `NameMatcher`.
- **Параметры получают роли полей тела по слабым сигналам.** У cardpay
  заголовок `webhook-timestamp` получил роль `recipient_phone` 0.24: его
  пример — юникс-время из десяти цифр, а шаблон телефона роли принимает
  десять цифр. Предупреждение честное и роль ниже порога, но так будет у
  каждого провайдера на Standard Webhooks. То же у depositbank с
  query-параметрами `created_from` и `created_to`. Общее лекарство —
  запретить роли, у которой в справочнике не объявлен `locations`,
  присваиваться параметру операции; это меняет поведение на чужих спеках и
  требует замера, поэтому отложено.
- **`IR::Response` не помнит, был ли объявлен `content`.** Из-за этого
  «`description` без `content`» и «`content` без `schema`» различаются
  эвристикой по коду ответа, а не структурно. Заявка ir-architect.
