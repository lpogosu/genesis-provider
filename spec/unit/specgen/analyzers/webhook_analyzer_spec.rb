# frozen_string_literal: true

RSpec.describe SpecGen::Analyzers::WebhookAnalyzer do
  include Fixtures
  include RulesFixtures

  # The fixture dictionaries: canon pending/completed/failed with on_hold
  # ambiguous; signature profiles standard_webhooks and raw_hex
  # (X-Signature), plus x-callback-signature as a header with no profile.
  let(:rules) { load_rules }

  def analyze(data, family = :oas30)
    document = SpecGen::SpecLoader::Document.new(file: 'provider_api.yaml', version: family == :oas31 ? '3.1.0' : '3.0.3',
                                                 family: family, raw: data, data: data)
    described_class.call(document: document, profile: SpecGen::IR::ProviderProfile.new,
                         rules: rules)
  end

  def header(name, description = nil)
    { 'name' => name, 'in' => 'header', 'required' => true, 'schema' => { 'type' => 'string' },
      'description' => description }.compact
  end

  def body_schema(properties)
    { 'x-specgen-ref' => '#/components/schemas/WebhookPayload', 'type' => 'object', 'properties' => properties }
  end

  def event_properties
    { 'event' => { 'type' => 'string', 'enum' => %w[payout.completed payout.failed payout.pending] },
      'status' => { 'type' => 'string', 'enum' => %w[pending completed failed] } }
  end

  def webhook_operation(properties: event_properties, headers: [header('X-Signature', 'HMAC-SHA256 of the body')],
                        examples: {}, description: nil)
    media = { 'schema' => body_schema(properties) }
    media['examples'] = examples unless examples.empty?
    { 'operationId' => 'payoutWebhook', 'security' => [], 'parameters' => headers, 'description' => description,
      'requestBody' => { 'required' => true, 'content' => { 'application/json' => media } },
      'responses' => { '200' => { 'description' => 'ok' } } }.compact
  end

  def with_webhook(**options)
    operation = webhook_operation(**options)
    analyze('openapi' => '3.0.3', 'paths' => { '/webhooks/payout' => { 'post' => operation } })
  end

  def codes(profile)
    profile.warnings.map(&:code)
  end

  describe 'finding the webhook' do
    it 'reads an unsecured POST with a body as the inbound webhook, naming its body schema' do
      webhook = with_webhook.webhooks.first

      expect(webhook).to have_attributes(path: '/webhooks/payout', operation: 'payoutWebhook',
                                         schema: 'WebhookPayload', json_path: "$.paths['/webhooks/payout'].post")
    end

    it 'reads the 3.1 webhooks section too, with no operation of its own' do
      operation = webhook_operation
      operation.delete('security')
      profile = analyze({ 'openapi' => '3.1.0', 'paths' => {}, 'webhooks' => { 'payoutEvent' => { 'post' => operation } } },
                        :oas31)
      webhook = profile.webhooks.first

      expect(webhook).to have_attributes(path: 'payoutEvent', operation: nil, schema: 'WebhookPayload',
                                         json_path: '$.webhooks.payoutEvent.post')
      expect(webhook.events.size).to eq(3)
    end

    # Found on Mollie's public spec: webhooks entries carry no requestBody
    # schema at all. A missing schema is a webhook with nothing to read, not
    # a crash.
    it 'survives a webhooks entry without a body schema' do
      operation = { 'operationId' => 'paymentWebhook', 'requestBody' => { 'content' => { 'application/json' => {} } },
                    'responses' => { '200' => { 'description' => 'ok' } } }
      profile = analyze({ 'openapi' => '3.1.0', 'paths' => {}, 'webhooks' => { 'payment' => { 'post' => operation } } },
                        :oas31)

      expect(profile.webhooks.first).to have_attributes(path: 'payment', schema: nil, events: [])
    end

    it 'reports a spec with no webhook at all as information: status by polling only' do
      profile = analyze('openapi' => '3.0.3',
                        'paths' => { '/payouts' => { 'post' => { 'operationId' => 'createPayout',
                                                                 'requestBody' => { 'content' => {} } } } })

      expect(profile.webhooks).to be_empty
      expect(profile.warnings.first).to have_attributes(code: :webhook_missing, severity: :info, json_path: '$.paths')
      expect(profile.warnings.first.message).to include('только опросом')
    end
  end

  describe 'events' do
    it 'reads every event of the enum and translates each through the status reader, prefix stripped' do
      events = with_webhook.webhooks.first.events

      expect(events.map(&:name)).to eq(%w[payout.completed payout.failed payout.pending])
      expect(events.map { |event| event.internal_status.value }).to eq(%i[approved rejected in_progress])
      expect(events.map(&:provider_status)).to eq(%w[completed failed pending])
      expect(events.first.internal_status.evidence)
        .to eq('событие payout.completed читается как статус completed; канон кейса: completed -> approved')
      expect(events.first.json_path).to eq('$.components.schemas.WebhookPayload.properties.event.enum[0]')
    end

    it 'attaches the example whose event matches' do
      examples = { 'done' => { 'value' => { 'event' => 'payout.completed', 'status' => 'completed' } } }
      events = with_webhook(examples: examples).webhooks.first.events

      expect(events.first.example).to eq('event' => 'payout.completed', 'status' => 'completed')
      expect(events.last.example).to be_nil
    end

    it 'leaves an event it cannot read unknown and offers the status-map overlay on the event field' do
      properties = { 'event' => { 'type' => 'string', 'enum' => %w[payout.completed payout.on_hold] } }
      profile = with_webhook(properties: properties)
      event = profile.webhooks.first.events.last
      warning = profile.warnings.find { |w| w.code == :webhook_event_unmapped }

      expect(event.internal_status).to be_unknown
      expect(warning.message).to include('событие payout.on_hold не переведено', 'неоднозначен')
      expect(warning.json_path).to end_with('.event.enum[1]')
      expect(warning.suggested_overlay).to include('$.components.schemas.WebhookPayload.properties.event', 'payout.on_hold: in_progress')
    end

    it 'adds an event that only an example carries, and reports it' do
      examples = { 'stuck' => { 'value' => { 'event' => 'payout.pending_review' } } }
      profile = with_webhook(examples: examples)

      expect(profile.webhooks.first.events.map(&:name)).to include('payout.pending_review')
      warning = profile.warnings.find { |w| w.code == :webhook_event_undeclared }
      expect(warning.message).to include('payout.pending_review встречается в примере stuck')
      expect(warning.json_path).to end_with('.examples.stuck.value')
    end

    it 'falls back to the status field when no enum reads as events' do
      properties = { 'kind' => { 'type' => 'string', 'enum' => %w[sbp card] },
                     'status' => { 'type' => 'string', 'enum' => %w[pending completed] } }
      events = with_webhook(properties: properties).webhooks.first.events

      expect(events.map(&:name)).to eq(%w[pending completed])
      expect(events.first.internal_status.evidence).to start_with('поле события не найдено')
    end

    it 'reports a body with neither events nor statuses' do
      profile = with_webhook(properties: { 'payout_id' => { 'type' => 'string' } })

      expect(profile.webhooks.first.events).to be_empty
      expect(codes(profile)).to include(:webhook_event_unmapped)
      expect(profile.warnings.find { |w| w.code == :webhook_event_unmapped }.message).to include('нет ни поля события')
    end
  end

  describe 'signature' do
    it 'takes the whole profile from the dictionary when the header matches one, confirmed by the description' do
      signature = with_webhook.webhooks.first.signature

      expect(signature.profile).to have_attributes(value: :custom, source: :registry)
      expect(signature.header).to have_attributes(value: 'X-Signature', source: :structural)
      expect(signature.algorithm.value).to eq(:hmac_sha256)
      expect(signature.algorithm.evidence)
        .to eq('профиль rules/signatures.yml raw_hex совпал по заголовку X-Signature; описание подтверждает: "HMAC-SHA256"')
      expect(signature.encoding.value).to eq(:hex)
      expect(signature.payload.value).to eq(:raw_body)
      expect(signature.secret_key.value).to eq('webhook_secret')
      expect(signature.complete?).to be(true)
    end

    it 'keeps the dictionary profile but warns when the description names another algorithm' do
      profile = with_webhook(headers: [header('X-Signature', 'HMAC-SHA512 of the body')])
      signature = profile.webhooks.first.signature
      warning = profile.warnings.find { |w| w.code == :signature_profile_conflict }

      expect(signature.algorithm.value).to eq(:hmac_sha256)
      expect(warning.message).to include('"HMAC-SHA512"', 'hmac_sha512', 'raw_hex', 'hmac_sha256')
    end

    it 'recognises Standard Webhooks by its three headers' do
      headers = [header('webhook-id'), header('webhook-timestamp'), header('webhook-signature')]
      signature = with_webhook(headers: headers).webhooks.first.signature

      expect(signature.profile.value).to eq(:standard_webhooks)
      expect(signature.payload.value).to eq(:id_timestamp_body)
      expect(signature.tolerance.value).to eq(300)
      expect(signature).to have_attributes(id_header: 'webhook-id', timestamp_header: 'webhook-timestamp')
      expect(signature.complete?).to be(true)
    end

    it 'builds a custom profile for a known header with no dictionary profile, and asks for the rest' do
      profile = with_webhook(headers: [header('X-Callback-Signature', 'HMAC-SHA256 подпись тела')])
      signature = profile.webhooks.first.signature
      warning = profile.warnings.find { |w| w.code == :signature_profile_incomplete }

      expect(signature.profile.value).to eq(:custom)
      expect(signature.algorithm).to have_attributes(value: :hmac_sha256, source: :heuristic, confidence: 0.7)
      expect(signature.encoding).to be_unknown
      expect(signature.payload).to be_unknown
      expect(signature.secret_key).to have_attributes(value: 'webhook_secret', source: :registry)
      expect(signature.missing).to eq(%i[encoding payload])
      expect(warning.message).to include('неполон: не выведены encoding, payload')
      expect(warning.suggested_overlay).to include('x-specgen-signature:', 'header: X-Callback-Signature',
                                                   'algorithm: hmac_sha256', 'encoding: hex')
    end

    it 'leaves the signature nil and warns when the webhook declares no signature header' do
      profile = with_webhook(headers: [header('X-Request-Id')])

      expect(profile.webhooks.first.signature).to be_nil
      warning = profile.warnings.find { |w| w.code == :signature_profile_incomplete }
      expect(warning.message).to include('не объявляет заголовок подписи')
      expect(warning.suggested_overlay).to include('x-specgen-signature:')
    end

    it 'lets x-specgen-signature complete a custom profile, and rejects values outside the vocabulary' do
      operation = webhook_operation(headers: [header('X-Callback-Signature')])
      operation['x-specgen-signature'] = { 'encoding' => 'base64', 'payload' => 'raw_body', 'algorithm' => 'md5' }
      profile = analyze('openapi' => '3.0.3', 'paths' => { '/webhooks/payout' => { 'post' => operation } })
      signature = profile.webhooks.first.signature

      expect(signature.encoding).to have_attributes(value: :base64, source: :overlay)
      expect(signature.payload.value).to eq(:raw_body)
      expect(signature.algorithm).to be_unknown
      expect(profile.warnings.map(&:code)).to include(:spec_element_unsupported, :signature_profile_incomplete)
      expect(profile.warnings.find { |w| w.code == :spec_element_unsupported }.message).to include('"md5"')
    end

    it 'says the same in English when the locale is switched' do
      SpecGen::Texts.locale = 'en'
      profile = with_webhook(headers: [header('X-Callback-Signature')])

      expect(profile.warnings.find { |w| w.code == :signature_profile_incomplete }.message)
        .to include('is incomplete: algorithm, encoding, payload not derived')
    end
  end

  describe 'on the spec as shipped' do
    let(:profile) do
      document = SpecGen::SpecLoader.load(spec_fixture('novapay.yaml'))
      described_class.call(document: document, profile: SpecGen::IR::ProviderProfile.new,
                           rules: SpecGen::Rules.load)
    end

    it 'reads the one webhook with its four events, all mapped' do
      webhook = profile.webhooks.first

      expect(profile.webhooks.size).to eq(1)
      expect(webhook).to have_attributes(path: '/webhooks/payout', operation: 'payoutWebhook', schema: 'WebhookPayload')
      expect(webhook.events.map(&:name)).to eq(%w[payout.completed payout.failed payout.processing payout.cancelled])
      expect(webhook.events.map { |event| event.internal_status.value }).to eq(%i[approved rejected in_progress rejected])
      expect(webhook.events.first.example).to include('event' => 'payout.completed', 'status' => 'completed')
      expect(webhook.unmapped_events).to be_empty
    end

    it 'takes the signature profile the dictionary declares for the header, confirmed by the prose' do
      signature = profile.webhooks.first.signature

      expect(signature.header.value).to eq('X-NovaPay-Signature')
      expect(signature.profile).to have_attributes(value: :custom, source: :registry)
      expect(signature.algorithm.value).to eq(:hmac_sha256)
      expect(signature.algorithm.evidence).to include('подтверждает: "HMAC-SHA256"')
      expect(signature.encoding.value).to eq(:hex)
      expect(signature.payload.value).to eq(:raw_body)
      expect(profile.webhooks.first.verifiable?).to be(true)
      expect(profile.warnings).to be_empty
    end
  end
end
