# frozen_string_literal: true

RSpec.describe SpecGen::IR::Units do
  def units(currency:, unit:, exponent:)
    described_class.new(currency: currency, unit: unit, exponent: exponent)
  end

  def known(value, evidence)
    SpecGen::IR::Derived.structural(value, evidence: evidence)
  end

  def missing(evidence)
    SpecGen::IR::Derived.unknown(evidence: evidence)
  end

  describe '#multiplier' do
    it 'is ten to the exponent for minor units' do
      subject = units(currency: known('RUB', 'enum'), unit: known(:minor, 'type: integer'),
                      exponent: known(2, 'ISO 4217'))

      expect(subject.multiplier).to eq(100)
      expect(subject).to be_known
    end

    it 'is one for major units, whatever the exponent says' do
      subject = units(currency: known('JPY', 'enum'), unit: known(:major, 'type: number'),
                      exponent: known(0, 'ISO 4217'))

      expect(subject.multiplier).to eq(1)
    end
  end

  # Комментарий у AMOUNT_MULTIPLIER в сгенерированном сервисе и строка
  # допущений прогона в INTEGRATION.md берут обоснование отсюда. Пока они
  # брали его у члена `unit`, у мультивалютного провайдера получалось
  # «единицы не выведены (type: integer -> минорные единицы)» — фраза,
  # которая спорит сама с собой.
  describe '#blocker' do
    it 'has nothing to blame when the multiplier is derived' do
      subject = units(currency: known('USD', 'enum'), unit: known(:minor, 'type: integer'),
                      exponent: known(2, 'ISO 4217'))

      expect(subject.blocker).to be_nil
    end

    it 'blames the exponent when the unit is known but the currency is not' do
      subject = units(currency: missing('валюта не объявлена'),
                      unit: known(:minor, 'type: integer'),
                      exponent: missing('без кода валюты экспоненту взять неоткуда'))

      expect(subject).not_to be_known
      expect(subject.blocker.evidence).to include('экспоненту взять неоткуда')
    end

    it 'blames the unit itself when even that is not derived' do
      subject = units(currency: known('USD', 'enum'), unit: missing('type: object'),
                      exponent: known(2, 'ISO 4217'))

      expect(subject.blocker.evidence).to eq('type: object')
    end
  end
end
