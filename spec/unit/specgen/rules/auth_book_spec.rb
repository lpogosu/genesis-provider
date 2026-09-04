# frozen_string_literal: true

RSpec.describe SpecGen::Rules::AuthBook do
  include RulesFixtures

  def auth(patch = {})
    load_rules('auth.yml' => rule('auth.yml').merge(patch)).auth
  end

  def schemes(&)
    patch = rule('auth.yml')
    yield patch['schemes']
    patch
  end

  describe 'recognising a declared security scheme' do
    it 'matches an API key in a header' do
      entry = auth.scheme_for({ 'type' => 'apiKey', 'in' => 'header', 'name' => 'X-API-Key' })

      expect(entry[:ir_type]).to eq(:api_key)
      expect(entry[:credential_keys]).to eq(['api_key'])
    end

    it 'matches HTTP bearer' do
      entry = auth.scheme_for({ 'type' => 'http', 'scheme' => 'Bearer' })

      expect(entry[:ir_type]).to eq(:bearer)
      expect(entry[:headers]).to include('Authorization')
    end

    it 'matches on the OAuth2 flow when the spec declares one' do
      patch = schemes do |set|
        set['oauth2_client_credentials'] = {
          'match' => { 'type' => 'oauth2', 'flow' => 'clientCredentials' },
          'ir_type' => 'oauth2', 'location' => 'header', 'requires_token_url' => true,
          'credential_keys' => %w[client_id client_secret],
          'headers' => { 'Authorization' => 'token(client_id, client_secret)' }
        }
      end
      entry = auth('schemes' => patch['schemes'])
              .scheme_for({ 'type' => 'oauth2', 'flows' => { 'clientCredentials' => {} } })

      expect(entry[:ir_type]).to eq(:oauth2)
      expect(entry[:token_url_required]).to be(true)
    end

    it 'finds nothing for a scheme the dictionary does not describe' do
      expect(auth.scheme_for({ 'type' => 'mutualTLS' })).to be_nil
    end
  end

  describe 'what an analyzer asks about a matched entry' do
    it 'names the entry, so a report can cite the dictionary it came from' do
      book = auth
      entry = book.scheme_for({ 'type' => 'apiKey', 'in' => 'header' })

      expect(book.name_of(entry)).to eq('api_key_header')
    end

    it 'takes the parameter name from the spec where a fragment key is a placeholder' do
      book = auth
      entry = book.scheme_for({ 'type' => 'apiKey', 'in' => 'header' })

      expect(book.spec_names_param?(entry)).to be(true)
      expect(book.param_name_for(entry, { 'name' => 'X-API-Key' })).to eq('X-API-Key')
      expect(book.param_name_for(entry, {})).to be_nil
    end

    it 'keeps the fixed header name where the dictionary spells one out' do
      book = auth
      entry = book.scheme_for({ 'type' => 'http', 'scheme' => 'bearer' })

      expect(book.spec_names_param?(entry)).to be(false)
      expect(book.param_name_for(entry, { 'name' => 'X-Ignored' })).to eq('Authorization')
    end
  end

  describe 'guarding the entries' do
    it 'refuses an auth type outside IR::Auth' do
      patch = schemes { |set| set['bearer']['ir_type'] = 'jwt' }

      expect(rules_error('auth.yml' => patch)).to include('unknown auth type "jwt"')
    end

    it 'refuses a location outside IR::Auth' do
      patch = schemes { |set| set['bearer']['location'] = 'body' }

      expect(rules_error('auth.yml' => patch)).to include('unknown auth location "body"')
    end

    it 'refuses a match block keyed on something the spec does not have' do
      patch = schemes { |set| set['bearer']['match'] = { 'type' => 'http', 'vendor' => 'nova' } }

      expect(rules_error('auth.yml' => patch)).to include('match cannot key on vendor')
    end

    it 'refuses a credential no fragment ever reads' do
      patch = schemes { |set| set['bearer']['credential_keys'] = %w[access_token unused_secret] }

      expect(rules_error('auth.yml' => patch))
        .to include('credential keys no fragment reads: unused_secret')
    end

    it 'refuses an empty dictionary' do
      expect(rules_error('auth.yml' => rule('auth.yml').merge('schemes' => {})))
        .to include('no security scheme is described')
    end
  end
end
