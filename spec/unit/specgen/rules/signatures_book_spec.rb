# frozen_string_literal: true

RSpec.describe SpecGen::Rules::SignaturesBook do
  include RulesFixtures

  describe 'looking a profile up by its header, and the algorithm words' do
    let(:book) { load_rules.signatures }

    it 'finds the profile whose header the spec names, whatever the case' do
      name, entry = book.profile_for_header('x-signature')

      expect(name).to eq('raw_hex')
      expect(entry[:encoding]).to eq(:hex)
      expect(book.profile_for_header('X-Callback-Signature')).to be_nil
    end

    it 'reads the algorithm a description names, and nothing from an ambiguous one' do
      expect(book.algorithm_hint('HMAC-SHA256 подпись тела запроса')).to eq([:hmac_sha256, 'HMAC-SHA256'])
      expect(book.algorithm_hint('hmac_sha512')).to eq([:hmac_sha512, 'hmac_sha512'])
      expect(book.algorithm_hint('HMAC-SHA256 or HMAC-SHA512')).to be_nil
      expect(book.algorithm_hint('signed body')).to be_nil
      expect(book.algorithm_hint(nil)).to be_nil
    end

    it 'refuses an algorithm outside the vocabulary and a pattern that does not compile' do
      patch = rule('signatures.yml')
      patch['algorithm_words'] = { 'md5' => ['md5'] }
      expect(rules_error('signatures.yml' => patch)).to include('алгоритм подписи: неизвестное значение "md5"')

      patch['algorithm_words'] = { 'hmac_sha1' => ['(?<x'] }
      expect(rules_error('signatures.yml' => patch)).to include('$.algorithm_words.hmac_sha1[0]')
    end
  end

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
        .to include('профиль standard_webhooks обязателен как профиль по умолчанию')
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
        .to include('применимы только к payload id_timestamp_body')
    end

    it 'refuses a tolerance that is not a number of seconds' do
      patch = profiles { |set| set['standard_webhooks']['tolerance'] = 0 }

      expect(rules_error('signatures.yml' => patch)).to include('в диапазоне 1..86400')
    end
  end

  describe 'the vocabularies' do
    it 'refuses an algorithm outside IR::SignatureProfile' do
      patch = profiles { |set| set['raw_hex']['algorithm'] = 'md5' }

      expect(rules_error('signatures.yml' => patch))
        .to include('алгоритм подписи: неизвестное значение "md5"')
    end

    it 'refuses an encoding outside IR::SignatureProfile' do
      patch = profiles { |set| set['raw_hex']['encoding'] = 'base32' }

      expect(rules_error('signatures.yml' => patch)).to include('кодирование подписи: неизвестное значение')
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
