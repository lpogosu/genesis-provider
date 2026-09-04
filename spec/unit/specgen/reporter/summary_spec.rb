# frozen_string_literal: true

RSpec.describe SpecGen::Reporter::Summary do
  include Fixtures

  let(:rules) { SpecGen::Rules.load }
  let(:document) { SpecGen::SpecLoader.load(spec_fixture('novapay.yaml')) }
  let(:profile) { SpecGen::Analyzers::Runner.call(document: document, rules: rules) }

  def render(explain: false)
    described_class.new(profile, document, explain: explain).render
  end

  describe 'on the shipped spec' do
    subject(:text) { render }

    it 'opens with the file, the version and the counts' do
      expect(text.lines.first)
        .to eq("Parsing spec... novapay.yaml: OpenAPI 3.0.3, 5 operations, 8 schemas, 31 fields\n")
    end

    it 'shows the provider with its derivation source and confidence' do
      expect(text).to include('Provider: novapay (heuristic 0.80)')
        .and include('Base URL: ENV NOVAPAY_BASE_URL')
    end

    it 'shows every server with its environment' do
      expect(text).to match(%r{sandbox\s+https://api\.sandbox\.novapay\.example/v1})
        .and match(%r{production\s+https://api\.novapay\.example/v1})
    end

    it 'shows the auth scheme, where the credential goes and which key it reads' do
      expect(text).to include('Auth: ApiKeyAuth -> api_key in header X-API-Key, credentials: api_key')
    end

    it 'lists every operation with role, confidence and operationId' do
      expect(text).to match(%r{POST /payouts\s+create_payout\s+0\.95\s+createPayout$})
        .and match(%r{GET  /payouts/\{payout_id\}\s+fetch_status\s+0\.95\s+getPayoutStatus$})
    end

    it 'flags operations outside the contract and unsecured ones on their own line' do
      expect(text).to match(/cancel\s+0\.95\s+cancelPayout  \(not in contract\)/)
        .and match(/balance\s+0\.93\s+getBalance  \(not in contract\)/)
        .and match(/webhook\s+0\.83\s+payoutWebhook  \(unsecured\)/)
    end

    it 'shows what each operation sends and receives' do
      expect(text).to include('request:   CreatePayoutRequest; header Idempotency-Key (optional)')
        .and include('409 PayoutResponse')
        .and include('429 ErrorResponse +Retry-After')
    end

    it 'prints each field with type, requiredness and constraints' do
      expect(text).to match(/amount\s+integer\s+required\s+minimum=100000/)
        .and match(/currency\s+string\s+required\s+enum=RUB/)
        .and match(/external_id\s+string\s+required\s+max_length=64/)
        .and match(/created_at\s+string date-time\s+optional/)
        .and match(/recipient\s+object\s+required\s+-> Recipient/)
    end

    it 'states a conditional requirement with the origin it was read from' do
      expect(text).to include('required when type = sbp (description hint 0.50)')
        .and include('required when type = card (description hint 0.50)')
    end

    it 'counts warnings by severity and lists each with its JSONPath' do
      expect(text).to include('Warnings: 4 (0 error, 2 warning, 2 info)')
        .and include("WARNING $.components.schemas.Recipient\n")
        .and include("INFO    $.paths['/balance'].get\n")
    end

    it 'keeps evidence and overlays out of the default view' do
      expect(text).not_to include('= rules/auth.yml')
      expect(text).not_to include('overlay:')
    end

    it 'ends every line with LF and the text with exactly one newline' do
      expect(text).not_to include("\r")
      expect(text).to end_with("\n")
      expect(text).not_to end_with("\n\n")
    end

    it 'renders byte-identically on every call' do
      expect(render).to eq(render)
    end
  end

  describe 'with explain' do
    subject(:text) { render(explain: true) }

    it 'follows each derived value with the evidence it rests on' do
      expect(text).to include('= info.title "NovaPay Payout API" -> novapay')
        .and include('= rules/auth.yml entry "api_key_header" matched type=apikey, in=header')
        .and include('= composite match: operation_id 5.0')
    end

    it 'prints the overlay fragment under a fixable warning' do
      expect(text).to include("overlay:\n")
        .and include('- target: "$.components.schemas.Recipient"')
        .and include('required: [bank_code]')
    end
  end

  describe 'on an empty profile' do
    let(:profile) { SpecGen::IR::ProviderProfile.new }
    let(:document) do
      SpecGen::SpecLoader::Document.new(file: 'empty.yaml', version: '3.1.0', family: :oas31,
                                        raw: {}, data: {})
    end

    it 'says what was not analysed instead of failing' do
      expect(render).to include('0 operations, 0 schemas, 0 fields')
        .and include('Provider: not analysed')
        .and include('Servers: none declared')
        .and include('Auth: not analysed')
        .and include('Operations: none')
        .and include('Schemas: none')
        .and include('Warnings: 0 (0 error, 0 warning, 0 info)')
    end
  end
end
