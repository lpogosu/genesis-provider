# frozen_string_literal: true

require 'tmpdir'
require 'psych'

# Builds a valid set of dictionaries in a temporary directory, so an example
# can break exactly one thing and assert on the message. The defaults are
# deliberately minimal: they satisfy every rule the loader enforces and
# nothing more, which keeps each example about the one field it changes.
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
        'ambiguous' => { 'on_hold' => 'a freeze at some providers, a manual review at others' } }
    },
    'currencies.yml' => lambda {
      { 'version' => 1, 'default_exponent' => 2,
        'currencies' => { 'RUB' => { 'exponent' => 2, 'name' => 'Russian Ruble' },
                          'JPY' => { 'exponent' => 0, 'name' => 'Yen' },
                          'KWD' => { 'exponent' => 3, 'name' => 'Kuwaiti Dinar' } } }
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
    'contract.yml' => lambda {
      { 'version' => 1, 'base_class' => 'Provider::BaseService',
        'assumption' => 'Modelled from the case description; the real class was never handed out.',
        'methods' => CONTRACT_METHODS, 'helpers' => CONTRACT_HELPERS,
        'internal_statuses' => %w[in_progress approved rejected],
        'request_method' => { 'semantics' => 'logical action type, not an HTTP verb',
                              'known_values' => %w[create status] },
        'operation' => { 'amount_unit' => 'major' } }
    }
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

  # Writes the dictionaries into a temporary directory and yields its path.
  #
  # @param patch [Hash] file name => replacement. A Hash replaces the whole
  #   document, a String is written verbatim (for syntax and duplicate-key
  #   examples), and :delete leaves the file out entirely.
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

  # Loads a patched set of dictionaries.
  # @return [SpecGen::Rules::Registry]
  def load_rules(patch = {})
    with_rules(patch) { |dir| SpecGen::Rules.load(dir) }
  end

  # @return [String] the message of the RulesError a patched set raises
  def rules_error(patch = {})
    load_rules(patch)
    raise 'expected the dictionaries to be rejected'
  rescue SpecGen::RulesError => e
    e.message
  end

  # @param document [Hash] a default document, deep-copied for patching
  def rule(name)
    Psych.safe_load(Psych.dump(DEFAULTS.fetch(name).call))
  end

  private

  def write_rule(path, content)
    text = content.is_a?(String) ? content : Psych.dump(content)
    File.binwrite(path, text.gsub("\r\n", "\n"))
  end
end
