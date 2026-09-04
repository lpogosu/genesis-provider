# frozen_string_literal: true

RSpec.describe SpecGen::Rules::ConditionsBook do
  include RulesFixtures

  def conditions(patch = {})
    load_rules('conditions.yml' => rule('conditions.yml').merge(patch)).conditions
  end

  def patched
    document = rule('conditions.yml')
    yield document
    document
  end

  def error_for(&)
    rules_error('conditions.yml' => patched(&))
  end

  def only_pattern(document)
    document['required_when']['patterns'].first
  end

  describe 'reading the dictionary' do
    it 'hands the analyzer the confidence and the patterns, in order' do
      book = conditions

      expect(book.hint_confidence).to eq(0.5)
      expect(book.hints.map(&:name)).to eq(['equals'])
      expect(book.hints.first.kind).to eq('equals')
    end

    it 'returns the first matching pattern with its captures' do
      hint, found = conditions.match('required when type is card')

      expect(hint.name).to eq('equals')
      expect(found[:field]).to eq('type')
      expect(found[:value]).to eq('card')
    end

    it 'says nothing about a description that states no rule' do
      expect(conditions.match('Recipient phone number')).to be_nil
      expect(conditions.match(nil)).to be_nil
    end

    it 'treats text it cannot read as text with no rule in it, instead of raising' do
      unreadable = (+"\xFF\xFE required when type is card").force_encoding('UTF-8')

      expect { conditions.match(unreadable) }.not_to raise_error
      expect(conditions.match(unreadable)).to be_nil
    end
  end

  describe 'guarding the data' do
    it 'refuses a pattern that captures no field, which is the whole point' do
      message = error_for { |doc| only_pattern(doc)['pattern'] = 'required when (.+)' }

      expect(message).to include('шаблон должен захватывать field, value как именованную группу')
    end

    it 'refuses an equality pattern that captures no value' do
      message = error_for { |doc| only_pattern(doc)['pattern'] = 'required (?<field>[a-z]+)' }

      expect(message).to include('шаблон должен захватывать value как именованную группу')
    end

    it 'refuses a kind it does not know' do
      expect(error_for { |doc| only_pattern(doc)['kind'] = 'maybe' })
        .to include('kind: ожидается одно из equals, presence')
    end

    it 'refuses a regular expression that does not compile' do
      expect(error_for { |doc| only_pattern(doc)['pattern'] = '(?<field>[a-z' })
        .to include('регулярное выражение: не компилируется')
    end

    it 'refuses a confidence outside 0..1 and an empty pattern list' do
      expect(error_for { |doc| doc['required_when']['confidence'] = 1.5 })
        .to include('уверенность: ожидается число в диапазоне 0.0..1.0')
      expect(error_for { |doc| doc['required_when']['patterns'] = [] })
        .to include('список patterns: ожидается непустой массив')
    end
  end
end
