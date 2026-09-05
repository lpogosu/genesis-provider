# frozen_string_literal: true

require 'json'
require 'rack/mock_request'
require 'specgen/web'

RSpec.describe SpecGen::Web::App do
  include Fixtures

  # Каталог тот же, что у пакетного прогона: семь спецификаций, три из них
  # чужие. Каталог статики намеренно несуществующий — сервер обязан
  # подниматься без собранного фронта.
  def specs_dir
    File.join(SpecGen::ROOT, 'spec', 'fixtures', 'specs')
  end

  def request
    @request ||= Rack::MockRequest.new(
      SpecGen::Web.app(specs_dir: specs_dir, public_dir: File.join(SpecGen::ROOT, 'no-public'))
    )
  end

  def post(path, payload)
    request.post(path, input: JSON.generate(payload), 'CONTENT_TYPE' => 'application/json')
  end

  def json(response)
    JSON.parse(response.body)
  end

  describe 'GET /api/health' do
    it 'answers with status, version and locale' do
      response = request.get('/api/health')

      expect(response.status).to eq(200)
      expect(response.headers['content-type']).to eq('application/json; charset=utf-8')
      expect(json(response)).to eq('status' => 'ok', 'version' => SpecGen::VERSION, 'locale' => 'ru')
    end

    it 'allows any origin so the front end may live on another port' do
      response = request.get('/api/health')

      expect(response.headers['access-control-allow-origin']).to eq('*')
    end
  end

  describe 'OPTIONS' do
    it 'answers the preflight request without a body' do
      response = request.options('/api/generate')

      expect(response.status).to eq(204)
      expect(response.headers['access-control-allow-methods']).to include('POST')
    end
  end

  describe 'GET /api/specs' do
    it 'lists every specification of the directory with its title' do
      specs = json(request.get('/api/specs'))['specs']

      expect(specs.size).to eq(7)
      expect(specs.map { |spec| spec['id'] }).to include('novapay', 'broken', 'paypal_payouts_v1')
      novapay = specs.find { |spec| spec['id'] == 'novapay' }
      expect(novapay).to include('file' => 'novapay.yaml', 'title' => 'NovaPay Payout API',
                                 'openapi' => '3.0.3', 'own' => true)
      expect(novapay['bytes']).to be > 0
    end

    it 'marks specifications of other vendors as not our own' do
      specs = json(request.get('/api/specs'))['specs']
      foreign = specs.reject { |spec| spec['own'] }

      expect(foreign.map { |spec| spec['file'] }).to all(start_with('real/'))
      expect(foreign.size).to eq(3)
    end
  end

  describe 'POST /api/generate' do
    it 'returns four artifacts in the order of the pipeline' do
      body = json(post('/api/generate', spec_id: 'novapay'))

      expect(body['provider']).to eq('novapay')
      expect(body['artifacts'].map { |artifact| artifact['kind'] })
        .to eq(%w[service integration fixtures report])
      expect(body['artifacts'].map { |artifact| artifact['filename'] })
        .to eq(['novapay_service.rb', 'INTEGRATION.md', 'fixtures.json', 'report.md'])
    end

    it 'fills every artifact with content, size and language' do
      artifacts = json(post('/api/generate', spec_id: 'novapay'))['artifacts']

      artifacts.each do |artifact|
        expect(artifact['content']).not_to be_empty
        expect(artifact['bytes']).to eq(artifact['content'].bytesize)
        expect(artifact['lines']).to be > 0
      end
      expect(artifacts.map { |artifact| artifact['language'] })
        .to eq(%w[ruby markdown json markdown])
    end

    it 'reports the summary of the analysis in numbers and ready phrases' do
      summary = json(post('/api/generate', spec_id: 'novapay'))['summary']

      expect(summary['coverage_percent']).to be_a(Integer)
      expect(summary['operations']).to eq(summary['operations_with_role'])
      expect(summary['warnings']['total'])
        .to eq(summary['warnings'].values_at('error', 'warning', 'info').sum)
      expect(summary['units']).to include('minor')
      expect(summary['base_url']).to start_with('https://')
      expect(summary['webhook']).to include('present' => true)
      expect(summary['idempotency_header']).to eq('Idempotency-Key')
    end

    it 'writes nothing into the output directory of the command line' do
      before = Dir.glob(File.join(SpecGen::ROOT, 'output', '*'))
      post('/api/generate', spec_id: 'novapay')

      expect(Dir.glob(File.join(SpecGen::ROOT, 'output', '*'))).to eq(before)
    end

    it 'accepts an uploaded specification instead of a catalogue name' do
      body = json(post('/api/generate', filename: 'acme.yaml', provider: 'acme',
                                        content: File.read(spec_fixture('cardpay.yaml'))))

      expect(body['provider']).to eq('acme')
      expect(body['artifacts'].first['filename']).to eq('acme_service.rb')
      expect(body['summary']['operations']).to be > 0
    end

    it 'answers with the error envelope when the specification is broken' do
      response = post('/api/generate', filename: 'acme.yaml', content: "openapi: 3.0.3\n")

      expect(response.status).to eq(422)
      error = json(response)['error']
      expect(error['message']).not_to be_empty
      expect(error['location']).to eq('$.paths')
      expect(error['file']).to eq('acme.yaml')
      expect(response.body).not_to include('.rb:')
    end

    it 'refuses a catalogue name that tries to leave the directory' do
      response = post('/api/generate', spec_id: '../../Gemfile')

      expect(response.status).to eq(422)
      expect(json(response)['error']['code']).to eq('spec_unknown')
    end

    it 'refuses a body that is not JSON' do
      response = request.post('/api/generate', input: '{oops')

      expect(response.status).to eq(400)
      expect(json(response)['error']['code']).to eq('invalid_json')
    end

    it 'refuses a body above the size limit' do
      oversized = 'x' * (SpecGen::Web::Params::MAX_BODY_BYTES + 1)
      response = request.post('/api/generate', input: oversized)

      expect(response.status).to eq(413)
      expect(json(response)['error']['code']).to eq('body_too_large')
    end
  end

  describe 'POST /api/analyze' do
    it 'answers with the summary alone, without artifacts' do
      body = json(post('/api/analyze', spec_id: 'novapay'))

      expect(body.keys).to contain_exactly('provider', 'summary', 'warnings')
      expect(body['warnings'].first.keys)
        .to contain_exactly('code', 'severity', 'message', 'json_path', 'suggested_overlay')
    end

    it 'follows the locale of the request' do
      body = json(post('/api/analyze', spec_id: 'novapay', locale: 'en'))

      expect(body['summary']['units']).to include('minor')
      expect(json(request.get('/api/health'))['locale']).to eq('ru')
    end
  end

  describe 'GET /api/batch' do
    it 'runs every specification of the directory and keeps failures as rows' do
      body = json(request.get('/api/batch'))

      expect(body['total']).to eq(7)
      expect(body['rows'].size).to eq(7)
      row = body['rows'].find { |candidate| candidate['provider'] == 'novapay' }
      expect(row).to include('file' => 'novapay.yaml', 'artifacts' => 4, 'error' => nil)
      expect(row['coverage_percent']).to be_a(Integer)
    end
  end

  describe 'unknown routes' do
    it 'answers 404 with the same envelope' do
      response = request.get('/api/nothing')

      expect(response.status).to eq(404)
      expect(json(response)['error']['code']).to eq('route_not_found')
    end

    it 'answers 404 for a page when the front end is not built' do
      response = request.get('/index.html')

      expect(response.status).to eq(404)
    end
  end

  # Фронт собирается отдельно и в репозиторий не попадает, поэтому статику
  # проверяем на временном каталоге, а не на public/: тест обязан работать и
  # до первой сборки.
  describe 'the built front end' do
    around do |example|
      Dir.mktmpdir('specgen-public') do |dir|
        File.binwrite(File.join(dir, 'index.html'), '<!DOCTYPE html><title>ok</title>')
        Dir.mkdir(File.join(dir, 'assets'))
        File.binwrite(File.join(dir, 'assets', 'app.js'), 'console.log(1)')
        @public_dir = dir
        example.run
      end
    end

    def serve(path)
      Rack::MockRequest.new(SpecGen::Web.app(specs_dir: specs_dir, public_dir: @public_dir)).get(path)
    end

    it 'serves the page itself and its assets with their own content types' do
      expect(serve('/').status).to eq(200)
      expect(serve('/').headers['content-type']).to include('text/html')
      expect(serve('/assets/app.js').headers['content-type']).to include('text/javascript')
    end

    it 'answers an address without an extension with the page: the front end routes it itself' do
      response = serve('/some-route')

      expect(response.status).to eq(200)
      expect(response.body).to include('<title>ok</title>')
    end

    # Отдать index.html вместо отсутствующего скрипта значит спрятать
    # причину: браузер попытается разобрать HTML как JavaScript и назовёт
    # синтаксическую ошибку вместо неверного пути.
    it 'answers a missing asset with 404 instead of the page' do
      response = serve('/assets/missing.js')

      expect(response.status).to eq(404)
      expect(response.body).not_to include('<title>ok</title>')
    end

    it 'refuses to read anything outside the directory' do
      expect(serve('/../../Gemfile').status).to eq(404)
    end
  end
end
