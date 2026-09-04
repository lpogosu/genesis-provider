# frozen_string_literal: true

RSpec.describe SpecGen::Analyzers::InfoAnalyzer do
  include Fixtures

  # InfoAnalyzer reads no dictionaries: identity comes from the spec and
  # from the command line, so `rules` is deliberately nil in these examples.
  def analyze(data, options: {}, file: 'provider_api.yaml', version: '3.0.3', family: :oas30)
    document = SpecGen::SpecLoader::Document.new(file: file, version: version, family: family,
                                                 raw: data, data: data)
    described_class.call(document: document, profile: SpecGen::IR::ProviderProfile.new,
                         rules: nil, options: options)
  end

  def with_title(title, options: {})
    analyze({ 'info' => { 'title' => title } }, options: options)
  end

  def with_servers(*entries)
    analyze({ 'info' => { 'title' => 'AcmePay API' }, 'servers' => entries })
  end

  def codes(profile)
    profile.warnings.map(&:code)
  end

  describe 'provider name' do
    it 'takes --provider as certain, without second-guessing it by the title' do
      name = with_title('AcmePay Payout API', options: { provider: 'acmepay' }).info.name

      expect(name.value).to eq('acmepay')
      expect(name.source).to eq(:structural)
      expect(name.confidence).to eq(1.0)
      expect(name.evidence).to eq('--provider acmepay')
    end

    it 'slugifies what --provider was given, so the name is usable as a file name' do
      expect(with_title('x', options: { provider: 'Acme Bank!' }).info.name.value).to eq('acme_bank')
    end

    it 'derives the name from info.title, keeping a camel-case brand as one word' do
      name = with_title('NovaPay Payout API').info.name

      expect(name.value).to eq('novapay')
      expect(name.source).to eq(:heuristic)
      expect(name.confidence).to eq(0.8)
      expect(name.evidence).to eq('из info.title "NovaPay Payout API" -> novapay')
    end

    it 'keeps every word the industry vocabulary does not explain, with less confidence' do
      name = with_title('Acme Bank Payout API v2').info.name

      expect(name.value).to eq('acme_bank')
      expect(name.confidence).to eq(0.6)
    end

    it 'derives nothing from a title that is only industry vocabulary, and says so' do
      profile = with_title('Payment Gateway API')

      expect(profile.info.name).to be_unknown
      expect(profile.warnings.first).to have_attributes(code: :provider_name_unknown,
                                                        severity: :error,
                                                        json_path: '$.info.title')
      expect(profile.warnings.first.message).to include('--provider')
    end

    it 'derives nothing when the document has no info section at all' do
      profile = analyze({})

      expect(profile.info.name).to be_unknown
      expect(codes(profile)).to include(:provider_name_unknown)
    end
  end

  describe 'base URL variable' do
    it 'names the ENV variable after the provider' do
      env = with_title('Acme Bank Payout API').info.base_url_env

      expect(env.value).to eq('ACME_BANK_BASE_URL')
      expect(env.evidence).to include('соглашение: <PROVIDER>_BASE_URL')
    end

    it 'is exactly as certain as the provider name it was built from' do
      from_flag = with_title('Acme API', options: { provider: 'acmepay' }).info.base_url_env
      from_title = with_title('Acme Bank Payout API').info.base_url_env

      expect(from_flag).to have_attributes(value: 'ACMEPAY_BASE_URL', source: :structural,
                                           confidence: 1.0)
      expect(from_title).to have_attributes(source: :heuristic, confidence: 0.6)
    end

    it 'stays unknown when the provider name is unknown' do
      expect(with_title('Payment Gateway API').info.base_url_env).to be_unknown
    end
  end

  describe 'facts read straight off the document' do
    it 'copies title and version verbatim and names the spec by its basename' do
      data = { 'info' => { 'title' => 'AcmePay API', 'version' => '2.1.0' } }
      info = analyze(data, file: File.join('specs', 'acme', 'api.yaml'),
                           version: '3.1.0', family: :oas31).info

      expect(info).to have_attributes(title: 'AcmePay API', spec_version: '2.1.0',
                                      oas_version: '3.1.0', oas_family: :oas31,
                                      spec_file: 'api.yaml', overlay_file: nil)
      expect(info.oas31?).to be(true)
    end

    it 'leaves title and version nil when the spec omits them' do
      info = analyze({ 'info' => { 'contact' => { 'name' => 'AcmePay' } } }).info

      expect(info.title).to be_nil
      expect(info.spec_version).to be_nil
    end
  end

  describe 'servers' do
    it 'reads the environment from the description, in spec order' do
      profile = with_servers({ 'url' => 'https://api.sandbox.acme.example/v1', 'description' => 'Sandbox' },
                             { 'url' => 'https://api.acme.example/v1', 'description' => 'Production' })

      expect(profile.servers.map { |server| server.environment.value }).to eq(%i[sandbox production])
      expect(profile.servers.map(&:json_path)).to eq(['$.servers[0]', '$.servers[1]'])
      expect(profile.servers.first.environment)
        .to have_attributes(source: :heuristic, confidence: 0.8)
      expect(profile.servers.last.environment.evidence)
        .to eq('описание сервера "Production" содержит "production" -> production')
      expect(profile.warnings).to be_empty
    end

    it 'falls back to the host when the description says nothing an ASCII lexicon knows' do
      profile = with_servers({ 'url' => 'https://api.sandbox.acme.example/v1',
                               'description' => 'Основной хост' })

      expect(profile.servers.first.environment)
        .to have_attributes(value: :sandbox, source: :heuristic, confidence: 0.7)
      expect(profile.servers.first.environment.evidence).to include('хост сервера')
    end

    it 'recognises a production host as well' do
      profile = with_servers({ 'url' => 'https://live.acme.example' })

      expect(profile.servers.first.environment.value).to eq(:production)
    end

    it 'prefers sandbox when a host claims both, because the opposite mistake costs a payment' do
      profile = with_servers({ 'url' => 'https://sandbox.live.acme.example' })

      expect(profile.servers.first.environment.value).to eq(:sandbox)
    end

    it 'does not choke on a templated URL' do
      profile = with_servers({ 'url' => 'https://{region}.api.acme.example/{version}',
                               'description' => 'Production' })

      expect(profile.servers.first)
        .to have_attributes(url: 'https://{region}.api.acme.example/{version}')
      expect(profile.servers.first.environment.value).to eq(:production)
    end

    it 'leaves the environment unknown and warns instead of guessing' do
      profile = with_servers({ 'url' => 'https://api.acme.example/v1', 'description' => 'Main host' })
      warning = profile.warnings.first

      expect(profile.servers.first.environment).to be_unknown
      expect(warning).to have_attributes(code: :server_environment_unknown, severity: :info,
                                         json_path: '$.servers[0]')
      expect(warning.fixable?).to be(true)
      expect(warning.suggested_overlay).to include('- target: "$.servers[0]"')
    end

    it 'warns once when the spec declares no servers at all' do
      profile = analyze({ 'info' => { 'title' => 'AcmePay API' } })

      expect(profile.servers).to be_empty
      expect(codes(profile)).to eq([:spec_element_unsupported])
      expect(profile.warnings.first).to have_attributes(json_path: '$.servers')
      expect(profile.warnings.first.suggested_overlay).to include('servers:')
    end
  end

  describe 'input the loader let through' do
    it 'does not raise when servers is not a list' do
      profile = nil

      expect { profile = analyze({ 'servers' => 'https://api.acme.example' }) }.not_to raise_error
      expect(profile.servers).to be_empty
      expect(profile.warnings.map(&:json_path)).to include('$.servers')
    end

    it 'skips entries that are not a mapping or carry no url string' do
      profile = with_servers('https://api.acme.example',
                             { 'url' => 42 },
                             { 'description' => 'Production' },
                             { 'url' => 'https://api.acme.example', 'description' => 'Production' })

      expect(profile.servers.map(&:url)).to eq(['https://api.acme.example'])
      expect(profile.warnings.map(&:json_path)).to eq(['$.servers[0]', '$.servers[1]', '$.servers[2]'])
      expect(codes(profile).uniq).to eq([:spec_element_unsupported])
    end

    it 'survives an info section of the wrong shape' do
      profile = nil

      expect { profile = analyze({ 'info' => 'AcmePay' }) }.not_to raise_error
      expect(profile.info.title).to be_nil
      expect(profile.info.name).to be_unknown
    end
  end

  describe 'on the spec as shipped' do
    let(:profile) do
      document = SpecGen::SpecLoader.load(spec_fixture('novapay.yaml'))
      described_class.call(document: document, profile: SpecGen::IR::ProviderProfile.new, rules: nil)
    end

    it 'derives the provider identity without a single flag' do
      expect(profile.info).to have_attributes(title: 'NovaPay Payout API', spec_version: '1.0.0',
                                              oas_version: '3.0.3', oas_family: :oas30,
                                              spec_file: 'novapay.yaml')
      expect(profile.info.name).to have_attributes(value: 'novapay', source: :heuristic)
      expect(profile.info.base_url_env.value).to eq('NOVAPAY_BASE_URL')
    end

    it 'classifies both hosts and has nothing to warn about' do
      expect(profile.servers.map(&:url)).to eq(['https://api.sandbox.novapay.example/v1',
                                                'https://api.novapay.example/v1'])
      expect(profile.servers.map { |server| server.environment.value }).to eq(%i[sandbox production])
      expect(profile.warnings).to be_empty
    end

    it 'produces the same profile on every run' do
      first = profile.to_h
      document = SpecGen::SpecLoader.load(spec_fixture('novapay.yaml'))
      second = described_class.call(document: document, profile: SpecGen::IR::ProviderProfile.new,
                                    rules: nil).to_h

      expect(second).to eq(first)
    end
  end
end
