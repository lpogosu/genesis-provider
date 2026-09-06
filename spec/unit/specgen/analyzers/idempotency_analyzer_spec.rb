# frozen_string_literal: true

RSpec.describe SpecGen::Analyzers::IdempotencyAnalyzer do
  include Fixtures
  include RulesFixtures

  # The fixture dictionary: aliases Idempotency-Key, X-Idempotency-Key and
  # X-Request-Id; conflict status 409; strategy uuid_v5; send_when_optional.
  let(:rules) { load_rules }

  def analyze(paths)
    data = { 'openapi' => '3.0.3', 'paths' => paths }
    document = SpecGen::SpecLoader::Document.new(file: 'provider_api.yaml', version: '3.0.3',
                                                 family: :oas30, raw: data, data: data)
    described_class.call(document: document, profile: SpecGen::IR::ProviderProfile.new,
                         rules: rules)
  end

  def header(name, required: false)
    { 'name' => name, 'in' => 'header', 'required' => required, 'schema' => { 'type' => 'string', 'format' => 'uuid' } }
  end

  def response(schema)
    { 'description' => 'x', 'content' => { 'application/json' => { 'schema' => {
      'x-specgen-ref' => "#/components/schemas/#{schema}", 'type' => 'object'
    } } } }
  end

  def create(parameters: [header('Idempotency-Key')], responses: nil, security: nil)
    responses ||= { '201' => response('PayoutResponse'), '409' => response('PayoutResponse') }
    { 'operationId' => 'createPayout', 'tags' => ['Payouts'], 'parameters' => parameters,
      'requestBody' => { 'content' => { 'application/json' => { 'schema' => { 'type' => 'object' } } } },
      'responses' => responses, 'security' => security }.compact
  end

  def with_create(**options)
    analyze('/payouts' => { 'post' => create(**options) })
  end

  describe 'the header' do
    let(:profile) { with_create }

    it 'reads a header parameter that matches an alias, as a structural fact, and lists who accepts it' do
      idempotency = profile.idempotency

      expect(idempotency.header).to have_attributes(value: 'Idempotency-Key', source: :structural)
      expect(idempotency.header.evidence)
        .to eq('параметр-заголовок Idempotency-Key совпал с алиасом rules/idempotency.yml; принимают: createPayout' \
               '; объявлен required: false, но по rules/idempotency.yml (send_when_optional) ключ отправляется всегда')
      expect(idempotency.operations).to eq(['createPayout'])
      expect(idempotency.required).to be(false)
      expect(idempotency.json_path).to eq("$.paths['/payouts'].post.parameters[0]")
    end

    it 'takes the strategy from the dictionary and says why it is deterministic' do
      expect(profile.idempotency.strategy).to have_attributes(value: :uuid_v5, source: :registry)
      expect(profile.idempotency.strategy.evidence).to include('default_strategy uuid_v5', 'operation.id')
      expect(profile.idempotency.supported?).to be(true)
    end

    it 'recognises an industry alias such as X-Request-Id' do
      idempotency = with_create(parameters: [header('X-Request-Id', required: true)]).idempotency

      expect(idempotency.header.value).to eq('X-Request-Id')
      expect(idempotency.required).to be(true)
      expect(idempotency.header.evidence).not_to include('send_when_optional')
    end

    # Moov PayGate объявляет X-Idempotency-Key у создания перевода и
    # X-Request-ID у четырёх остальных операций. Порядок обхода отдавал
    # победу второму — заголовку трассировки, уникальному на каждый повтор.
    it 'prefers the header the dictionary ranks higher when several are declared' do
      profile = analyze('/status' => { 'get' => { 'operationId' => 'getStatus', 'tags' => ['Payouts'],
                                                  'parameters' => [header('X-Request-Id')],
                                                  'responses' => { '200' => response('PayoutResponse') } } },
                        '/payouts' => { 'post' => create(parameters: [header('X-Idempotency-Key')]) })

      expect(profile.idempotency.header.value).to eq('X-Idempotency-Key')
    end

    it 'never picks between two headers silently' do
      profile = analyze('/status' => { 'get' => { 'operationId' => 'getStatus', 'tags' => ['Payouts'],
                                                  'parameters' => [header('X-Request-Id')],
                                                  'responses' => { '200' => response('PayoutResponse') } } },
                        '/payouts' => { 'post' => create(parameters: [header('X-Idempotency-Key')]) })
      warning = profile.warnings.find { |item| item.code == :idempotency_header_ambiguous }

      expect(warning).not_to be_nil
      expect(warning.severity).to eq(:info)
      expect(warning.message).to include('выбран X-Idempotency-Key', 'отклонены: X-Request-Id')
    end

    it 'stays quiet when the same header is declared by every operation' do
      profile = analyze('/status' => { 'get' => { 'operationId' => 'getStatus', 'tags' => ['Payouts'],
                                                  'parameters' => [header('Idempotency-Key')],
                                                  'responses' => { '200' => response('PayoutResponse') } } },
                        '/payouts' => { 'post' => create })

      expect(profile.warnings.map(&:code)).not_to include(:idempotency_header_ambiguous)
    end

    it 'sees a header inherited from the path item' do
      profile = analyze('/payouts' => { 'parameters' => [header('X-Idempotency-Key')],
                                        'post' => create(parameters: []) })

      expect(profile.idempotency.header.value).to eq('X-Idempotency-Key')
      expect(profile.idempotency.json_path).to eq("$.paths['/payouts'].parameters[0]")
    end

    it 'ignores headers that are not idempotency keys' do
      profile = with_create(parameters: [header('X-Trace-Id')])

      expect(profile.idempotency).to be_nil
    end
  end

  describe 'the deduplication path' do
    it 'reads the conflict status whose schema is the success schema as dedup on 409' do
      idempotency = with_create.idempotency

      expect(idempotency.conflict_status).to have_attributes(value: 409, source: :structural)
      expect(idempotency.dedup?).to be(true)
      expect(idempotency.conflict_status.evidence)
        .to start_with('createPayout: 409 возвращает PayoutResponse — ту же схему, что 201')
    end

    it 'derives nothing when the conflict response carries an error schema, and asks the provider' do
      responses = { '201' => response('PayoutResponse'), '409' => response('ErrorResponse') }
      profile = with_create(responses: responses)
      warning = profile.warnings.first

      expect(profile.idempotency.conflict_status).to be_unknown
      expect(profile.idempotency.dedup?).to be(false)
      expect(warning).to have_attributes(code: :idempotency_dedup_unclear, severity: :warning,
                                         json_path: "$.paths['/payouts'].post")
      expect(warning.message).to include('Idempotency-Key объявлен', 'ответ 409 со схемой успешного ответа')
      expect(warning.suggested_overlay).to include("$.paths['/payouts'].post.responses", "'409':",
                                                   "$ref: '#/components/schemas/PayoutResponse'")
    end

    it 'derives nothing when no conflict response is declared at all' do
      profile = with_create(responses: { '201' => response('PayoutResponse') })

      expect(profile.idempotency.conflict_status).to be_unknown
      expect(profile.idempotency.conflict_status.evidence).to include('createPayout', '409')
      expect(profile.warnings.map(&:code)).to eq([:idempotency_dedup_unclear])
    end
  end

  describe 'a spec with no idempotency header' do
    it 'leaves idempotency nil and warns about duplicate payouts, aiming the overlay at the creating operation' do
      profile = analyze('/balance' => { 'get' => { 'operationId' => 'getBalance' } },
                        '/payouts' => { 'post' => create(parameters: []) })
      warning = profile.warnings.first

      expect(profile.idempotency).to be_nil
      expect(warning).to have_attributes(code: :idempotency_header_missing, severity: :warning,
                                         json_path: "$.paths['/payouts'].post")
      expect(warning.message).to include('Idempotency-Key, X-Idempotency-Key, X-Request-Id', 'вторую выплату')
      expect(warning.suggested_overlay).to include('- target: "$.paths[\'/payouts\'].post"', 'name: Idempotency-Key')
    end

    it 'falls back to the paths section when no operation creates anything' do
      profile = analyze('/balance' => { 'get' => { 'operationId' => 'getBalance' } })

      expect(profile.warnings.first.json_path).to eq('$.paths')
    end

    it 'says the same in English when the locale is switched' do
      SpecGen::Texts.locale = 'en'
      profile = analyze('/balance' => { 'get' => { 'operationId' => 'getBalance' } })

      expect(profile.warnings.first.message).to include('no operation declares an idempotency header')
    end
  end

  describe 'input the loader let through' do
    it 'does not raise on parameters or responses of the wrong shape' do
      paths = { '/payouts' => { 'post' => { 'operationId' => 'createPayout', 'parameters' => 'nope',
                                            'responses' => 'nope' } } }

      expect { analyze(paths) }.not_to raise_error
      expect(analyze(paths).idempotency).to be_nil
    end
  end

  describe 'on the spec as shipped' do
    let(:profile) do
      document = SpecGen::SpecLoader.load(spec_fixture('novapay.yaml'))
      described_class.call(document: document, profile: SpecGen::IR::ProviderProfile.new,
                           rules: SpecGen::Rules.load)
    end

    it 'reads the optional Idempotency-Key on payout creation with dedup on 409, and warns about nothing' do
      idempotency = profile.idempotency

      expect(idempotency.header.value).to eq('Idempotency-Key')
      expect(idempotency.operations).to eq(['createPayout'])
      expect(idempotency.required).to be(false)
      expect(idempotency.strategy.value).to eq(:uuid_v5)
      expect(idempotency.conflict_status.value).to eq(409)
      expect(idempotency.json_path).to eq("$.paths['/payouts'].post.parameters[0]")
      expect(profile.warnings).to be_empty
    end
  end
end
