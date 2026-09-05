# frozen_string_literal: true

require 'json'
require 'net/http'
require 'openssl'
require 'tmpdir'

RSpec.describe SpecGen::Generators::FixturesGenerator do
  include Fixtures

  def generate(spec, dir, provider: nil)
    rules = SpecGen::Rules.load
    document = SpecGen::SpecLoader.load(spec)
    options = { provider: provider, output: dir }.compact
    profile = SpecGen::Analyzers::Runner.call(document: document, rules: rules, options: options)
    artifacts = SpecGen::Generators.call(profile: profile, rules: rules, options: options)
    artifact = artifacts.find { |item| item.kind == :fixtures }
    [JSON.parse(File.read(artifact.path, encoding: 'UTF-8')), artifact]
  end

  def write_bare_spec(dir, body)
    path = File.join(dir, 'bare.yaml')
    File.binwrite(path, body)
    path
  end

  describe 'the fixtures for novapay.yaml' do
    before(:all) do
      @dir = Dir.mktmpdir('specgen-fixtures')
      @json, @artifact = generate(File.join(Fixtures::ROOT, 'specs', 'novapay.yaml'), @dir,
                                  provider: 'novapay')
    end

    after(:all) { FileUtils.remove_entry(@dir) }

    it 'is written as fixtures.json after the service and the guide' do
      expect(@artifact.file).to eq('fixtures.json')
      order = SpecGen::Generators::Runner::ORDER
      expect(order.index(described_class)).to be > order.index(SpecGen::Generators::IntegrationGenerator)
    end

    it 'carries all three kinds the criterion asks for' do
      expect(@json.keys).to eq(%w[provider spec base_url credentials requests responses
                                  notifications])
      expect(@json['requests']).not_to be_empty
      expect(@json['responses']).not_to be_empty
      expect(@json['notifications']).not_to be_empty
    end

    it 'describes the provider and the specification it was generated from' do
      expect(@json['provider']).to eq('novapay')
      expect(@json['base_url']).to eq('https://api.sandbox.novapay.example/v1')
      expect(@json['spec']).to eq('file' => 'novapay.yaml', 'version' => '1.0.0',
                                  'openapi' => '3.0.3')
    end

    it 'stores only obvious stubs instead of secrets' do
      expect(@json['credentials']).to eq('api_key' => 'test_api_key',
                                         'webhook_secret' => 'test_webhook_secret')
      expect(JSON.generate(@json)).not_to match(/sk_live|_live_[A-Za-z0-9]{8}/)
    end

    it 'has one request per operation of the specification' do
      names = @json['requests'].map { |request| request['name'] }
      expect(names).to eq(%w[createPayout getPayoutStatus cancelPayout payoutWebhook getBalance])
    end

    it 'takes the request body from the examples of the specification verbatim' do
      request = @json['requests'].first
      expect(request['source']).to eq('spec_example')
      expect(request['example_name']).to eq('sbp_payout')
      expect(request['body']).to eq('amount' => 1_500_000, 'currency' => 'RUB',
                                    'external_id' => 'op_abc123',
                                    'recipient' => { 'type' => 'sbp', 'phone' => '79001234567',
                                                     'bank_code' => '044525225',
                                                     'bank_name' => 'Сбербанк' })
    end

    it 'fills path parameters with examples instead of leaving the template' do
      paths = @json['requests'].to_h { |request| [request['name'], request['path']] }
      expect(paths['getPayoutStatus']).to eq('/payouts/np_7f3a9b2c')
      expect(paths['cancelPayout']).to eq('/payouts/np_7f3a9b2c/cancel')
      expect(paths.values.join).not_to include('{')
    end

    it 'sends the authorization and idempotency headers the service sends' do
      request = @json['requests'].first
      expect(request['headers']['X-API-Key']).to eq('test_api_key')
      expect(request['headers']['Content-Type']).to eq('application/json')
      expect(request['headers']['Idempotency-Key']).to match(/\A\h{8}-\h{4}-5\h{3}-\h{4}-\h{12}\z/)
    end

    it 'derives the idempotency key the way the generated service does' do
      key = @json['requests'].first['headers']['Idempotency-Key']
      namespace = SpecGen::Rules.load.idempotency.namespace
      expect(key).to eq(SpecGen::Generators::Uuid.v5(namespace, 'novapay:op_abc123'))
    end

    it 'covers the success, the deduplication and the error responses of createPayout' do
      statuses = @json['responses'].select { |item| item['operation'] == 'createPayout' }
                                   .map { |item| item['status'] }
      expect(statuses).to eq([201, 400, 401, 402, 409, 422, 429, 500])
    end

    it 'says what the platform expects of every response' do
      by_name = @json['responses'].to_h { |item| [item['name'], item['expected']] }
      expect(by_name['createPayout 201']).to eq('internal_status' => 'in_progress')
      expect(by_name['createPayout 409']).to eq('dedup' => true,
                                                'internal_status' => 'in_progress')
      expect(by_name['createPayout 402']).to eq('action' => 'retry_backoff')
      expect(by_name['createPayout 429']).to eq('action' => 'retry_backoff')
    end

    it 'admits in "_todo" that an operation declares no error response' do
      balance = @json['responses'].find { |item| item['operation'] == 'getBalance' }
      expect(balance['_todo']).to include('ни одного ответа с ошибкой')
    end

    it 'has one notification per declared event plus two negative ones' do
      names = @json['notifications'].map { |item| item['event'] }
      expect(names).to eq(%w[payout.cancelled payout.completed payout.failed payout.processing
                             payout.completed payout.unknown])
      expect(@json['notifications'].last(2).map { |item| item['expected'] })
        .to eq([{ 'result' => 'signature_invalid' }, { 'result' => 'unknown_event' }])
    end

    it 'signs every notification for real, over the exact bytes of raw_body' do
      secret = @json['credentials']['webhook_secret']
      @json['notifications'].each do |notification|
        signature = notification['headers']['X-NovaPay-Signature']
        expected = OpenSSL::HMAC.hexdigest('SHA256', secret, notification['raw_body'])
        expect(signature.length).to eq(64)
        expect(JSON.generate(notification['body'])).to eq(notification['raw_body'])
        matches = notification['expected']['result'] != 'signature_invalid'
        expect(signature == expected).to be(matches)
      end
    end

    it 'maps every notification to the internal status of EVENT_MAP' do
      statuses = @json['notifications'].first(4)
                                       .to_h { |item| [item['event'], item['expected']] }
      expect(statuses).to eq('payout.cancelled' => { 'internal_status' => 'rejected' },
                             'payout.completed' => { 'internal_status' => 'approved' },
                             'payout.failed' => { 'internal_status' => 'rejected' },
                             'payout.processing' => { 'internal_status' => 'in_progress' })
    end

    it 'never passes an invented value off as an example of the specification' do
      all = @json.values_at('requests', 'responses', 'notifications').flatten
      expect(all.map { |item| item['source'] }.uniq - %w[spec_example schema_example synthesized])
        .to be_empty
      all.reject { |item| item['source'] == 'spec_example' }.each do |item|
        expect(item['_todo']).not_to be_nil, "#{item['name']} has no explanation"
      end
    end

    it 'is usable from WebMock without repacking' do
      request = @json['requests'].first
      response = @json['responses'].first
      stub_request(request['method'].to_sym, @json['base_url'] + request['path'])
        .with(body: request['body'], headers: request['headers'])
        .to_return(status: response['status'], body: JSON.generate(response['body']),
                   headers: { 'Content-Type' => 'application/json' })

      uri = URI.parse(@json['base_url'] + request['path'])
      answer = Net::HTTP.post(uri, JSON.generate(request['body']), request['headers'])
      expect(answer.code.to_i).to eq(response['status'])
      expect(JSON.parse(answer.body)).to eq(response['body'])
    end
  end

  describe 'a specification that says almost nothing' do
    let(:bare) do
      <<~YAML
        openapi: 3.0.3
        info: { title: Bare API, version: "0.1" }
        paths:
          /transfers:
            post:
              operationId: createTransfer
              requestBody:
                required: true
                content:
                  application/json:
                    schema:
                      type: object
                      required: [amount, tax_id]
                      properties:
                        amount: { type: integer }
                        tax_id: { type: string }
              responses:
                "200": { description: ok }
      YAML
    end

    it 'still writes all three kinds and marks the invented values' do
      Dir.mktmpdir('specgen-bare') do |dir|
        json, = generate(write_bare_spec(dir, bare), dir)
        request = json['requests'].first
        expect(request['body']).to eq('amount' => 0, 'tax_id' => 'string')
        expect(request['source']).to eq('synthesized')
        expect(request['_todo']).to include('нет примера')
        expect(json['notifications']).to eq([])
      end
    end

    it 'calls a promised but undescribed response body a gap, not an example of the spec' do
      Dir.mktmpdir('specgen-bare') do |dir|
        json, = generate(write_bare_spec(dir, bare), dir)
        response = json['responses'].first
        expect(response['body']).to be_nil
        expect(response['source']).to eq('undeclared')
        expect(response['_todo']).to include('не описано')
      end
    end
  end

  describe 'an operation that has no body and a response that may not have one' do
    let(:bodyless) do
      <<~YAML
        openapi: 3.0.3
        info: { title: Bodyless API, version: "0.1" }
        paths:
          /transfers/{ref}:
            delete:
              operationId: voidTransfer
              parameters:
                - { name: ref, in: path, required: true, schema: { type: string } }
              responses:
                "204": { description: voided }
      YAML
    end

    it 'keeps a null body an example of the spec when the spec itself said there is none' do
      Dir.mktmpdir('specgen-bodyless') do |dir|
        json, = generate(write_bare_spec(dir, bodyless), dir)
        request = json['requests'].first
        expect(request['body']).to be_nil
        expect(request['source']).to eq('spec_example')
        expect(request['_todo'].to_s).not_to include('не описано')

        response = json['responses'].first
        expect(response['body']).to be_nil
        expect(response['source']).to eq('spec_example')
      end
    end
  end
end
