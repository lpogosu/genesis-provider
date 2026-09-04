# frozen_string_literal: true

RSpec.describe SpecGen::Rules::StatusesBook do
  include RulesFixtures

  def statuses(patch = {})
    load_rules('statuses.yml' => rule('statuses.yml').merge(patch)).statuses
  end

  describe 'mapping a provider status' do
    it 'follows the canon of the case description' do
      book = statuses

      expect(book.internal_for('pending')).to eq(:in_progress)
      expect(book.internal_for('completed')).to eq(:approved)
      expect(book.internal_for('failed')).to eq(:rejected)
    end

    it 'follows a synonym as well, and marks it as not canonical' do
      book = statuses

      expect(book.internal_for('PAID')).to eq(:approved)
      expect(book.canonical?('paid')).to be(false)
      expect(book.canonical?('completed')).to be(true)
    end

    it 'maps nothing for a status nobody listed' do
      expect(statuses.internal_for('quantum')).to be_nil
    end
  end

  describe 'a status that means different things' do
    it 'is never mapped, and says why' do
      book = statuses

      expect(book.internal_for('on_hold')).to be_nil
      expect(book).to be_ambiguous('on_hold')
      expect(book.ambiguity('ON-HOLD')).to include('manual review')
    end

    it 'refuses to be both ambiguous and mapped' do
      patch = rule('statuses.yml')
      patch['synonyms']['approved'] << 'on_hold'

      expect(rules_error('statuses.yml' => patch))
        .to include('on_hold').and include('already mapped to approved')
    end
  end

  describe 'a status mapped twice' do
    it 'stops the load and points at the first mapping' do
      patch = rule('statuses.yml')
      patch['synonyms']['rejected'] << 'paid'

      expect(rules_error('statuses.yml' => patch))
        .to include('"paid" is already mapped to approved')
        .and include('$.synonyms.approved[0]')
    end

    it 'catches a canonical entry repeated among the synonyms' do
      patch = rule('statuses.yml')
      patch['synonyms']['in_progress'] << 'Pending'

      expect(rules_error('statuses.yml' => patch)).to include('already mapped to in_progress')
    end
  end

  describe 'the internal vocabulary' do
    it 'refuses an internal status IR does not know' do
      patch = rule('statuses.yml')
      patch['canonical']['refunded'] = 'reversed'

      expect(rules_error('statuses.yml' => patch)).to include('unknown internal status "reversed"')
    end

    it 'requires at least one provider status per internal status' do
      patch = rule('statuses.yml')
      patch['canonical'].delete('failed')
      patch['synonyms']['rejected'] = []

      expect(rules_error('statuses.yml' => patch))
        .to include('no provider status maps to rejected')
        .or include('synonyms of rejected must be a non-empty array')
    end
  end
end
