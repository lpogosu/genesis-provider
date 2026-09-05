# frozen_string_literal: true

RSpec.describe SpecGen::Analyzers::ErrorAnalyzer do
  include Fixtures

  # The shipped dictionaries: recognising `error.code` structurally rests on
  # the tokens and parents of rules/roles.yml, and the actions on
  # rules/errors.yml; a stub would prove nothing about either.
  let(:rules) { SpecGen::Rules.load }

  def analyze(paths, components = {})
    data = { 'openapi' => '3.0.3', 'paths' => paths, 'components' => components }
    document = SpecGen::SpecLoader::Document.new(file: 'provider_api.yaml', version: '3.0.3',
                                                 family: :oas30, raw: data, data: data)
    described_class.call(document: document, profile: SpecGen::IR::ProviderProfile.new,
                         rules: rules)
  end

  def json(schema, example = nil)
    media = { 'schema' => schema }
    media['example'] = example unless example.nil?
    { 'description' => 'x', 'content' => { 'application/json' => media } }
  end

  def component(name)
    { 'x-specgen-ref' => "#/components/schemas/#{name}", 'type' => 'object' }
  end

  def error_schema(enum)
    code = { 'type' => 'string', 'enum' => enum }
    error = { 'type' => 'object', 'properties' => { 'code' => code, 'message' => { 'type' => 'string' } } }
    { 'type' => 'object', 'properties' => { 'error' => error } }
  end

  def operation(id, responses, http_method = 'post')
    { http_method => { 'operationId' => id, 'responses' => responses } }
  end

  def rule(profile, http_status: nil, provider_code: nil, operation: nil)
    profile.error_map.find do |rule|
      rule.http_status == http_status && rule.provider_code == provider_code && rule.operation == operation
    end
  end

  def generic_http(profile)
    profile.error_map.select { |rule| rule.http_status && rule.generic? }
  end

  def codes(profile)
    profile.warnings.map(&:code)
  end

  describe 'rules by HTTP status' do
    let(:profile) do
      retry_after = { 'headers' => { 'Retry-After' => { 'schema' => { 'type' => 'integer' } } } }
      responses = { '201' => json(component('Payout')), '401' => json(component('Error')),
                    '402' => json(component('Error')), '422' => json(component('Error')),
                    '429' => json(component('Error')).merge(retry_after), '500' => json(component('Error')) }
      analyze('/payouts' => operation('createPayout', responses))
    end

    it 'takes the action from the dictionary by exact code, then by class, and says which' do
      expect(rule(profile, http_status: 401, operation: 'createPayout').action)
        .to have_attributes(value: :alert, source: :registry, confidence: 0.9)
      expect(rule(profile, http_status: 401, operation: 'createPayout').action.evidence)
        .to eq('rules/errors.yml: HTTP 401 совпал с записью 401 -> alert')
      expect(rule(profile, http_status: 422, operation: 'createPayout').action.evidence)
        .to eq('rules/errors.yml: HTTP 422 совпал с записью 4xx -> reject')
      expect(rule(profile, http_status: 500, operation: 'createPayout').action.value).to eq(:retry_backoff)
    end

    it 'marks the response that declares Retry-After, and no other' do
      expect(rule(profile, http_status: 429, operation: 'createPayout').retry_after).to be(true)
      expect(rule(profile, http_status: 500, operation: 'createPayout').retry_after).to be(false)
    end

    it 'writes no rule for success responses and remembers where each rule came from' do
      expect(profile.error_map.map(&:http_status)).not_to include(201)
      expect(rule(profile, http_status: 402, operation: 'createPayout'))
        .to have_attributes(seen_in: [:response], json_path: "$.paths['/payouts'].post.responses['402']")
    end

    it 'falls back to the default action with a warning for a status the dictionary does not cover' do
      responses = { '200' => json(component('X')), '301' => json(component('Y')) }
      profile = analyze('/x' => operation('getX', responses, 'get'))
      moved = rule(profile, http_status: 301, operation: 'getX')

      expect(moved.action).to have_attributes(value: :reject, confidence: 0.3)
      expect(profile.warnings.first).to have_attributes(code: :error_action_unknown, severity: :warning)
      expect(profile.warnings.first.message).to include('для HTTP 301 нет правила', 'по умолчанию reject')
    end

    it 'leaves the responses of an inbound webhook alone: they are ours, not the provider' do
      responses = { '200' => json(component('Ack')), '401' => json(component('Error')) }
      inbound = operation('payoutWebhook', responses)
      inbound['post']['security'] = []
      profile = analyze('/webhooks/payout' => inbound)

      expect(profile.error_map).to be_empty
    end
  end

  describe 'the conflict status' do
    it 'reads 409 with the success schema as deduplication, and names both schemas' do
      responses = { '201' => json(component('PayoutResponse')), '409' => json(component('PayoutResponse')) }
      profile = analyze('/payouts' => operation('createPayout', responses))
      conflict = rule(profile, http_status: 409, operation: 'createPayout')

      expect(conflict.action).to have_attributes(value: :dedup, source: :structural)
      expect(conflict.dedup?).to be(true)
      expect(conflict.action.evidence).to include('409 возвращает PayoutResponse — ту же схему, что 201', 'IETF')
    end

    it 'reads 409 with an error schema as a plain rejection' do
      responses = { '200' => json(component('PayoutResponse')), '409' => json(component('ErrorResponse')) }
      profile = analyze('/payouts/{id}/cancel' => operation('cancelPayout', responses))

      expect(rule(profile, http_status: 409, operation: 'cancelPayout').action.value).to eq(:reject)
    end
  end

  describe 'codes the sibling operations declare' do
    let(:profile) do
      create = { '201' => json(component('P')), '401' => json(component('E')),
                 '429' => json(component('E')).merge('headers' => { 'Retry-After' => {} }),
                 '500' => json(component('E')) }
      fetch = { '200' => json(component('P')), '401' => json(component('E')), '404' => json(component('E')) }
      analyze('/payouts' => operation('createPayout', create),
              '/payouts/{id}' => operation('getPayoutStatus', fetch, 'get'))
    end

    it 'builds generic rules for the codes an operation lacks, keeping Retry-After from the sibling' do
      expect(generic_http(profile).map(&:http_status)).to eq([404, 429, 500])
      expect(rule(profile, http_status: 429).retry_after).to be(true)
      expect(rule(profile, http_status: 429).action.evidence)
        .to include('rules/errors.yml: HTTP 429', 'объявлен у createPayout')
    end

    it 'reports each gap as information, naming the codes and the operations that declare them' do
      gaps = profile.warnings.select { |w| w.code == :undeclared_status_code }

      expect(gaps.map(&:severity).uniq).to eq([:info])
      expect(gaps.map(&:json_path)).to eq(["$.paths['/payouts'].post", "$.paths['/payouts/{id}'].get"])
      expect(gaps.last.message).to include('getPayoutStatus не объявляет 429, 500', 'createPayout')
    end
  end

  describe 'codes of the provider' do
    let(:error_component) do
      { 'ErrorResponse' => error_schema(%w[rate_limit_exceeded bank_unavailable insufficient_balance]) }
    end

    def with_examples(examples)
      responses = { '200' => json(component('P')) }
      examples.each do |status, code|
        responses[status] = json(component('ErrorResponse'), { 'error' => { 'code' => code, 'message' => 'x' } })
      end
      analyze({ '/p' => operation('createPayout', responses) }, { 'schemas' => error_component })
    end

    it 'builds one rule per enum code with the pattern action and the pattern confidence' do
      profile = with_examples({})
      rule = rule(profile, provider_code: 'insufficient_balance')

      expect(rule.action).to have_attributes(value: :retry_backoff, source: :registry, confidence: 0.8)
      expect(rule.action.evidence).to eq('rules/errors.yml: код insufficient_balance совпал с шаблоном funds -> retry_backoff')
      expect(rule.json_path).to eq('$.components.schemas.ErrorResponse.properties.error.properties.code.enum[2]')
      expect(rule.seen_in).to eq([:enum])
    end

    it 'adds a code that only an example carries, and reports it as undeclared' do
      profile = with_examples('404' => 'not_found', '429' => 'rate_limit_exceeded')
      undeclared = rule(profile, provider_code: 'not_found')

      expect(undeclared.seen_in).to eq([:example])
      expect(undeclared.action.value).to eq(:reject)
      expect(undeclared.json_path).to eq("$.paths['/p'].post.responses['404'].content['application/json'].example.error.code")
      warning = profile.warnings.find { |w| w.code == :error_code_undeclared }
      expect(warning.message).to include('код not_found встречается в примере, но не объявлен в enum',
                                         '$.components.schemas.ErrorResponse.properties.error.properties.code')
      expect(rule(profile, provider_code: 'rate_limit_exceeded').seen_in).to eq(%i[enum example])
    end

    it 'reports an enum code that no example shows, as information' do
      profile = with_examples({})
      unused = profile.warnings.select { |w| w.code == :error_code_unused }

      expect(unused.size).to eq(3)
      expect(unused.map(&:severity).uniq).to eq([:info])
      expect(unused.first.message).to include('rate_limit_exceeded объявлен в enum, но не встречается ни в одном примере')
    end

    it 'takes the default action for a code no pattern explains, warns and offers the overlay' do
      profile = analyze({ '/p' => operation('createPayout', {}) },
                        { 'schemas' => { 'ErrorResponse' => error_schema(%w[np_err_17]) } })
      rule = rule(profile, provider_code: 'np_err_17')
      warning = profile.warnings.find { |w| w.code == :error_action_unknown }

      expect(rule.action).to have_attributes(value: :reject, source: :registry, confidence: 0.3)
      expect(warning.message).to include('для кода np_err_17 нет правила в rules/errors.yml')
      expect(warning.suggested_overlay).to include('x-specgen-error-actions:', 'np_err_17: reject')
    end

    it 'lets x-specgen-error-actions decide, with overlay as the source' do
      schema = error_schema(%w[np_err_17])
      schema['properties']['error']['properties']['code']['x-specgen-error-actions'] = { 'np_err_17' => 'escalate' }
      profile = analyze({ '/p' => operation('createPayout', {}) }, { 'schemas' => { 'ErrorResponse' => schema } })

      expect(rule(profile, provider_code: 'np_err_17').action).to have_attributes(value: :escalate, source: :overlay)
      expect(codes(profile)).not_to include(:error_action_unknown)
    end

    it 'does not mistake a bare code outside an error parent for an error code' do
      currency = { 'type' => 'object', 'properties' => { 'code' => { 'type' => 'string', 'enum' => %w[RUB] } } }
      schema = { 'type' => 'object', 'properties' => { 'currency' => currency } }
      profile = analyze({ '/p' => operation('getBalance', {}, 'get') }, { 'schemas' => { 'Balance' => schema } })

      expect(profile.error_map).to be_empty
    end

    it 'says the same in English when the locale is switched' do
      SpecGen::Texts.locale = 'en'
      profile = with_examples('404' => 'not_found')

      expect(profile.warnings.find { |w| w.code == :error_code_undeclared }.message)
        .to include('code not_found appears in an example but is not declared in the enum')
    end
  end

  describe 'input the loader let through' do
    it 'does not raise on responses, headers or enums of the wrong shape' do
      schema = error_schema('nope')
      paths = { '/a' => operation('a', 'nope', 'get'),
                '/b' => operation('b', { '500' => { 'headers' => 'nope' } }, 'get') }

      expect { analyze(paths, { 'schemas' => { 'E' => schema } }) }.not_to raise_error
      expect(analyze(paths, { 'schemas' => { 'E' => schema } }).error_map.map(&:http_status)).to eq([500])
    end
  end

  describe 'on the spec as shipped' do
    let(:profile) do
      document = SpecGen::SpecLoader.load(spec_fixture('novapay.yaml'))
      described_class.call(document: document, profile: SpecGen::IR::ProviderProfile.new, rules: rules)
    end

    it 'finds the three codes the examples carry but the enum does not' do
      undeclared = profile.warnings.select { |w| w.code == :error_code_undeclared }

      expect(undeclared.map { |w| w.message[/код (\w+)/, 1] }).to contain_exactly('unauthorized', 'not_found', 'invalid_status')
      expect(profile.error_map.count(&:provider_code)).to eq(10)
    end

    it 'finds the three enum codes no example shows' do
      unused = profile.warnings.select { |w| w.code == :error_code_unused }

      expect(unused.map { |w| w.message[/код (\w+)/, 1] })
        .to contain_exactly('bank_unavailable', 'amount_limit_exceeded', 'internal_error')
    end

    it 'reads 409 on creation as deduplication and 409 on cancel as rejection' do
      expect(rule(profile, http_status: 409, operation: 'createPayout').action.value).to eq(:dedup)
      expect(rule(profile, http_status: 409, operation: 'cancelPayout').action.value).to eq(:reject)
    end

    it 'extends the codes to the operations that do not declare them, with Retry-After kept' do
      expect(generic_http(profile).map(&:http_status)).to eq([400, 401, 402, 404, 409, 422, 429, 500])
      expect(rule(profile, http_status: 429).retry_after).to be(true)
      gaps = profile.warnings.select { |w| w.code == :undeclared_status_code }
      expect(gaps.map(&:json_path)).not_to include("$.paths['/webhooks/payout'].post")
      expect(gaps.find { |w| w.json_path.include?("{payout_id}'].get") }.message).to include('429, 500')
    end

    it 'assigns an action to every rule, none of them by default' do
      expect(profile.error_map.map { |r| r.action.confidence }).to all(be >= 0.8)
      expect(codes(profile)).not_to include(:error_action_unknown)
    end
  end
end
