# frozen_string_literal: true

# On the shipped dictionaries: patterns, samples, enum hints, ISO 4217 and
# the status synonyms are data, and the point of these examples is that the
# shipped data recognises the constraints of real specs.
RSpec.describe SpecGen::Matchers::ConstraintMatcher do
  let(:rules) { SpecGen::Rules.load }
  let(:matcher) do
    described_class.new(book: rules.roles, statuses: rules.statuses, currencies: rules.currencies)
  end

  def votes(attributes)
    matcher.call(SpecGen::Matchers::Subject.new(name: 'contact', **attributes))
  end

  describe 'pattern' do
    it 'reads the phone pattern of the shipped spec as recipient_phone, whatever the name' do
      listed = votes(constraints: { pattern: '^7\d{10}$' })

      expect(listed.map(&:role)).to eq([:recipient_phone])
      expect(listed.first).to have_attributes(kind: :pattern_same, score: 1.0)
      expect(listed.first).to be_identifying
    end

    it 'recognises a pattern written differently by the sample values it accepts' do
      listed = votes(constraints: { pattern: '^[0-9]{9}$' })

      expect(listed.map(&:role)).to eq([:bank_code])
      expect(listed.first.kind).to eq(:pattern_sample)
      expect(listed.first.evidence).to include('044525225')
    end

    it 'reads 13 to 19 digits as a card number and three capitals as a currency' do
      expect(votes(constraints: { pattern: '^\d{13,19}$' }).map(&:role)).to eq([:card_number])
      expect(votes(constraints: { pattern: '^[A-Z]{3}$' }).map(&:role)).to eq([:currency])
    end

    it 'says nothing for a pattern that accepts the samples of several roles' do
      expect(votes(constraints: { pattern: '^\d+$' })).to be_empty
      expect(votes(constraints: { pattern: '^.*$' })).to be_empty
    end

    it 'survives a pattern that does not compile' do
      expect { votes(constraints: { pattern: '^7\d{10}(' }) }.not_to raise_error
      expect(votes(constraints: { pattern: '^7\d{10}(' })).to be_empty
    end
  end

  describe 'example' do
    it 'reads an example value through the patterns of the roles' do
      expect(votes(example: '79001234567').map { |v| [v.role, v.kind] })
        .to eq([%i[recipient_phone example]])
      expect(votes(example: '4111111111111111').map(&:role)).to eq([:card_number])
    end

    it 'ignores an example that is not a string' do
      expect(votes(example: 1_500_000)).to be_empty
    end
  end

  describe 'enum' do
    it 'reads an enum of statuses as the status role, by share' do
      listed = votes(constraints: { enum: %w[pending processing completed failed cancelled] })

      expect(listed.map(&:role)).to eq([:status])
      expect(listed.first.score).to eq(1.0)
      expect(listed.first.evidence).to include('rules/statuses.yml').and include('100%')
    end

    it 'reads an enum of ISO 4217 codes as the currency role' do
      expect(votes(constraints: { enum: %w[RUB USD] }).map(&:role)).to eq([:currency])
      expect(votes(constraints: { const: 'RUB' }).map(&:role)).to eq([:currency])
    end

    it 'reads the recipient types of the shipped spec through the enum hints' do
      listed = votes(constraints: { enum: %w[sbp card] })

      expect(listed.map(&:role)).to eq([:recipient_type])
    end

    it 'votes for nothing when fewer than half the values are known' do
      expect(votes(constraints: { enum: %w[pending foo bar baz] })).to be_empty
    end
  end

  describe 'weak signals' do
    it 'confirms currency by maxLength 3 without identifying it' do
      vote = votes(constraints: { max_length: 3 }).find { |v| v.role == :currency }

      expect(vote).to have_attributes(kind: :length, score: 0.3)
      expect(vote).not_to be_identifying
    end

    it 'confirms an amount by numeric bounds without identifying it' do
      vote = votes(type: 'integer', constraints: { minimum: 100_000 }).find { |v| v.role == :amount }

      expect(vote).to have_attributes(kind: :bounds)
      expect(vote).not_to be_identifying
      expect(votes(type: 'string', constraints: { minimum: 1 })).to be_empty
    end
  end

  it 'votes for nothing without constraints or example' do
    expect(votes({})).to be_empty
  end
end
