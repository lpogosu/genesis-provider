# frozen_string_literal: true

RSpec.describe SpecGen::IR::ProviderProfile do
  include IRBuilders

  describe 'an empty profile' do
    subject(:profile) { described_class.new }

    it 'starts with every collection empty and every optional part absent' do
      expect(profile.to_h).to eq(
        info: nil, servers: [], auth: nil, operations: [], schemas: {}, status_map: [],
        error_map: [], webhooks: [], units: nil, idempotency: nil, conditions: [], warnings: []
      )
    end

    it 'reports no warnings' do
      expect([profile.warnings?, profile.warnings?(:error)]).to eq([false, false])
    end

    it 'rejects a member of the wrong type instead of failing later in a template' do
      expect { described_class.new(units: :minor) }
        .to raise_error(ArgumentError, /units: ожидается Units или nil/)
    end
  end

  describe '#warn' do
    subject(:profile) { described_class.new }

    it 'records a warning and hands it back' do
      warning = profile.warn(:units_unknown, 'amount unit not derived', json_path: '$.x')
      expect(warning.json_path).to eq('$.x')
      expect(profile.warnings.map(&:code)).to eq([:units_unknown])
    end

    it 'defaults to :warning and accepts an overlay suggestion' do
      profile.warn(:status_unmapped, 'unknown status', suggested_overlay: 'actions: []')
      expect(profile.warnings.first).to have_attributes(severity: :warning, fixable?: true)
    end

    it 'refuses a code outside the vocabulary' do
      expect { profile.warn(:made_up, 'x') }.to raise_error(ArgumentError, /код предупреждения: неизвестное значение/)
    end

    it 'answers whether a given severity occurred' do
      profile.warn(:auth_unknown, 'no security scheme', severity: :error)
      expect([profile.warnings?(:error), profile.warnings?(:info)]).to eq([true, false])
    end
  end

  describe 'ordering' do
    subject(:profile) { described_class.new }

    before do
      profile.warn(:status_unmapped, 'later', json_path: '$.b', severity: :info)
      profile.warn(:units_unknown, 'first', json_path: '$.z', severity: :error)
      profile.warn(:currency_unknown, 'middle', json_path: '$.a')
    end

    it 'sorts warnings by severity, then location, then code' do
      expect(profile.sorted_warnings.map(&:message)).to eq(%w[first middle later])
    end

    it 'groups warnings by severity, most severe first, with empty groups kept' do
      grouped = profile.warnings_by_severity
      expect(grouped.keys).to eq(%i[error warning info])
      expect(grouped[:error].map(&:code)).to eq([:units_unknown])
    end
  end

  describe 'lookups' do
    subject(:profile) { described_class.new(operations: [create, balance], schemas: { 'Payout' => schema }) }

    let(:create) { operation(:create_payout, :post, '/payouts', id: 'createPayout') }
    let(:balance) { operation(:balance, :get, '/balance') }
    let(:schema) { SpecGen::IR::Schema.new(name: 'Payout') }

    it 'finds operations by contract role' do
      expect(profile.operations_by_role(:create_payout)).to eq([create])
      expect(profile.operation_for(:fetch_status)).to be_nil
    end

    it 'refuses a role outside the vocabulary rather than returning nothing' do
      expect { profile.operations_by_role(:refund) }.to raise_error(ArgumentError, /роль операции/)
    end

    it 'finds an operation by its key, which falls back to method and path' do
      expect(profile.operation('createPayout')).to eq(create)
      expect(profile.operation('GET /balance')).to eq(balance)
    end

    it 'finds a schema by name' do
      expect(profile.schema('Payout')).to eq(schema)
      expect(profile.schema('Missing')).to be_nil
    end
  end

  describe '#to_h' do
    it 'sorts schemas by name, error rules by selector and warnings by severity' do
      profile = described_class.new(
        schemas: { 'Zebra' => SpecGen::IR::Schema.new(name: 'Zebra'),
                   'Alpha' => SpecGen::IR::Schema.new(name: 'Alpha') },
        error_map: [error_rule(500, :retry_backoff), error_rule(402, :retry)]
      )
      profile.warn(:status_unmapped, 'second', severity: :info)
      profile.warn(:units_unknown, 'first', severity: :error)

      hash = profile.to_h
      expect(hash[:schemas].keys).to eq(%w[Alpha Zebra])
      expect(hash[:error_map].map { |rule| rule[:http_status] }).to eq([402, 500])
      expect(hash[:warnings].map { |warning| warning[:message] }).to eq(%w[first second])
    end

    it 'sorts the collections that can be filled from several places, whatever the order' do
      forward = full_profile.to_h
      backward = full_profile(reverse: true).to_h
      sorted = %i[schemas error_map warnings]
      expect(backward.slice(*sorted)).to eq(forward.slice(*sorted))
    end

    it 'keeps operations and statuses in spec order, which is itself deterministic' do
      expect(full_profile.to_h[:operations].map { |op| op[:path] }).to eq(['/payouts', '/balance'])
      expect(full_profile.to_h[:status_map].map { |s| s[:provider_status] }).to eq(%w[pending completed])
    end

    it 'gives byte-identical output for identical input, which golden tests rely on' do
      expect(Marshal.dump(full_profile.to_h)).to eq(Marshal.dump(full_profile.to_h))
    end

    it 'contains plain data only, so it can be serialised for golden tests' do
      expect(plain?(full_profile.to_h)).to be(true)
    end

    it 'expands nested IR objects, keeping every derivation explainable' do
      units = full_profile.to_h[:units]
      expect(units[:unit]).to eq(value: :minor, source: :structural, confidence: 1.0,
                                 evidence: 'type: integer')
      expect(units[:exponent][:evidence]).to eq('ISO 4217: экспонента RUB 2')
    end

    it 'keeps interaction conditions in the order they were found, each with its derivation' do
      condition = full_profile.to_h[:conditions].first
      expect(condition).to include(kind: :min_amount, field: 'amount', operation: 'createPayout')
      expect(condition[:value]).to include(value: 100_000, source: :structural)
    end
  end
end
