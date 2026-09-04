# frozen_string_literal: true

RSpec.describe SpecGen::Rules::Registry do
  include RulesFixtures

  describe 'a healthy set of dictionaries' do
    it 'loads every book' do
      registry = load_rules

      expect(registry.roles).to be_a(SpecGen::Rules::RolesBook)
      expect(registry.statuses).to be_a(SpecGen::Rules::StatusesBook)
      expect(registry.currencies).to be_a(SpecGen::Rules::CurrenciesBook)
      expect(registry.signatures).to be_a(SpecGen::Rules::SignaturesBook)
      expect(registry.idempotency).to be_a(SpecGen::Rules::IdempotencyBook)
      expect(registry.auth).to be_a(SpecGen::Rules::AuthBook)
      expect(registry.contract).to be_a(SpecGen::Rules::ContractBook)
    end

    it 'is frozen, so nothing can edit a dictionary at runtime' do
      expect(load_rules).to be_frozen
    end
  end

  describe 'file level problems' do
    it 'names a dictionary that is missing' do
      expect(rules_error('roles.yml' => :delete))
        .to include('roles.yml').and include('not found')
    end

    it 'reports a YAML syntax error with the line and column' do
      expect(rules_error('statuses.yml' => "version: 1\ncanonical: [\n"))
        .to include('statuses.yml').and include('line').and include('YAML syntax error')
    end

    it 'refuses a key declared twice instead of silently keeping the last' do
      duplicated = <<~YAML
        version: 1
        default_exponent: 2
        currencies:
          RUB: { exponent: 2, name: "Russian Ruble" }
          RUB: { exponent: 0, name: "Russian Ruble" }
      YAML

      expect(rules_error('currencies.yml' => duplicated))
        .to include('$.currencies.RUB').and include('more than once')
    end

    it 'rejects an unsupported dictionary version' do
      expect(rules_error('roles.yml' => rule('roles.yml').merge('version' => 2)))
        .to include('$.version').and include('version must be 1')
    end

    it 'rejects a document that is not an object' do
      expect(rules_error('auth.yml' => "- one\n- two\n")).to include('non-empty object')
    end
  end

  describe 'reporting' do
    it 'lists every problem from every dictionary in one error' do
      message = rules_error(
        'roles.yml' => rule('roles.yml').merge('version' => 9),
        'currencies.yml' => rule('currencies.yml').merge('default_exponent' => 'two')
      )

      expect(message).to include('2 problems').and include('roles.yml').and include('currencies.yml')
    end

    it 'says how many problems it found' do
      expect(rules_error('roles.yml' => rule('roles.yml').merge('version' => 9)))
        .to start_with('1 problem in the rules dictionaries:')
    end
  end

  describe 'names that two dictionaries claim' do
    it 'refuses an idempotency alias that is also a role synonym' do
      roles = rule('roles.yml')
      roles['roles']['external_id']['names'] << 'X-Request-Id'

      expect(rules_error('roles.yml' => roles))
        .to include('idempotency.yml').and include('claimed by role external_id')
    end

    it 'allows an alias that maps to the idempotency_key role itself' do
      roles = rule('roles.yml')
      roles['roles']['idempotency_key']['names'] << 'X-Idempotency-Key'

      expect { load_rules('roles.yml' => roles) }.not_to raise_error
    end

    it 'refuses a signature header that is also a role synonym' do
      roles = rule('roles.yml')
      roles['roles']['error_code']['names'] << 'x_signature'

      expect(rules_error('roles.yml' => roles))
        .to include('signatures.yml').and include('claimed by role error_code')
    end
  end
end
