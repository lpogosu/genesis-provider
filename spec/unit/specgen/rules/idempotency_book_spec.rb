# frozen_string_literal: true

RSpec.describe SpecGen::Rules::IdempotencyBook do
  include RulesFixtures

  def idempotency(patch = {})
    load_rules('idempotency.yml' => rule('idempotency.yml').merge(patch)).idempotency
  end

  describe 'the header' do
    it 'recognises every alias, however the provider spells it' do
      book = idempotency

      expect(book).to be_alias('Idempotency-Key')
      expect(book).to be_alias('x_request_id')
      expect(book).not_to be_alias('Authorization')
    end

    it 'keeps the canonical name the generated service sends' do
      expect(idempotency.canonical_header).to eq('Idempotency-Key')
    end

    it 'requires the canonical name to be one of the aliases' do
      expect(rules_error('idempotency.yml' => idempotency_rule('canonical_header' => 'X-Key')))
        .to include('"X-Key" is missing from the aliases')
    end

    it 'refuses the same alias twice under two spellings' do
      patch = idempotency_rule
      patch['aliases'] << 'idempotency key'

      expect(rules_error('idempotency.yml' => patch)).to include('repeats "Idempotency-Key"')
    end
  end

  describe 'how the key is produced' do
    it 'reads the strategy and the fixed namespace' do
      book = idempotency

      expect(book.default_strategy).to eq(:uuid_v5)
      expect(book.namespace).to eq('6ba7b810-9dad-11d1-80b4-00c04fd430c8')
      expect(book.conflict_status).to eq(409)
      expect(book).to be_send_when_optional
    end

    it 'refuses a strategy IR does not know' do
      expect(rules_error('idempotency.yml' => idempotency_rule('default_strategy' => 'random')))
        .to include('unknown idempotency strategy "random"')
    end

    it 'refuses a namespace that is not a UUID, because the key must be reproducible' do
      expect(rules_error('idempotency.yml' => idempotency_rule('uuid_v5_namespace' => 'nova')))
        .to include('must be a UUID')
    end

    it 'refuses a conflict status that is not an HTTP status' do
      expect(rules_error('idempotency.yml' => idempotency_rule('conflict_status' => 42)))
        .to include('within 100..599')
    end
  end

  def idempotency_rule(patch = {})
    rule('idempotency.yml').merge(patch)
  end
end
