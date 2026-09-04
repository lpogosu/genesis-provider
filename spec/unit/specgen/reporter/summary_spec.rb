# frozen_string_literal: true

RSpec.describe SpecGen::Reporter::Summary do
  include Fixtures

  let(:rules) { SpecGen::Rules.load }
  let(:document) { SpecGen::SpecLoader.load(spec_fixture('novapay.yaml')) }
  let(:profile) { SpecGen::Analyzers::Runner.call(document: document, rules: rules) }

  def render(explain: false)
    described_class.new(profile, document, explain: explain).render
  end

  describe 'on the shipped spec, in Russian by default' do
    subject(:text) { render }

    it 'opens with the file, the version and the counts, declined properly' do
      expect(text.lines.first)
        .to eq("Разбор спецификации... novapay.yaml: OpenAPI 3.0.3, 5 операций, 8 схем, 31 поле\n")
    end

    it 'shows the provider with its derivation source and confidence' do
      expect(text).to include('Провайдер: novapay (эвристика 0.80)')
        .and include('Базовый URL: переменная окружения NOVAPAY_BASE_URL')
    end

    it 'shows every server with its environment' do
      expect(text).to match(%r{песочница\s+https://api\.sandbox\.novapay\.example/v1})
        .and match(%r{продакшен\s+https://api\.novapay\.example/v1})
    end

    it 'shows the auth scheme, where the credential goes and which key it reads' do
      expect(text).to include('Авторизация: ApiKeyAuth -> api_key, заголовок X-API-Key, ключи credentials: api_key')
    end

    it 'lists every operation with role, confidence and operationId' do
      expect(text).to match(%r{POST /payouts\s+create_payout\s+0\.95\s+createPayout$})
        .and match(%r{GET  /payouts/\{payout_id\}\s+fetch_status\s+0\.95\s+getPayoutStatus$})
    end

    it 'flags operations outside the contract and unsecured ones on their own line' do
      expect(text).to match(/cancel\s+0\.95\s+cancelPayout  \(вне контракта\)/)
        .and match(/balance\s+0\.93\s+getBalance  \(вне контракта\)/)
        .and match(/webhook\s+0\.83\s+payoutWebhook  \(без авторизации\)/)
    end

    it 'shows what each operation sends and receives' do
      expect(text).to include('запрос: CreatePayoutRequest; заголовок Idempotency-Key (необязательный)')
        .and include('путь payout_id (обязательный)')
        .and include('409 PayoutResponse')
        .and include('429 ErrorResponse +Retry-After')
    end

    it 'prints each field with type, requiredness and constraints' do
      expect(text).to match(/amount\s+integer\s+обязательное\s+minimum=100000/)
        .and match(/currency\s+string\s+обязательное\s+enum=RUB/)
        .and match(/external_id\s+string\s+обязательное\s+max_length=64/)
        .and match(/created_at\s+string date-time\s+необязательное$/)
        .and match(/recipient\s+object\s+обязательное\s+-> Recipient/)
    end

    it 'states a conditional requirement with the origin it was read from' do
      expect(text).to include('обязательно при type = sbp (намёк в описании 0.50)')
        .and include('обязательно при type = card (намёк в описании 0.50)')
    end

    it 'counts warnings by severity, declined, and lists each with its JSONPath' do
      expect(text).to include('Предупреждения: 4 (0 ошибок, 2 предупреждения, 2 справки)')
        .and include("ВНИМАНИЕ $.components.schemas.Recipient\n")
        .and include("СПРАВКА  $.paths['/balance'].get\n")
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

  describe 'in English' do
    before { SpecGen::Texts.locale = 'en' }

    subject(:text) { render }

    it 'switches every label, keeping identifiers and values as they are' do
      expect(text.lines.first)
        .to eq("Parsing spec... novapay.yaml: OpenAPI 3.0.3, 5 operations, 8 schemas, 31 fields\n")
      expect(text).to include('Provider: novapay (heuristic 0.80)')
        .and include('Auth: ApiKeyAuth -> api_key, header X-API-Key, credentials: api_key')
        .and match(/cancel\s+0\.95\s+cancelPayout  \(not in contract\)/)
        .and include('required when type = sbp (description hint 0.50)')
        .and include('Warnings: 4 (0 errors, 2 warnings, 2 info)')
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
      expect(render).to include('0 операций, 0 схем, 0 полей')
        .and include('Провайдер: не анализировался')
        .and include('Серверы: не объявлены')
        .and include('Авторизация: не анализировалась')
        .and include('Операции: не найдены')
        .and include('Схемы: не найдены')
        .and include('Предупреждения: 0 (0 ошибок, 0 предупреждений, 0 справок)')
    end
  end
end
