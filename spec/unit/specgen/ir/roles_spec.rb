# frozen_string_literal: true

RSpec.describe SpecGen::IR::Roles do
  it 'holds the payment-domain field roles from CLAUDE.md' do
    expect(described_class::FIELD).to include(:amount, :currency, :external_id, :bank_code,
                                              :idempotency_key, :signature)
    expect(described_class::FIELD.uniq).to eq(described_class::FIELD)
  end

  it 'keeps :unmapped as a real operation role, not an absence' do
    expect(described_class::OPERATION).to include(:unmapped)
  end

  it 'maps only payout, deposit, status and webhook onto the contract' do
    expect(described_class::CONTRACT).to eq(%i[create_payout create_deposit fetch_status webhook])
  end

  it 'leaves cancel and balance outside the contract, as CLAUDE.md requires' do
    expect(described_class.contract?(:cancel)).to be(false)
    expect(described_class.contract?(:balance)).to be(false)
    expect(described_class.contract?(:create_payout)).to be(true)
  end

  it 'has exactly three internal statuses' do
    expect(described_class::INTERNAL_STATUS).to eq(%i[in_progress approved rejected])
  end

  it 'includes dedup among the error actions, for the idempotent conflict' do
    expect(described_class::ERROR_ACTION).to include(:dedup, :retry_backoff, :alert)
  end

  it 'treats only structural and overlay as certain sources' do
    expect(described_class::CERTAIN_SOURCE).to eq(%i[structural overlay])
    expect(described_class::SOURCE).to include(*described_class::CERTAIN_SOURCE)
  end

  it 'freezes every vocabulary' do
    vocabularies = %i[FIELD OPERATION CONTRACT INTERNAL_STATUS ERROR_ACTION SOURCE CERTAIN_SOURCE]
    expect(vocabularies.map { |name| described_class.const_get(name) }).to all(be_frozen)
  end

  describe 'the bang checks' do
    it 'return the value when it belongs to the vocabulary' do
      expect(described_class.field!(:amount)).to eq(:amount)
      expect(described_class.operation!(:unmapped)).to eq(:unmapped)
      expect(described_class.internal_status!(:approved)).to eq(:approved)
      expect(described_class.error_action!(:dedup)).to eq(:dedup)
      expect(described_class.source!(:registry)).to eq(:registry)
    end

    it 'raise ArgumentError naming the vocabulary, because this is a bug, not bad input' do
      expect { described_class.field!(:bik) }
        .to raise_error(ArgumentError, /роль поля: неизвестное значение :bik.*amount, currency/)
      expect { described_class.operation!(:teleport) }.to raise_error(ArgumentError, /роль операции/)
      expect { described_class.internal_status!(:done) }.to raise_error(ArgumentError, /внутренний статус/)
    end
  end
end
