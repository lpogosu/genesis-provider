# frozen_string_literal: true

require 'tmpdir'
require 'psych'

# Собирает годный набор справочников во временном каталоге, чтобы пример мог
# сломать ровно одну вещь и проверить сообщение. Значения по умолчанию
# сознательно минимальны: они удовлетворяют каждому правилу загрузчика и
# ничему больше, поэтому каждый пример остаётся про то одно поле, которое он
# меняет.
module RulesFixtures
  DEFAULTS = {
    'roles.yml' => lambda {
      { 'version' => 1,
        'roles' => SpecGen::IR::Roles::FIELD.to_h { |role| [role.to_s, { 'names' => [role.to_s] }] } }
    },
    'statuses.yml' => lambda {
      { 'version' => 1,
        'canonical' => { 'pending' => 'in_progress', 'completed' => 'approved',
                         'failed' => 'rejected' },
        'synonyms' => { 'approved' => ['paid'], 'rejected' => ['declined'],
                        'in_progress' => ['queued'] },
        'ambiguous' => { 'on_hold' => 'у одних провайдеров заморозка, у других ручная проверка' } }
    },
    'currencies.yml' => lambda {
      { 'version' => 1, 'default_exponent' => 2,
        'currencies' => { 'RUB' => { 'exponent' => 2, 'name' => 'Russian Ruble' },
                          'JPY' => { 'exponent' => 0, 'name' => 'Yen' },
                          'KWD' => { 'exponent' => 3, 'name' => 'Kuwaiti Dinar' } },
        'unit_words' => { 'minor' => ['(?i)(?<![[:alpha:]])копе[йе]к[[:alpha:]]*', '(?i)\bcents?\b'],
                          'major' => ['(?i)(?<![[:alpha:]])в рублях', '(?i)\brubles?\b'] } }
    },
    'signatures.yml' => lambda {
      { 'version' => 1,
        'profiles' => {
          'standard_webhooks' => {
            'profile' => 'standard_webhooks', 'header' => 'webhook-signature',
            'id_header' => 'webhook-id', 'timestamp_header' => 'webhook-timestamp',
            'algorithm' => 'hmac_sha256', 'encoding' => 'base64',
            'payload' => 'id_timestamp_body', 'tolerance' => 300,
            'value_prefix' => 'v1,', 'secret_key' => 'webhook_secret'
          },
          'raw_hex' => {
            'profile' => 'custom', 'header' => 'X-Signature', 'algorithm' => 'hmac_sha256',
            'encoding' => 'hex', 'payload' => 'raw_body', 'secret_key' => 'webhook_secret'
          }
        },
        'header_names' => ['x-signature'] }
    },
    'idempotency.yml' => lambda {
      { 'version' => 1, 'canonical_header' => 'Idempotency-Key',
        'aliases' => %w[Idempotency-Key X-Idempotency-Key X-Request-Id],
        'default_strategy' => 'uuid_v5',
        'uuid_v5_namespace' => '6ba7b810-9dad-11d1-80b4-00c04fd430c8',
        'conflict_status' => 409, 'send_when_optional' => true }
    },
    'auth.yml' => lambda {
      { 'version' => 1,
        'schemes' => {
          'api_key_header' => {
            'match' => { 'type' => 'apiKey', 'in' => 'header' }, 'ir_type' => 'api_key',
            'location' => 'header', 'credential_keys' => ['api_key'],
            'headers' => { '%{param_name}' => 'provider.credentials[:api_key]' }
          },
          'bearer' => {
            'match' => { 'type' => 'http', 'scheme' => 'bearer' }, 'ir_type' => 'bearer',
            'location' => 'header', 'credential_keys' => ['access_token'],
            'headers' => { 'Authorization' => 'bearer(provider.credentials[:access_token])' }
          }
        } }
    },
    'operations.yml' => lambda {
      { 'version' => 1,
        'weights' => { 'operation_id' => 5, 'path_tail' => 3, 'unsecured' => 4,
                       'path_resource' => 2, 'http_method' => 2, 'tag' => 1,
                       'request_body' => 1 },
        'scoring' => { 'partial' => 0.5, 'minimum' => 0.4, 'margin' => 0.1,
                       'ceiling' => 0.95, 'floor' => 5 },
        'roles' => OPERATION_ROLES }
    },
    'conditions.yml' => lambda {
      { 'version' => 1,
        'required_when' => { 'confidence' => 0.5, 'patterns' => [HINT_PATTERN] } }
    },
    'contract.yml' => lambda {
      { 'version' => 1, 'base_class' => 'Provider::BaseService',
        'assumption' => 'Восстановлен по описанию кейса; реального класса нам не выдали.',
        'methods' => CONTRACT_METHODS, 'helpers' => CONTRACT_HELPERS,
        'internal_statuses' => %w[in_progress approved rejected],
        'request_method' => { 'semantics' => 'логический тип действия, а не HTTP-метод',
                              'known_values' => %w[create status] },
        'operation' => { 'amount_unit' => 'major' } }
    }
  }.freeze

  # Достаточно, чтобы доказать: загрузчик и анализатор согласны о форме
  # записи. Шаблоны, которые идут в поставке, живут в rules/conditions.yml.
  HINT_PATTERN = {
    'name' => 'equals', 'kind' => 'equals',
    'pattern' => '(?i)required[^.;]{0,40}?(?<field>[a-z_][a-z0-9_]*)\s*(?:=|\bis\b)\s*(?<value>[a-z0-9_]+)'
  }.freeze

  # По строке на роль: загрузчику достаточно, чтобы каждый список был
  # непустым, а на файлы тестов не распространяется ограничение длины строки.
  OPERATION_ROLES = {
    'create_payout' => { 'verbs' => %w[create new], 'nouns' => %w[payout payouts], 'resources' => %w[payout payouts], 'tail' => %w[payouts], 'http_methods' => %w[post], 'tags' => %w[payouts], 'request_body' => true },
    'create_deposit' => { 'verbs' => %w[create new], 'nouns' => %w[deposit deposits], 'resources' => %w[deposit deposits], 'tail' => %w[deposits], 'http_methods' => %w[post], 'request_body' => true },
    'fetch_status' => { 'verbs' => %w[get fetch check], 'nouns' => %w[status state], 'resources' => %w[payout payouts deposits], 'tail' => %w[status], 'tail_parameter' => true, 'http_methods' => %w[get], 'tags' => %w[payouts], 'request_body' => false },
    'cancel' => { 'verbs' => %w[cancel void], 'nouns' => %w[cancel cancellation], 'resources' => %w[payout payouts], 'tail' => %w[cancel], 'http_methods' => %w[post delete], 'request_body' => false },
    'balance' => { 'verbs' => %w[get check], 'nouns' => %w[balance balances], 'resources' => %w[balance], 'tail' => %w[balance], 'http_methods' => %w[get], 'request_body' => false },
    'webhook' => { 'verbs' => %w[notify receive], 'nouns' => %w[webhook callback], 'resources' => %w[webhooks callbacks], 'tail' => %w[webhooks callbacks], 'http_methods' => %w[post], 'tags' => %w[webhooks], 'request_body' => true, 'unsecured' => true }
  }.freeze

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
    'success' => {}, 'client' => {}, 'auth_headers' => {},
    'failure' => { 'params' => [{ 'name' => 'code' }, { 'name' => 'i18n_key' }] },
    'approve_operation' => { 'params' => [{ 'name' => 'operation' }] },
    'reject_operation' => { 'params' => [{ 'name' => 'operation' }] }
  }.freeze

  # Пишет справочники во временный каталог и отдаёт его путь блоку.
  #
  # @param patch [Hash] имя файла => замена. Hash заменяет весь документ,
  #   String пишется дословно (для примеров с битым синтаксисом и
  #   продублированным ключом), а :delete вообще не создаёт файл.
  # @yieldparam dir [String]
  def with_rules(patch = {})
    Dir.mktmpdir('specgen-rules') do |dir|
      DEFAULTS.each do |name, builder|
        replacement = patch.fetch(name, :keep)
        next if replacement == :delete

        write_rule(File.join(dir, name), replacement == :keep ? builder.call : replacement)
      end
      yield dir
    end
  end

  # Загружает набор справочников с наложенными изменениями.
  # @return [SpecGen::Rules::Registry]
  def load_rules(patch = {})
    with_rules(patch) { |dir| SpecGen::Rules.load(dir) }
  end

  # @return [String] сообщение RulesError, которую поднимает такой набор
  def rules_error(patch = {})
    load_rules(patch)
    raise 'expected the dictionaries to be rejected'
  rescue SpecGen::RulesError => e
    e.message
  end

  # @param document [Hash] документ по умолчанию, скопированный для правок
  def rule(name)
    Psych.safe_load(Psych.dump(DEFAULTS.fetch(name).call))
  end

  private

  def write_rule(path, content)
    text = content.is_a?(String) ? content : Psych.dump(content)
    File.binwrite(path, text.gsub("\r\n", "\n"))
  end
end
