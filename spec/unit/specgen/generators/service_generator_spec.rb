# frozen_string_literal: true

require 'tmpdir'

# Заглушка базового класса платформы: ровно то, что сгенерированный сервис
# зовёт у BaseService по rules/contract.yml. Реального класса нам не выдали.
class Provider
  class BaseService
    Credentials = Struct.new(:credentials)

    def provider
      Credentials.new({ api_key: 'test_api_key', webhook_secret: 'test_secret' })
    end

    def success
      :success
    end

    def failure(code, key)
      [:failure, code, key]
    end
  end
end

RSpec.describe SpecGen::Generators::ServiceGenerator do
  include Fixtures

  def generate(spec, dir, provider: nil)
    rules = SpecGen::Rules.load
    document = SpecGen::SpecLoader.load(spec)
    options = { provider: provider, output: dir }.compact
    profile = SpecGen::Analyzers::Runner.call(document: document, rules: rules, options: options)
    [SpecGen::Generators.call(profile: profile, rules: rules, options: options).first, profile]
  end

  def syntax_ok?(path)
    RubyVM::InstructionSequence.compile(File.read(path, encoding: 'UTF-8'), path)
    true
  rescue SyntaxError
    false
  end

  describe 'the generated service for novapay.yaml' do
    before(:all) do
      @dir = Dir.mktmpdir('specgen-service')
      @artifact, = generate(File.join(Fixtures::ROOT, 'specs', 'novapay.yaml'), @dir, provider: 'novapay')
      load @artifact.path
      @service = Provider::NovapayService.new
    end

    after(:all) { FileUtils.remove_entry(@dir) }

    it 'reports the artifact with its file, path and line count' do
      expect(@artifact.kind).to eq(:service)
      expect(@artifact.file).to eq('novapay_service.rb')
      expect(@artifact.lines).to be > 300
    end

    it 'implements UUID v5 per RFC 4122: the python.org vector in the DNS namespace' do
      expect(@service.send(:uuid_v5, '6ba7b810-9dad-11d1-80b4-00c04fd430c8', 'python.org'))
        .to eq('886313e1-3b8a-5372-9b90-0c9aee199e5d')
    end

    it 'derives the same idempotency key for the same operation id, without randomness' do
      operation = Struct.new(:id).new('op-42')
      first = @service.send(:idempotency_key_for, operation)
      expect(first).to match(/\A\h{8}-\h{4}-5\h{3}-[89ab]\h{3}-\h{12}\z/)
      expect(@service.send(:idempotency_key_for, operation)).to eq(first)
      expect(@service.send(:idempotency_key_for, Struct.new(:id).new('op-43'))).not_to eq(first)
    end

    it 'maps statuses and events through frozen tables' do
      expect(Provider::NovapayService::STATUS_MAP).to be_frozen
      expect(Provider::NovapayService::STATUS_MAP['completed']).to eq(:approved)
      expect(Provider::NovapayService::EVENT_MAP.keys).to eq(Provider::NovapayService::EVENT_MAP.keys.sort)
      expect(Provider::NovapayService::ERROR_MAP[409]).to eq(:reject)
      expect(Provider::NovapayService::DEDUP_STATUS).to eq(409)
      expect(Provider::NovapayService::RETRY_POLICY[:retry_after_header]).to eq('Retry-After')
    end

    it 'rejects a callback without the signature header instead of raising' do
      expect(@service.verify_webhook_signature('{}', {})).to eq([:failure, :signature_missing, 'errors.signature_missing'])
    end

    it 'accepts a valid HMAC-SHA256 hex signature regardless of header case' do
      body = '{"event":"payout.completed"}'
      signature = OpenSSL::HMAC.hexdigest('SHA256', 'test_secret', body)
      expect(@service.verify_webhook_signature(body, { 'x-novapay-signature' => signature })).to be_nil
      expect(@service.verify_webhook_signature(body, { 'X-NovaPay-Signature' => signature.tr('0-9', '1-90') }))
        .to eq([:failure, :signature_invalid, 'errors.signature_invalid'])
    end

    it 'verifies the signature inside the callback only when the route passed the raw bytes' do
      body = '{"event":"payout.completed"}'
      signature = OpenSSL::HMAC.hexdigest('SHA256', 'test_secret', body)
      expect(@service.send(:verify_signature!, JSON.parse(body))).to be_nil
      expect(@service.send(:verify_signature!, 'raw_body' => body,
                                               'headers' => { 'X-NovaPay-Signature' => signature })).to be_nil
      expect(@service.send(:verify_signature!, 'raw_body' => body, 'headers' => {}))
        .to eq([:failure, :signature_missing, 'errors.signature_missing'])
    end

    it 'takes the notification target from the payload instead of looking the operation up' do
      expect(@service.send(:callback_target, 'payout_id' => 'np_1')).to eq('np_1')
      expect(@service.send(:callback_target, 'external_id' => 'op_1')).to eq('op_1')
      expect(@service.send(:callback_target, {})).to be_nil
    end

    it 'compares signatures of different length as false, not as an exception' do
      expect(@service.send(:secure_equal?, 'abc', 'abcd')).to be(false)
    end

    it 'builds the payload from roles in provider units and drops nil optionals' do
      fields = %i[amount currency id recipient_type recipient_phone bank_code bank_name card_number]
      operation = Struct.new(*fields).new(1000.5, 'RUB', 'ext-1', 'sbp', '79001234567', '044525225', nil, nil)
      expect(@service.send(:build_payload, operation)).to eq(
        amount: 100_050, currency: 'RUB', external_id: 'ext-1',
        recipient: { type: 'sbp', phone: '79001234567', bank_code: '044525225' }
      )
    end

    it 'sends the API key from credentials and the idempotency key in the request headers' do
      headers = @service.send(:request_headers, Struct.new(:id).new('op-1'))
      expect(headers['X-API-Key']).to eq('test_api_key')
      expect(headers['Idempotency-Key']).to match(/\A\h{8}-/)
      expect(headers['Content-Type']).to eq('application/json')
    end
  end

  describe 'a specification with no webhook, idempotency, units or create operation' do
    it 'still yields a syntactically valid service full of TODOs' do
      Dir.mktmpdir('specgen-bare') do |dir|
        spec = File.join(dir, 'bare.yaml')
        File.binwrite(spec, <<~YAML)
          openapi: 3.0.3
          info: { title: Bare Ledger API, version: '0.1' }
          paths:
            /entries/{entry_id}:
              get:
                operationId: getEntry
                parameters:
                  - { name: entry_id, in: path, required: true, schema: { type: string } }
                responses:
                  '200': { description: ok }
        YAML
        artifact, profile = generate(spec, dir)

        expect(syntax_ok?(artifact.path)).to be(true)
        expect(profile.warnings).not_to be_empty
        source = File.read(artifact.path, encoding: 'UTF-8')
        expect(source).to include('class BareLedgerService', 'TODO', 'def create_request', 'def process_callback',
                                  'webhooks_not_supported')
        expect(source).not_to include('verify_signature!', 'SIGNATURE_HEADER')
      end
    end
  end
end
