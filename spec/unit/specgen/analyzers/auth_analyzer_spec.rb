# frozen_string_literal: true

RSpec.describe SpecGen::Analyzers::AuthAnalyzer do
  include Fixtures

  # The real dictionaries on purpose: this analyzer is worth exactly as much
  # as its link to rules/auth.yml, and a stubbed book would test nothing.
  let(:rules) { SpecGen::Rules.load }

  def analyze(data, file: 'provider_api.yaml')
    document = SpecGen::SpecLoader::Document.new(file: file, version: '3.0.3', family: :oas30,
                                                 raw: data, data: data)
    described_class.call(document: document, profile: SpecGen::IR::ProviderProfile.new,
                         rules: rules)
  end

  # One operation requiring one scheme, which is all most examples need.
  def spec(schemes, security: [{ 'Scheme' => [] }], paths: nil)
    { 'openapi' => '3.0.3',
      'components' => { 'securitySchemes' => schemes },
      'paths' => paths || { '/payouts' => { 'post' => { 'security' => security } } } }
  end

  def auth_for(declaration, security: [{ 'Scheme' => [] }])
    analyze(spec({ 'Scheme' => declaration }, security: security)).auth
  end

  def profile_for(declaration)
    analyze(spec({ 'Scheme' => declaration }))
  end

  def codes(profile)
    profile.warnings.map(&:code)
  end

  describe 'schemes the dictionary describes' do
    it 'reads an API key in a header, naming the parameter as the spec spells it' do
      auth = auth_for({ 'type' => 'apiKey', 'in' => 'header', 'name' => 'X-API-Key' })

      expect(auth).to have_attributes(scheme_name: 'Scheme', location: :header,
                                      param_name: 'X-API-Key', token_url: nil, scopes: [],
                                      json_path: '$.components.securitySchemes.Scheme')
      expect(auth.type).to have_attributes(value: :api_key, source: :registry)
      expect(auth.type.evidence).to eq('запись rules/auth.yml "api_key_header" совпала по ' \
                                       'type=apikey, in=header')
      expect(auth.credential_keys.value).to eq(['api_key'])
    end

    it 'reads an API key in the query string and says what it costs' do
      profile = profile_for({ 'type' => 'apiKey', 'in' => 'query', 'name' => 'api_key' })
      warning = profile.warnings.first

      expect(profile.auth).to have_attributes(location: :query, param_name: 'api_key')
      expect(profile.auth.type.value).to eq(:api_key)
      expect(warning).to have_attributes(code: :auth_key_in_query, severity: :info,
                                         json_path: '$.components.securitySchemes.Scheme')
      expect(warning.message).to include('query-строке')
    end

    it 'reads HTTP bearer, taking the header name from the dictionary, not the spec' do
      auth = auth_for({ 'type' => 'http', 'scheme' => 'Bearer' })

      expect(auth.type.value).to eq(:bearer)
      expect(auth).to have_attributes(location: :header, param_name: 'Authorization')
      expect(auth.credential_keys.value).to eq(['token'])
    end

    it 'reads HTTP basic and names both credentials the service needs' do
      auth = auth_for({ 'type' => 'http', 'scheme' => 'basic' })

      expect(auth.type.value).to eq(:basic)
      expect(auth.credential_keys.value).to eq(%w[password username])
    end
  end

  describe 'OAuth2' do
    def oauth2(flow, body, security: [{ 'Scheme' => [] }])
      auth_for({ 'type' => 'oauth2', 'flows' => { flow => body } }, security: security)
    end

    it 'takes the token endpoint from the spec and merges declared and requested scopes' do
      auth = oauth2('clientCredentials',
                    { 'tokenUrl' => 'https://api.example.com/oauth/token',
                      'scopes' => { 'payouts:write' => 'create payouts' } },
                    security: [{ 'Scheme' => ['payouts:read'] }])

      expect(auth.type.value).to eq(:oauth2)
      expect(auth.token_url).to eq('https://api.example.com/oauth/token')
      expect(auth.scopes).to eq(['payouts:read', 'payouts:write'])
      expect(auth.credential_keys.value).to eq(%w[client_id client_secret])
    end

    it 'refuses to invent a token endpoint when the flow declares none' do
      profile = profile_for({ 'type' => 'oauth2', 'flows' => { 'clientCredentials' => {} } })

      expect(profile.auth).to have_attributes(token_url: nil)
      expect(profile.auth.type.value).to eq(:oauth2)
      expect(profile.warnings.first)
        .to have_attributes(code: :auth_unknown, severity: :error,
                            json_path: '$.components.securitySchemes.Scheme.flows.clientCredentials')
    end

    it 'treats a browser flow as unknown, because the dictionary covers no such thing' do
      profile = profile_for({ 'type' => 'oauth2', 'flows' => { 'authorizationCode' => {} } })

      expect(profile.auth.type).to be_unknown
      expect(codes(profile)).to eq([:auth_unknown])
    end
  end

  describe 'choosing among several declared schemes' do
    def two_schemes(operations)
      analyze(spec({ 'ApiKeyAuth' => { 'type' => 'apiKey', 'in' => 'header', 'name' => 'X-Key' },
                     'BearerAuth' => { 'type' => 'http', 'scheme' => 'bearer' } },
                   paths: operations))
    end

    def requiring(*names)
      { 'security' => names.map { |name| { name => [] } } }
    end

    it 'picks the one most operations require and reports the rest with their paths' do
      profile = two_schemes('/a' => { 'post' => requiring('BearerAuth') },
                            '/b' => { 'get' => requiring('BearerAuth') },
                            '/c' => { 'get' => requiring('ApiKeyAuth') })
      warning = profile.warnings.first

      expect(profile.auth.scheme_name).to eq('BearerAuth')
      expect(warning).to have_attributes(code: :auth_multiple_schemes, severity: :warning,
                                         json_path: '$.components.securitySchemes')
      expect(warning.message).to include('выбрана BearerAuth', 'её требуют 2 операции')
        .and include('ApiKeyAuth ($.components.securitySchemes.ApiKeyAuth)')
    end

    it 'breaks a tie by declaration order rather than by cleverness' do
      profile = two_schemes('/a' => { 'post' => requiring('BearerAuth') },
                            '/b' => { 'get' => requiring('ApiKeyAuth') })

      expect(profile.auth.scheme_name).to eq('ApiKeyAuth')
    end

    it 'does not let an operation with security: [] vote' do
      profile = two_schemes('/payouts' => { 'post' => requiring('ApiKeyAuth') },
                            '/webhooks/payout' => { 'post' => { 'security' => [] } })

      expect(profile.auth.scheme_name).to eq('ApiKeyAuth')
      expect(profile.auth.type.value).to eq(:api_key)
      expect(codes(profile)).to eq([:auth_multiple_schemes])
    end

    it 'lets operations inherit the document-level security' do
      data = spec({ 'ApiKeyAuth' => { 'type' => 'apiKey', 'in' => 'header', 'name' => 'X-Key' },
                    'BearerAuth' => { 'type' => 'http', 'scheme' => 'bearer' } },
                  paths: { '/a' => { 'get' => {} }, '/b' => { 'get' => {} } })
      profile = analyze(data.merge('security' => [{ 'BearerAuth' => [] }]))

      expect(profile.auth.scheme_name).to eq('BearerAuth')
      expect(profile.warnings.first.message).to include('её требуют 2 операции')
    end

    it 'says nothing when the spec declares exactly one scheme' do
      profile = profile_for({ 'type' => 'http', 'scheme' => 'bearer' })

      expect(profile.warnings).to be_empty
    end
  end

  describe 'what it refuses to guess' do
    it 'reports a scheme the dictionary does not describe, with an overlay to fix it' do
      profile = analyze(spec({ 'OIDC' => { 'type' => 'openIdConnect',
                                           'openIdConnectUrl' => 'https://id.example.com' } },
                             security: [{ 'OIDC' => [] }]))
      warning = profile.warnings.first

      expect(profile.auth).to have_attributes(scheme_name: 'OIDC', location: nil,
                                              json_path: '$.components.securitySchemes.OIDC')
      expect(profile.auth.type).to be_unknown
      expect(warning).to have_attributes(code: :auth_unknown, severity: :error)
      expect(warning.suggested_overlay).to include('- target: "$.components.securitySchemes.OIDC"')
    end

    it 'reports an apiKey that names no parameter instead of inventing a header' do
      profile = profile_for({ 'type' => 'apiKey', 'in' => 'header' })

      expect(profile.auth.param_name).to be_nil
      expect(profile.auth.type.value).to eq(:api_key)
      expect(profile.warnings.first).to have_attributes(code: :auth_unknown, severity: :error)
    end

    it 'blocks when operations require a scheme components never declares' do
      operation = { 'security' => [{ 'ApiKeyAuth' => [] }] }
      profile = analyze({ 'paths' => { '/payouts' => { 'post' => operation } } })

      expect(profile.auth.scheme_name).to eq('ApiKeyAuth')
      expect(profile.auth.type).to be_unknown
      expect(profile.warnings.first)
        .to have_attributes(code: :auth_unknown, severity: :error,
                            json_path: '$.components.securitySchemes')
      expect(profile.warnings.first.message).to include('ApiKeyAuth')
    end

    it 'still uses the declared scheme when only some requirement is undeclared' do
      profile = analyze(spec({ 'Scheme' => { 'type' => 'http', 'scheme' => 'bearer' } },
                             security: [{ 'Scheme' => [] }, { 'Ghost' => [] }]))

      expect(profile.auth.type.value).to eq(:bearer)
      expect(profile.warnings.first).to have_attributes(code: :auth_unknown, severity: :warning)
    end
  end

  describe 'a spec that declares no security at all' do
    it 'records :none as read from the spec, and flags it for a human' do
      profile = analyze({ 'paths' => { '/payouts' => { 'post' => {} } } })

      expect(profile.auth.none?).to be(true)
      expect(profile.auth.type).to have_attributes(source: :structural, confidence: 1.0)
      expect(profile.auth.type.evidence).to include('нет components.securitySchemes')
      expect(profile.warnings.first).to have_attributes(code: :auth_absent, severity: :info)
    end

    it 'keeps a declared scheme even when no operation requires it' do
      profile = analyze(spec({ 'Scheme' => { 'type' => 'http', 'scheme' => 'bearer' } },
                             paths: { '/hook' => { 'post' => { 'security' => [] } } }))

      expect(profile.auth.type.value).to eq(:bearer)
      expect(profile.warnings).to be_empty
    end
  end

  describe 'input the loader let through' do
    it 'does not raise when securitySchemes is not an object' do
      profile = nil

      expect { profile = analyze({ 'components' => { 'securitySchemes' => 'ApiKeyAuth' } }) }
        .not_to raise_error
      expect(codes(profile)).to eq(%i[spec_element_unsupported auth_absent])
      expect(profile.auth.none?).to be(true)
    end

    it 'skips a scheme declaration that is not an object' do
      profile = analyze(spec({ 'Broken' => 'apiKey',
                               'Scheme' => { 'type' => 'http', 'scheme' => 'bearer' } }))

      expect(profile.auth.scheme_name).to eq('Scheme')
      expect(profile.warnings.first)
        .to have_attributes(code: :spec_element_unsupported,
                            json_path: '$.components.securitySchemes.Broken')
    end

    it 'reports a security section that is not a list' do
      profile = analyze(spec({ 'Scheme' => { 'type' => 'http', 'scheme' => 'bearer' } },
                             security: 'Scheme'))

      expect(profile.warnings.first)
        .to have_attributes(code: :spec_element_unsupported,
                            json_path: "$.paths['/payouts'].post.security")
      expect(profile.auth.type.value).to eq(:bearer)
    end

    it 'reports a requirement entry that is not an object' do
      profile = analyze(spec({ 'Scheme' => { 'type' => 'http', 'scheme' => 'bearer' } },
                             security: ['Scheme']))

      expect(codes(profile)).to include(:spec_element_unsupported)
    end

    it 'does not raise when flows is not an object' do
      profile = nil

      expect { profile = profile_for({ 'type' => 'oauth2', 'flows' => 'none' }) }
        .not_to raise_error
      expect(profile.auth.type).to be_unknown
      expect(codes(profile)).to eq([:auth_unknown])
    end

    it 'does not raise when a flow body or its scopes are of the wrong shape' do
      profile = nil
      flows = { 'clientCredentials' => { 'tokenUrl' => 'https://t.example', 'scopes' => 'all' } }

      expect { profile = profile_for({ 'type' => 'oauth2', 'flows' => flows }) }
        .not_to raise_error
      expect(profile.auth).to have_attributes(scopes: [], token_url: 'https://t.example')
    end
  end

  describe 'on the spec as shipped' do
    let(:profile) do
      document = SpecGen::SpecLoader.load(spec_fixture('novapay.yaml'))
      described_class.call(document: document, profile: SpecGen::IR::ProviderProfile.new,
                           rules: rules)
    end

    it 'recognises the API key header the operations require' do
      expect(profile.auth).to have_attributes(scheme_name: 'ApiKeyAuth', location: :header,
                                              param_name: 'X-API-Key', token_url: nil, scopes: [],
                                              json_path: '$.components.securitySchemes.ApiKeyAuth')
      expect(profile.auth.type.value).to eq(:api_key)
      expect(profile.auth.credential_keys.value).to eq(['api_key'])
    end

    it 'has nothing to warn about: one scheme, and the webhook opts out with security: []' do
      expect(profile.warnings).to be_empty
    end
  end
end
