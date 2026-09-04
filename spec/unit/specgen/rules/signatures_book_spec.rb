# frozen_string_literal: true

RSpec.describe SpecGen::Rules::SignaturesBook do
  include RulesFixtures

  def signatures(patch = {})
    load_rules('signatures.yml' => rule('signatures.yml').merge(patch)).signatures
  end

  def profiles(&)
    patch = rule('signatures.yml')
    yield patch['profiles']
    patch
  end

  describe 'the profiles' do
    it 'reads Standard Webhooks with all of its parameters' do
      profile = signatures.default

      expect(profile).to include(profile: :standard_webhooks, algorithm: :hmac_sha256,
                                 encoding: :base64, payload: :id_timestamp_body, tolerance: 300)
      expect(profile[:id_header]).to eq('webhook-id')
      expect(profile[:value_prefix]).to eq('v1,')
    end

    it 'reads a custom raw-body profile' do
      expect(signatures.profile('raw_hex'))
        .to include(profile: :custom, encoding: :hex, payload: :raw_body)
    end

    it 'requires the Standard Webhooks profile to exist as the default' do
      patch = rule('signatures.yml')
      patch['profiles'].delete('standard_webhooks')

      expect(rules_error('signatures.yml' => patch))
        .to include('standard_webhooks is required as the default')
    end
  end

  describe 'replay protection' do
    it 'requires the id, timestamp and tolerance for a timestamped payload' do
      patch = profiles { |set| set['standard_webhooks'].delete('tolerance') }

      expect(rules_error('signatures.yml' => patch))
        .to include('$.profiles.standard_webhooks.tolerance')
    end

    it 'refuses a tolerance on a payload that carries no timestamp' do
      patch = profiles { |set| set['raw_hex']['tolerance'] = 300 }

      expect(rules_error('signatures.yml' => patch))
        .to include('only apply to an id_timestamp_body payload')
    end

    it 'refuses a tolerance that is not a number of seconds' do
      patch = profiles { |set| set['standard_webhooks']['tolerance'] = 0 }

      expect(rules_error('signatures.yml' => patch)).to include('within 1..86400')
    end
  end

  describe 'the vocabularies' do
    it 'refuses an algorithm outside IR::SignatureProfile' do
      patch = profiles { |set| set['raw_hex']['algorithm'] = 'md5' }

      expect(rules_error('signatures.yml' => patch))
        .to include('unknown signature algorithm "md5"')
    end

    it 'refuses an encoding outside IR::SignatureProfile' do
      patch = profiles { |set| set['raw_hex']['encoding'] = 'base32' }

      expect(rules_error('signatures.yml' => patch)).to include('unknown signature encoding')
    end
  end

  describe 'recognising a signature header in a spec' do
    it 'knows the headers of the profiles and the extra names' do
      book = signatures

      expect(book).to be_signature_header('X-Signature')
      expect(book).to be_signature_header('Webhook-Signature')
      expect(book).not_to be_signature_header('Content-Type')
    end
  end
end
