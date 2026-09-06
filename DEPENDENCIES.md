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
| rack | 3.2.7 | MIT | Rack-приложение веб-интерфейса: пять маршрутов API и раздача статики |
| rspec | 3.13.2 | MIT | тесты ядра, golden-тесты, сгенерированные негативные тесты |
| webmock | 3.26.4 | MIT | запрет сетевых вызовов в тестах и заглушки HTTP для сгенерированного сервиса |
| rubocop | 1.90.0 | MIT | линтер для ядра и для сгенерированного кода |
| json_schemer | 2.5.0 | MIT | стадия сверки: тела из `fixtures.json` проверяются схемами той же спецификации (draft 2020-12, OpenAPI 3.0 и 3.1) |

**Парсер OpenAPI написан свой** и в этой таблице гема не имеет.
`openapi3_parser` и `openapi_parser` рассматривались и отклонены: смысловая
интерпретация спеки — наша ценность, а разбор YAML и разрешение `$ref` мы
контролируем сами (сообщения об ошибках с JSONPath, размыкание циклов,
отказ от сетевых `$ref`).

**Валидатор запросов** выбран после замера. `committee` отклонён: не читает
OpenAPI 3.1. `openapi_first` отклонён: падает на путях с буквой диска
(Windows). Остался `json_schemer` — он проверяет тела схемами самой
спецификации, чего и требует Definition of done.

## Транзитивные зависимости

Подтягиваются гемами выше, в коде проекта напрямую не используются.

| Гем | Версия | Лицензия | Кем подтягивается |
|---|---|---|---|
| addressable | 2.9.0 | Apache-2.0 | webmock |
| ast | 2.4.3 | MIT | rubocop (parser) |
| bigdecimal | 4.1.2 | Ruby / BSD-2-Clause | webmock (crack) |
| crack | 1.0.1 | MIT | webmock |
| diff-lcs | 1.6.2 | MIT / Artistic-1.0-Perl / GPL-2.0-or-later | rspec |
| hana | 1.3.7 | MIT | json_schemer (JSON Pointer) |
| hashdiff | 1.2.1 | MIT | webmock |
| json | 2.21.2 | Ruby | rubocop |
| language_server-protocol | 3.17.0.6 | MIT | rubocop |
| lint_roller | 1.1.0 | MIT | rubocop |
| parallel | 1.28.0 | MIT | rubocop; закреплён ниже 2.0, потому что 2.x требует Ruby 3.3 |
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
| simpleidn | 0.3.0 | MIT | json_schemer (формат idn-hostname) |
| unicode-display_width | 3.2.0 | MIT | rubocop |
| unicode-emoji | 4.2.0 | MIT | rubocop (unicode-display_width) |

`prism` и `bigdecimal` содержат нативные расширения. На Linux и macOS они
собираются штатно, на Windows нужен RubyInstaller с DevKit (MSYS2).

## Веб-интерфейс

Фронтенд — оболочка над Ruby-API: он отображает то, что вернул сервер, и
ничего не вычисляет (условие в `docs/PRINCIPLES.md`, раздел «Правила хакатона», «Ruby больше 50
процентов»). Исходники — `space-payments-dashboard/`, доля в объёме кода
команды около 5 %, считается командой `bin/ruby-share`.

| Пакет | Версия | Лицензия | Зачем |
|---|---|---|---|
| next | 16.3.3 | MIT | каркас приложения; собирается в статику (`output: 'export'`), Node в рантайме не нужен |
| react | 19.2.4 | MIT | библиотека представления |
| react-dom | 19.2.4 | MIT | рендер React в DOM |
| react-markdown | 10.1.0 | MIT | рендер `INTEGRATION.md` и `report.md`, которые API отдаёт сырым текстом |
| remark-gfm | 4.0.1 | MIT | таблицы GitHub-разметки: без них таблицы обоих документов не рендерятся |
| lucide-react | 1.17.0 | ISC | иконки |
| tailwindcss | 4.3.3 | MIT | стили без отдельного CSS-фреймворка |
| @tailwindcss/postcss | 4.3.3 | MIT | сборка стилей |
| postcss | 8.5.6 | MIT | подтягивается сборкой стилей |
| tailwind-merge | 3.4.0 | MIT | склейка конфликтующих классов Tailwind |
| tw-animate-css | 1.4.0 | MIT | переходы |
| class-variance-authority | 0.7.1 | Apache-2.0 | варианты компонентов |
| clsx | 2.1.1 | MIT | сборка списка классов |
| shadcn | 4.19.0 | MIT | генератор компонентов, использован при первичной сборке макета |
| @base-ui/react | 1.5.0 | MIT | примитивы доступности под компонентами |
| typescript | 5.7.3 | Apache-2.0 | типы; сборка падает на ошибке типа, `ignoreBuildErrors` выключен |
| @types/node, @types/react, @types/react-dom | 24.10.4 / 19.2.14 / 19.2.3 | MIT | описания типов |

Проприетарного и закрытого нет. `@vercel/analytics` из первоначального
макета удалён осознанно: пакет с открытой лицензией, но в рантайме
обращается к закрытому сервису Vercel, а пункт 3 положения запрещает
зависимость от проприетарных внешних API. Пользы для демонстрации он не
давал.

Проверить:

```sh
cd space-payments-dashboard && pnpm licenses list
```

## Как проверить

```sh
bundle exec ruby -e 'Bundler.load.specs.sort_by(&:name).each { |s| puts [s.name, s.version, s.licenses.join("/")].join("\t") }'
```

Вывод должен совпадать с таблицами выше.
