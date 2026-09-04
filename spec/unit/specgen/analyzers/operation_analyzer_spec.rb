# frozen_string_literal: true

RSpec.describe SpecGen::Analyzers::OperationAnalyzer do
  include Fixtures

  # The shipped dictionaries: the weights that decide a role are data, and
  # an example that stubbed them would prove nothing about the real ones.
  let(:rules) { SpecGen::Rules.load }

  def analyze(paths)
    data = { 'openapi' => '3.0.3', 'paths' => paths }
    document = SpecGen::SpecLoader::Document.new(file: 'provider_api.yaml', version: '3.0.3',
                                                 family: :oas30, raw: data, data: data)
    described_class.call(document: document, profile: SpecGen::IR::ProviderProfile.new,
                         rules: rules)
  end

  def only(paths)
    analyze(paths).operations.first
  end

  def json_body(schema = { 'type' => 'object' }, **rest)
    { 'required' => true, 'content' => { 'application/json' => { 'schema' => schema }.merge(rest) } }
  end

  def role_of(paths)
    only(paths).role
  end

  def codes(profile)
    profile.warnings.map(&:code)
  end

  describe 'roles the contract has a method for' do
    it 'reads a payout creation out of the name, the path, the method and the body' do
      role = role_of('/payouts' => { 'post' => { 'operationId' => 'createPayout',
                                                 'tags' => ['Payouts'],
                                                 'requestBody' => json_body } })

      expect(role.value).to eq(:create_payout)
      expect(role.source).to eq(:heuristic)
      expect(role.confidence).to eq(0.95)
      expect(role.evidence).to include('operation_id 5.0', 'path_tail 3.0', 'http_method 2.0')
        .and include('из 14.0 поданных голосов')
    end

    it 'tells a deposit from a payout by the noun, not by the verb' do
      role = role_of('/deposits' => { 'post' => { 'operationId' => 'createDeposit',
                                                  'requestBody' => json_body } })

      expect(role.value).to eq(:create_deposit)
    end

    it 'reads a status poll from a path that ends in a parameter' do
      operation = only('/payouts/{payout_id}' => { 'get' => { 'operationId' => 'getPayoutStatus',
                                                              'tags' => ['Payouts'] } })

      expect(operation.role.value).to eq(:fetch_status)
      expect(operation.contract?).to be(true)
      expect(operation.role.evidence).to include('path_tail 3.0')
    end

    it 'reads an inbound webhook from security: [] as much as from its name' do
      operation = only('/webhooks/payout' => { 'post' => { 'operationId' => 'payoutWebhook',
                                                           'tags' => ['Webhooks'],
                                                           'security' => [],
                                                           'requestBody' => json_body } })

      expect(operation.role.value).to eq(:webhook)
      expect(operation.secured).to be(false)
      expect(operation.role.evidence).to include('unsecured 4.0')
    end
  end

  describe 'roles the contract has no method for' do
    it 'recognises a cancellation and says it is not mapped to the contract' do
      profile = analyze('/payouts/{id}/cancel' => { 'post' => { 'operationId' => 'cancelPayout',
                                                                'tags' => ['Payouts'] } })
      operation = profile.operations.first

      expect(operation.role.value).to eq(:cancel)
      expect(operation.contract?).to be(false)
      expect(operation.unmapped?).to be(false)
      expect(profile.warnings.first).to have_attributes(code: :operation_unmapped, severity: :info)
      expect(profile.warnings.first.message).to include('вне контракта')
    end

    it 'recognises a balance endpoint the same way' do
      profile = analyze('/balance' => { 'get' => { 'operationId' => 'getBalance' } })

      expect(profile.operations.first.role.value).to eq(:balance)
      expect(profile.warnings.map(&:severity)).to eq([:info])
    end
  end

  describe 'when the signals disagree' do
    it 'assigns no role when two of them fit equally well, and shows the arithmetic' do
      profile = analyze('/payouts' => { 'post' => { 'operationId' => 'receiveCallback',
                                                    'requestBody' => json_body } })
      warning = profile.warnings.first

      expect(profile.operations.first.unmapped?).to be(true)
      expect(warning).to have_attributes(code: :operation_role_ambiguous, severity: :warning,
                                         json_path: "$.paths['/payouts'].post")
      expect(warning.message)
        .to include('create_payout 8.0', 'webhook 8.0', 'из 13.0 поданных голосов')
    end

    it 'assigns no role when nothing but the method and the body voted' do
      profile = analyze('/things' => { 'patch' => { 'requestBody' => json_body } })

      expect(profile.operations.first.role.value).to eq(:unmapped)
      expect(profile.operations.first.role.confidence).to eq(0.0)
      expect(codes(profile)).to include(:operation_unmapped)
      expect(profile.warnings.map(&:message).join)
        .to include('слишком мало признаков того, для чего эта операция')
    end

    it 'still derives a role from method, path and tag when there is no operationId' do
      profile = analyze('/payouts' => { 'post' => { 'tags' => ['Payouts'],
                                                    'requestBody' => json_body } })
      operation = profile.operations.first

      expect(operation.role.value).to eq(:create_payout)
      expect(operation.key).to eq('POST /payouts')
      expect(profile.warnings.first).to have_attributes(code: :operation_id_missing, severity: :info)
      expect(profile.warnings.first.message).to include('"POST /payouts"')
    end
  end

  describe 'parameters' do
    it 'inherits the parameters of the path item and lets the operation override them' do
      shared = [{ 'name' => 'payout_id', 'in' => 'path', 'schema' => { 'type' => 'string' } },
                { 'name' => 'trace', 'in' => 'header', 'schema' => { 'type' => 'string' } }]
      own = [{ 'name' => 'trace', 'in' => 'header', 'required' => true,
               'description' => 'overridden', 'schema' => { 'type' => 'string' } },
             { 'name' => 'expand', 'in' => 'query', 'schema' => { 'type' => 'string' } }]
      operation = only('/payouts/{payout_id}' => { 'parameters' => shared,
                                                   'get' => { 'operationId' => 'getPayoutStatus',
                                                              'parameters' => own } })

      expect(operation.parameters.map(&:name)).to eq(%w[payout_id trace expand])
      expect(operation.parameters[1]).to have_attributes(required: true, description: 'overridden',
                                                         json_path: "$.paths['/payouts/{payout_id}'].get.parameters[0]")
    end

    it 'marks a path parameter required even when the spec forgets to' do
      operation = only('/payouts/{payout_id}' => {
                         'get' => { 'operationId' => 'getPayoutStatus',
                                    'parameters' => [{ 'name' => 'payout_id', 'in' => 'path',
                                                       'schema' => { 'type' => 'string',
                                                                     'format' => 'uuid' },
                                                       'example' => 'np_1' }] }
                       })
      parameter = operation.parameters.first

      expect(parameter).to have_attributes(name: 'payout_id', location: :path, required: true,
                                           type: 'string', format: 'uuid', example: 'np_1')
      expect(parameter.role.value).to eq(:provider_operation_id)
      expect(parameter.role.source).to eq(:registry)
      expect(parameter.role.evidence).to include('расположение параметра — путь')
    end
  end

  describe 'request body and responses' do
    it 'names a referenced schema by its component and an inline one by where it sits' do
      referenced = { 'x-specgen-ref' => '#/components/schemas/CreatePayoutRequest',
                     'type' => 'object' }
      operation = only('/payouts' => { 'post' => { 'operationId' => 'createPayout',
                                                   'requestBody' => json_body(referenced),
                                                   'responses' => { '200' => {
                                                     'content' => { 'application/json' => {
                                                       'schema' => { 'type' => 'object' }
                                                     } }
                                                   } } } })

      expect(operation).to have_attributes(request_schema: 'CreatePayoutRequest',
                                           request_required: true,
                                           request_media_type: 'application/json')
      expect(operation.responses.first.schema).to eq('createPayout.responses.200')
    end

    it 'synthesises a body schema name from method and path when there is no operationId' do
      operation = only('/payouts' => { 'post' => { 'requestBody' => json_body } })

      expect(operation.request_schema).to eq('post_payouts.requestBody')
    end

    it 'reads named examples and a bare example the same way' do
      named = json_body({ 'type' => 'object' },
                        'examples' => { 'sbp' => { 'summary' => 'СБП', 'value' => { 'a' => 1 } } })
      bare = { 'description' => 'ok',
               'content' => { 'application/json' => { 'example' => { 'b' => 2 } } } }
      operation = only('/payouts' => { 'post' => { 'operationId' => 'createPayout',
                                                   'requestBody' => named,
                                                   'responses' => { '201' => bare } } })

      expect(operation.request_examples).to eq('sbp' => { 'a' => 1 })
      expect(operation.responses.first.examples).to eq('default' => { 'b' => 2 })
    end

    it 'keeps declared response headers, ranges and the default response' do
      responses = { '200' => { 'description' => 'ok' },
                    '429' => { 'description' => 'slow down',
                               'headers' => { 'Retry-After' => { 'schema' => {
                                 'type' => 'integer'
                               } } } },
                    '4xx' => { 'description' => 'client error' },
                    'default' => { 'description' => 'anything else' } }
      operation = only('/balance' => { 'get' => { 'operationId' => 'getBalance',
                                                  'responses' => responses } })

      expect(operation.responses.map(&:status)).to eq(%w[200 429 4XX default])
      expect(operation.response('429').header?('retry-after')).to be(true)
      expect(operation.responses.last.json_path).to eq("$.paths['/balance'].get.responses.default")
    end

    it 'falls back to the media type the spec does offer' do
      body = { 'content' => { 'application/xml' => { 'schema' => { 'type' => 'object' } } } }
      operation = only('/payouts' => { 'post' => { 'operationId' => 'createPayout',
                                                   'requestBody' => body } })

      expect(operation.request_media_type).to eq('application/xml')
      expect(operation.request_required).to be(false)
    end
  end

  describe 'input the loader let through' do
    it 'reports parameters that are not a list and keeps the operation' do
      profile = analyze('/payouts' => { 'post' => { 'operationId' => 'createPayout',
                                                    'parameters' => 'payout_id' } })

      expect(profile.operations.size).to eq(1)
      expect(profile.warnings.first)
        .to have_attributes(code: :spec_element_unsupported,
                            json_path: "$.paths['/payouts'].post.parameters")
    end

    it 'reports a parameter without a name or a known location' do
      parameters = [{ 'in' => 'header' }, { 'name' => 'x', 'in' => 'body' }]
      profile = analyze('/payouts' => { 'post' => { 'operationId' => 'createPayout',
                                                    'parameters' => parameters } })

      expect(profile.operations.first.parameters).to be_empty
      expect(profile.warnings.map(&:json_path))
        .to include("$.paths['/payouts'].post.parameters[0]",
                    "$.paths['/payouts'].post.parameters[1]")
    end

    it 'reports responses of the wrong shape and a key that is not a status' do
      profile = analyze('/a' => { 'post' => { 'operationId' => 'createPayout',
                                              'responses' => { 'okay' => {} } } },
                        '/b' => { 'get' => { 'operationId' => 'getBalance',
                                             'responses' => 'none' } })

      expect(profile.operations.map(&:responses)).to eq([[], []])
      expect(profile.warnings.map(&:message).join)
        .to include('ключ ответа "okay"').and include('`responses` должен быть объектом')
    end

    it 'reports tags of the wrong shape without losing the operation' do
      profile = analyze('/payouts' => { 'post' => { 'operationId' => 'createPayout',
                                                    'tags' => 'Payouts' } })

      expect(profile.operations.first.tags).to eq([])
      expect(codes(profile)).to include(:spec_element_unsupported)
    end

    it 'skips a path item that is not an object and a paths section that is not one either' do
      expect { analyze('/payouts' => 'post') }.not_to raise_error
      expect(analyze('/payouts' => 'post').operations).to be_empty
    end
  end

  describe 'on the spec as shipped' do
    let(:profile) do
      document = SpecGen::SpecLoader.load(spec_fixture('novapay.yaml'))
      described_class.call(document: document, profile: SpecGen::IR::ProviderProfile.new,
                           rules: rules)
    end

    it 'maps every operation of the spec, in spec order' do
      expect(profile.operations.map(&:key))
        .to eq(%w[createPayout getPayoutStatus cancelPayout payoutWebhook getBalance])
      expect(profile.operations.map { |operation| operation.role.value })
        .to eq(%i[create_payout fetch_status cancel webhook balance])
      expect(profile.operations.map { |operation| operation.role.confidence })
        .to all(be > 0.8)
    end

    it 'reads the payout creation in full' do
      operation = profile.operation('createPayout')

      expect(operation).to have_attributes(http_method: :post, path: '/payouts',
                                           request_schema: 'CreatePayoutRequest',
                                           request_required: true, secured: true,
                                           json_path: "$.paths['/payouts'].post")
      expect(operation.parameters.map(&:name)).to eq(['Idempotency-Key'])
      expect(operation.request_examples.keys).to eq(['sbp_payout'])
      expect(operation.responses.map(&:status)).to eq(%w[201 400 401 402 409 422 429 500])
      expect(operation.response('409').schema).to eq('PayoutResponse')
      expect(operation.response('429').header?('Retry-After')).to be(true)
    end

    it 'reads the webhook as unsecured and names its inline response schema' do
      operation = profile.operation('payoutWebhook')

      expect(operation.secured).to be(false)
      expect(operation.request_schema).to eq('WebhookPayload')
      expect(operation.request_examples.keys).to eq(%w[completed failed])
      expect(operation.responses.first.schema).to eq('payoutWebhook.responses.200')
    end

    it 'warns only about the two endpoints the contract has no method for' do
      expect(profile.warnings.map { |warning| [warning.code, warning.severity] }.uniq)
        .to eq([%i[operation_unmapped info]])
      expect(profile.sorted_warnings.map(&:json_path))
        .to eq(["$.paths['/balance'].get", "$.paths['/payouts/{payout_id}/cancel'].post"])
    end
  end
end
