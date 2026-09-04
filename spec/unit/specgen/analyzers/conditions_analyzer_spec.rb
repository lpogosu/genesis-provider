# frozen_string_literal: true

RSpec.describe SpecGen::Analyzers::ConditionsAnalyzer do
  include Fixtures
  include RulesFixtures

  # The fixture dictionaries: one synonym per role, Retry-After as the pause
  # header, Idempotency-Key as an alias, one status-restriction pattern
  # ("only in statuses ..." / "только в статусах ...").
  let(:rules) { load_rules }

  def analyze(paths, components = {})
    data = { 'openapi' => '3.0.3', 'paths' => paths, 'components' => components }
    document = SpecGen::SpecLoader::Document.new(file: 'provider_api.yaml', version: '3.0.3',
                                                 family: :oas30, raw: data, data: data)
    described_class.call(document: document, profile: SpecGen::IR::ProviderProfile.new,
                         rules: rules)
  end

  def request(properties)
    schema = { 'type' => 'object', 'properties' => properties }
    { 'required' => true, 'content' => { 'application/json' => { 'schema' => schema } } }
  end

  # Positional `extra`, not keywords: a braceless string-keyed hash in the
  # first position would otherwise be taken as keyword arguments.
  def create(properties, extra = {})
    { 'operationId' => 'createPayout', 'requestBody' => request(properties),
      'responses' => { '201' => { 'description' => 'ok' } } }.merge(extra)
  end

  def conditions_of(profile, kind)
    profile.conditions.select { |condition| condition.kind == kind }
  end

  def only(profile, kind)
    found = conditions_of(profile, kind)
    expect(found.size).to eq(1), "expected one #{kind}, got #{found.size}"
    found.first
  end

  describe 'conditions of an operation' do
    it 'reads Retry-After on a response as the pause before a retry, remembering the status' do
      responses = { '201' => {}, '429' => { 'headers' => { 'Retry-After' => { 'schema' => { 'type' => 'integer' } } } } }
      profile = analyze('/payouts' => { 'post' => create({}, 'responses' => responses) })
      condition = only(profile, :retry_after)

      expect(condition).to have_attributes(operation: 'createPayout', field: nil,
                                           json_path: "$.paths['/payouts'].post.responses['429']")
      expect(condition.value).to have_attributes(value: 429, source: :structural)
      expect(condition.value.evidence).to eq('ответ 429 объявляет заголовок Retry-After — пауза до повтора')
      expect(only(profile, :rate_limited).value.value).to eq(429)
    end

    it 'reads an optional idempotency header as a condition the service must still honour' do
      header = { 'name' => 'Idempotency-Key', 'in' => 'header', 'required' => false, 'schema' => { 'type' => 'string' } }
      profile = analyze('/payouts' => { 'post' => create({}, 'parameters' => [header]) })
      condition = only(profile, :idempotency_optional)

      expect(condition.value.value).to eq('Idempotency-Key')
      expect(condition.json_path).to eq("$.paths['/payouts'].post.parameters[0]")
    end

    it 'records nothing for a required idempotency header' do
      header = { 'name' => 'Idempotency-Key', 'in' => 'header', 'required' => true, 'schema' => { 'type' => 'string' } }
      profile = analyze('/payouts' => { 'post' => create({}, 'parameters' => [header]) })

      expect(conditions_of(profile, :idempotency_optional)).to be_empty
    end
  end

  describe 'the cancellation restriction' do
    let(:status_component) do
      { 'Payout' => { 'type' => 'object', 'properties' => { 'status' => { 'type' => 'string',
                                                                          'enum' => %w[pending processing completed] } } } }
    end

    def cancel(description)
      { '/payouts/{id}/cancel' => { 'post' => { 'operationId' => 'cancelPayout', 'description' => description,
                                                'responses' => { '200' => {} } } } }
    end

    it 'reads the statuses the description names, as a heuristic with the dictionary confidence' do
      profile = analyze(cancel('Отмена возможна только в статусах pending и processing.'),
                        { 'schemas' => status_component })
      condition = only(profile, :cancel_status_restriction)

      expect(condition).to have_attributes(operation: 'cancelPayout',
                                           json_path: "$.paths['/payouts/{id}/cancel'].post.description")
      expect(condition.value).to have_attributes(value: %w[pending processing], source: :heuristic, confidence: 0.6)
      expect(condition.value.evidence).to include('only_in_statuses', 'pending, processing', 'только в статусах')
      expect(profile.warnings).to be_empty
    end

    it 'keeps the spelling of the enum and reads English prose the same way' do
      profile = analyze(cancel('Allowed only in statuses PENDING or processing'), { 'schemas' => status_component })

      expect(only(profile, :cancel_status_restriction).value.value).to eq(%w[pending processing])
    end

    it 'derives nothing when the sentence names no status the spec declares, and says so' do
      profile = analyze(cancel('Отмена возможна только в статусах new и waiting'), { 'schemas' => status_component })

      expect(conditions_of(profile, :cancel_status_restriction)).to be_empty
      expect(profile.warnings.first).to have_attributes(code: :condition_unclear, severity: :warning)
      expect(profile.warnings.first.message).to include('cancelPayout', 'только в статусах new и waiting')
    end

    it 'ignores a description with no restriction in it' do
      profile = analyze(cancel('Отменяет выплату.'), { 'schemas' => status_component })

      expect(profile.conditions).to be_empty
      expect(profile.warnings).to be_empty
    end

    it 'looks for the restriction only on the cancel operation' do
      paths = { '/payouts' => { 'post' => create({}, 'description' => 'Только в статусах pending') } }

      expect(analyze(paths, { 'schemas' => status_component }).conditions).to be_empty
    end
  end

  describe 'constraints of request fields with a role' do
    let(:profile) do
      recipient = { 'type' => 'object', 'properties' => {
        'recipient_type' => { 'type' => 'string', 'enum' => %w[sbp card] },
        'recipient_phone' => { 'type' => 'string', 'pattern' => '^7\d{10}$' },
        'note' => { 'type' => 'string', 'maxLength' => 10 }
      } }
      analyze('/payouts' => { 'post' => create(
        'amount' => { 'type' => 'integer', 'minimum' => 100_000, 'maximum' => 50_000_000 },
        'currency' => { 'type' => 'string', 'enum' => ['RUB'] },
        'external_id' => { 'type' => 'string', 'maxLength' => 64 },
        'recipient' => recipient
      ) })
    end

    it 'reads the amount bounds as they are written, leaving the unit conversion to the generator' do
      minimum = only(profile, :min_amount)

      expect(minimum).to have_attributes(field: 'amount', operation: 'createPayout')
      expect(minimum.value.value).to eq(100_000)
      expect(minimum.value.evidence).to eq('minimum: 100000 у поля `amount` (роль amount по синониму rules/roles.yml)')
      expect(only(profile, :max_amount).value.value).to eq(50_000_000)
    end

    it 'reads length, pattern and enum of role fields, nested objects included' do
      expect(only(profile, :field_max_length)).to have_attributes(field: 'external_id')
      expect(only(profile, :field_max_length).value.value).to eq(64)
      expect(only(profile, :field_pattern)).to have_attributes(field: 'recipient_phone')
      expect(only(profile, :field_pattern).value.value).to eq('^7\d{10}$')
      expect(conditions_of(profile, :field_enum).map(&:field)).to eq(%w[currency recipient_type])
      expect(conditions_of(profile, :field_enum).map { |c| c.value.value }).to eq([['RUB'], %w[sbp card]])
    end

    it 'leaves fields without a role to the matchers' do
      expect(profile.conditions.map(&:field)).not_to include('note')
    end

    it 'keeps the order of the spec' do
      expect(profile.conditions.map(&:kind))
        .to eq(%i[min_amount max_amount field_enum field_max_length field_enum field_pattern])
    end
  end

  describe 'what is left alone' do
    it 'reads nothing from an inbound webhook or from response schemas' do
      webhook = { 'operationId' => 'payoutWebhook', 'security' => [],
                  'requestBody' => request('amount' => { 'type' => 'integer', 'minimum' => 1 }),
                  'responses' => { '200' => {}, '429' => {} } }
      response = { 'content' => { 'application/json' => { 'schema' => { 'type' => 'object', 'properties' => {
        'amount' => { 'type' => 'integer', 'minimum' => 1 }
      } } } } }
      profile = analyze('/webhooks/payout' => { 'post' => webhook },
                        '/balance' => { 'get' => { 'operationId' => 'getBalance', 'responses' => { '200' => response } } })

      expect(profile.conditions).to be_empty
    end

    it 'does not raise on responses, parameters or schemas of the wrong shape' do
      paths = { '/a' => { 'post' => { 'operationId' => 'a', 'responses' => 'nope', 'parameters' => 'nope',
                                      'requestBody' => { 'content' => 'nope' } } } }

      expect { analyze(paths) }.not_to raise_error
    end
  end

  describe 'on the spec as shipped' do
    let(:profile) do
      document = SpecGen::SpecLoader.load(spec_fixture('novapay.yaml'))
      described_class.call(document: document, profile: SpecGen::IR::ProviderProfile.new,
                           rules: SpecGen::Rules.load)
    end

    it 'finds every interaction condition the spec states, formally or in prose' do
      expect(profile.conditions.map { |c| [c.kind, c.field || c.operation] })
        .to eq([[:rate_limited, 'createPayout'], [:retry_after, 'createPayout'],
                [:idempotency_optional, 'createPayout'], [:min_amount, 'amount'], [:field_enum, 'currency'],
                [:field_max_length, 'external_id'], [:field_enum, 'type'], [:field_pattern, 'phone'],
                [:cancel_status_restriction, 'cancelPayout']])
    end

    it 'reads the minimum amount raw, the cancel statuses from prose, and warns about nothing' do
      expect(only(profile, :min_amount).value.value).to eq(100_000)
      expect(only(profile, :min_amount).json_path).to eq('$.components.schemas.CreatePayoutRequest.properties.amount')
      expect(only(profile, :cancel_status_restriction).value)
        .to have_attributes(value: %w[pending processing], source: :heuristic, confidence: 0.6)
      expect(only(profile, :field_pattern).value.value).to eq('^7\d{10}$')
      expect(profile.warnings).to be_empty
    end
  end
end
