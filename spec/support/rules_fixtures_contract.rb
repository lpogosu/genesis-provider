# frozen_string_literal: true

# Контракт Provider::BaseService для фикстур справочников: методы, хелперы и
# раздел platform. Отдельный файл, потому что модуль RulesFixtures уже на
# пределе длины; лямбды DEFAULTS ленивые, поэтому порядок загрузки файлов
# поддержки не важен.
module RulesFixtures
  CONTRACT_METHODS = {
    'check_conditions' => {
      'params' => [{ 'name' => 'operation' }, { 'name' => 'request_method' }],
      'calls_super' => true
    },
    'create_request' => {
      'params' => [{ 'name' => 'operation' },
                   { 'name' => 'request_method', 'default' => "'create'" }],
      'roles' => %w[create_payout create_deposit]
    },
    'process_callback' => { 'params' => [{ 'name' => 'payload' }], 'roles' => ['webhook'] },
    'fetch_status' => { 'params' => [{ 'name' => 'operation' }], 'roles' => ['fetch_status'] }
  }.freeze

  CONTRACT_HELPERS = {
    'success' => {}, 'client' => {}, 'auth_headers' => {}, 'failure' => { 'params' => [{ 'name' => 'code' }, { 'name' => 'i18n_key' }] },
    'approve_operation' => { 'params' => [{ 'name' => 'operation' }], 'status' => 'approved' }, 'reject_operation' => { 'params' => [{ 'name' => 'operation' }], 'status' => 'rejected' }
  }.freeze

  # Минимум раздела platform: по одному выражению каждого вида, чтобы
  # загрузчик и генератор были согласны о форме записи.
  CONTRACT_PLATFORM = {
    'source' => 'допущение', 'callback' => { 'body' => 'payload[:body]', 'headers' => 'payload[:headers]' }, 'result' => { 'success_predicate' => 'success?' },
    'accessors' => { 'amount' => 'operation.amount', 'currency' => 'operation.currency', 'external_id' => 'operation.id', 'provider_operation_id' => 'operation.provider_operation_id' },
    'lookup' => { 'provider_operation_id' => 'Operation.find_by(provider_operation_id: %{value})' }, 'writers' => { 'provider_operation_id' => 'operation.update(provider_operation_id: %{value})' }
  }.freeze
end
