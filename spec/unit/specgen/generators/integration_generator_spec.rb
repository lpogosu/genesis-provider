# frozen_string_literal: true

require 'tmpdir'
require 'yaml'

RSpec.describe SpecGen::Generators::IntegrationGenerator do
  include Fixtures

  let(:sections) do
    [
      '## 1. Авторизация и хранение секрета', '## 2. ENV-переменные',
      '## 3. Таблица методов с идемпотентностью', '## 4. Маппинг статусов',
      '## 5. Обработка ошибок с действиями', '## 6. Параметры подключения',
      '## 7. Схема подписи вебхука', '## 8. Как подключить в приложение',
      '## 9. Принятые допущения'
    ]
  end

  def generate(spec, dir, provider: nil)
    rules = SpecGen::Rules.load
    document = SpecGen::SpecLoader.load(spec)
    options = { provider: provider, output: dir }.compact
    profile = SpecGen::Analyzers::Runner.call(document: document, rules: rules, options: options)
    artifacts = SpecGen::Generators.call(profile: profile, rules: rules, document: document, options: options)
    artifact = artifacts.find { |item| item.kind == :integration }
    [File.read(artifact.path, encoding: 'UTF-8'), artifact, artifacts.first]
  end

  def headings(text)
    text.lines.grep(/\A## /).map(&:chomp)
  end

  def write_bare_spec(dir, body)
    path = File.join(dir, 'bare.yaml')
    File.binwrite(path, body)
    path
  end

  describe 'the guide for novapay.yaml' do
    before(:all) do
      @dir = Dir.mktmpdir('specgen-integration')
      @text, @artifact, @service = generate(File.join(Fixtures::ROOT, 'specs', 'novapay.yaml'), @dir,
                                            provider: 'novapay')
      @code = File.read(@service.path, encoding: 'UTF-8')
    end

    after(:all) { FileUtils.remove_entry(@dir) }

    it 'is written as INTEGRATION.md after the service, with exactly nine numbered sections' do
      expect(@artifact.file).to eq('INTEGRATION.md')
      expect(headings(@text)).to eq(sections)
    end

    it 'lists every STATUS_MAP and EVENT_MAP entry of the service, with its source' do
      %w[STATUS_MAP EVENT_MAP].each do |constant|
        block = @code[/#{constant} = \{(.*?)\}\.freeze/m, 1]
        entries = block.scan(/'([\w.]+)' => :(\w+)/)
        expect(entries.size).to be >= 4
        entries.each do |provider_status, internal|
          expect(@text).to include("| `#{provider_status}` | `#{internal}` |")
        end
      end
      expect(@text).to include('канон описания кейса')
    end

    it 'lists every ERROR_MAP entry with the failure call the service makes' do
      expect(@text).to include("| `validation_error` | любой — читается из тела ответа | enum и примеры | `reject` | `failure(platform_failure_code(response.status, :reject), 'errors.validation_error')` |")
      expect(@text).to include("| `429` | `retry_backoff` | `failure(:too_many_requests, 'errors.429')` |")
      expect(@text).to include('FAILURE_CODES_BY_ACTION')
      expect(@text).to include('`Retry-After` объявлен у ответов `429`')
      expect(@text).to include('draft-ietf-httpapi-idempotency-key-header')
    end

    it 'recomputes the amount limits into major units the same way check_conditions does' do
      expect(@text).to include('minimum: 1000  # minimum: 100000 в единицах провайдера = 1000.00 RUB')
      expect(@text).to include('multiplier: 100  # ISO 4217: экспонента RUB 2')
    end

    it 'describes the signature scheme without any secret value' do
      expect(@text).to include('`X-NovaPay-Signature`', '`hmac_sha256`', '`hex`', '`raw_body`',
                               'provider.credentials[:webhook_secret]', 'OpenSSL.fixed_length_secure_compare')
      expect(@text).not_to match(/test_secret|secret\s*=\s*['"][^'"]+['"]/)
    end

    it 'names the ENV variables exactly as the service declares them' do
      %w[NOVAPAY_BASE_URL NOVAPAY_OPEN_TIMEOUT NOVAPAY_READ_TIMEOUT].each do |env|
        expect(@code).to include("'#{env}'")
        expect(@text).to include("`#{env}`")
      end
    end

    it 'carries the project assumptions from rules/assumptions.yml plus the run assumptions' do
      expect(@text).to include('№1. Контракт Provider::BaseService', 'раздел platform в rules/contract.yml')
      expect(@text).to include('условная обязательность `bank_code` при type = sbp')
      expect(@text).to include('cancel_status_restriction')
      expect(@text).not_to include('#<', ' nil ', '[]')
    end

    it 'emits a gateway fragment that parses as YAML' do
      yaml = @text[/```yaml\n(.*?)```/m, 1]
      config = YAML.safe_load(yaml)
      expect(config.dig('providers', 'novapay', 'service')).to eq('Provider::NovapayService')
      expect(config.dig('providers', 'novapay', 'currencies')).to eq(['RUB'])
    end
  end

  describe 'a specification with no webhook, idempotency, units, statuses or authorization' do
    it 'still renders all nine sections, saying what the specification did not declare' do
      Dir.mktmpdir('specgen-bare') do |dir|
        spec = write_bare_spec(dir, <<~YAML)
          openapi: 3.0.3
          info: { title: Bare Ledger API, version: '0.1' }
          paths:
            /entries/{entry_id}:
              get:
                operationId: getEntry
                parameters:
                  - { name: entry_id, in: path, required: true, schema: { type: string } }
                responses:
                  '200': { description: ok }
        YAML
        text, = generate(spec, dir)

        expect(headings(text)).to eq(sections)
        expect(text).to include('не объявляет авторизации', 'Вебхуков в спецификации не объявлено',
                                'STATUS_MAP пуста', 'ERROR_MAP пуста', 'серверов в спецификации нет')
        expect(text).to include('Допущения этого прогона')
        expect(text).not_to include('#<')
      end
    end
  end

  describe 'a webhook without a signature' do
    it 'says the service rejects every notification and offers the overlay fragment' do
      Dir.mktmpdir('specgen-unsigned') do |dir|
        spec = write_bare_spec(dir, <<~YAML)
          openapi: 3.0.3
          info: { title: Unsigned Pay, version: '1' }
          paths:
            /payouts:
              post:
                operationId: createPayout
                requestBody:
                  content:
                    application/json:
                      schema: { type: object, properties: { amount: { type: integer }, currency: { type: string, enum: [RUB] } } }
                responses:
                  '201': { description: created }
            /webhooks/payout:
              post:
                operationId: payoutWebhook
                security: []
                requestBody:
                  content:
                    application/json:
                      schema: { type: object, properties: { payout_id: { type: string }, status: { type: string, enum: [completed, failed] } } }
                responses:
                  '200': { description: ok }
        YAML
        text, = generate(spec, dir)

        expect(headings(text)).to eq(sections)
        expect(text).to include('отклоняет все уведомления', 'x-specgen-signature')
        expect(text).to include('по умолчанию — не выведено')
      end
    end
  end
end
