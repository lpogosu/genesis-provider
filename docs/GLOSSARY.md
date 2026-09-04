# Глоссарий

Как термины проекта называются по-русски в комментариях, сообщениях и
документации. Один термин — один перевод: через месяц в коде не должно быть
пяти вариантов слова `evidence`. Идентификаторы в коде, YARD-теги, ключи YAML
и названия стандартов не переводятся никогда.

Правило языка коротко: **всё, что читает человек, — по-русски; всё, что
читает машина, — по-английски.** Смешанная строка вида «схема с маркером
`x-specgen-ref` получает канонический путь» — норма.

## Модель и вывод

| В коде | По-русски | Примечание |
|---|---|---|
| `Derived` | выведенное значение | класс не переводить, в прозе — «выведенное значение» |
| `value` | значение | |
| `source` | источник | |
| `:structural` | задано явно | прочитано из структуры спеки или из флага `--provider` |
| `:registry` | по справочнику | |
| `:heuristic` | эвристика | |
| `:overlay` | из overlay | |
| `:unknown` | не выведено | |
| `confidence` | уверенность | число 0.0–1.0 |
| `evidence` | обоснование | фраза, которую печатает отчёт |
| `Warning` | предупреждение | |
| `severity` | серьёзность | `error` — ошибка, `warning` — предупреждение, `info` — справка |
| `suggested_overlay` | заготовка overlay / фрагмент overlay | |
| `json_path` | JSONPath | не переводить |
| `ProviderProfile` | профиль провайдера | |
| `role` | роль | роли операций и роли полей |
| `:unmapped` | не отображена на контракт | результат, не ошибка |
| `contract` | контракт | контракт `Provider::BaseService` |

## Конвейер

| В коде | По-русски |
|---|---|
| `SpecLoader` | загрузчик спецификации |
| `RefResolver` | резолвер `$ref` |
| `OverlayApplier` | применение overlay |
| `Analyzer` | анализатор |
| `Matcher` | матчер |
| `composite matcher` | композитный матчер |
| `Generator` | генератор |
| `Validator` | валидатор |
| `Reporter` | отчёт / стадия отчёта |
| `Runner` | раннер |
| `pipeline` | конвейер |
| `stage` | стадия |

## Справочники

| В коде | По-русски |
|---|---|
| `rules/` | справочники |
| `Book` | книга справочника / справочник |
| `Registry` | реестр справочников |
| `dictionary` | справочник (не «словарь») |
| `synonym` | синоним |
| `canonical mapping` | канонический маппинг |
| `hint` | подсказка |
| `weight` | вес |
| `threshold` | порог |
| `floor` / `minimum` / `margin` | порог `floor` / `minimum` / `margin` — имена не переводить |

## Спецификация

| В коде | По-русски | Примечание |
|---|---|---|
| spec | спецификация | в комментариях полностью; «спека» — только в разговорной документации |
| operation | операция | |
| endpoint | эндпоинт | |
| path item | path item | термин OpenAPI, не переводить |
| request body | тело запроса | |
| response | ответ | |
| status code | HTTP-код / код ответа | |
| schema | схема | |
| property / field | поле | «свойство» — только про ключевое слово `properties` |
| parameter | параметр | path / query / header / cookie не переводить как места |
| required | обязательное (поле) / обязательный (параметр) | |
| conditional requirement | условная обязательность | |
| constraint | ограничение | |
| `enum`, `pattern`, `minimum`, `format` | не переводить | ключевые слова JSON Schema |
| `$ref` | `$ref` | |
| inline schema | инлайновая схема | |
| component schema | компонентная схема | |
| security scheme | схема авторизации | |
| credentials | учётные данные / `credentials` | в коде — `provider.credentials` |
| webhook | вебхук | |
| callback | колбэк | |
| payload | тело / payload | |
| signature | подпись | |
| idempotency key | ключ идемпотентности | |
| deduplication | дедупликация | |
| minor units / major units | минорные единицы / мажорные единицы | RUB: копейки / рубли |
| exponent | экспонента | ISO 4217 |

## Результаты и решения

| В коде | По-русски |
|---|---|
| deterministic | детерминированный |
| byte-for-byte | байт-в-байт |
| golden test | golden-тест |
| silent mistake | молчаливая ошибка |
| manual step | ручной шаг |
| three levels of trust | три уровня доверия |
| fallback | запасной путь |
| guess | догадка |
| known / unknown | известно / не выведено |

## Ошибки и места в файле

| В коде | По-русски | Примечание |
|---|---|---|
| location (префикс ошибки) | место ошибки; в строке — «файл, место» | запятая вместо предлога: вторая половина бывает и JSONPath, и позицией |
| line / column | строка / столбец | |
| root (документа) | корень документа | |
| syntax error | ошибка синтаксиса | не «синтаксическая ошибка» |
| dangling `$ref` | цель `$ref` не найдена | |
| cyclic `$ref` | циклический `$ref` | |
| remote `$ref` | `$ref` по сети | не «удалённый» |
| nesting depth | вложенность; «глубже N уровней» | |
| stack overflow | переполнение стека | |
| dialect / family (OAS) | диалект / семейство | |

## Сопоставление и композиция схем

| В коде | По-русски | Примечание |
|---|---|---|
| composite match | композитное сопоставление | |
| votes cast | поданных голосов | |
| below threshold | ниже порога | |
| ambiguous | неоднозначно | |
| next `<role>` | следующая `<роль>` | второе место матчера |
| composition keywords | ключевые слова композиции | `allOf`, `oneOf`, `anyOf` |
| branch | ветка | ветка `allOf`, ветка `else` |
| variant | вариант | вариант `oneOf` / `anyOf` |
| flatten | уплощать, сводить к плоской структуре | в коде встречается «сплющивать» — допустимый синоним |
| fold (`allOf`) | сворачивать | |
| negative branch / condition | отрицательная ветка / условие | |
| presence condition | условие на наличие | |
| sibling property | соседнее свойство | |
| coerce a value | привести значение | |
| use site | место использования | |
| opaque hash | непрозрачный хеш | |
| prose | проза | описание поля как источник условия |

## Авторизация и сеть

| В коде | По-русски | Примечание |
|---|---|---|
| flow (OAuth2) | поток | |
| token endpoint | эндпоинт токена | |
| scopes | scopes | не переводить |
| query string | query-строка | |
| authority (URI) | authority-часть URL | термин URI латиницей |
| slug | slug | имя файла и константы, не переводить |
| common / industry vocabulary | общий словарь / словарь индустрии | список слов, не справочник |

## Справочники: загрузчик и его сообщения

| В коде | По-русски | Примечание |
|---|---|---|
| noun (в локали) | название проверяемого элемента | подставляется в сообщение как `%{what}` |
| derivation source | источник вывода | |
| error action | действие по ошибке | |
| severity | серьёзность предупреждения | |
| signature payload | подписываемое тело | |
| encoding (подписи) | кодирование подписи | hex / base64 |
| secret_key | ключ секрета подписи | имя ключа в `provider.credentials` |
| replay tolerance | допуск на повтор | |
| match block | блок match | |
| auth location | место учётных данных | header / query / cookie |
| credential_keys | ключи credentials | |
| code fragments | фрагменты кода | значения в `rules/auth.yml` |
| conflict_status | код ответа на повтор | 409 у идемпотентности |
| uuid_v5_namespace | пространство имён UUID v5 | |
| default_exponent | экспонента по умолчанию | |
| signal (матчера) | сигнал | |
| helper | хелпер | `success`, `failure`, `client`… |
| assumption | пометка о допущении | |
| base_class | базовый класс | |
| OAS family | семейство OAS | |
| server environment | среда сервера | в экране `analyze` — «песочница» / «продакшен» |
| whole number | целое число | |
| nothing (о nil) | ничего | |

Стиль сообщений загрузчика справочников: «что проверяли: что не так» —
`роль поля: неизвестное значение "x" (допустимо: …)`. Один шаблон на форму
проверки без согласования рода в русском.

## Стандарты — не переводить

OpenAPI, OpenAPI Overlay, JSON Schema, JSONPath, JSON Pointer, ISO 4217,
Standard Webhooks, Idempotency-Key, HMAC-SHA256, COMA, YARD, RuboCop, RSpec,
Thor, Rack, ERB.
