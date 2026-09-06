# frozen_string_literal: true

RSpec.describe SpecGen::Analyzers::UnitsAnalyzer do
  include Fixtures
  include RulesFixtures

  # The fixture dictionaries: RUB (2), JPY (0), KWD (3) and one synonym per
  # role, so every example says which signal it is about.
  let(:rules) { load_rules }

  def analyze(data)
    document = SpecGen::SpecLoader::Document.new(file: 'provider_api.yaml', version: '3.0.3',
                                                 family: :oas30, raw: data, data: data)
    described_class.call(document: document, profile: SpecGen::IR::ProviderProfile.new,
                         rules: rules)
  end

  def with_request(properties)
    schema = { 'type' => 'object', 'properties' => properties }
    body = { 'required' => true, 'content' => { 'application/json' => { 'schema' => schema } } }
    analyze('openapi' => '3.0.3',
            'paths' => { '/payouts' => { 'post' => { 'operationId' => 'createPayout',
                                                     'requestBody' => body } } })
  end

  def units_for(amount, currency = { 'type' => 'string', 'enum' => ['RUB'] })
    with_request('amount' => amount, 'currency' => currency).units
  end

  def codes(profile)
    profile.warnings.map(&:code)
  end

  describe 'ISO 4217 by the currency code' do
    it 'reads integer plus RUB as minor units with exponent 2, and says which standard' do
      units = units_for('type' => 'integer', 'example' => 1500)

      expect(units.unit).to have_attributes(value: :minor, source: :structural)
      expect(units.exponent).to have_attributes(value: 2, source: :registry, confidence: 0.9)
      expect(units.exponent.evidence).to eq('ISO 4217: экспонента RUB 2')
      expect(units.currency).to have_attributes(value: 'RUB', source: :structural)
      expect(units.currency.evidence).to eq('enum: [RUB] у поля `currency`')
      expect(units.multiplier).to eq(100)
    end

    it 'gives JPY exponent 0, so minor and major coincide' do
      units = units_for({ 'type' => 'integer' }, { 'type' => 'string', 'enum' => ['JPY'] })

      expect(units.exponent.value).to eq(0)
      expect(units.exponent.evidence).to eq('ISO 4217: экспонента JPY 0')
      expect(units.multiplier).to eq(1)
    end

    it 'states the exponent in English when the locale is switched' do
      SpecGen::Texts.locale = 'en'

      expect(units_for('type' => 'integer').exponent.evidence).to eq('ISO 4217: RUB exponent 2')
    end

    it 'reads a currency const the same way as a one-value enum' do
      units = units_for({ 'type' => 'integer' }, { 'type' => 'string', 'const' => 'KWD' })

      expect(units.currency.evidence).to eq('const: [KWD] у поля `currency`')
      expect(units.exponent.value).to eq(3)
    end

    it 'takes the default exponent for a code outside the table, but never silently' do
      profile = with_request('amount' => { 'type' => 'integer' },
                             'currency' => { 'type' => 'string', 'enum' => ['XYZ'] })
      units = profile.units

      expect(units.exponent).to have_attributes(value: 2, source: :registry, confidence: 0.5)
      expect(profile.warnings.first).to have_attributes(code: :currency_unknown, severity: :warning)
      expect(profile.warnings.first.message).to include('XYZ', 'ISO 4217', 'по умолчанию 2')
      expect(profile.warnings.first.suggested_overlay).to include('x-specgen-currency: RUB')
    end
  end

  describe 'the currency when the enum does not settle it' do
    it 'takes a default with less confidence, and an example with less still' do
      by_default = units_for({ 'type' => 'integer' }, { 'type' => 'string', 'default' => 'rub' })
      by_example = units_for({ 'type' => 'integer' }, { 'type' => 'string', 'example' => 'RUB' })

      expect(by_default.currency).to have_attributes(value: 'RUB', source: :heuristic, confidence: 0.7)
      expect(by_example.currency).to have_attributes(value: 'RUB', source: :heuristic, confidence: 0.6)
      expect(by_example.currency.evidence).to include('example: RUB', 'одна из возможных валют')
      expect(by_example.exponent.value).to eq(2)
    end

    it 'looks for the currency in other schemas when the request has none' do
      response = { 'type' => 'object',
                   'properties' => { 'currency' => { 'type' => 'string', 'example' => 'JPY' } } }
      request = { 'type' => 'object', 'properties' => { 'amount' => { 'type' => 'integer' } } }
      profile = analyze(
        'openapi' => '3.0.3',
        'paths' => { '/payouts' => { 'post' => {
          'operationId' => 'createPayout',
          'requestBody' => { 'content' => { 'application/json' => { 'schema' => request } } },
          'responses' => { '201' => { 'content' => { 'application/json' => { 'schema' => response } } } }
        } } }
      )

      expect(profile.units.currency.value).to eq('JPY')
      expect(profile.units.exponent.value).to eq(0)
    end

    it 'derives a shared exponent from several currencies, and still reports the choice' do
      profile = with_request('amount' => { 'type' => 'integer' },
                             'currency' => { 'type' => 'string', 'enum' => %w[RUB KWD] })

      expect(profile.units.currency).to be_unknown
      expect(profile.units.exponent).to be_unknown
      expect(profile.units.exponent.evidence).to include('разные экспоненты')
      expect(profile.warnings.first).to have_attributes(code: :currency_unknown, severity: :warning)

      shared = with_request('amount' => { 'type' => 'integer' },
                            'currency' => { 'type' => 'string', 'enum' => %w[RUB RUB] })
      expect(shared.units.exponent.value).to eq(2)
    end

    # У GOV.UK Pay поле `method` объекта ссылок (пример `GET`) набрало роль
    # currency на 0.24 — три заглавные буквы прошли ограничения. Пример это
    # образец значения, а не объявление: образец вне ISO 4217 роль поля не
    # уточняет, а опровергает.
    it 'refuses an example that is not an ISO 4217 code, and names the rejected candidate' do
      profile = with_request('amount' => { 'type' => 'integer' },
                             'currency' => { 'type' => 'string', 'example' => 'GET' })

      expect(profile.units.currency).to be_unknown
      expect(profile.units.currency.evidence).to include('пример `GET` не код ISO 4217')
    end

    # Неофициальный код в enum законен: справочник даёт ему экспоненту по
    # умолчанию вместе с предупреждением. Отсеиваются только подсказки.
    it 'still accepts a declared code the table does not know, with a warning' do
      profile = with_request('amount' => { 'type' => 'integer' },
                             'currency' => { 'type' => 'string', 'enum' => ['XBT'] })

      expect(profile.units.currency.value).to eq('XBT')
      expect(codes(profile)).to include(:currency_unknown)
    end

    it 'derives nothing when no field names the currency, and asks for an overlay' do
      profile = with_request('amount' => { 'type' => 'integer' })

      expect(profile.units.currency).to be_unknown
      expect(profile.units.exponent).to be_unknown
      expect(profile.units.known?).to be(false)
      warning = profile.warnings.find { |w| w.code == :currency_unknown }
      expect(warning.message).to include('валюта суммы не выведена', 'задайте валюту в overlay')
      expect(warning.json_path).to eq("$.paths['/payouts'].post.requestBody.content['application/json'].schema.properties.amount")
    end
  end

  describe 'minor or major' do
    it 'reads a number with a fractional example as major units' do
      units = units_for('type' => 'number', 'example' => 1500.5)

      expect(units.unit).to have_attributes(value: :major, source: :structural)
      expect(units.unit.evidence).to eq('type: number, дробный example 1500.5 -> мажорные единицы')
      expect(units.multiplier).to eq(1)
    end

    it 'reads a decimal string example as major units too' do
      expect(units_for('type' => 'string', 'example' => '1500.50').unit.value).to eq(:major)
    end

    it 'derives nothing from a number without a fractional example, and warns' do
      profile = with_request('amount' => { 'type' => 'number' },
                             'currency' => { 'type' => 'string', 'enum' => ['RUB'] })

      expect(profile.units.unit).to be_unknown
      expect(profile.units.multiplier).to be_nil
      warning = profile.warnings.first
      expect(warning).to have_attributes(code: :units_unknown, severity: :warning)
      expect(warning.suggested_overlay).to include('x-specgen-amount-unit: minor', 'x-specgen-exponent: 2')
    end

    it 'uses the description only to confirm, and says so in the evidence' do
      units = units_for('type' => 'integer', 'description' => 'Сумма в копейках', 'minimum' => 100_000)

      expect(units.unit.evidence)
        .to eq('type: integer -> минорные единицы; описание подтверждает: "копейках"; minimum 100000 = 1000.00 RUB')
    end

    it 'reports a description that contradicts the type instead of believing either silently' do
      profile = with_request('amount' => { 'type' => 'integer', 'description' => 'Сумма в рублях' },
                             'currency' => { 'type' => 'string', 'enum' => ['RUB'] })

      expect(profile.units.unit.value).to eq(:minor)
      warning = profile.warnings.first
      expect(warning).to have_attributes(code: :units_inconsistent, severity: :warning)
      expect(warning.message).to include('минорные единицы', 'мажорные единицы', '"Сумма в рублях"')
    end

    it 'reports a fractional minimum on minor units' do
      profile = with_request('amount' => { 'type' => 'integer', 'minimum' => 0.01 },
                             'currency' => { 'type' => 'string', 'enum' => ['RUB'] })

      expect(codes(profile)).to eq([:units_inconsistent])
      expect(profile.warnings.first.message).to include('minimum = 0.01')
    end
  end

  describe 'overlay extensions on the amount field' do
    it 'take precedence over everything the spec says' do
      units = units_for('type' => 'integer', 'x-specgen-amount-unit' => 'major',
                        'x-specgen-exponent' => 0, 'x-specgen-currency' => 'isk')

      expect(units.unit).to have_attributes(value: :major, source: :overlay)
      expect(units.exponent).to have_attributes(value: 0, source: :overlay)
      expect(units.currency).to have_attributes(value: 'ISK', source: :overlay)
      expect(units.unit.evidence).to eq('x-specgen-amount-unit: major на поле суммы')
    end

    it 'ignores an amount unit it does not know, and reports it' do
      profile = with_request('amount' => { 'type' => 'integer', 'x-specgen-amount-unit' => 'kopecks' },
                             'currency' => { 'type' => 'string', 'enum' => ['RUB'] })

      expect(profile.units.unit).to have_attributes(value: :minor, source: :structural)
      expect(codes(profile)).to eq([:spec_element_unsupported])
    end
  end

  describe 'where the amount field is looked for' do
    it 'prefers a request body over a response, because that is what the service sends' do
      request = { 'type' => 'object', 'properties' => { 'amount' => { 'type' => 'number', 'example' => 1.5 },
                                                        'currency' => { 'type' => 'string', 'enum' => ['RUB'] } } }
      component = { 'type' => 'object', 'properties' => { 'amount' => { 'type' => 'integer' } } }
      profile = analyze(
        'openapi' => '3.0.3',
        'components' => { 'schemas' => { 'Payout' => component } },
        'paths' => { '/payouts' => { 'post' => {
          'operationId' => 'createPayout',
          'requestBody' => { 'content' => { 'application/json' => { 'schema' => request } } }
        } } }
      )

      expect(profile.units.unit.value).to eq(:major)
      expect(profile.units.json_path).to start_with("$.paths['/payouts'].post.requestBody")
    end

    # У GOV.UK Pay все тела вынесены в components и приходят по $ref, а
    # разыменованная схема сохраняет имя компонента и не заводит второй
    # записи. Пока предпочтение опиралось на место объявления, ни одна
    # схема не считалась телом запроса, и поле суммы искалось по алфавиту:
    # побеждал счётчик результатов поиска.
    it 'prefers a component the request body refers to over one that only sorts earlier' do
      referred = { 'type' => 'object', 'x-specgen-ref' => '#/components/schemas/PayoutRequest',
                   'properties' => { 'amount' => { 'type' => 'number', 'example' => 1.5 },
                                     'currency' => { 'type' => 'string', 'enum' => ['RUB'] } } }
      profile = analyze(
        'openapi' => '3.0.3',
        'components' => { 'schemas' => {
          'AgreementSearchResults' => { 'type' => 'object',
                                        'properties' => { 'amount' => { 'type' => 'integer' } } },
          'PayoutRequest' => referred
        } },
        'paths' => { '/payouts' => { 'post' => {
          'operationId' => 'createPayout',
          'requestBody' => { 'content' => { 'application/json' => { 'schema' => referred } } }
        } } }
      )

      expect(profile.units.json_path).to eq('$.components.schemas.PayoutRequest.properties.amount')
      expect(profile.units.unit.value).to eq(:major)
    end

    it 'leaves units nil and warns when no schema has an amount at all' do
      profile = analyze('openapi' => '3.0.3',
                        'components' => { 'schemas' => { 'Thing' => { 'type' => 'object',
                                                                      'properties' => { 'x' => { 'type' => 'string' } } } } },
                        'paths' => {})

      expect(profile.units).to be_nil
      expect(profile.warnings.first).to have_attributes(code: :units_unknown, json_path: '$.components.schemas')
      expect(profile.warnings.first.message).to include('поле суммы не найдено')
    end

    it 'does not raise on a document whose schemas are malformed' do
      expect { analyze('openapi' => '3.0.3', 'components' => { 'schemas' => 'nope' }, 'paths' => 'nope') }
        .not_to raise_error
    end
  end

  # The shipped dictionaries: `amt` is a token hint of the amount role, not a
  # synonym, so only the composite matcher can name that field — and the
  # fixture dictionaries carry no hints.
  describe 'an amount field only the matchers can name' do
    def with_shipped(properties)
      body = { 'content' => { 'application/json' => { 'schema' => { 'type' => 'object',
                                                                    'properties' => properties } } } }
      document = SpecGen::SpecLoader::Document.new(
        file: 'provider_api.yaml', version: '3.0.3', family: :oas30, raw: {},
        data: { 'openapi' => '3.0.3',
                'paths' => { '/t' => { 'post' => { 'operationId' => 'createTransaction',
                                                   'requestBody' => body } } } }
      )
      described_class.call(document: document, profile: SpecGen::IR::ProviderProfile.new,
                           rules: SpecGen::Rules.load)
    end

    it 'takes the role the matchers assigned instead of saying no amount field exists' do
      profile = with_shipped('amt' => { 'type' => 'integer' },
                             'currency' => { 'type' => 'string', 'enum' => ['RUB'] })

      expect(profile.units.unit.value).to eq(:minor)
      expect(profile.units.exponent.value).to eq(2)
      expect(profile.units.json_path).to end_with('.properties.amt')
      expect(profile.warnings.map(&:code)).not_to include(:units_unknown)
    end

    it 'never claims more confidence than the role it rests on, and names it' do
      profile = with_shipped('amt' => { 'type' => 'integer' },
                             'currency' => { 'type' => 'string', 'enum' => ['RUB'] })

      expect(profile.units.unit).to have_attributes(value: :minor, source: :heuristic)
      expect(profile.units.unit.confidence).to be < 1.0
      expect(profile.units.unit.evidence).to include('`amt` опознано как amount матчерами')
    end

    it 'leaves the dictionary in charge when the document names an amount field itself' do
      profile = with_shipped('amount' => { 'type' => 'integer' },
                             'amt' => { 'type' => 'integer' },
                             'currency' => { 'type' => 'string', 'enum' => ['RUB'] })

      expect(profile.units.json_path).to end_with('.properties.amount')
      expect(profile.units.unit).to have_attributes(source: :structural, confidence: 1.0)
    end
  end

  describe 'on the spec as shipped' do
    let(:profile) do
      document = SpecGen::SpecLoader.load(spec_fixture('novapay.yaml'))
      described_class.call(document: document, profile: SpecGen::IR::ProviderProfile.new,
                           rules: SpecGen::Rules.load)
    end

    it 'derives minor units, exponent 2 and RUB from the payout request, with no warning' do
      units = profile.units

      expect(units.unit.value).to eq(:minor)
      expect(units.exponent.value).to eq(2)
      expect(units.currency.value).to eq('RUB')
      expect(units.multiplier).to eq(100)
      expect(units.json_path).to eq('$.components.schemas.CreatePayoutRequest.properties.amount')
      expect(units.unit.evidence).to include('описание подтверждает: "копейках"', 'minimum 100000 = 1000.00 RUB')
      expect(profile.warnings).to be_empty
    end
  end
end
