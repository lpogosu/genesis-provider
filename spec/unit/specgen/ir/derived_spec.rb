# frozen_string_literal: true

RSpec.describe SpecGen::IR::Derived do
  describe 'factories' do
    it 'reads a value from the spec structure with full confidence' do
      derived = described_class.structural(:minor, evidence: 'type: integer')
      expect(derived.to_h).to eq(value: :minor, source: :structural, confidence: 1.0,
                                 evidence: 'type: integer')
    end

    it 'takes a human override from an overlay with full confidence' do
      derived = described_class.overlay(2, evidence: 'overlay: amount_unit')
      expect([derived.source, derived.confidence]).to eq([:overlay, 1.0])
    end

    it 'takes a value from a standard, just short of certain' do
      derived = described_class.registry(2, evidence: 'ISO 4217: RUB exponent 2')
      expect([derived.source, derived.confidence]).to eq([:registry, 0.9])
      expect(derived.certain?).to be(false)
    end

    it 'records what the matchers actually scored for a heuristic' do
      derived = described_class.heuristic(:amount, confidence: 0.82, evidence: 'name: amount~sum')
      expect([derived.source, derived.confidence, derived.value]).to eq([:heuristic, 0.82, :amount])
    end

    it 'has no value and no confidence when nothing could be derived' do
      derived = described_class.unknown(evidence: 'no currency field found')
      expect(derived.to_h).to eq(value: nil, source: :unknown, confidence: 0.0,
                                 evidence: 'no currency field found')
    end
  end

  describe '#known?' do
    it 'is true only when there is a value from a real source' do
      expect(described_class.structural('RUB', evidence: 'enum').known?).to be(true)
      expect(described_class.unknown(evidence: 'nothing').known?).to be(false)
    end

    it 'treats a nil value as unknown even under a confident source' do
      derived = described_class.new(value: nil, source: :structural, evidence: 'empty enum')
      expect([derived.known?, derived.unknown?]).to eq([false, true])
    end
  end

  describe '#certain?' do
    it 'holds for the sources that carry no doubt' do
      certain = %i[structural overlay].map { |s| described_class.new(value: 1, source: s).certain? }
      doubtful = %i[registry heuristic unknown].map do |source|
        described_class.new(value: 1, source: source, confidence: 0.7).certain?
      end
      expect(certain).to all(be(true))
      expect(doubtful).to all(be(false))
    end
  end

  describe 'validation' do
    it 'rejects a source outside the vocabulary and lists the accepted ones' do
      expect { described_class.new(value: 1, source: :guessed) }
        .to raise_error(ArgumentError, /unknown derivation source :guessed.*structural, registry/)
    end

    it 'rejects a confidence outside 0.0..1.0' do
      expect { described_class.heuristic(:amount, confidence: 1.4, evidence: 'x') }
        .to raise_error(ArgumentError, /confidence must be within 0.0..1.0, got 1.4/)
    end

    it 'rejects a confidence that is not a number' do
      expect { described_class.heuristic(:amount, confidence: 'high', evidence: 'x') }
        .to raise_error(ArgumentError, /confidence must be a number/)
    end

    it 'ignores a confidence given for a certain source rather than trusting it' do
      derived = described_class.new(value: 1, source: :structural, confidence: 0.2)
      expect(derived.confidence).to eq(1.0)
    end

    it 'defaults a heuristic without a score to the midpoint' do
      expect(described_class.new(value: 1, source: :heuristic).confidence).to eq(0.5)
    end
  end

  it 'is frozen, so an analyzer replaces a value instead of mutating it' do
    derived = described_class.structural(1, evidence: 'x')
    expect(derived).to be_frozen
    expect { derived.value = 2 }.to raise_error(FrozenError)
  end

  it 'prints value, source, confidence and evidence for the report' do
    derived = described_class.registry(:minor, evidence: 'ISO 4217: RUB exponent 2')
    expect(derived.to_s).to eq(':minor (registry 0.90: ISO 4217: RUB exponent 2)')
  end

  it 'compares by value, as a Struct does' do
    expect(described_class.structural(1, evidence: 'x')).to eq(described_class.structural(1, evidence: 'x'))
  end
end
