# frozen_string_literal: true

RSpec.describe SpecGen::Matchers::Levenshtein do
  describe '.distance' do
    it 'counts insertions, deletions and substitutions' do
      expect(described_class.distance('amount', 'amount')).to eq(0)
      expect(described_class.distance('amount', 'amout')).to eq(1)
      expect(described_class.distance('amount', 'amonut')).to eq(2)
      expect(described_class.distance('', 'abc')).to eq(3)
      expect(described_class.distance('abc', '')).to eq(3)
    end
  end

  describe '.similarity' do
    it 'is 1.0 for equal strings and falls with the distance' do
      expect(described_class.similarity('amount', 'amount')).to eq(1.0)
      expect(described_class.similarity('amount', 'amout')).to be_within(0.01).of(0.83)
    end

    it 'keeps sum and amount far apart, which is why the dictionary exists' do
      expect(described_class.similarity('sum', 'amount')).to be < 0.2
    end

    it 'treats two empty strings as identical' do
      expect(described_class.similarity('', '')).to eq(1.0)
    end
  end
end
