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

    it 'shows the amount units with the multiplier, the standard behind it and the currency' do
      expect(text).to include('Единицы суммы: minor, x100 (ISO 4217: экспонента RUB 2); валюта RUB (задано явно 1.00)')
    end

    it 'counts the statuses and lists each with its internal status' do
      expect(text).to include('Статусы: 5 сопоставлено, 0 не выведено')
        .and match(/pending\s+-> in_progress \(по справочнику 1\.00\)/)
        .and match(/cancelled\s+-> rejected \(по справочнику 1\.00\)/)
    end

    it 'shows the webhook with its events and the signature profile' do
      expect(text).to include('Вебхук: /webhooks/payout — 4 события, подпись X-NovaPay-Signature (custom: hmac_sha256, hex, raw_body)')
        .and match(/payout\.completed\s+-> approved \(по справочнику 1\.00\)/)
    end

    it 'shows the idempotency header, the key strategy and the deduplication status' do
      expect(text).to include('Идемпотентность: заголовок Idempotency-Key (необязательный), стратегия uuid_v5, dedup on 409')
    end

    it 'counts the error codes by where they were seen and names the deduplication' do
      expect(text).to include('Ошибки: 7 в enum + 3 только в примерах; дедупликация 409 у createPayout')
        .and match(/insufficient_balance\s+escalate \(по справочнику 0\.80\)  \[enum \+ пример\]/)
        .and match(/not_found\s+reject \(по справочнику 0\.80\)  \[пример\]/)
        .and match(/createPayout\s+400 reject, 401 alert, 402 escalate, 409 dedup, 422 reject, 429 retry_backoff \+Retry-After, 500 retry_backoff/)
        .and match(/общие\s+400 reject, 401 alert, 402 escalate, 404 reject, 409 reject, 422 reject, 429 retry_backoff \+Retry-After, 500 retry_backoff/)
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
      expect(text).to include('Предупреждения: 14 (0 ошибок, 5 предупреждений, 9 справок)')
        .and include("ВНИМАНИЕ $.components.schemas.Recipient\n")
        .and include("СПРАВКА  $.paths['/balance'].get\n")
    end

    it 'keeps evidence and overlays out of the default view' do
      expect(text).not_to include('= запись rules/auth.yml')
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
        .and include('Amount units: minor, x100 (ISO 4217: RUB exponent 2); currency RUB (structural 1.00)')
        .and include('Statuses: 5 mapped, 0 unknown')
        .and include('Errors: 7 in enum + 3 found in examples only; dedup on 409 at createPayout')
        .and include('Webhook: /webhooks/payout — 4 events, signature X-NovaPay-Signature (custom: hmac_sha256, hex, raw_body)')
        .and include('Idempotency: header Idempotency-Key (optional), strategy uuid_v5, dedup on 409')
        .and match(/cancel\s+0\.95\s+cancelPayout  \(not in contract\)/)
        .and include('required when type = sbp (description hint 0.50)')
        .and include('Warnings: 14 (0 errors, 5 warnings, 9 info)')
    end
  end

  describe 'with explain' do
    subject(:text) { render(explain: true) }

    it 'follows each derived value with the evidence it rests on' do
      expect(text).to include('= из info.title "NovaPay Payout API" -> novapay')
        .and include('= запись rules/auth.yml "api_key_header" совпала по type=apikey, in=header')
        .and include('= композитное сопоставление: operation_id 5.0')
        .and include('= type: integer -> минорные единицы; описание подтверждает: "копейках"; minimum 100000 = 1000.00 RUB')
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
        .and include('Единицы суммы: поле суммы не найдено')
        .and include('Статусы: не найдены')
        .and include('Ошибки: правил нет')
        .and include('Вебхук: не описан (статус только опросом)')
        .and include('Идемпотентность: заголовок не объявлен')
        .and include('Операции: не найдены')
        .and include('Схемы: не найдены')
        .and include('Предупреждения: 0 (0 ошибок, 0 предупреждений, 0 справок)')
    end
  end
end
