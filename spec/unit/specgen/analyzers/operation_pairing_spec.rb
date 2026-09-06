# frozen_string_literal: true

RSpec.describe SpecGen::Analyzers::OperationPairing do
  include Fixtures

  # The shipped dictionaries: the weights that pick the pair are data, and an
  # example that stubbed them would prove nothing about the real ones.
  let(:rules) { SpecGen::Rules.load }

  def analyze(paths, extra = {})
    data = { 'openapi' => '3.0.3', 'paths' => paths }.merge(extra)
    document = SpecGen::SpecLoader::Document.new(file: 'provider_api.yaml', version: '3.0.3',
                                                 family: :oas30, raw: data, data: data)
    SpecGen::Analyzers::OperationAnalyzer.call(
      document: document, profile: SpecGen::IR::ProviderProfile.new, rules: rules
    )
  end

  def json_body(schema = { 'type' => 'object' })
    { 'required' => true, 'content' => { 'application/json' => { 'schema' => schema } } }
  end

  def json_response(schema, status = '200')
    { status => { 'description' => 'ok',
                  'content' => { 'application/json' => { 'schema' => schema } } } }
  end

  def object(name)
    { 'x-specgen-ref' => "#/components/schemas/#{name}", 'type' => 'object',
      'properties' => { 'id' => { 'type' => 'string' }, 'status' => { 'type' => 'string' } } }
  end

  def create(path, id, schema = object('Transfer'))
    { path => { 'post' => { 'operationId' => id, 'requestBody' => json_body,
                            'responses' => json_response(schema, '201') } } }
  end

  def read(path, id, schema = object('Transfer'))
    { path => { 'get' => { 'operationId' => id, 'responses' => json_response(schema) } } }
  end

  def codes(profile)
    profile.warnings.map(&:code)
  end

  def slot(profile, role)
    operation = profile.operation_for(role)
    operation && "#{operation.http_method.to_s.upcase} #{operation.path}"
  end

  describe 'a pair the spec relates by its own paths' do
    # The measured bug: two status candidates tie at the confidence ceiling,
    # and the winner was whichever the YAML declared first — Adyen Transfers
    # created /transfers and polled /transactions/{id}.
    let(:profile) do
      analyze(create('/transfers', 'post-transfers')
        .merge(read('/transactions/{id}', 'get-transactions-id', object('Transaction')))
        .merge(read('/transfers/{id}', 'get-transfers-id', object('TransferData'))))
    end

    it 'polls the resource it creates, not the one declared first' do
      expect(slot(profile, :create_payout)).to eq('POST /transfers')
      expect(slot(profile, :fetch_status)).to eq('GET /transfers/{id}')
    end

    it 'marks the chosen operations and leaves the runner-up unmarked' do
      chosen = profile.operations.select(&:primary).map(&:key)

      expect(chosen).to eq(%w[post-transfers get-transfers-id])
    end

    it 'says in the report which candidates tied and what broke the tie' do
      warning = profile.warnings.find { |item| item.code == :operation_tie }

      expect(warning.severity).to eq(:info)
      expect(warning.message)
        .to include('get-transactions-id', 'get-transfers-id')
        .and include('общий контейнер ресурса `transfers`')
    end

    it 'names the pairing in the evidence of the role it decided' do
      expect(profile.operation('get-transfers-id').role.evidence)
        .to include('пара с post-transfers выбрана согласованно')
    end
  end

  describe 'an ambiguous spec where nothing relates the two resources' do
    # Neither path, nor schema, nor a link says these belong together, and the
    # tool must not pretend otherwise: it takes the pair and says so.
    let(:profile) do
      analyze(create('/payouts', 'createPayout', object('Payout'))
        .merge(read('/transactions/{id}', 'getTransaction', object('Transaction'))))
    end

    it 'still fills both slots' do
      expect([slot(profile, :create_payout), slot(profile, :fetch_status)])
        .to eq(['POST /payouts', 'GET /transactions/{id}'])
    end

    it 'warns that the service would create one resource and read another' do
      warning = profile.warnings.find { |item| item.code == :operation_pair_mismatch }

      expect(warning).to have_attributes(severity: :warning,
                                         json_path: "$.paths['/payouts'].post")
      expect(warning.message).to include('POST /payouts', 'GET /transactions/{id}')
    end

    it 'offers the Link Object that would settle it, targeting the created response' do
      warning = profile.warnings.find { |item| item.code == :operation_pair_mismatch }

      expect(warning.suggested_overlay)
        .to include("- target: \"$.paths['/payouts'].post.responses['201']\"")
        .and include('operationId: getTransaction')
        .and include('$response.body#/id')
      expect(YAML.safe_load(warning.suggested_overlay)).to be_an(Array)
    end

    it 'says in the evidence that the choice was made alone' do
      expect(profile.operation('getTransaction').role.evidence)
        .to include('спецификация не связывает её с createPayout')
    end
  end

  describe 'a spec that declares the relation formally' do
    let(:linked) do
      paths = create('/payouts', 'createPayout', object('Payout'))
              .merge(read('/transactions/{id}', 'getTransaction', object('Transaction')))
      paths['/payouts']['post']['responses']['201']['links'] = {
        'status' => { 'operationId' => 'getTransaction',
                      'parameters' => { 'id' => '$response.body#/id' } }
      }
      paths
    end

    it 'follows the link instead of the heuristics and says so' do
      profile = analyze(linked)
      role = profile.operation('getTransaction').role

      expect(slot(profile, :fetch_status)).to eq('GET /transactions/{id}')
      expect(role.source).to eq(:structural)
      expect(role.confidence).to eq(1.0)
      expect(role.evidence).to include('OpenAPI Link Object status', 'id = $response.body#/id')
    end

    it 'reports no mismatch once the spec has said it itself' do
      expect(codes(analyze(linked))).not_to include(:operation_pair_mismatch)
    end

    it 'reads operationRef as well as operationId' do
      paths = linked
      paths['/payouts']['post']['responses']['201']['links']['status'] =
        { 'operationRef' => '#/paths/~1transactions~1{id}/get' }
      profile = analyze(paths)

      expect(profile.operation('getTransaction').role.source).to eq(:structural)
    end

    it 'gives the role to the link target even when the votes did not' do
      paths = create('/payouts', 'createPayout', object('Payout'))
              .merge(read('/receipts/{id}', 'getReceipt', object('Receipt')))
      paths['/payouts']['post']['responses']['201']['links'] = {
        'poll' => { 'operationId' => 'getReceipt' }
      }
      profile = analyze(paths)

      expect(profile.operation('getReceipt').role.value).to eq(:fetch_status)
      expect(slot(profile, :fetch_status)).to eq('GET /receipts/{id}')
    end

    it 'reports a link that points nowhere instead of following it' do
      paths = linked
      paths['/payouts']['post']['responses']['201']['links']['status'] =
        { 'operationId' => 'getNothing' }
      profile = analyze(paths)

      expect(codes(profile)).to include(:spec_element_unsupported)
      expect(profile.warnings.map(&:message).join).to include('"getNothing"')
    end
  end

  describe 'cancellation follows the pair' do
    it 'takes the cancel endpoint of the same resource' do
      paths = create('/transfers', 'post-transfers')
              .merge(read('/transfers/{id}', 'get-transfers-id'))
      paths['/transfers/{id}/cancel'] = {
        'post' => { 'operationId' => 'cancelTransfer', 'responses' => json_response(object('T')) }
      }
      paths['/payments/{id}/cancel'] = {
        'post' => { 'operationId' => 'cancelPayment', 'responses' => json_response(object('P')) }
      }

      expect(slot(analyze(paths), :cancel)).to eq('POST /transfers/{id}/cancel')
    end
  end

  describe 'the spec as shipped' do
    let(:profile) do
      document = SpecGen::SpecLoader.load(spec_fixture('novapay.yaml'))
      SpecGen::Analyzers::OperationAnalyzer.call(document: document,
                                                 profile: SpecGen::IR::ProviderProfile.new,
                                                 rules: rules)
    end

    # One candidate per slot: there is nothing to disambiguate, so the report
    # must stay exactly as it was — silence is the correct output here.
    it 'keeps the same three operations and says nothing extra about them' do
      expect([slot(profile, :create_payout), slot(profile, :fetch_status),
              slot(profile, :cancel)])
        .to eq(['POST /payouts', 'GET /payouts/{payout_id}', 'POST /payouts/{payout_id}/cancel'])
      expect(codes(profile)).not_to include(:operation_tie, :operation_pair_mismatch)
      expect(profile.operation('createPayout').role.evidence).not_to include('пара')
    end
  end
end
