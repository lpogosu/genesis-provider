# frozen_string_literal: true

RSpec.describe SpecGen::IR::Condition do
  include IRBuilders

  def condition(**overrides)
    described_class.new(kind: :min_amount, value: structural(100_000, 'minimum: 100000'),
                        field: 'amount', operation: 'createPayout', **overrides)
  end

  it 'keeps the raw constraint together with its derivation' do
    expect(condition.to_h).to include(kind: :min_amount, field: 'amount', operation: 'createPayout',
                                      json_path: nil)
    expect(condition.value.value).to eq(100_000)
    expect(condition.field?).to be(true)
  end

  it 'tells a condition read from prose from one read from keywords' do
    prose = condition(kind: :cancel_status_restriction, field: nil,
                      value: SpecGen::IR::Derived.heuristic(%w[pending], confidence: 0.6, evidence: 'prose'))

    expect(prose.heuristic?).to be(true)
    expect(prose.field?).to be(false)
    expect(condition.heuristic?).to be(false)
  end

  it 'refuses a kind outside the vocabulary, so a typo cannot reach the report' do
    expect { condition(kind: :max_speed) }
      .to raise_error(ArgumentError, /вид условия: неизвестное значение :max_speed/)
  end

  it 'requires the value to be a Derived' do
    expect { condition(value: 100_000) }.to raise_error(ArgumentError, /значение условия: ожидается Derived/)
  end
end
