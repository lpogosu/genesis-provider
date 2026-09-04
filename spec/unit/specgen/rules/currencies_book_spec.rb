# frozen_string_literal: true

RSpec.describe SpecGen::Rules::CurrenciesBook do
  include RulesFixtures

  def currencies(patch = {})
    load_rules('currencies.yml' => rule('currencies.yml').merge(patch)).currencies
  end

  describe 'the ISO 4217 exponent' do
    it 'answers with the exponent of the standard, whatever the case' do
      book = currencies

      expect(book.exponent('RUB')).to eq(2)
      expect(book.exponent('jpy')).to eq(0)
      expect(book.exponent(' KWD ')).to eq(3)
    end

    it 'says nothing for a code outside the table, so the caller can warn' do
      book = currencies

      expect(book.exponent('XYZ')).to be_nil
      expect(book).not_to be_known('XYZ')
      expect(book.default_exponent).to eq(2)
    end

    it 'carries the name of the currency for the report' do
      expect(currencies.name_of('JPY')).to eq('Yen')
    end
  end

  describe 'guarding the table' do
    it 'refuses a code that is not three capital letters' do
      patch = rule('currencies.yml')
      patch['currencies']['Rub'] = { 'exponent' => 2, 'name' => 'Russian Ruble' }

      expect(rules_error('currencies.yml' => patch))
        .to include('три заглавные латинские буквы').and include('"Rub"')
    end

    it 'refuses an exponent outside the range the standard uses' do
      patch = rule('currencies.yml')
      patch['currencies']['RUB'] = { 'exponent' => 7, 'name' => 'Russian Ruble' }

      expect(rules_error('currencies.yml' => patch))
        .to include('$.currencies.RUB.exponent').and include('в диапазоне 0..4')
    end

    it 'refuses an exponent that is not a whole number' do
      patch = rule('currencies.yml')
      patch['currencies']['RUB'] = { 'exponent' => '2', 'name' => 'Russian Ruble' }

      expect(rules_error('currencies.yml' => patch)).to include('ожидается целое число')
    end

    it 'refuses an entry with no name' do
      patch = rule('currencies.yml')
      patch['currencies']['RUB'] = { 'exponent' => 2 }

      expect(rules_error('currencies.yml' => patch)).to include('название валюты: ожидается непустая строка')
    end

    it 'refuses an empty table' do
      expect(rules_error('currencies.yml' => rule('currencies.yml').merge('currencies' => {})))
        .to include('таблица валют пуста')
    end
  end
end
