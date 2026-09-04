# frozen_string_literal: true

# The dictionaries the tool actually ships with. Everything else under
# spec/unit/specgen/rules exercises the loader on hand-made fixtures; this
# file is the acceptance test for the data in rules/ itself, and it is the
# reason a bad synonym cannot reach a release: the suite goes red first.
RSpec.describe 'the shipped dictionaries' do
  subject(:rules) { SpecGen::Rules.load }

  it 'loads without a single complaint' do
    expect { SpecGen::Rules.load }.not_to raise_error
  end

  describe 'roles' do
    it 'covers every role of the closed vocabulary' do
      expect(rules.roles.roles).to eq(SpecGen::IR::Roles::FIELD)
    end

    it 'reads both the English and the transliterated spelling of a bank code' do
      expect(rules.roles.role_for('bic')).to eq(:bank_code)
      expect(rules.roles.role_for('bik')).to eq(:bank_code)
      expect(rules.roles.role_for('BIK')).to eq(:bank_code)
    end

    it 'tells our identifier at the provider from the provider own one' do
      expect(rules.roles.role_for('external_id')).to eq(:external_id)
      expect(rules.roles.role_for('payout_id')).to eq(:provider_operation_id)
    end
  end

  describe 'statuses' do
    it 'maps the canon of the case description' do
      expect(rules.statuses.internal_for('pending')).to eq(:in_progress)
      expect(rules.statuses.internal_for('processing')).to eq(:in_progress)
      expect(rules.statuses.internal_for('completed')).to eq(:approved)
      expect(rules.statuses.internal_for('failed')).to eq(:rejected)
      expect(rules.statuses.internal_for('cancelled')).to eq(:rejected)
    end

    it 'maps the synonyms other providers use' do
      expect(rules.statuses.internal_for('succeeded')).to eq(:approved)
      expect(rules.statuses.internal_for('declined')).to eq(:rejected)
      expect(rules.statuses.internal_for('queued')).to eq(:in_progress)
    end
  end

  describe 'currencies' do
    it 'carries the whole of ISO 4217, not a handful of codes' do
      expect(rules.currencies.codes.size).to be >= 150
    end

    it 'knows the exponents that are not two' do
      expect(rules.currencies.exponent('RUB')).to eq(2)
      expect(rules.currencies.exponent('JPY')).to eq(0)
      expect(rules.currencies.exponent('ISK')).to eq(0)
      expect(rules.currencies.exponent('KWD')).to eq(3)
      expect(rules.currencies.exponent('CLF')).to eq(4)
    end
  end

  describe 'signatures' do
    it 'ships the Standard Webhooks profile as the default' do
      expect(rules.signatures.default)
        .to include(profile: :standard_webhooks, algorithm: :hmac_sha256, encoding: :base64,
                    payload: :id_timestamp_body)
    end

    it 'ships a raw-body hex profile as well' do
      raw = rules.signatures.names.map { |name| rules.signatures.profile(name) }
      expect(raw).to include(hash_including(payload: :raw_body, encoding: :hex))
    end
  end

  describe 'idempotency' do
    it 'knows the header names the industry uses' do
      expect(rules.idempotency).to be_alias('Idempotency-Key')
      expect(rules.idempotency).to be_alias('X-Idempotency-Key')
      expect(rules.idempotency).to be_alias('X-Request-Id')
      expect(rules.idempotency).to be_alias('X-Unique-Transaction-Id')
    end

    it 'derives the key deterministically' do
      expect(rules.idempotency.default_strategy).to eq(:uuid_v5)
      expect(rules.idempotency.conflict_status).to eq(409)
    end
  end

  describe 'auth' do
    {
      api_key: { 'type' => 'apiKey', 'in' => 'header', 'name' => 'X-API-Key' },
      bearer: { 'type' => 'http', 'scheme' => 'bearer' },
      basic: { 'type' => 'http', 'scheme' => 'basic' },
      oauth2: { 'type' => 'oauth2', 'flows' => { 'clientCredentials' => {} } }
    }.each do |expected, declaration|
      it "recognises #{expected}" do
        expect(rules.auth.scheme_for(declaration)&.fetch(:ir_type)).to eq(expected)
      end
    end
  end

  describe 'the contract' do
    it 'serves every operation role the contract covers' do
      SpecGen::IR::Roles::CONTRACT.each do |role|
        expect(rules.contract.method_for(role)).not_to be_nil, "no method serves #{role}"
      end
    end

    it 'names the four methods and the six helpers' do
      expect(rules.contract.method_names)
        .to include('check_conditions', 'create_request', 'process_callback', 'fetch_status')
      SpecGen::Rules::ContractBook::HELPERS.each do |helper|
        expect(rules.contract.helper(helper)).not_to be_nil, "no name for helper #{helper}"
      end
    end

    it 'states that the contract is an assumption' do
      expect(rules.contract.assumption).not_to be_nil
      expect(rules.contract.amount_unit).to eq(:major)
    end
  end
end
