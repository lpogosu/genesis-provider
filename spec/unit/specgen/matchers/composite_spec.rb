# frozen_string_literal: true

# On the shipped dictionaries and weights: the arithmetic below is the
# arithmetic of rules/roles.yml, and the point is that those numbers rank the
# candidates the way the design intends.
RSpec.describe SpecGen::Matchers::Composite do
  let(:rules) { SpecGen::Rules.load }
  let(:composite) { described_class.new(rules: rules) }

  def result_for(name, attributes = {})
    composite.call(SpecGen::Matchers::Subject.new(name: name, **attributes))
  end

  it 'sums weight times score over the fixed total of all weights' do
    result = result_for('code', type: 'string', parents: ['PayoutError'])
    best = result.best

    expect(result.total).to eq(14.0)
    expect(best.role).to eq(:error_code)
    expect(best.points).to eq(5.0 + 4.0 + 1.0)
    expect(best.confidence).to be_within(0.001).of(10.0 / 14)
    expect(best.source).to eq(:heuristic)
  end

  it 'gives a dictionary hit the registry source and the registry confidence' do
    best = result_for('sum', type: 'integer').best

    expect(best.source).to eq(:registry)
    expect(best).to be_registry
    expect(best.confidence).to eq(SpecGen::IR::Derived::REGISTRY_CONFIDENCE)
    expect(best.confirmations.map(&:matcher)).to eq([:type])
  end

  it 'lets a pattern decide the role when the name alone would not reach the threshold' do
    without = result_for('contact', type: 'string', parents: ['Recipient'])
    with = result_for('contact', type: 'string', parents: ['Recipient'],
                                 constraints: { pattern: '^7\d{10}$' })

    expect(without.best.role).to eq(:recipient_phone)
    expect(without.best.confidence).to be < 0.6
    expect(with.candidates.map(&:role)).to eq([:recipient_phone])
    expect(with.best.vote(:constraint)).to have_attributes(kind: :pattern_same, score: 1.0)
    expect(with.best.points).to eq(without.best.points + 4.0)
    expect(with.best.confidence).to be >= 0.6
  end

  it 'identifies the role by the pattern alone when the name says nothing at all' do
    result = result_for('xref', type: 'string', parents: ['Recipient'],
                                constraints: { pattern: '^7\d{10}$' })

    expect(result.candidates.map(&:role)).to eq([:recipient_phone])
    expect(result.best.vote(:name)).to be_nil
    expect(result.best.points).to eq(4.0 + 4.0 + 1.0)
  end

  it 'never makes a candidate out of confirming votes alone' do
    expect(result_for('xref_tag_9', type: 'string', parents: ['Recipient'])).to be_none
    expect(result_for('when', type: 'string', format: 'date-time')).to be_none
    expect(result_for('page', type: 'integer', constraints: { minimum: 1 })).to be_none
  end

  it 'counts a weak token only next to a matching parent' do
    expect(result_for('country_code', type: 'string', parents: ['Address'])).to be_none
    expect(result_for('code', type: 'string', parents: ['error']).best.role).to eq(:error_code)
  end

  it 'ranks by points, then by the order of IR::Roles::FIELD, and caps the confidence' do
    result = result_for('phone_card', type: 'string', parents: ['Recipient'])

    expect(result.candidates.map(&:role)).to eq(%i[recipient_phone card_number])
    expect(result.candidates.map(&:points).uniq.size).to eq(1)
    expect(result.candidates.map(&:confidence)).to all(be <= rules.roles.scoring(:ceiling))
  end

  it 'lets strong evidence outvote the dictionary, so bank.id with a BIC pattern is a bank code' do
    result = result_for('id', type: 'string', parents: ['bank'],
                              constraints: { pattern: '^\d{9}$' })

    expect(result.best.role).to eq(:bank_code)
    expect(result.best.source).to eq(:heuristic)
    expect(result.runner_up.role).to eq(:provider_operation_id)
  end
end
