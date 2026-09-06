# Карта критериев оценки

Критерии из описания кейса, и для каждого — артефакт репозитория, который
его закрывает, и команда, которой это проверяется. Правило: пункт считается
закрытым, только если проверка выполняется на живом прогоне, а не описана
словами.

Все команды — из корня репозитория. Перед ними `bundle install`; на Windows
в PowerShell вместо `./integrate` пишется `ruby integrate`.

## 1. Разбор API-спецификации — 20

| Подпункт | Баллы | Артефакт | Как проверить |
|---|---|---|---|
| Определены доступные методы API | 5 | `lib/specgen/analyzers/operation_analyzer.rb`, `operation_role.rb`; экран `analyze` | `./integrate analyze --spec provider_api.yaml` — пять операций с методом, путём, ролью и уверенностью |
| Распознаны параметры запросов и ответов | 5 | `schema_analyzer.rb`, `parameter_reader.rb`, `schema_normalizer.rb` | тот же экран: восемь схем, каждое поле с типом, обязательностью и ограничениями; параметры каждой операции с ролью |
| Распознаны требования к авторизации | 4 | `auth_analyzer.rb`, `rules/auth.yml` | строка «Авторизация: ApiKeyAuth → api_key, заголовок X-API-Key»; на `cardpay.yaml` — bearer, на `depositbank.yaml` — oauth2 |
| Распознаны статусы и ошибки | 3 | `status_analyzer.rb`, `error_analyzer.rb`, `rules/statuses.yml`, `rules/errors.yml` | экран `analyze`: пять статусов с внутренними, карта ошибок «7 в enum + 3 только в примерах»; `report.md` раздел 5 о расхождении enum и примеров |
| Распознаны webhook и дополнительные условия взаимодействия | 3 | `webhook_analyzer.rb`, `idempotency_analyzer.rb`, `conditions_analyzer.rb` | экран `analyze`: вебхук с четырьмя событиями и профилем подписи, идемпотентность, девять условий (Retry-After, минимум суммы, ограничение отмены по статусу, условная обязательность) |

## 2. Генерация интеграционного сервиса — 25

| Подпункт | Баллы | Артефакт | Как проверить |
|---|---|---|---|
| Сервис, соответствующий контракту `Provider::BaseService` | 5 | `templates/service.rb.erb`, `lib/specgen/generators/service/`, `rules/contract.yml` | `./integrate --spec provider_api.yaml --provider novapay`; в `output/novapay_service.rb` четыре метода контракта, `ruby -c` и RuboCop по `config/rubocop_generated.yml` чистые |
| Формирование и отправка запросов | 5 | `service/payload.rb`, `service/requisites.rb`, `service/http.rb`; стадия `Validators::ServiceCheck` | в сервисе `build_payload` и ветка `case request_method`; в `report.md` раздел 1 «Прогон собранного класса»: сгенерированный класс исполняется на своих фикстурах, запрос ушёл на нужный адрес с нужными заголовками и телом |
| Получение и обработка статуса операции | 4 | `service/polling.rb`, `STATUS_MAP` | `fetch_status` в сервисе; прогон класса проверяет каждый пример ответа → нужный хелпер платформы |
| Обработка ответов и ошибок | 4 | `ERROR_MAP`, `RETRY_POLICY`, `rules/errors.yml`, `Validators::FixtureCheck` | в сервисе карта ошибок и политика повторов; `report.md` раздел 1 «Сверка»: тела фикстур проходят схемы спецификации |
| Обработка входящих уведомлений | 4 | `service/callback.rb`, `service/signature.rb`, `EVENT_MAP` | `process_callback` и `verify_webhook_signature` с константным сравнением; в `fixtures.json` уведомления с настоящей подписью и две негативные |
| Конфигурация адресов и параметров подключения | 3 | `service/constants.rb`, `INTEGRATION.md` разделы 2 и 6 | `BASE_URL` через `ENV.fetch` с адресом из спецификации, секреты через `provider.credentials` |

## 3. Корректность преобразования данных — 15

| Подпункт | Баллы | Артефакт | Как проверить |
|---|---|---|---|
| Сопоставление статусов | 5 | `rules/statuses.yml`, `analyzers/status_reader.rb` | `STATUS_MAP` в сервисе совпадает с каноном описания кейса; `cardpay.yaml` даёт другие имена статусов с тем же результатом |
| Сопоставление полей запросов и ответов | 4 | `lib/specgen/matchers/`, `rules/roles.yml` | `./integrate analyze --spec provider_api.yaml --explain` — арифметика голосов под каждой ролью поля |
| Преобразование форматов и единиц данных | 3 | `analyzers/units_analyzer.rb`, `rules/currencies.yml` (ISO 4217) | «minor, x100 (ISO 4217: экспонента RUB 2)»; на `depositbank.yaml` JPY даёт множитель 1 |
| Обязательные и необязательные поля | 3 | `analyzers/condition_reader.rb`, `IR::RequiredWhen` | ветка `case request_method` в сервисе; на `depositbank.yaml` (OpenAPI 3.1) `dependentRequired` читается с уверенностью 1.00 |

## 4. Универсальность и адаптируемость — 10

| Подпункт | Баллы | Артефакт | Как проверить |
|---|---|---|---|
| Спецификации с разным набором методов и полей | 5 | `spec/fixtures/specs/` — четыре свои и шесть настоящих чужих | `./integrate --all` — десять спецификаций одной командой, сводная таблица |
| Логика генерации отделена от особенностей провайдера | 3 | `lib/` без имён провайдеров, всё специфичное в `rules/` | `grep -rinE 'novapay\|\bsbp\b' lib/` пусто; `spec/unit/specgen/neutrality_spec.rb` |
| Расширение шаблонов и правил генерации | 1 | `rules/*.yml`, `templates/`, OpenAPI Overlay | строка в `rules/statuses.yml` меняет распознавание без правки кода; `--overlay` |
| Сообщает о неподдерживаемых и неоднозначных элементах | 1 | `report.md` разделы 3–7, `--fix` | `./integrate --spec spec/fixtures/specs/broken.yaml --provider broken` — по строке отчёта на каждую из одиннадцати дыр, генерация не блокируется |

## 5. Генерация документации и тестовых материалов — 13

| Подпункт | Баллы | Артефакт | Как проверить |
|---|---|---|---|
| Описание настройки и авторизации | 5 | `INTEGRATION.md` разделы 1, 2, 6, 8 | `grep '^## ' output/INTEGRATION.md` — девять разделов |
| Описание методов, статусов и ошибок | 4 | `INTEGRATION.md` разделы 3, 4, 5 | таблицы совпадают с константами сервиса по построению — их печатают одни презентеры |
| Примеры запросов, ответов и уведомлений в `fixtures.json` | 4 | `lib/specgen/generators/fixtures/` | `ruby -rjson -e 'JSON.parse(File.read("output/fixtures.json"))'`; три массива `requests`, `responses`, `notifications`, подпись настоящая |

## 6. Удобство использования и демонстрация — 10

| Подпункт | Баллы | Артефакт | Как проверить |
|---|---|---|---|
| Понятный способ запуска | 4 | README, `Dockerfile`, `docker-compose.yml` | быстрый старт README с ожидаемым выводом; `docker compose up --build` |
| Результат за один последовательный процесс | 3 | `lib/specgen/cli.rb` | одна команда — четыре файла, без ручных шагов |
| Понятные сообщения о результате и ошибках | 3 | `locales/ru/`, иерархия `SpecGen::Error` | `spec/fixtures/bad/` — 18 видов плохого входа дают сообщение с файлом и JSONPath, без стектрейса |

## 7. Качество реализации — 10

| Подпункт | Баллы | Артефакт | Как проверить |
|---|---|---|---|
| Понятная архитектура и читаемый код | 4 | `docs/ARCHITECTURE.md`, по каталогу на стадию в `lib/specgen/` | `bundle exec rubocop` |
| Обработка ошибок при разборе и генерации | 3 | `lib/specgen/errors.rb`, `spec_loader/structure_validator.rb`, `generators/base.rb` | `bundle exec rspec spec/unit/specgen/spec_loader` |
| Инструкция по запуску и настройке | 3 | README | выполнить команды README на чистом клоне |

## Отраслевые критерии — 20

| Критерий | Баллы | Чем закрываем |
|---|---|---|
| Реализация дополнительных идей | 6 | раздел README «Сверх требований кейса»: overlay-цикл `report.md` → `--fix` → `--overlay`, прогон собранного класса, `diff` двух версий спецификации, две цифры покрытия, пакетный прогон, `analyze --explain`, два языка вывода, веб-интерфейс |
| Выступление команды | 6 | итоги трёх встреч — `docs/CHECKPOINT-*.md` |
| Полнота проработки решения | 8 | метрика покрытия спецификации в `report.md` и таблица `--all`: что покрыто, что нет и почему |
