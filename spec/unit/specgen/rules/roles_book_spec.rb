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

      expect(message).to include('"bic" is already claimed by role bank_code')
        .and include('$.roles.bank_code.names[1]')
        .and include('$.roles.card_number.names[1]')
    end

    it 'sees through spelling, so bankBIC and Bank-BIC collide too' do
      roles = rule('roles.yml')
      roles['roles']['bank_code']['names'] = %w[bank_code bankBIC]
      roles['roles']['bank_name']['names'] = %w[bank_name Bank-BIC]

      expect(rules_error('roles.yml' => roles))
        .to include('"bank_bic" is already claimed by role bank_code')
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

      expect(rules_error('roles.yml' => roles)).to include('no synonyms for signature')
    end

    it 'refuses a role IR does not know' do
      roles = rule('roles.yml')
      roles['roles']['merchant_mood'] = { 'names' => ['mood'] }

      expect(rules_error('roles.yml' => roles)).to include('unknown field role "merchant_mood"')
    end

    it 'refuses a role with no synonyms at all' do
      roles = rule('roles.yml')
      roles['roles']['amount'] = { 'names' => [] }

      expect(rules_error('roles.yml' => roles)).to include('names must be a non-empty array')
    end
  end

  describe 'the other hints' do
    it 'compiles patterns into regular expressions' do
      roles = rule('roles.yml')
      roles['roles']['recipient_phone']['patterns'] = ['^7\d{10}$']

      expect(roles_book('roles' => roles['roles']).hints(:recipient_phone)[:patterns])
        .to eq([/^7\d{10}$/])
    end

    it 'refuses a pattern that does not compile' do
      roles = rule('roles.yml')
      roles['roles']['recipient_phone']['patterns'] = ['^7\d{10}(']

      expect(rules_error('roles.yml' => roles)).to include('not a valid regular expression')
    end

    it 'refuses an OpenAPI type that does not exist' do
      roles = rule('roles.yml')
      roles['roles']['amount']['types'] = %w[integer decimal]

      expect(rules_error('roles.yml' => roles)).to include('unknown OpenAPI type "decimal"')
    end
  end
end
