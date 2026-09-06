# Интеграция с провайдером «Paystack»

| | |
|---|---|
| Провайдер | `paystack_v1` |
| Спецификация | `paystack_v1.yaml`, версия 1.0.0, OpenAPI 3.0.1 |
| Класс сервиса | `Provider::PaystackV1Service < Provider::BaseService` |
| Файл сервиса | `paystack_v1_service.rb` |

Документ сгенерирован инструментом integrate из той же модели провайдера,
что и сервис: таблицы ниже совпадают с константами `STATUS_MAP`, `EVENT_MAP`,
`ERROR_MAP` и `RETRY_POLICY` по построению. Не редактируйте вручную: правки —
в overlay (OpenAPI Overlay 1.0.0) и повторная генерация. Что инструмент не
вывел или вывел с сомнением, перечислено в `report.md` и в разделе 9.

## 1. Авторизация и хранение секрета

Тип авторизации: `bearer` — схема `bearerAuth` из securitySchemes, запись справочника rules/auth.yml «bearer».

Учётные данные уходят в заголовке `Authorization` каждого запроса к провайдеру.

| Ключ credentials | Где читается | Назначение |
|---|---|---|
| `provider.credentials[:token]` | `auth_headers` | учётные данные для запросов к провайдеру |

Значения секретов хранятся только в credentials платформы: в этом документе и в сервисе — одни имена ключей; в fixtures.json — только заглушки вида test_api_key, нужные, чтобы посчитать подпись уведомления.

## 2. ENV-переменные

| Переменная | Назначение | По умолчанию | Обязательна |
|---|---|---|---|
| `PAYSTACK_V1_BASE_URL` | базовый URL API провайдера (константа BASE_URL) | `https://api.paystack.co` — первый сервер спецификации, среда не выведена: проверьте, что это песочница | нет |
| `PAYSTACK_V1_OPEN_TIMEOUT` | таймаут соединения, секунды (константа OPEN_TIMEOUT) | 5 | нет |
| `PAYSTACK_V1_READ_TIMEOUT` | таймаут чтения ответа, секунды (константа READ_TIMEOUT) | 15 | нет |

Продакшен-сервер в спецификации не объявлен: URL боевой среды возьмите у провайдера.

Секреты через ENV не читаются: ключи credentials — `token`.

## 3. Таблица методов с идемпотентностью

Методы контракта `Provider::BaseService` в порядке `rules/contract.yml`.
Ключ идемпотентности — детерминированный UUID v5 от `operation.id`
(RFC 4122 §4.3, `Digest::SHA1`, без `SecureRandom`): повтор запроса даёт тот
же ключ и дедуплицируется провайдером.

| Метод | HTTP-метод и путь провайдера | request_method | Идемпотентность | Результат |
|---|---|---|---|---|
| `check_conditions(operation, request_method)` | — (без обращения к провайдеру) | значение шлюза, передаётся в super: `create`, `status`, `check` | не применимо | `success` или `failure` базового класса |
| `create_request(operation, _request_method = 'create')` | `POST /transfer` | `'create'` по умолчанию | заголовок идемпотентности в спецификации не объявлен: ключ не отправляется — подробнее — report.md | `success` с идентификатором операции у провайдера — платформа берёт его как `payload.dig(:result, :id)`; `failure` с кодом платформы по FAILURE_CODES |
| `process_callback(_payload)` | в спецификации не объявлено; метод отказывает `failure(:not_implemented, 'errors.webhooks_not_supported')` — подробнее — report.md | — | нет: входящий запрос; повторное уведомление применяет тот же статус ещё раз | `success` после `approve_operation` / `reject_operation`, без result; `failure` с кодом платформы при неверной подписи, неизвестной операции или событии |
| `fetch_status(operation)` | `GET /transfer/{code}` | — | идемпотентен по семантике HTTP (RFC 9110, GET) | `success` после перевода статуса хелпером, без result; `failure` с кодом платформы и ключом `errors.operation_not_found`, `errors.status_unknown` или ошибкой провайдера |

Не отображено на контракт Provider::BaseService: отдельные публичные методы, платформа зовёт их сама; см. report.md.

| Метод | HTTP-метод и путь провайдера | request_method | Идемпотентность | Результат |
|---|---|---|---|---|
| `transaction_initialize(operation)` — роль create_payout (эвристика 0.77) | `POST /transaction/initialize` | — | нет | тело ответа (Hash) или `failure` с кодом платформы по FAILURE_CODES |
| `transaction_verify(operation)` — роль fetch_status (эвристика 0.82) | `GET /transaction/verify/{reference}` | — | идемпотентен по семантике HTTP (RFC 9110, GET) | тело ответа (Hash) или `failure` с кодом платформы по FAILURE_CODES |
| `transaction_list` — роль fetch_status (эвристика 0.77) | `GET /transaction` | — | идемпотентен по семантике HTTP (RFC 9110, GET) | тело ответа (Hash) или `failure` с кодом платформы по FAILURE_CODES |
| `transaction_fetch(operation)` — роль fetch_status (эвристика 0.95) | `GET /transaction/{id}` | — | идемпотентен по семантике HTTP (RFC 9110, GET) | тело ответа (Hash) или `failure` с кодом платформы по FAILURE_CODES |
| `transaction_timeline(operation)` — роль fetch_status (эвристика 0.82) | `GET /transaction/timeline/{id_or_reference}` | — | идемпотентен по семантике HTTP (RFC 9110, GET) | тело ответа (Hash) или `failure` с кодом платформы по FAILURE_CODES |
| `transaction_totals` — роль fetch_status (эвристика 0.77) | `GET /transaction/totals` | — | идемпотентен по семантике HTTP (RFC 9110, GET) | тело ответа (Hash) или `failure` с кодом платформы по FAILURE_CODES |
| `transaction_download` — роль fetch_status (эвристика 0.77) | `GET /transaction/export` | — | идемпотентен по семантике HTTP (RFC 9110, GET) | тело ответа (Hash) или `failure` с кодом платформы по FAILURE_CODES |
| `transaction_charge_authorization(operation)` — роль create_payout (эвристика 0.77) | `POST /transaction/charge_authorization` | — | нет | тело ответа (Hash) или `failure` с кодом платформы по FAILURE_CODES |
| `transaction_check_authorization(operation)` — роль create_payout (эвристика 0.77) | `POST /transaction/check_authorization` | — | нет | тело ответа (Hash) или `failure` с кодом платформы по FAILURE_CODES |
| `transaction_partial_debit(operation)` — роль create_payout (эвристика 0.77) | `POST /transaction/partial_debit` | — | нет | тело ответа (Hash) или `failure` с кодом платформы по FAILURE_CODES |
| `transaction_event(operation)` — роль fetch_status (эвристика 0.61) | `GET /transaction/{id}/event` | — | идемпотентен по семантике HTTP (RFC 9110, GET) | тело ответа (Hash) или `failure` с кодом платформы по FAILURE_CODES |
| `transaction_session(operation)` — роль fetch_status (эвристика 0.77) | `GET /transaction/{id}/session` | — | идемпотентен по семантике HTTP (RFC 9110, GET) | тело ответа (Hash) или `failure` с кодом платформы по FAILURE_CODES |
| `split_create(operation)` — роль не распознана (unmapped): метод с TODO | `POST /split` | — | нет | тело ответа (Hash) или `failure` с кодом платформы по FAILURE_CODES |
| `split_list` — роль не распознана (unmapped): метод с TODO | `GET /split` | — | идемпотентен по семантике HTTP (RFC 9110, GET) | тело ответа (Hash) или `failure` с кодом платформы по FAILURE_CODES |
| `split_fetch(operation)` — роль не распознана (unmapped): метод с TODO | `GET /split/{id}` | — | идемпотентен по семантике HTTP (RFC 9110, GET) | тело ответа (Hash) или `failure` с кодом платформы по FAILURE_CODES |
| `split_update(operation)` — роль не распознана (unmapped): метод с TODO | `PUT /split/{id}` | — | нет | тело ответа (Hash) или `failure` с кодом платформы по FAILURE_CODES |
| `split_add_subaccount(operation)` — роль не распознана (unmapped): метод с TODO | `POST /split/{id}/subaccount/add` | — | нет | тело ответа (Hash) или `failure` с кодом платформы по FAILURE_CODES |
| `split_remove_subaccount(operation)` — роль не распознана (unmapped): метод с TODO | `POST /split/{id}/subaccount/remove` | — | нет | тело ответа (Hash) или `failure` с кодом платформы по FAILURE_CODES |
| `customer_create(operation)` — роль не распознана (unmapped): метод с TODO | `POST /customer` | — | нет | тело ответа (Hash) или `failure` с кодом платформы по FAILURE_CODES |
| `customer_list` — роль не распознана (unmapped): метод с TODO | `GET /customer` | — | идемпотентен по семантике HTTP (RFC 9110, GET) | тело ответа (Hash) или `failure` с кодом платформы по FAILURE_CODES |
| `customer_fetch(operation)` — роль не распознана (unmapped): метод с TODO | `GET /customer/{code}` | — | идемпотентен по семантике HTTP (RFC 9110, GET) | тело ответа (Hash) или `failure` с кодом платформы по FAILURE_CODES |
| `customer_update(operation)` — роль не распознана (unmapped): метод с TODO | `PUT /customer/{code}` | — | нет | тело ответа (Hash) или `failure` с кодом платформы по FAILURE_CODES |
| `customer_risk_action(operation)` — роль не распознана (unmapped): метод с TODO | `POST /customer/set_risk_action` | — | нет | тело ответа (Hash) или `failure` с кодом платформы по FAILURE_CODES |
| `customer_deactivate_authorization(operation)` — роль не распознана (unmapped): метод с TODO | `POST /customer/deactivate_authorization` | — | нет | тело ответа (Hash) или `failure` с кодом платформы по FAILURE_CODES |
| `customer_validatte(operation)` — роль не распознана (unmapped): метод с TODO | `POST /customer/{code}/identification` | — | нет | тело ответа (Hash) или `failure` с кодом платформы по FAILURE_CODES |
| `dedicated_account_create(operation)` — роль не распознана (unmapped): метод с TODO | `POST /dedicated_account` | — | нет | тело ответа (Hash) или `failure` с кодом платформы по FAILURE_CODES |
| `balance` — роль balance (эвристика 0.82) | `GET /dedicated_account` | — | идемпотентен по семантике HTTP (RFC 9110, GET) | тело ответа (Hash) или `failure` с кодом платформы по FAILURE_CODES |
| `dedicated_account_fetch(operation)` — роль balance (эвристика 0.79) | `GET /dedicated_account/{account_id}` | — | идемпотентен по семантике HTTP (RFC 9110, GET) | тело ответа (Hash) или `failure` с кодом платформы по FAILURE_CODES |
| `dedicated_account_deactivate(operation)` — роль не распознана (unmapped): метод с TODO | `DELETE /dedicated_account/{account_id}` | — | нет | тело ответа (Hash) или `failure` с кодом платформы по FAILURE_CODES |
| `dedicated_account_available_providers` — роль balance (эвристика 0.77) | `GET /dedicated_account/available_providers` | — | идемпотентен по семантике HTTP (RFC 9110, GET) | тело ответа (Hash) или `failure` с кодом платформы по FAILURE_CODES |
| `dedicated_account_add_split(operation)` — роль не распознана (unmapped): метод с TODO | `POST /dedicated_account/split` | — | нет | тело ответа (Hash) или `failure` с кодом платформы по FAILURE_CODES |
| `subaccount_create(operation)` — роль не распознана (unmapped): метод с TODO | `POST /subaccount` | — | нет | тело ответа (Hash) или `failure` с кодом платформы по FAILURE_CODES |
| `subaccount_list` — роль не распознана (unmapped): метод с TODO | `GET /subaccount` | — | идемпотентен по семантике HTTP (RFC 9110, GET) | тело ответа (Hash) или `failure` с кодом платформы по FAILURE_CODES |
| `subaccount_fetch(operation)` — роль не распознана (unmapped): метод с TODO | `GET /subaccount/{code}` | — | идемпотентен по семантике HTTP (RFC 9110, GET) | тело ответа (Hash) или `failure` с кодом платформы по FAILURE_CODES |
| `subaccount_update(operation)` — роль не распознана (unmapped): метод с TODO | `PUT /subaccount/{code}` | — | нет | тело ответа (Hash) или `failure` с кодом платформы по FAILURE_CODES |
| `plan_create(operation)` — роль не распознана (unmapped): метод с TODO | `POST /plan` | — | нет | тело ответа (Hash) или `failure` с кодом платформы по FAILURE_CODES |
| `plan_list` — роль не распознана (unmapped): метод с TODO | `GET /plan` | — | идемпотентен по семантике HTTP (RFC 9110, GET) | тело ответа (Hash) или `failure` с кодом платформы по FAILURE_CODES |
| `plan_fetch(operation)` — роль не распознана (unmapped): метод с TODO | `GET /plan/{code}` | — | идемпотентен по семантике HTTP (RFC 9110, GET) | тело ответа (Hash) или `failure` с кодом платформы по FAILURE_CODES |
| `plan_update(operation)` — роль не распознана (unmapped): метод с TODO | `PUT /plan/{code}` | — | нет | тело ответа (Hash) или `failure` с кодом платформы по FAILURE_CODES |
| `subscription_create(operation)` — роль не распознана (unmapped): метод с TODO | `POST /subscription` | — | нет | тело ответа (Hash) или `failure` с кодом платформы по FAILURE_CODES |
| `subscription_list` — роль не распознана (unmapped): метод с TODO | `GET /subscription` | — | идемпотентен по семантике HTTP (RFC 9110, GET) | тело ответа (Hash) или `failure` с кодом платформы по FAILURE_CODES |
| `subscription_fetch(operation)` — роль не распознана (unmapped): метод с TODO | `GET /subscription/{code}` | — | идемпотентен по семантике HTTP (RFC 9110, GET) | тело ответа (Hash) или `failure` с кодом платформы по FAILURE_CODES |
| `subscription_disable(operation)` — роль не распознана (unmapped): метод с TODO | `POST /subscription/disable` | — | нет | тело ответа (Hash) или `failure` с кодом платформы по FAILURE_CODES |
| `subscription_enable(operation)` — роль не распознана (unmapped): метод с TODO | `POST /subscription/enable` | — | нет | тело ответа (Hash) или `failure` с кодом платформы по FAILURE_CODES |
| `subscription_manage_link(operation)` — роль не распознана (unmapped): метод с TODO | `POST /subscription/{code}/manage/link` | — | нет | тело ответа (Hash) или `failure` с кодом платформы по FAILURE_CODES |
| `subscription_manage_email(operation)` — роль не распознана (unmapped): метод с TODO | `POST /subscription/{code}/manage/email` | — | нет | тело ответа (Hash) или `failure` с кодом платформы по FAILURE_CODES |
| `product_create(operation)` — роль не распознана (unmapped): метод с TODO | `POST /product` | — | нет | тело ответа (Hash) или `failure` с кодом платформы по FAILURE_CODES |
| `product_list` — роль не распознана (unmapped): метод с TODO | `GET /product` | — | идемпотентен по семантике HTTP (RFC 9110, GET) | тело ответа (Hash) или `failure` с кодом платформы по FAILURE_CODES |
| `product_fetch(operation)` — роль не распознана (unmapped): метод с TODO | `GET /product/{id}` | — | идемпотентен по семантике HTTP (RFC 9110, GET) | тело ответа (Hash) или `failure` с кодом платформы по FAILURE_CODES |
| `product_update(operation)` — роль не распознана (unmapped): метод с TODO | `PUT /product/{id}` | — | нет | тело ответа (Hash) или `failure` с кодом платформы по FAILURE_CODES |
| `product_delete(operation)` — роль не распознана (unmapped): метод с TODO | `DELETE /product/{id}` | — | нет | тело ответа (Hash) или `failure` с кодом платформы по FAILURE_CODES |
| `page_create(operation)` — роль не распознана (unmapped): метод с TODO | `POST /page` | — | нет | тело ответа (Hash) или `failure` с кодом платформы по FAILURE_CODES |
| `page_list` — роль не распознана (unmapped): метод с TODO | `GET /page` | — | идемпотентен по семантике HTTP (RFC 9110, GET) | тело ответа (Hash) или `failure` с кодом платформы по FAILURE_CODES |
| `page_fetch(operation)` — роль не распознана (unmapped): метод с TODO | `GET /page/{id}` | — | идемпотентен по семантике HTTP (RFC 9110, GET) | тело ответа (Hash) или `failure` с кодом платформы по FAILURE_CODES |
| `page_update(operation)` — роль не распознана (unmapped): метод с TODO | `PUT /page/{id}` | — | нет | тело ответа (Hash) или `failure` с кодом платформы по FAILURE_CODES |
| `page_check_slug_availability(operation)` — роль не распознана (unmapped): метод с TODO | `GET /page/check_slug_availability/{slug}` | — | идемпотентен по семантике HTTP (RFC 9110, GET) | тело ответа (Hash) или `failure` с кодом платформы по FAILURE_CODES |
| `page_add_products(operation)` — роль не распознана (unmapped): метод с TODO | `POST /page/{id}/product` | — | нет | тело ответа (Hash) или `failure` с кодом платформы по FAILURE_CODES |
| `payment_request_create(operation)` — роль create_payout (эвристика 0.95) | `POST /paymentrequest` | — | нет | тело ответа (Hash) или `failure` с кодом платформы по FAILURE_CODES |
| `payment_request_list` — роль fetch_status (эвристика 0.72) | `GET /paymentrequest` | — | идемпотентен по семантике HTTP (RFC 9110, GET) | тело ответа (Hash) или `failure` с кодом платформы по FAILURE_CODES |
| `payment_request_fetch(operation)` — роль fetch_status (эвристика 0.95) | `GET /paymentrequest/{id}` | — | идемпотентен по семантике HTTP (RFC 9110, GET) | тело ответа (Hash) или `failure` с кодом платформы по FAILURE_CODES |
| `payment_request_update(operation)` — роль не распознана (unmapped): метод с TODO | `PUT /paymentrequest/{id}` | — | нет | тело ответа (Hash) или `failure` с кодом платформы по FAILURE_CODES |
| `payment_request_verify(operation)` — роль fetch_status (эвристика 0.79) | `GET /paymentrequest/verify/{id}` | — | идемпотентен по семантике HTTP (RFC 9110, GET) | тело ответа (Hash) или `failure` с кодом платформы по FAILURE_CODES |
| `cancel(operation)` — роль cancel (эвристика 0.54) | `POST /paymentrequest/notify/{id}` | — | нет | `success` или `failure` с кодом платформы; до запроса — проверка CANCELLABLE_STATUSES |
| `payment_request_totals` — роль fetch_status (эвристика 0.72) | `GET /paymentrequest/totals` | — | идемпотентен по семантике HTTP (RFC 9110, GET) | тело ответа (Hash) или `failure` с кодом платформы по FAILURE_CODES |
| `payment_request_finalize(operation)` — роль cancel (эвристика 0.54) | `POST /paymentrequest/finalize/{id}` | — | нет | `success` или `failure` с кодом платформы; до запроса — проверка CANCELLABLE_STATUSES |
| `payment_request_archive(operation)` — роль cancel (эвристика 0.54) | `POST /paymentrequest/archive/{id}` | — | нет | `success` или `failure` с кодом платформы; до запроса — проверка CANCELLABLE_STATUSES |
| `settlements_fetch` — роль не распознана (unmapped): метод с TODO | `GET /settlement` | — | идемпотентен по семантике HTTP (RFC 9110, GET) | тело ответа (Hash) или `failure` с кодом платформы по FAILURE_CODES |
| `settlements_transaction(operation)` — роль fetch_status (эвристика 0.75) | `GET /settlement/{id}/transaction` | — | идемпотентен по семантике HTTP (RFC 9110, GET) | тело ответа (Hash) или `failure` с кодом платформы по FAILURE_CODES |
| `transferrecipient_create(operation)` — роль create_payout (эвристика 0.72) | `POST /transferrecipient` | — | нет | тело ответа (Hash) или `failure` с кодом платформы по FAILURE_CODES |
| `transferrecipient_list` — роль fetch_status (эвристика 0.80) | `GET /transferrecipient` | — | идемпотентен по семантике HTTP (RFC 9110, GET) | тело ответа (Hash) или `failure` с кодом платформы по FAILURE_CODES |
| `transferrecipient_bulk(operation)` — роль create_payout (эвристика 0.80) | `POST /transferrecipient/bulk` | — | нет | тело ответа (Hash) или `failure` с кодом платформы по FAILURE_CODES |
| `transferrecipient_fetch(operation)` — роль fetch_status (эвристика 0.79) | `GET /transferrecipient/{code}` | — | идемпотентен по семантике HTTP (RFC 9110, GET) | тело ответа (Hash) или `failure` с кодом платформы по FAILURE_CODES |
| `put_transferrecipient_code(operation)` — роль не распознана (unmapped): метод с TODO | `PUT /transferrecipient/{code}` | — | нет | тело ответа (Hash) или `failure` с кодом платформы по FAILURE_CODES |
| `delete_transferrecipient_code(operation)` — роль cancel (эвристика 0.57) | `DELETE /transferrecipient/{code}` | — | нет | `success` или `failure` с кодом платформы; до запроса — проверка CANCELLABLE_STATUSES |
| `transfer_list` — роль fetch_status (эвристика 0.77) | `GET /transfer` | — | идемпотентен по семантике HTTP (RFC 9110, GET) | тело ответа (Hash) или `failure` с кодом платформы по FAILURE_CODES |
| `transfer_finalize(operation)` — роль create_payout (эвристика 0.77) | `POST /transfer/finalize_transfer` | — | нет | тело ответа (Hash) или `failure` с кодом платформы по FAILURE_CODES |
| `transfer_bulk(operation)` — роль create_payout (эвристика 0.77) | `POST /transfer/bulk` | — | нет | тело ответа (Hash) или `failure` с кодом платформы по FAILURE_CODES |
| `transfer_verify(operation)` — роль fetch_status (эвристика 0.82) | `GET /transfer/verify/{reference}` | — | идемпотентен по семантике HTTP (RFC 9110, GET) | тело ответа (Hash) или `failure` с кодом платформы по FAILURE_CODES |
| `transfer_download` — роль fetch_status (эвристика 0.77) | `GET /transfer/export` | — | идемпотентен по семантике HTTP (RFC 9110, GET) | тело ответа (Hash) или `failure` с кодом платформы по FAILURE_CODES |
| `transfer_resend_otp(operation)` — роль create_payout (эвристика 0.77) | `POST /transfer/resend_otp` | — | нет | тело ответа (Hash) или `failure` с кодом платформы по FAILURE_CODES |
| `transfer_disable_otp` — роль cancel (эвристика 0.77) | `POST /transfer/disable_otp` | — | нет | `success` или `failure` с кодом платформы; до запроса — проверка CANCELLABLE_STATUSES |
| `transfer_disable_otp_finalize(operation)` — роль create_payout (эвристика 0.77) | `POST /transfer/disable_otp_finalize` | — | нет | тело ответа (Hash) или `failure` с кодом платформы по FAILURE_CODES |
| `transfer_enable_otp` — роль cancel (эвристика 0.77) | `POST /transfer/enable_otp` | — | нет | `success` или `failure` с кодом платформы; до запроса — проверка CANCELLABLE_STATUSES |
| `balance_fetch` — роль balance (эвристика 0.95) | `GET /balance` | — | идемпотентен по семантике HTTP (RFC 9110, GET) | тело ответа (Hash) или `failure` с кодом платформы по FAILURE_CODES |
| `balance_ledger` — роль balance (эвристика 0.77) | `GET /balance/ledger` | — | идемпотентен по семантике HTTP (RFC 9110, GET) | тело ответа (Hash) или `failure` с кодом платформы по FAILURE_CODES |
| `charge_create(operation)` — роль create_deposit (эвристика 0.95) | `POST /charge` | — | нет | тело ответа (Hash) или `failure` с кодом платформы по FAILURE_CODES |
| `charge_submit_pin(operation)` — роль create_deposit (эвристика 0.95) | `POST /charge/submit_pin` | — | нет | тело ответа (Hash) или `failure` с кодом платформы по FAILURE_CODES |
| `charge_submit_otp(operation)` — роль create_deposit (эвристика 0.95) | `POST /charge/submit_otp` | — | нет | тело ответа (Hash) или `failure` с кодом платформы по FAILURE_CODES |
| `charge_submit_phone(operation)` — роль create_deposit (эвристика 0.95) | `POST /charge/submit_phone` | — | нет | тело ответа (Hash) или `failure` с кодом платформы по FAILURE_CODES |
| `charge_submit_birthday(operation)` — роль create_deposit (эвристика 0.95) | `POST /charge/submit_birthday` | — | нет | тело ответа (Hash) или `failure` с кодом платформы по FAILURE_CODES |
| `charge_submit_address(operation)` — роль create_deposit (эвристика 0.95) | `POST /charge/submit_address` | — | нет | тело ответа (Hash) или `failure` с кодом платформы по FAILURE_CODES |
| `charge_check(operation)` — роль fetch_status (эвристика 0.95) | `GET /charge/{reference}` | — | идемпотентен по семантике HTTP (RFC 9110, GET) | тело ответа (Hash) или `failure` с кодом платформы по FAILURE_CODES |
| `bulk_charge_initiate(operation)` — роль create_deposit (эвристика 0.95) | `POST /bulkcharge` | — | нет | тело ответа (Hash) или `failure` с кодом платформы по FAILURE_CODES |
| `bulk_charge_list` — роль fetch_status (эвристика 0.69) | `GET /bulkcharge` | — | идемпотентен по семантике HTTP (RFC 9110, GET) | тело ответа (Hash) или `failure` с кодом платформы по FAILURE_CODES |
| `bulk_charge_fetch(operation)` — роль fetch_status (эвристика 0.95) | `GET /bulkcharge/{code}` | — | идемпотентен по семантике HTTP (RFC 9110, GET) | тело ответа (Hash) или `failure` с кодом платформы по FAILURE_CODES |
| `bulk_charge_charges(operation)` — роль fetch_status (эвристика 0.58) | `GET /bulkcharge/{code}/charges` | — | идемпотентен по семантике HTTP (RFC 9110, GET) | тело ответа (Hash) или `failure` с кодом платформы по FAILURE_CODES |
| `bulk_charge_pause(operation)` — роль fetch_status (эвристика 0.77) | `GET /bulkcharge/pause/{code}` | — | идемпотентен по семантике HTTP (RFC 9110, GET) | тело ответа (Hash) или `failure` с кодом платформы по FAILURE_CODES |
| `bulk_charge_resume(operation)` — роль fetch_status (эвристика 0.77) | `GET /bulkcharge/resume/{code}` | — | идемпотентен по семантике HTTP (RFC 9110, GET) | тело ответа (Hash) или `failure` с кодом платформы по FAILURE_CODES |
| `integration_fetch_payment_session_timeout` — роль fetch_status (эвристика 0.95) | `GET /integration/payment_session_timeout` | — | идемпотентен по семантике HTTP (RFC 9110, GET) | тело ответа (Hash) или `failure` с кодом платформы по FAILURE_CODES |
| `integration_update_payment_session_timeout(operation)` — роль не распознана (unmapped): метод с TODO | `PUT /integration/payment_session_timeout` | — | нет | тело ответа (Hash) или `failure` с кодом платформы по FAILURE_CODES |
| `refund(operation)` — роль refund (эвристика 0.92) | `POST /refund` | — | нет | тело ответа (Hash) или `failure` с кодом платформы по FAILURE_CODES |
| `refund_list` — роль не распознана (unmapped): метод с TODO | `GET /refund` | — | идемпотентен по семантике HTTP (RFC 9110, GET) | тело ответа (Hash) или `failure` с кодом платформы по FAILURE_CODES |
| `refund_fetch(operation)` — роль не распознана (unmapped): метод с TODO | `GET /refund/{id}` | — | идемпотентен по семантике HTTP (RFC 9110, GET) | тело ответа (Hash) или `failure` с кодом платформы по FAILURE_CODES |
| `dispute_list` — роль не распознана (unmapped): метод с TODO | `GET /dispute` | — | идемпотентен по семантике HTTP (RFC 9110, GET) | тело ответа (Hash) или `failure` с кодом платформы по FAILURE_CODES |
| `dispute_fetch(operation)` — роль не распознана (unmapped): метод с TODO | `GET /dispute/{id}` | — | идемпотентен по семантике HTTP (RFC 9110, GET) | тело ответа (Hash) или `failure` с кодом платформы по FAILURE_CODES |
| `dispute_update(operation)` — роль не распознана (unmapped): метод с TODO | `PUT /dispute/{id}` | — | нет | тело ответа (Hash) или `failure` с кодом платформы по FAILURE_CODES |
| `dispute_upload_url(operation)` — роль не распознана (unmapped): метод с TODO | `GET /dispute/{id}/upload_url` | — | идемпотентен по семантике HTTP (RFC 9110, GET) | тело ответа (Hash) или `failure` с кодом платформы по FAILURE_CODES |
| `dispute_download` — роль не распознана (unmapped): метод с TODO | `GET /dispute/export` | — | идемпотентен по семантике HTTP (RFC 9110, GET) | тело ответа (Hash) или `failure` с кодом платформы по FAILURE_CODES |
| `dispute_transaction(operation)` — роль fetch_status (эвристика 0.81) | `GET /dispute/transaction/{id}` | — | идемпотентен по семантике HTTP (RFC 9110, GET) | тело ответа (Hash) или `failure` с кодом платформы по FAILURE_CODES |
| `dispute_resolve(operation)` — роль не распознана (unmapped): метод с TODO | `PUT /dispute/{id}/resolve` | — | нет | тело ответа (Hash) или `failure` с кодом платформы по FAILURE_CODES |
| `dispute_evidence(operation)` — роль не распознана (unmapped): метод с TODO | `POST /dispute/{id}/evidence` | — | нет | тело ответа (Hash) или `failure` с кодом платформы по FAILURE_CODES |
| `verification_bvn_match(operation)` — роль не распознана (unmapped): метод с TODO | `POST /bvn/match` | — | нет | тело ответа (Hash) или `failure` с кодом платформы по FAILURE_CODES |
| `verification_resolve_bvn(operation)` — роль не распознана (unmapped): метод с TODO | `GET /bank/resolve_bvn/{bvn}` | — | идемпотентен по семантике HTTP (RFC 9110, GET) | тело ответа (Hash) или `failure` с кодом платформы по FAILURE_CODES |
| `verification_resolve_account_number` — роль balance (эвристика 0.69) | `GET /bank/resolve` | — | идемпотентен по семантике HTTP (RFC 9110, GET) | тело ответа (Hash) или `failure` с кодом платформы по FAILURE_CODES |
| `verification_resolve_card_bin(operation)` — роль не распознана (unmapped): метод с TODO | `GET /decision/bin/{bin}` | — | идемпотентен по семантике HTTP (RFC 9110, GET) | тело ответа (Hash) или `failure` с кодом платформы по FAILURE_CODES |
| `verification_list_countries` — роль не распознана (unmapped): метод с TODO | `GET /country` | — | идемпотентен по семантике HTTP (RFC 9110, GET) | тело ответа (Hash) или `failure` с кодом платформы по FAILURE_CODES |
| `verification_fetch_banks` — роль не распознана (unmapped): метод с TODO | `GET /bank` | — | идемпотентен по семантике HTTP (RFC 9110, GET) | тело ответа (Hash) или `failure` с кодом платформы по FAILURE_CODES |
| `verification_avs` — роль не распознана (unmapped): метод с TODO | `GET /address_verification/states` | — | идемпотентен по семантике HTTP (RFC 9110, GET) | тело ответа (Hash) или `failure` с кодом платформы по FAILURE_CODES |

## 4. Маппинг статусов

Спецификация не объявляет статусов операции: STATUS_MAP пуста, `map_status` возвращает nil для любого значения — подробнее — report.md.

Вебхуков в спецификации не объявлено: EVENT_MAP не генерируется, статус — только опросом `fetch_status`.

## 5. Обработка ошибок с действиями

`ERROR_MAP` читается в два шага: сначала код ошибки из тела ответа, потом
HTTP-код. Символ действия — это политика обработки на стороне платформы;
первым аргументом `failure` уходит код платформы (см. ниже).

| HTTP-код | Действие | Что делает сервис |
|---|---|---|
| `404` | `reject` | `failure(:not_found, 'errors.http_404')` |

Коды, которые у отдельной операции означают не то, что в общей таблице (ERROR_MAP_BY_OPERATION):

| Операция | HTTP-код | Действие |
|---|---|---|
| `balance_fetch` | `401` | `alert` |
| `balance_ledger` | `401` | `alert` |
| `bulkCharge_charges` | `401` | `alert` |
| `bulkCharge_fetch` | `401` | `alert` |
| `bulkCharge_initiate` | `401` | `alert` |
| `bulkCharge_list` | `401` | `alert` |
| `bulkCharge_pause` | `401` | `alert` |
| `bulkCharge_resume` | `401` | `alert` |
| `charge_check` | `401` | `alert` |
| `charge_create` | `401` | `alert` |
| `charge_submitAddress` | `401` | `alert` |
| `charge_submitBirthday` | `401` | `alert` |
| `charge_submitOtp` | `401` | `alert` |
| `charge_submitPhone` | `401` | `alert` |
| `charge_submitPin` | `401` | `alert` |
| `customer_create` | `401` | `alert` |
| `customer_deactivateAuthorization` | `401` | `alert` |
| `customer_fetch` | `401` | `alert` |
| `customer_list` | `401` | `alert` |
| `customer_riskAction` | `401` | `alert` |
| `customer_update` | `401` | `alert` |
| `customer_validatte` | `401` | `alert` |
| `dedicatedAccount_addSplit` | `401` | `alert` |
| `dedicatedAccount_availableProviders` | `401` | `alert` |
| `dedicatedAccount_create` | `401` | `alert` |
| `dedicatedAccount_deactivate` | `401` | `alert` |
| `dedicatedAccount_fetch` | `401` | `alert` |
| `dedicatedAccount_list` | `401` | `alert` |
| `delete_transferrecipient_code` | `401` | `alert` |
| `dispute_download` | `401` | `alert` |
| `dispute_evidence` | `401` | `alert` |
| `dispute_fetch` | `401` | `alert` |
| `dispute_list` | `401` | `alert` |
| `dispute_resolve` | `401` | `alert` |
| `dispute_transaction` | `401` | `alert` |
| `dispute_update` | `401` | `alert` |
| `dispute_uploadUrl` | `401` | `alert` |
| `integration_fetchPaymentSessionTimeout` | `401` | `alert` |
| `integration_updatePaymentSessionTimeout` | `401` | `alert` |
| `page_addProducts` | `401` | `alert` |
| `page_checkSlugAvailability` | `401` | `alert` |
| `page_create` | `401` | `alert` |
| `page_fetch` | `401` | `alert` |
| `page_list` | `401` | `alert` |
| `page_update` | `401` | `alert` |
| `paymentRequest_archive` | `401` | `alert` |
| `paymentRequest_create` | `401` | `alert` |
| `paymentRequest_fetch` | `401` | `alert` |
| `paymentRequest_finalize` | `401` | `alert` |
| `paymentRequest_list` | `401` | `alert` |
| `paymentRequest_notify` | `401` | `alert` |
| `paymentRequest_totals` | `401` | `alert` |
| `paymentRequest_update` | `401` | `alert` |
| `paymentRequest_verify` | `401` | `alert` |
| `plan_create` | `401` | `alert` |
| `plan_fetch` | `401` | `alert` |
| `plan_list` | `401` | `alert` |
| `plan_update` | `401` | `alert` |
| `product_create` | `401` | `alert` |
| `product_delete` | `401` | `alert` |
| `product_fetch` | `401` | `alert` |
| `product_list` | `401` | `alert` |
| `product_update` | `401` | `alert` |
| `put_transferrecipient_code` | `401` | `alert` |
| `refund_create` | `401` | `alert` |
| `refund_fetch` | `401` | `alert` |
| `refund_list` | `401` | `alert` |
| `settlements_fetch` | `401` | `alert` |
| `settlements_transaction` | `401` | `alert` |
| `split_addSubaccount` | `401` | `alert` |
| `split_create` | `401` | `alert` |
| `split_fetch` | `401` | `alert` |
| `split_list` | `401` | `alert` |
| `split_removeSubaccount` | `401` | `alert` |
| `split_update` | `401` | `alert` |
| `subaccount_create` | `401` | `alert` |
| `subaccount_fetch` | `401` | `alert` |
| `subaccount_list` | `401` | `alert` |
| `subaccount_update` | `401` | `alert` |
| `subscription_create` | `401` | `alert` |
| `subscription_disable` | `401` | `alert` |
| `subscription_enable` | `401` | `alert` |
| `subscription_fetch` | `401` | `alert` |
| `subscription_list` | `401` | `alert` |
| `subscription_manageEmail` | `401` | `alert` |
| `subscription_manageLink` | `401` | `alert` |
| `transaction_chargeAuthorization` | `401` | `alert` |
| `transaction_checkAuthorization` | `401` | `alert` |
| `transaction_download` | `401` | `alert` |
| `transaction_event` | `401` | `alert` |
| `transaction_fetch` | `401` | `alert` |
| `transaction_initialize` | `401` | `alert` |
| `transaction_list` | `401` | `alert` |
| `transaction_partialDebit` | `401` | `alert` |
| `transaction_session` | `401` | `alert` |
| `transaction_timeline` | `401` | `alert` |
| `transaction_totals` | `401` | `alert` |
| `transaction_verify` | `401` | `alert` |
| `transfer_bulk` | `401` | `alert` |
| `transfer_disableOtp` | `401` | `alert` |
| `transfer_disableOtpFinalize` | `401` | `alert` |
| `transfer_download` | `401` | `alert` |
| `transfer_enableOtp` | `401` | `alert` |
| `transfer_fetch` | `401` | `alert` |
| `transfer_finalize` | `401` | `alert` |
| `transfer_initiate` | `401` | `alert` |
| `transfer_list` | `401` | `alert` |
| `transfer_resendOtp` | `401` | `alert` |
| `transfer_verify` | `401` | `alert` |
| `transferrecipient_bulk` | `401` | `alert` |
| `transferrecipient_create` | `401` | `alert` |
| `transferrecipient_fetch` | `401` | `alert` |
| `transferrecipient_list` | `401` | `alert` |
| `verification_avs` | `401` | `alert` |
| `verification_bvnMatch` | `401` | `alert` |
| `verification_fetchBanks` | `401` | `alert` |
| `verification_listCountries` | `401` | `alert` |
| `verification_resolveAccountNumber` | `401` | `alert` |
| `verification_resolveBvn` | `401` | `alert` |
| `verification_resolveCardBin` | `401` | `alert` |

| Действие | Что это значит для платформы |
|---|---|
| `reject` | операция отклоняется, повтор не поможет |

Первым аргументом `failure` уходит код платформы, а не наше действие: по HTTP-коду ответа (FAILURE_CODES: 400 → `:bad_request`, 401 → `:unauthorized`, 403 → `:forbidden`, 404 → `:not_found`, 409 → `:conflict`, 422 → `:unprocessable_entity`, 429 → `:too_many_requests`, 500 → `:internal_server_error`, 502 → `:bad_gateway`, 503 → `:service_unavailable`, 504 → `:gateway_timeout`), иначе по действию из ERROR_MAP (FAILURE_CODES_BY_ACTION: `reject` → `:unprocessable_entity`, `retry` → `:service_unavailable`, `retry_backoff` → `:service_unavailable`, `alert` → `:internal_server_error`, `escalate` → `:unprocessable_entity`). Действие остаётся политикой обработки — оно в ERROR_MAP, RETRY_POLICY и в таблицах выше.

Политика ретраев (RETRY_POLICY): платформа повторяет запрос при действиях `retry`, `retry_backoff`; по HTTP-кодам это —. Заголовок паузы до повтора в спецификации не объявлен.

Механизм ретраев, очереди и алерты — инфраструктура платформы; сервис не повторяет запросы сам, а только отдаёт политику данными.

Код, которого нет в таблицах, получает действие по умолчанию `reject` (DEFAULT_ERROR_ACTION).

Дедупликация. Идемпотентность в спецификации не объявлена: повтор запроса провайдер не отличит от нового — подробнее — report.md.

## 6. Параметры подключения

Этот раздел закрывает `## ProviderGateway config` из описания кейса; форма другая, потому что отдельный конфиг шлюза платформе не нужен, а адрес и авторизация берутся из спецификации (ответ экспертов 5 сентября 2026, `docs/QUESTIONS.md`, вопрос 15).

Всё ниже выведено из самой спецификации: адрес, ключи учётных данных, валюты, единицы и границы суммы, ограничения полей, путь и заголовок уведомлений. Отдельного конфига сервис не требует — это сводка для сверки. Значения вычислены тем же кодом, что предпроверки `check_conditions` сервиса: суммы — во внутренних (мажорных) единицах.

```yaml
providers:
  paystack_v1:
    service: Provider::PaystackV1Service
    base_url: https://api.paystack.co  # переменная окружения PAYSTACK_V1_BASE_URL, адрес из серверов спецификации
    credentials: [token]
    request_methods: [create, status, check]
    currencies: []  # TODO: валюта в спецификации не выведена
    amount:
      platform_unit: major
      provider_unit: minor
      multiplier: 100  # ISO 4217: у всех валют enum (NGN, GHS, ZAR, USD) экспонента 2
```

### Куда мапить поля тела запроса

Строка на каждое поле тела запроса операции создания: чем его заполняет сервис. Пустая ячейка выражения — место под ручной маппинг: платформа такого реквизита не описывает, и выдумывать его инструмент не имеет права (эксперты кейса, 5 сентября 2026). Реквизиты получателя раскрыты по способам выплаты: ключ верхнего уровня в `operation.payout_requisite` — это payment_method шлюза, он же request_method.

| Поле тела запроса | Роль | Способ выплаты | Чем заполняется |
|---|---|---|---|
| `source` | роль не распознана | нет | — заполните вручную |
| `amount` | `amount` | нет | `operation.amount` |
| `recipient` | `recipient_type` | нет | — заполните вручную |
| `reason` | роль не распознана | нет | — заполните вручную |
| `currency` | `currency` | нет | — заполните вручную |
| `reference` | `provider_operation_id` | нет | `operation.provider_operation_key` |

## 7. Схема подписи вебхука

Вебхуков в спецификации не объявлено: подписи нет, `process_callback` отказывает `failure(:not_implemented, 'errors.webhooks_not_supported')`.

## 8. Как подключить в приложение

1. Положите `paystack_v1_service.rb` в каталог провайдеров платформы рядом с
   остальными наследниками `Provider::BaseService`; класс — `Provider::PaystackV1Service`.
2. Задайте ключи `provider.credentials` из раздела 1 и переменные окружения из
   раздела 2. Значения секретов — только в хранилище credentials платформы.
3. Сверьте параметры подключения из раздела 6 с тем, как провайдер заведён
   у вас: адрес, ключи учётных данных, валюты и границы суммы выведены из
   спецификации, отдельного конфига сервис не требует.
4. Направьте маршрут входящих уведомлений провайдера на `process_callback`,
   передавая уже разобранный JSON (`payload`). Подпись считается по
   сырым байтам тела, которых в разобранном JSON уже нет, поэтому вызовите
   `verify_webhook_signature(raw_body, headers)` в самом маршруте, до разбора
   тела; форма аргумента задана в `rules/contract.yml`, раздел `platform`.
5. Включите `fetch_status` в поллинг незавершённых операций:
   это единственный путь узнать статус, если уведомление не пришло.
6. Прогоните `fixtures.json` через WebMock: в нём запросы, ответы и
   уведомления из примеров спецификации с ожидаемым внутренним статусом.
7. Пройдите по пунктам `report.md`: каждая строка там — действие, а TODO в
   сервисе указывают на то же место.

## 9. Принятые допущения

Реального класса Provider::BaseService нам не выдали. Контракт восстановлен по примеру из описания кейса и подтверждениям экспертов. Это допущение, оно продублировано в docs/ASSUMPTIONS.md и в INTEGRATION.md. Сигнатуры четырёх методов и имена хелперов видны в примере; типы возвращаемых значений и арность части хелперов выведены нами.

- №1. Контракт Provider::BaseService восстановлен по примеру из описания кейса; реального класса нет и не будет. Имена и арность четырёх методов и хелперов — как в примере. Источник: описание кейса; эксперты 4 сентября 2026: «неважно, как он устроен… базовый класс-фабрика». Где влияет: rules/contract.yml, шаблон сервиса, INTEGRATION.md.
- №2. HTTP-клиент платформы вызывается как client.post(url, payload, headers) и client.get(url, headers); ответ читается как response.status и response.body; базовый URL берётся из ENV. Источник: эксперты 4 сентября 2026: «есть какой-то клиент, к которому обращаемся через POST, передавая URL, payload и header». Где влияет: шаблон сервиса, rules/contract.yml.
- №3. Генерация не блокируется никогда. Там, где спецификация не даёт ответа, сервис получает лучшего кандидата из справочников с пометкой TODO и строкой в report.md, а не пустое значение. Источник: эксперты 4 сентября 2026: «инструмент должен больше решать сам… человек уже всё равно всё будет смотреть, но после того, как сгенерировано». Где влияет: генераторы, report.md, третий уровень доверия (docs/PRINCIPLES.md).
- №4. Дубли операций отсекает платформа до вызова сервиса. Ветка кода конфликта со схемой успеха («взять существующую операцию») генерируется, потому что так говорит спецификация, но не считается ключевой функцией. Источник: эксперты 4 сентября 2026, вопрос 12 в docs/QUESTIONS.md. Где влияет: шаблон сервиса, INTEGRATION.md.
- №6. operation.amount приходит в мажорных единицах (рубли), провайдер ждёт минорные; множитель — 10 в степени экспоненты ISO 4217 для кода валюты, а не слово «копейках» в описании. Источник: описание кейса; ISO 4217. Где влияет: UnitsAnalyzer, шаблон сервиса, check_conditions.
- №7. Канонический маппинг статусов из описания кейса подтверждён экспертами; cancelled отображается в rejected, четвёртого внутреннего статуса нет. Источник: описание кейса; вопрос 3 в docs/QUESTIONS.md открыт. Где влияет: rules/statuses.yml, STATUS_MAP, EVENT_MAP.
- №10. Аргумент process_callback — уже разобранный JSON уведомления. Подпись считается по сырым байтам тела, которых в разобранном JSON нет, поэтому проверку вызывает маршрут вебхука публичным методом verify_webhook_signature до разбора тела; внутри process_callback подпись проверяется, только если маршрут положил байты и заголовки в аргумент. Источник: эксперты 5 сентября 2026: process_callback «получает уже разобранный JSON внутри payload». Где влияет: шаблон сервиса, INTEGRATION.md раздел 8, report.md чек-лист.
- №11. Валюта запроса берётся из спецификации — из единственного значения enum, const или example поля с ролью currency, — а не у платформы: поля currency у операции нет. Источник: эксперты 5 сентября 2026: в перечне полей операции валюты нет, «адрес, авторизация и т.д. должны браться из open api документа провайдера». Где влияет: константа CURRENCY сервиса, build_payload, INTEGRATION.md.
- №12. Реквизит, для которого в таблице requisites rules/contract.yml нет выражения, вслепую не генерируется: поле получает TODO и строку «куда мапить» в INTEGRATION.md. Догадка о спецификации обязательна, догадка о платформе запрещена. Источник: эксперты 5 сентября 2026: «Для поля из спеки, которого нет в известной схеме платформы, не генерировать вслепую. Лучше TODO и явное место маппинга в INTEGRATION.md». Где влияет: build_payload, report.md, INTEGRATION.md.
- №13. Ключ верхнего уровня в payout_requisite — это payment_method шлюза, он же request_method. Значение enum роли recipient_type из спецификации сопоставляется с ним по нормализованному имени. Источник: эксперты 5 сентября 2026: «request_method — логический метод шлюза (gateway.payment_method: sbp, p2p, …), в одном сервисе — ветки по request_method и/или форме payout_requisite»; сопоставление имён — наше решение. Где влияет: ветка case request_method в сборке реквизитов.

Выражения, которыми сервис разговаривает с платформой, — раздел platform в rules/contract.yml (источник: эксперты кейса 5 сентября 2026 (вопросы 18–25 в docs/QUESTIONS.md) и допущение), например `operation.amount`, `operation.id`, `operation.provider_operation_key`, `payload`; поменялась платформа — правится справочник, не сервис.

Допущения этого прогона — то, что в коде взято по лучшему кандидату или по умолчанию:

- обязательное поле `source` без роли: в payload со значением `nil` и TODO (роль currency отдана `currency` (0.90); ) (подробнее — report.md)
- поле `recipient` получило роль recipient_type с уверенностью ниже порога (эвристика 0.21): композитное сопоставление: name 2.0 (общие токены с синонимом `recipient_type`: recipient (50%)), type 1.0 (type string допустим для роли) = 3.0 из 14.0; следующая recipient_phone 0.21 (подробнее — report.md)
- поле `reference` получило роль provider_operation_id с уверенностью ниже порога (эвристика 0.50): композитное сопоставление: name 2.0 (общие токены с синонимом `acquirer_reference`: reference (50%)), structure 4.0 (родитель `transfer_initiate.requestBody` содержит токен `transfer` из подсказок роли), type 1.0 (type string допустим для роли) = 7.0 из 14.0; следующая external_id 0.21 (подробнее — report.md)
- параметр пути {code} операции customer_fetch без роли: подставлен идентификатор провайдера (подробнее — report.md)
- параметр пути {code} операции customer_update без роли: подставлен идентификатор провайдера (подробнее — report.md)
- параметр пути {account_id} операции dedicatedAccount_fetch без роли: подставлен идентификатор провайдера (подробнее — report.md)
- параметр пути {account_id} операции dedicatedAccount_deactivate без роли: подставлен идентификатор провайдера (подробнее — report.md)
- параметр пути {code} операции subaccount_fetch без роли: подставлен идентификатор провайдера (подробнее — report.md)
- параметр пути {code} операции subaccount_update без роли: подставлен идентификатор провайдера (подробнее — report.md)
- параметр пути {code} операции plan_fetch без роли: подставлен идентификатор провайдера (подробнее — report.md)
- параметр пути {code} операции plan_update без роли: подставлен идентификатор провайдера (подробнее — report.md)
- параметр пути {code} операции subscription_fetch без роли: подставлен идентификатор провайдера (подробнее — report.md)
- параметр пути {code} операции subscription_manageLink без роли: подставлен идентификатор провайдера (подробнее — report.md)
- параметр пути {code} операции subscription_manageEmail без роли: подставлен идентификатор провайдера (подробнее — report.md)
- параметр пути {slug} операции page_checkSlugAvailability без роли: подставлен идентификатор провайдера (подробнее — report.md)
- параметр пути {code} операции transferrecipient_fetch без роли: подставлен идентификатор провайдера (подробнее — report.md)
- параметр пути {code} операции put_transferrecipient_code без роли: подставлен идентификатор провайдера (подробнее — report.md)
- параметр пути {code} операции delete_transferrecipient_code без роли: подставлен идентификатор провайдера (подробнее — report.md)
- параметр пути {code} операции transfer_fetch без роли: подставлен идентификатор провайдера (подробнее — report.md)
- параметр пути {code} операции bulkCharge_fetch без роли: подставлен идентификатор провайдера (подробнее — report.md)
- параметр пути {code} операции bulkCharge_charges без роли: подставлен идентификатор провайдера (подробнее — report.md)
- параметр пути {code} операции bulkCharge_pause без роли: подставлен идентификатор провайдера (подробнее — report.md)
- параметр пути {code} операции bulkCharge_resume без роли: подставлен идентификатор провайдера (подробнее — report.md)
- параметр пути {bvn} операции verification_resolveBvn без роли: подставлен идентификатор провайдера (подробнее — report.md)
- параметр пути {bin} операции verification_resolveCardBin без роли: подставлен идентификатор провайдера (подробнее — report.md)
- в успешном ответе на создание нет поля с ролью provider_operation_id: идентификатор провайдера не сохраняется (подробнее — report.md)
- заголовок идемпотентности не найден: ключ не отправляется (подробнее — report.md)
- операция split_create не отображена на контракт: отдельный метод с TODO (подробнее — report.md)
- операция split_list не отображена на контракт: отдельный метод с TODO (подробнее — report.md)
- операция split_fetch не отображена на контракт: отдельный метод с TODO (подробнее — report.md)
- операция split_update не отображена на контракт: отдельный метод с TODO (подробнее — report.md)
- операция split_addSubaccount не отображена на контракт: отдельный метод с TODO (подробнее — report.md)
- операция split_removeSubaccount не отображена на контракт: отдельный метод с TODO (подробнее — report.md)
- операция customer_create не отображена на контракт: отдельный метод с TODO (подробнее — report.md)
- операция customer_list не отображена на контракт: отдельный метод с TODO (подробнее — report.md)
- операция customer_fetch не отображена на контракт: отдельный метод с TODO (подробнее — report.md)
- операция customer_update не отображена на контракт: отдельный метод с TODO (подробнее — report.md)
- операция customer_riskAction не отображена на контракт: отдельный метод с TODO (подробнее — report.md)
- операция customer_deactivateAuthorization не отображена на контракт: отдельный метод с TODO (подробнее — report.md)
- операция customer_validatte не отображена на контракт: отдельный метод с TODO (подробнее — report.md)
- операция dedicatedAccount_create не отображена на контракт: отдельный метод с TODO (подробнее — report.md)
- операция dedicatedAccount_deactivate не отображена на контракт: отдельный метод с TODO (подробнее — report.md)
- операция dedicatedAccount_addSplit не отображена на контракт: отдельный метод с TODO (подробнее — report.md)
- операция subaccount_create не отображена на контракт: отдельный метод с TODO (подробнее — report.md)
- операция subaccount_list не отображена на контракт: отдельный метод с TODO (подробнее — report.md)
- операция subaccount_fetch не отображена на контракт: отдельный метод с TODO (подробнее — report.md)
- операция subaccount_update не отображена на контракт: отдельный метод с TODO (подробнее — report.md)
- операция plan_create не отображена на контракт: отдельный метод с TODO (подробнее — report.md)
- операция plan_list не отображена на контракт: отдельный метод с TODO (подробнее — report.md)
- операция plan_fetch не отображена на контракт: отдельный метод с TODO (подробнее — report.md)
- операция plan_update не отображена на контракт: отдельный метод с TODO (подробнее — report.md)
- операция subscription_create не отображена на контракт: отдельный метод с TODO (подробнее — report.md)
- операция subscription_list не отображена на контракт: отдельный метод с TODO (подробнее — report.md)
- операция subscription_fetch не отображена на контракт: отдельный метод с TODO (подробнее — report.md)
- операция subscription_disable не отображена на контракт: отдельный метод с TODO (подробнее — report.md)
- операция subscription_enable не отображена на контракт: отдельный метод с TODO (подробнее — report.md)
- операция subscription_manageLink не отображена на контракт: отдельный метод с TODO (подробнее — report.md)
- операция subscription_manageEmail не отображена на контракт: отдельный метод с TODO (подробнее — report.md)
- операция product_create не отображена на контракт: отдельный метод с TODO (подробнее — report.md)
- операция product_list не отображена на контракт: отдельный метод с TODO (подробнее — report.md)
- операция product_fetch не отображена на контракт: отдельный метод с TODO (подробнее — report.md)
- операция product_update не отображена на контракт: отдельный метод с TODO (подробнее — report.md)
- операция product_delete не отображена на контракт: отдельный метод с TODO (подробнее — report.md)
- операция page_create не отображена на контракт: отдельный метод с TODO (подробнее — report.md)
- операция page_list не отображена на контракт: отдельный метод с TODO (подробнее — report.md)
- операция page_fetch не отображена на контракт: отдельный метод с TODO (подробнее — report.md)
- операция page_update не отображена на контракт: отдельный метод с TODO (подробнее — report.md)
- операция page_checkSlugAvailability не отображена на контракт: отдельный метод с TODO (подробнее — report.md)
- операция page_addProducts не отображена на контракт: отдельный метод с TODO (подробнее — report.md)
- операция paymentRequest_update не отображена на контракт: отдельный метод с TODO (подробнее — report.md)
- операция paymentRequest_notify: роль cancel с уверенностью ниже порога (эвристика 0.54) (подробнее — report.md)
- операция paymentRequest_finalize: роль cancel с уверенностью ниже порога (эвристика 0.54) (подробнее — report.md)
- операция paymentRequest_archive: роль cancel с уверенностью ниже порога (эвристика 0.54) (подробнее — report.md)
- операция settlements_fetch не отображена на контракт: отдельный метод с TODO (подробнее — report.md)
- операция put_transferrecipient_code не отображена на контракт: отдельный метод с TODO (подробнее — report.md)
- операция delete_transferrecipient_code: роль cancel с уверенностью ниже порога (эвристика 0.57) (подробнее — report.md)
- операция bulkCharge_charges: роль fetch_status с уверенностью ниже порога (эвристика 0.58) (подробнее — report.md)
- операция integration_updatePaymentSessionTimeout не отображена на контракт: отдельный метод с TODO (подробнее — report.md)
- операция refund_list не отображена на контракт: отдельный метод с TODO (подробнее — report.md)
- операция refund_fetch не отображена на контракт: отдельный метод с TODO (подробнее — report.md)
- операция dispute_list не отображена на контракт: отдельный метод с TODO (подробнее — report.md)
- операция dispute_fetch не отображена на контракт: отдельный метод с TODO (подробнее — report.md)
- операция dispute_update не отображена на контракт: отдельный метод с TODO (подробнее — report.md)
- операция dispute_uploadUrl не отображена на контракт: отдельный метод с TODO (подробнее — report.md)
- операция dispute_download не отображена на контракт: отдельный метод с TODO (подробнее — report.md)
- операция dispute_resolve не отображена на контракт: отдельный метод с TODO (подробнее — report.md)
- операция dispute_evidence не отображена на контракт: отдельный метод с TODO (подробнее — report.md)
- операция verification_bvnMatch не отображена на контракт: отдельный метод с TODO (подробнее — report.md)
- операция verification_resolveBvn не отображена на контракт: отдельный метод с TODO (подробнее — report.md)
- операция verification_resolveCardBin не отображена на контракт: отдельный метод с TODO (подробнее — report.md)
- операция verification_listCountries не отображена на контракт: отдельный метод с TODO (подробнее — report.md)
- операция verification_fetchBanks не отображена на контракт: отдельный метод с TODO (подробнее — report.md)
- операция verification_avs не отображена на контракт: отдельный метод с TODO (подробнее — report.md)
- песочница не выведена: BASE_URL по умолчанию — https://api.paystack.co (подробнее — report.md)
