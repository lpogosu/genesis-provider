# frozen_string_literal: true

RSpec.describe SpecGen::Rules::RolesBook do
  include RulesFixtures

  def roles_book(patch = {})
    load_rules('roles.yml' => rule('roles.yml').merge(patch)).roles
  end

  describe 'looking a field name up' do
    it 'matches a synonym regardless of how the provider spells it' do
      book = roles_book('roles' => rule('roles.yml')['roles'].merge(
        'bank_code' => { 'names' => %w[bank_code bic bik] }
      ))

      expect(book.role_for('BIK')).to eq(:bank_code)
      expect(book.role_for('bankCode')).to eq(:bank_code)
      expect(book.role_for('X-BIC')).to be_nil
    end

    it 'returns nothing for a name no role claims' do
      expect(roles_book.role_for('xref_tag_9')).to be_nil
    end
  end

  describe 'a synonym two roles claim' do
    it 'stops the load and names both roles and where the first one is' do
      roles = rule('roles.yml')
      roles['roles']['bank_code']['names'] = %w[bank_code bic]
      roles['roles']['card_number']['names'] = %w[card_number bic]

      message = rules_error('roles.yml' => roles)

      expect(message).to include('синоним "bic" уже занят ролью bank_code')
        .and include('$.roles.bank_code.names[1]')
        .and include('$.roles.card_number.names[1]')
    end

    it 'sees through spelling, so bankBIC and Bank-BIC collide too' do
      roles = rule('roles.yml')
      roles['roles']['bank_code']['names'] = %w[bank_code bankBIC]
      roles['roles']['bank_name']['names'] = %w[bank_name Bank-BIC]

      expect(rules_error('roles.yml' => roles))
        .to include('синоним "bank_bic" уже занят ролью bank_code')
    end

    it 'lets one role list the same synonym twice' do
      roles = rule('roles.yml')
      roles['roles']['bank_code']['names'] = %w[bank_code bic BIC]

      expect(roles_book('roles' => roles['roles']).names(:bank_code)).to eq(%w[bank_code bic])
    end

    it 'allows weaker hints to overlap between roles' do
      roles = rule('roles.yml')
      roles['roles']['bank_code']['tokens'] = %w[bank]
      roles['roles']['bank_name']['tokens'] = %w[bank]

      expect { load_rules('roles.yml' => roles) }.not_to raise_error
    end
  end

  describe 'coverage of the closed vocabulary' do
    it 'requires an entry for every role IR knows' do
      roles = rule('roles.yml')
      roles['roles'].delete('signature')

      expect(rules_error('roles.yml' => roles)).to include('нет синонимов для signature')
    end

    it 'refuses a role IR does not know' do
      roles = rule('roles.yml')
      roles['roles']['merchant_mood'] = { 'names' => ['mood'] }

      expect(rules_error('roles.yml' => roles)).to include('роль поля: неизвестное значение "merchant_mood"')
    end

    it 'refuses a role with no synonyms at all' do
      roles = rule('roles.yml')
      roles['roles']['amount'] = { 'names' => [] }

      expect(rules_error('roles.yml' => roles)).to include('список names: ожидается непустой массив')
    end
  end

  describe 'the other hints' do
    it 'compiles patterns into regular expressions' do
      roles = rule('roles.yml')
      roles['roles']['recipient_phone']['patterns'] = ['^7\d{10}$']

      expect(roles_book('roles' => roles['roles']).hints(:recipient_phone)[:patterns])
        .to eq([/^7\d{10}$/])
    end

    it 'reads locations, samples, enum values, lengths and bounds' do
      roles = rule('roles.yml')
      roles['roles']['currency'].merge!('samples' => ['RUB'], 'patterns' => ['^[A-Z]{3}$'],
                                        'lengths' => [3], 'enum_values' => %w[Card SBP])
      roles['roles']['signature']['locations'] = ['header']
      roles['roles']['amount']['bounds'] = true
      book = roles_book('roles' => roles['roles'])

      expect(book.hints(:currency)).to include(samples: ['RUB'], lengths: [3], enum_values: %w[card sbp])
      expect(book.hints(:signature)[:locations]).to eq([:header])
      expect(book.hints(:amount)[:bounds]).to be(true)
      expect(book.hints(:status)[:bounds]).to be(false)
    end

    it 'refuses a sample that its own patterns do not accept' do
      roles = rule('roles.yml')
      roles['roles']['recipient_phone'].merge!('patterns' => ['^7\d{10}$'], 'samples' => ['abc'])

      expect(rules_error('roles.yml' => roles))
        .to include('образец "abc" не подходит ни под один шаблон').and include('$.roles.recipient_phone.samples[0]')
    end

    it 'refuses a parameter location it does not know' do
      roles = rule('roles.yml')
      roles['roles']['signature']['locations'] = ['body']

      expect(rules_error('roles.yml' => roles)).to include('место параметра: неизвестное значение "body"')
    end

    it 'refuses a pattern that does not compile' do
      roles = rule('roles.yml')
      roles['roles']['recipient_phone']['patterns'] = ['^7\d{10}(']

      expect(rules_error('roles.yml' => roles)).to include('регулярное выражение: не компилируется')
    end

    it 'refuses an OpenAPI type that does not exist' do
      roles = rule('roles.yml')
      roles['roles']['amount']['types'] = %w[integer decimal]

      expect(rules_error('roles.yml' => roles)).to include('тип OpenAPI: неизвестное значение "decimal"')
    end
  end

  describe 'the matchers section' do
    def matchers_error(&)
      roles = rule('roles.yml')
      yield roles['matchers']
      rules_error('roles.yml' => roles)
    end

    it 'hands the matchers their weights, thresholds, scores and word lists' do
      book = roles_book

      expect(book.weight(:name)).to eq(5)
      expect(book.total_weight).to eq(14)
      expect(book.scoring(:threshold)).to eq(0.6)
      expect(book.score(:name, :token)).to eq(1.0)
      expect(book.score(:name, :min_length)).to eq(4)
      expect(book.generic_tokens).to include('id')
      expect(book.repeatable?(:amount)).to be(false)
    end

    it 'lists every contradiction of weights and thresholds in one error' do
      message = matchers_error do |matchers|
        matchers['weights']['type'] = 0
        matchers['weights']['vibes'] = 3
        matchers['scoring']['threshold'] = 2
        matchers['name']['token'] = 1.5
        matchers['repeatable'] = ['mood']
      end

      expect(message).to include('вес сигнала type должен быть больше нуля')
        .and include('неизвестные ключи vibes')
        .and include('балл или порог threshold: ожидается число в диапазоне 0.0..1.0')
        .and include('балл или порог token: ожидается число в диапазоне 0.0..1.0')
        .and include('роль поля: неизвестное значение "mood"')
        .and include('$.matchers.weights.type').and include('$.matchers.repeatable[0]')
    end

    it 'refuses a weight that lets one matcher reach the threshold alone' do
      expect(matchers_error { |matchers| matchers['weights']['name'] = 50 })
        .to include('матчер name в одиночку набирает 0.85 при пороге 0.60')
    end

    it 'refuses a missing section and an unknown one' do
      expect(rules_error('roles.yml' => rule('roles.yml').except('matchers')))
        .to include('раздел matchers: ожидается объект')
      expect(matchers_error { |matchers| matchers['vibes'] = {} })
        .to include('неизвестные ключи vibes').and include('$.matchers')
    end
  end
end
