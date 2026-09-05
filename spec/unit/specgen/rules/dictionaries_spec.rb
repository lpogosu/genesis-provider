# frozen_string_literal: true

# Справочники, с которыми инструмент действительно поставляется. Всё
# остальное в spec/unit/specgen/rules гоняет загрузчик на самодельных
# фикстурах; этот файл — приёмочный тест самих данных из rules/ и причина,
# по которой плохой синоним не может попасть в релиз: сначала краснеет прогон.
RSpec.describe 'the shipped dictionaries' do
  subject(:rules) { SpecGen::Rules.load }

  it 'loads without a single complaint' do
    expect { SpecGen::Rules.load }.not_to raise_error
  end

  describe 'roles' do
    it 'covers every role of the closed vocabulary' do
      expect(rules.roles.roles).to eq(SpecGen::IR::Roles::FIELD)
    end

    it 'reads both the English and the transliterated spelling of a bank code' do
      expect(rules.roles.role_for('bic')).to eq(:bank_code)
      expect(rules.roles.role_for('bik')).to eq(:bank_code)
      expect(rules.roles.role_for('BIK')).to eq(:bank_code)
    end

    it 'tells our identifier at the provider from the provider own one' do
      expect(rules.roles.role_for('external_id')).to eq(:external_id)
      expect(rules.roles.role_for('payout_id')).to eq(:provider_operation_id)
    end

    it 'weights the name above the constraints, the constraints no lower than the structure, the type last' do
      book = rules.roles

      expect(book.weight(:name)).to be > book.weight(:constraint)
      expect(book.weight(:constraint)).to be >= book.weight(:structure)
      expect(book.weight(:structure)).to be > book.weight(:type)
      expect(book.scoring(:threshold)).to eq(0.6)
    end

    it 'lets no matcher reach the threshold on its own' do
      book = rules.roles

      SpecGen::Rules::RolesMatchers::MATCHERS.each do |matcher|
        expect(book.weight(matcher).fdiv(book.total_weight)).to be < book.scoring(:threshold)
      end
    end

    it 'carries samples for every role with patterns, so a foreign pattern can be recognised' do
      book = rules.roles

      with_patterns = book.roles.reject { |role| book.hints(role)[:patterns].empty? }

      expect(with_patterns).not_to be_empty
      with_patterns.each do |role|
        expect(book.hints(role)[:samples]).not_to be_empty, "role #{role} has patterns but no samples"
      end
    end

    it 'expects the idempotency key and the signature in a header, the operation id in the path' do
      expect(rules.roles.hints(:idempotency_key)[:locations]).to eq([:header])
      expect(rules.roles.hints(:signature)[:locations]).to eq([:header])
      expect(rules.roles.hints(:provider_operation_id)[:locations]).to eq([:path])
    end

    it 'treats id, name, type and code as generic tokens' do
      expect(rules.roles.generic_tokens).to include('id', 'name', 'type', 'code')
    end
  end

  describe 'statuses' do
    it 'maps the canon of the case description' do
      expect(rules.statuses.internal_for('pending')).to eq(:in_progress)
      expect(rules.statuses.internal_for('processing')).to eq(:in_progress)
      expect(rules.statuses.internal_for('completed')).to eq(:approved)
      expect(rules.statuses.internal_for('failed')).to eq(:rejected)
      expect(rules.statuses.internal_for('cancelled')).to eq(:rejected)
    end

    it 'maps the synonyms other providers use' do
      expect(rules.statuses.internal_for('succeeded')).to eq(:approved)
      expect(rules.statuses.internal_for('declined')).to eq(:rejected)
      expect(rules.statuses.internal_for('queued')).to eq(:in_progress)
    end

    it 'lists the words that change the meaning of the status they precede' do
      expect(rules.statuses.modifier(%w[part])).to eq('part')
      expect(rules.statuses.modifier(%w[partially])).to eq('partially')
      expect(rules.statuses.modifier(%w[auth adjustment])).to be_nil
      expect(rules.statuses.tail_confidence).to be < 0.6
    end

    it 'keeps every modifier out of the statuses themselves' do
      expect(rules.statuses.modifiers.map { |word| rules.statuses.internal_for(word) }).to all(be_nil)
    end
  end

  describe 'currencies' do
    it 'carries the whole of ISO 4217, not a handful of codes' do
      expect(rules.currencies.codes.size).to be >= 150
    end

    it 'knows the exponents that are not two' do
      expect(rules.currencies.exponent('RUB')).to eq(2)
      expect(rules.currencies.exponent('JPY')).to eq(0)
      expect(rules.currencies.exponent('ISK')).to eq(0)
      expect(rules.currencies.exponent('KWD')).to eq(3)
      expect(rules.currencies.exponent('CLF')).to eq(4)
    end

    it 'reads the unit words of the shipped spec and of the industry, as confirmation only' do
      expect(rules.currencies.unit_hint('Сумма в копейках')).to eq([:minor, 'копейках'])
      expect(rules.currencies.unit_hint('Минимальная сумма — 1000 RUB (100000 коп.)')).to eq([:minor, 'коп.'])
      expect(rules.currencies.unit_hint('Amount in minor units')).to eq([:minor, 'minor units'])
      expect(rules.currencies.unit_hint('Amount in roubles')).to eq([:major, 'roubles'])
      expect(rules.currencies.unit_hint('Percents of the amount')).to be_nil
    end
  end

  describe 'signatures' do
    it 'ships the Standard Webhooks profile as the default' do
      expect(rules.signatures.default)
        .to include(profile: :standard_webhooks, algorithm: :hmac_sha256, encoding: :base64,
                    payload: :id_timestamp_body)
    end

    it 'ships a raw-body hex profile as well' do
      raw = rules.signatures.names.map { |name| rules.signatures.profile(name) }
      expect(raw).to include(hash_including(payload: :raw_body, encoding: :hex))
    end

    it 'reads the algorithm words of the shipped spec and of the industry' do
      expect(rules.signatures.algorithm_hint('HMAC-SHA256 подпись тела запроса')).to eq([:hmac_sha256, 'HMAC-SHA256'])
      expect(rules.signatures.algorithm_hint('sha512 hmac')).to eq([:hmac_sha512, 'sha512'])
      expect(rules.signatures.algorithm_hint('HMAC SHA1')).to eq([:hmac_sha1, 'HMAC SHA1'])
      expect(rules.signatures.algorithm_hint('signature of the body')).to be_nil
    end

    it 'finds the profile behind a header the spec declares' do
      name, entry = rules.signatures.profile_for_header('webhook-signature')

      expect(name).to eq('standard_webhooks')
      expect(entry[:payload]).to eq(:id_timestamp_body)
    end
  end

  describe 'idempotency' do
    it 'knows the header names the industry uses' do
      expect(rules.idempotency).to be_alias('Idempotency-Key')
      expect(rules.idempotency).to be_alias('X-Idempotency-Key')
      expect(rules.idempotency).to be_alias('X-Request-Id')
      expect(rules.idempotency).to be_alias('X-Unique-Transaction-Id')
    end

    it 'derives the key deterministically' do
      expect(rules.idempotency.default_strategy).to eq(:uuid_v5)
      expect(rules.idempotency.conflict_status).to eq(409)
    end
  end

  describe 'auth' do
    {
      api_key: { 'type' => 'apiKey', 'in' => 'header', 'name' => 'X-API-Key' },
      bearer: { 'type' => 'http', 'scheme' => 'bearer' },
      basic: { 'type' => 'http', 'scheme' => 'basic' },
      oauth2: { 'type' => 'oauth2', 'flows' => { 'clientCredentials' => {} } }
    }.each do |expected, declaration|
      it "recognises #{expected}" do
        expect(rules.auth.scheme_for(declaration)&.fetch(:ir_type)).to eq(expected)
      end
    end
  end

  describe 'operations' do
    it 'describes every role the matcher can assign' do
      expect(rules.operations.roles).to eq(SpecGen::IR::Roles::OPERATION - [:unmapped])
    end

    it 'weights the operation name above the path, and the path above the tag' do
      book = rules.operations

      expect(book.weight(:operation_id)).to be > book.weight(:path_tail)
      expect(book.weight(:path_tail)).to be > book.weight(:tag)
      expect(book.scoring(:floor)).to be >= book.weight(:operation_id)
    end
  end

  describe 'conditions' do
    {
      'БИК банка (обязателен для type=sbp)' => %w[type sbp],
      'Номер карты (обязателен для type=card)' => %w[type card],
      'Required when recipient_type is card' => %w[recipient_type card],
      'Only for type = sbp' => %w[type sbp]
    }.each do |sentence, (field, value)|
      it "reads #{sentence.inspect} as #{field}=#{value}" do
        _, found = rules.conditions.match(sentence)

        expect(found).not_to be_nil, 'no pattern matched'
        expect([found[:field], found[:value]]).to eq([field, value])
      end
    end

    it 'keeps a condition read from prose below the matcher threshold' do
      expect(rules.conditions.hint_confidence).to be < 0.6
    end

    it 'reads nothing out of a sentence that only describes a field' do
      expect(rules.conditions.match('Телефон получателя (11 цифр, начинается с 7)')).to be_nil
    end

    {
      'Отмена возможна только в статусах pending и processing' => 'pending и processing',
      'Cancellation is allowed only in status pending' => 'pending',
      'The payout can be cancelled only while pending or processing' => 'pending or processing',
      'A payout may be cancelled when the status is pending' => 'pending'
    }.each do |sentence, tail|
      it "reads the status tail of #{sentence.inspect}" do
        _, found = rules.conditions.match_restriction(sentence)

        expect(found).not_to be_nil, 'no restriction pattern matched'
        expect(found[:statuses]).to eq(tail)
      end
    end

    it 'reads no restriction out of a plain cancel description' do
      expect(rules.conditions.match_restriction('Отменить выплату')).to be_nil
      expect(rules.conditions.restriction_confidence).to eq(0.6)
    end
  end

  describe 'errors' do
    it 'treats credentials as an alert, the provider balance as a delayed retry and the rest of 4xx as a rejection' do
      expect(rules.errors.action_for_status(401)).to eq([:alert, '401'])
      expect(rules.errors.action_for_status(402)).to eq([:retry_backoff, '402'])
      expect(rules.errors.action_for_status(422)).to eq([:reject, '4xx'])
      expect(rules.errors.action_for_status(429)).to eq([:retry_backoff, '429'])
      expect(rules.errors.action_for_status(500)).to eq([:retry_backoff, '5xx'])
    end

    it 'never hands out dedup: that is derived from the response schemas' do
      expect(rules.errors.action_for_status(409)).to eq([:reject, '409'])
    end

    it 'reads every code of the shipped spec, with rate_limit winning over limit_exceeded' do
      actions = %w[validation_error insufficient_balance recipient_not_found bank_unavailable
                   amount_limit_exceeded rate_limit_exceeded internal_error unauthorized not_found
                   invalid_status].to_h { |code| [code, rules.errors.rule_for_code(code)&.action] }

      expect(actions).to eq('validation_error' => :reject, 'insufficient_balance' => :retry_backoff,
                            'recipient_not_found' => :reject, 'bank_unavailable' => :retry_backoff,
                            'amount_limit_exceeded' => :reject, 'rate_limit_exceeded' => :retry_backoff,
                            'internal_error' => :retry_backoff, 'unauthorized' => :alert,
                            'not_found' => :reject, 'invalid_status' => :reject)
    end

    # Эксперты 5 сентября 2026 (вопрос 22): amount_limit_exceeded — лимит ОДНОЙ
    # выплаты, операцию отклоняем. Суточная квота — другое: она восстановится,
    # но не в окне ретраев, и решение принимает человек.
    it 'tells a per-payout limit from a daily quota, since the answer differs' do
      limit = rules.errors.rule_for_code('amount_limit_exceeded')
      quota = rules.errors.rule_for_code('daily_limit_reached')

      expect([limit.name, limit.action]).to eq(['operation_limit', :reject])
      expect([quota.name, quota.action]).to eq(['quota', :escalate])
    end
  end

  describe 'the contract' do
    # Ответ экспертов от 5 сентября 2026 (вопрос 18): у операции есть id,
    # amount и payout_requisite; плоских реквизитов и валюты нет.
    it 'reads only what the platform guarantees on an operation, keeping the amount raw' do
      platform = rules.contract.platform

      %i[amount external_id provider_operation_id status idempotency_key].each do |role|
        expect(platform.accessor(role)).not_to be_nil, "no platform expression for #{role}"
      end
      expect(platform.accessor(:amount)).to eq('operation.amount')
      expect(platform.accessor(:provider_operation_id)).to eq('operation.provider_operation_key')
      %i[currency recipient_type recipient_phone bank_code bank_name card_number].each do |role|
        expect(platform.accessor(role)).to be_nil, "#{role} is not a field of an operation"
      end
      expect(platform.callback_body).to eq('payload')
      expect(platform.source).to include('эксперты кейса 5 сентября 2026')
    end

    # Реквизиты — из JSONB-хеша, ключ верхнего уровня это payment_method
    # шлюза; у карты плоский ключ (ответ на вопрос 23).
    it 'keeps the recipient requisites per payout method of the platform' do
      requisites = rules.contract.platform.requisites

      expect(requisites.hash_expression).to eq('operation.payout_requisite')
      expect(requisites.payment_methods).to eq(%w[sbp card])
      expect(requisites.expression('sbp', :recipient_phone))
        .to eq("operation.payout_requisite.dig('sbp', 'phone')")
      expect(requisites.expression('card', :card_number))
        .to eq("operation.payout_requisite['card_number']")
      expect(requisites.expression('card', :bank_code)).to be_nil
      expect(requisites.payment_methods_for(:bank_code)).to eq(['sbp'])
    end

    # Первым аргументом failure идёт код платформы, а не наше действие
    # (ответ на вопрос 20). Действие остаётся в ERROR_MAP и участвует в
    # выборе кода, когда HTTP-кода в таблице нет.
    it 'translates a provider answer into a platform failure code' do
      codes = rules.contract.platform.failure_codes
      actions = SpecGen::IR::Roles::ERROR_ACTION

      expect(codes.by_http[401]).to eq(:unauthorized)
      expect(codes.by_http[429]).to eq(:too_many_requests)
      expect(codes.by_http.keys).to eq(codes.by_http.keys.sort)
      expect(codes.by_action.keys).to all(satisfy { |action| actions.include?(action) })
      expect(codes.validation).to eq(:unprocessable_entity)
      expect(codes.internal(:signature_invalid)).to eq(:unauthorized)
      expect(codes.internal(:webhooks_not_supported)).to eq(:not_implemented)
    end

    # Голого success платформе мало: из результата она берёт
    # provider_operation_key (ответ на вопрос 19).
    it 'returns the provider identifier from create_request' do
      platform = rules.contract.platform

      expect(platform.create_success("body['id']")).to eq("success(result: { id: body['id'] })")
    end

    it 'leaves the lookup and the writers to the platform, keeping the mechanism' do
      platform = rules.contract.platform

      expect(platform.roles(:lookup)).to be_empty
      expect(platform.roles(:writers)).to be_empty
      expect(platform.lookup(:external_id, 'v')).to be_nil
      expect(platform.writer(:provider_operation_id, 'v')).to be_nil
    end

    it 'names the helpers for the two terminal statuses' do
      expect(rules.contract.helper_for_status(:approved)).to eq('approve_operation')
      expect(rules.contract.helper_for_status(:rejected)).to eq('reject_operation')
    end

    it 'serves every operation role the contract covers' do
      SpecGen::IR::Roles::CONTRACT.each do |role|
        expect(rules.contract.method_for(role)).not_to be_nil, "no method serves #{role}"
      end
    end

    it 'names the four methods and the six helpers' do
      expect(rules.contract.method_names)
        .to include('check_conditions', 'create_request', 'process_callback', 'fetch_status')
      SpecGen::Rules::ContractBook::HELPERS.each do |helper|
        expect(rules.contract.helper(helper)).not_to be_nil, "no name for helper #{helper}"
      end
    end

    it 'states that the contract is an assumption' do
      expect(rules.contract.assumption).not_to be_nil
      expect(rules.contract.amount_unit).to eq(:major)
    end
  end

  describe 'assumptions' do
    it 'carries every row of docs/ASSUMPTIONS.md with a source and marks the platform bindings as ours' do
      book = rules.assumptions

      expect(book.all.map(&:id)).to eq((1..book.all.size).to_a)
      expect(book.all.map(&:source)).to all(match(/\S/))
      documented = book.documented.map(&:text).join
      expect(documented).to include('Provider::BaseService', 'ISO 4217', 'process_callback')
    end

    it 'keeps the project-planning assumption out of the integration guide' do
      planning = rules.assumptions.all.reject(&:documented)

      expect(planning.map(&:text).join).to include('Мок-провайдер')
    end

    it 'never names a provider: assumptions are common to every integration' do
      expect(rules.assumptions.all.map(&:text).join.downcase).not_to include('novapay')
    end
  end
end
