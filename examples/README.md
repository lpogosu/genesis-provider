# Примеры сгенерированных артефактов

Результат одной команды по всем десяти спецификациям каталога
`spec/fixtures/specs/`, закоммиченный, чтобы читать без запуска:

```sh
./integrate --all --output examples
```

По каталогу на провайдера, в каждом четыре файла: `<provider>_service.rb`,
`INTEGRATION.md`, `fixtures.json`, `report.md`. CI перегенерирует каталог
и сверяет с этим `diff -r`: расхождение значит, что примеры отстали от
генератора.

| Спецификация | Провайдер | Операций | С ролью | Покрытие | В контракте | Замечаний |
|---|---|---|---|---|---|---|
| `broken.yaml` — одиннадцать намеренных дыр | [broken](broken/) | 6 | 5/6 | 43 % | 65 % | 64 |
| `cardpay.yaml` — карта, Bearer, Standard Webhooks | [cardpay](cardpay/) | 6 | 6/6 | 66 % | 94 % | 42 |
| `depositbank.yaml` — депозиты, OpenAPI 3.1, JPY, без вебхуков | [depositbank](depositbank/) | 6 | 4/6 | 60 % | 87 % | 43 |
| `novapay.yaml` — выданная спецификация | [novapay](novapay/) | 5 | 5/5 | 75 % | 98 % | 18 |
| `real/adyen_payout_v68.yaml` | [adyen_payout_v68](adyen_payout_v68/) | 6 | 2/6 | 23 % | 45 % | 216 |
| `real/adyen_transfers_v4.yaml` | [adyen_transfers_v4](adyen_transfers_v4/) | 12 | 7/12 | 32 % | 74 % | 377 |
| `real/govuk_pay_v1.json` | [govuk_pay_v1](govuk_pay_v1/) | 16 | 10/16 | 36 % | 89 % | 203 |
| `real/moov_paygate_v1.yaml` | [moov_paygate_v1](moov_paygate_v1/) | 10 | 7/10 | 56 % | 79 % | 55 |
| `real/paypal_payouts_v1.json` | [paypal_payouts_v1](paypal_payouts_v1/) | 4 | 4/4 | 34 % | 72 % | 88 |
| `real/paystack_v1.yaml` | [paystack_v1](paystack_v1/) | 120 | 59/120 | 51 % | 69 % | 469 |

Первая цифра покрытия — доля задействованных элементов от всех найденных,
вторая — то же в границах контракта `Provider::BaseService`; вычтенное
названо в разделе 2 каждого `report.md`. Чужие спецификации в разы шире
задачи выплат, поэтому у них первая цифра ниже. Источники и лицензии чужих
спецификаций — `spec/fixtures/specs/real/README.md`.

С чего начать читать: [novapay/novapay_service.rb](novapay/novapay_service.rb)
(ветка `case request_method` в реквизитах, таблицы статусов и ошибок,
проверка подписи), [broken/report.md](broken/report.md) (по строке отчёта
на каждую дыру спецификации, генерация не заблокирована),
[adyen_transfers_v4/adyen_transfers_v4_service.rb](adyen_transfers_v4/adyen_transfers_v4_service.rb)
(чужая спецификация: сумма как объект `{value, currency}`, TODO там, где
платформе нечего дать).
