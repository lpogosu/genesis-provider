# frozen_string_literal: true

# Справочники, с которыми инструмент действительно поставляется. Всё
# остальное в spec/unit/specgen/rules гоняет загрузчик на самодельных
# фикстурах; этот файл — приёмочный тест самих данных из rules/ и причина,
# по которой плохой синоним не может попасть в релиз: сначала краснеет прогон.
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

    it 'reads the unit words of the shipped spec and of the industry, as confirmation only' do
      expect(rules.currencies.unit_hint('Сумма в копейках')).to eq([:minor, 'копейках'])
      expect(rules.currencies.unit_hint('Минимальная сумма — 1000 RUB (100000 коп.)')).to eq([:minor, 'коп.'])
      expect(rules.currencies.unit_hint('Amount in minor units')).to eq([:minor, 'minor units'])
      expect(rules.currencies.unit_hint('Amount in roubles')).to eq([:major, 'roubles'])
      expect(rules.currencies.unit_hint('Percents of the amount')).to be_nil
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

  describe 'operations' do
    it 'describes every role the matcher can assign' do
      expect(rules.operations.roles).to eq(SpecGen::IR::Roles::OPERATION - [:unmapped])
    end

    it 'weights the operation name above the path, and the path above the tag' do
      book = rules.operations

      expect(book.weight(:operation_id)).to be > book.weight(:path_tail)
      expect(book.weight(:path_tail)).to be > book.weight(:tag)
      expect(book.scoring(:floor)).to be >= book.weight(:operation_id)
    end
  end

  describe 'conditions' do
    {
      'БИК банка (обязателен для type=sbp)' => %w[type sbp],
      'Номер карты (обязателен для type=card)' => %w[type card],
      'Required when recipient_type is card' => %w[recipient_type card],
      'Only for type = sbp' => %w[type sbp]
    }.each do |sentence, (field, value)|
      it "reads #{sentence.inspect} as #{field}=#{value}" do
        _, found = rules.conditions.match(sentence)

        expect(found).not_to be_nil, 'no pattern matched'
        expect([found[:field], found[:value]]).to eq([field, value])
      end
    end

    it 'keeps a condition read from prose below the matcher threshold' do
      expect(rules.conditions.hint_confidence).to be < 0.6
    end

    it 'reads nothing out of a sentence that only describes a field' do
      expect(rules.conditions.match('Телефон получателя (11 цифр, начинается с 7)')).to be_nil
    end
  end

  describe 'errors' do
    it 'treats credentials as an alert, the provider balance as an escalation and the rest of 4xx as a rejection' do
      expect(rules.errors.action_for_status(401)).to eq([:alert, '401'])
      expect(rules.errors.action_for_status(402)).to eq([:escalate, '402'])
      expect(rules.errors.action_for_status(422)).to eq([:reject, '4xx'])
      expect(rules.errors.action_for_status(429)).to eq([:retry_backoff, '429'])
      expect(rules.errors.action_for_status(500)).to eq([:retry_backoff, '5xx'])
    end

    it 'never hands out dedup: that is derived from the response schemas' do
      expect(rules.errors.action_for_status(409)).to eq([:reject, '409'])
    end

    it 'reads every code of the shipped spec, with rate_limit winning over limit_exceeded' do
      actions = %w[validation_error insufficient_balance recipient_not_found bank_unavailable
                   amount_limit_exceeded rate_limit_exceeded internal_error unauthorized not_found
                   invalid_status].to_h { |code| [code, rules.errors.rule_for_code(code)&.action] }

      expect(actions).to eq('validation_error' => :reject, 'insufficient_balance' => :escalate,
                            'recipient_not_found' => :reject, 'bank_unavailable' => :retry_backoff,
                            'amount_limit_exceeded' => :escalate, 'rate_limit_exceeded' => :retry_backoff,
                            'internal_error' => :retry_backoff, 'unauthorized' => :alert,
                            'not_found' => :reject, 'invalid_status' => :reject)
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
