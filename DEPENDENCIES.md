# Зависимости

Сведения о технологиях, библиотеках и лицензиях по требованию Положения
(п. 7.8.1, 7.8.5). Все зависимости с открытыми лицензиями, ни одна не
обращается к внешним сервисам. Генератор в рантайме не делает сетевых вызовов
вообще.

Версии зафиксированы в `Gemfile.lock`. При добавлении гема обновляй обе
таблицы; список ниже сверяется с `bundle list` аудитом перед каждым
чекпоинтом.

## Платформа

| Компонент | Версия | Лицензия | Зачем |
|---|---|---|---|
| Ruby | 3.2+ (проверено на 3.4.10) | Ruby / BSD-2-Clause | язык реализации, более 50% кода по требованию п. 7.8.3 |
| Bundler | 2.4+ | MIT | установка и фиксация версий гемов |

Из стандартной библиотеки Ruby используются `psych` (YAML), `json`, `erb`,
`openssl`, `digest` и `securerandom` — отдельной установки не требуют.

## Прямые зависимости

| Гем | Версия | Лицензия | Зачем |
|---|---|---|---|
| thor | 1.5.0 | MIT | CLI `./integrate`: команды, флаги, справка |
| rack | 3.2.7 | MIT | интерфейс для мок-провайдера и тонкого веб-слоя, без npm |
| rspec | 3.13.2 | MIT | тесты ядра, golden-тесты, сгенерированные негативные тесты |
| webmock | 3.26.4 | MIT | запрет сетевых вызовов в тестах и заглушки HTTP для сгенерированного сервиса |
| rubocop | 1.90.0 | MIT | линтер для ядра и для сгенерированного кода |

Парсер OpenAPI (`openapi3_parser` или `openapi_parser`) и валидатор запросов
против спеки (`committee` или `openapi_first`) будут добавлены на этапе
загрузчика и валидаторов и появятся в этой таблице.

## Транзитивные зависимости

Подтягиваются гемами выше, в коде проекта напрямую не используются.

| Гем | Версия | Лицензия | Кем подтягивается |
|---|---|---|---|
| addressable | 2.9.0 | Apache-2.0 | webmock |
| ast | 2.4.3 | MIT | rubocop (parser) |
| bigdecimal | 4.1.2 | Ruby / BSD-2-Clause | webmock (crack) |
| crack | 1.0.1 | MIT | webmock |
| diff-lcs | 1.6.2 | MIT / Artistic-1.0-Perl / GPL-2.0-or-later | rspec |
| hashdiff | 1.2.1 | MIT | webmock |
| json | 2.21.2 | Ruby | rubocop |
| language_server-protocol | 3.17.0.6 | MIT | rubocop |
| lint_roller | 1.1.0 | MIT | rubocop |
| parallel | 2.1.0 | MIT | rubocop |
| parser | 3.3.12.0 | MIT | rubocop |
| prism | 1.9.0 | MIT | rubocop (rubocop-ast) |
| public_suffix | 7.0.5 | MIT | webmock (addressable) |
| racc | 1.8.1 | Ruby / BSD-2-Clause | rubocop (parser) |
| rainbow | 3.1.1 | MIT | rubocop |
| regexp_parser | 2.12.0 | MIT | rubocop |
| rexml | 3.4.4 | BSD-2-Clause | webmock (crack) |
| rspec-core | 3.13.6 | MIT | rspec |
| rspec-expectations | 3.13.5 | MIT | rspec |
| rspec-mocks | 3.13.8 | MIT | rspec |
| rspec-support | 3.13.7 | MIT | rspec |
| rubocop-ast | 1.50.0 | MIT | rubocop |
| ruby-progressbar | 1.13.0 | MIT | rubocop |
| unicode-display_width | 3.2.0 | MIT | rubocop |
| unicode-emoji | 4.2.0 | MIT | rubocop (unicode-display_width) |

`prism` и `bigdecimal` содержат нативные расширения. На Linux и macOS они
собираются штатно, на Windows нужен RubyInstaller с DevKit (MSYS2).

## Как проверить

```sh
bundle exec ruby -e 'Bundler.load.specs.sort_by(&:name).each { |s| puts [s.name, s.version, s.licenses.join("/")].join("\t") }'
```

Вывод должен совпадать с таблицами выше.
