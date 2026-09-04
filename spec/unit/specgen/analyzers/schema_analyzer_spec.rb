# frozen_string_literal: true

RSpec.describe SpecGen::Analyzers::SchemaAnalyzer do
  include Fixtures

  # The shipped dictionaries: the prose patterns that spot a conditional
  # requirement are data, and a stub would not prove they work.
  let(:rules) { SpecGen::Rules.load }

  def analyze(data, oas31: false)
    document = SpecGen::SpecLoader::Document.new(
      file: 'provider_api.yaml', version: oas31 ? '3.1.0' : '3.0.3',
      family: oas31 ? :oas31 : :oas30, raw: data, data: data
    )
    described_class.call(document: document, profile: SpecGen::IR::ProviderProfile.new,
                         rules: rules)
  end

  def with_components(schemas, oas31: false)
    analyze({ 'components' => { 'schemas' => schemas } }, oas31: oas31)
  end

  def object(properties, required: [])
    { 'type' => 'object', 'properties' => properties, 'required' => required }
  end

  def schema_for(node, oas31: false)
    with_components({ 'Thing' => node }, oas31: oas31).schema('Thing')
  end

  def field_for(property, required: [], oas31: false)
    schema_for(object({ 'value' => property }, required: required), oas31: oas31).field('value')
  end

  def codes(profile)
    profile.warnings.map(&:code)
  end

  describe 'which schemas end up in the profile' do
    it 'keeps every component, in spec order, referenced or not' do
      profile = with_components({ 'Used' => object({ 'a' => { 'type' => 'string' } }),
                                  'Unused' => object({ 'b' => { 'type' => 'string' } }) })

      expect(profile.schemas.keys).to eq(%w[Used Unused])
      expect(profile.schema('Used').json_path).to eq('$.components.schemas.Used')
    end

    it 'names an inline body exactly as the operation analyzer refers to it' do
      schema = object({ 'balance' => { 'type' => 'integer' } })
      body = { 'content' => { 'application/json' => { 'schema' => schema } } }
      data = { 'openapi' => '3.0.3',
               'paths' => { '/balance' => { 'get' => { 'operationId' => 'getBalance',
                                                       'responses' => { '200' => body } } } } }
      document = SpecGen::SpecLoader::Document.new(file: 'a.yaml', version: '3.0.3',
                                                   family: :oas30, raw: data, data: data)
      profile = SpecGen::IR::ProviderProfile.new
      SpecGen::Analyzers::OperationAnalyzer.call(document: document, profile: profile,
                                                 rules: rules)
      described_class.call(document: document, profile: profile, rules: rules)
      referenced = profile.operation('getBalance').response('200').schema

      expect(referenced).to eq('getBalance.responses.200')
      expect(profile.schemas).to have_key(referenced)
      expect(profile.schema(referenced).field('balance').type).to eq('integer')
    end

    it 'reads a request body schema as well' do
      schema = object({ 'amount' => { 'type' => 'integer' } })
      body = { 'required' => true, 'content' => { 'application/json' => { 'schema' => schema } } }
      operation = { 'operationId' => 'createPayout', 'requestBody' => body }
      profile = analyze({ 'paths' => { '/payouts' => { 'post' => operation } } })

      expect(profile.schemas.keys).to eq(['createPayout.requestBody'])
    end
  end

  describe 'fields' do
    it 'takes required from the parent schema, never from the property' do
      properties = { 'a' => { 'type' => 'string', 'required' => true },
                     'b' => { 'type' => 'string' } }
      schema = schema_for(object(properties, required: ['b']))

      expect(schema.field('a').required?).to be(false)
      expect(schema.field('b').required?).to be(true)
      expect(schema.required_fields.map(&:name)).to eq(['b'])
    end

    it 'reads every constraint, snake_cased' do
      property = { 'type' => 'string', 'enum' => %w[a b], 'pattern' => '^a',
                   'minLength' => 1, 'maxLength' => 64, 'default' => 'a' }

      expect(field_for(property).constraints)
        .to eq(enum: %w[a b], pattern: '^a', min_length: 1, max_length: 64, default: 'a')
    end

    it 'reads the numeric and array constraints too' do
      property = { 'type' => 'array', 'items' => { 'type' => 'integer' }, 'minItems' => 1,
                   'maxItems' => 5, 'multipleOf' => 10, 'minimum' => 100, 'maximum' => 900 }

      expect(field_for(property).constraints)
        .to eq(minimum: 100, maximum: 900, min_items: 1, max_items: 5, multiple_of: 10)
    end

    it 'stores an OAS 3.0 exclusiveMinimum flag the way JSON Schema 2020-12 writes it' do
      property = { 'type' => 'integer', 'minimum' => 100, 'exclusiveMinimum' => true }

      expect(field_for(property).constraints).to eq(exclusive_minimum: 100)
    end

    it 'keeps a 3.1 exclusiveMinimum number as it is' do
      property = { 'type' => 'integer', 'exclusiveMinimum' => 100 }

      expect(field_for(property, oas31: true).constraints).to eq(exclusive_minimum: 100)
    end

    it 'reads nullability from either dialect' do
      old = field_for({ 'type' => 'string', 'nullable' => true })
      new = field_for({ 'type' => %w[string null] }, oas31: true)

      expect(old).to have_attributes(type: 'string', constraints: { nullable: true })
      expect(new).to have_attributes(type: 'string', constraints: { nullable: true })
    end

    it 'keeps a field that declares no type, and says so' do
      profile = with_components({ 'Thing' => object({ 'value' => { 'description' => 'any' } }) })

      expect(profile.schema('Thing').field('value')).to have_attributes(type: nil)
      expect(profile.warnings.first)
        .to have_attributes(code: :format_unknown, severity: :warning,
                            json_path: '$.components.schemas.Thing.properties.value')
      expect(profile.warnings.first.message).to include('`value`').and include('`type`')
    end

    it 'leaves the role unknown, because the field matchers decide it' do
      role = field_for({ 'type' => 'string' }).role

      expect(role).to be_unknown
      expect(role.evidence).to include('матчеры полей')
    end
  end

  describe 'nested structure' do
    it 'gives an inline object its own schema and links the field to it' do
      nested = object({ 'phone' => { 'type' => 'string' } })
      profile = with_components({ 'Thing' => object({ 'recipient' => nested }) })

      expect(profile.schema('Thing').field('recipient').schema).to eq('Thing.properties.recipient')
      expect(profile.schema('Thing.properties.recipient').field('phone').type).to eq('string')
    end

    it 'keeps the component name and path of a referenced schema, whichever field found it' do
      referenced = object({ 'phone' => { 'type' => 'string' } })
                   .merge('x-specgen-ref' => '#/components/schemas/Recipient')
      profile = with_components({ 'Thing' => object({ 'recipient' => referenced }) })

      expect(profile.schema('Thing').field('recipient').schema).to eq('Recipient')
      expect(profile.schema('Recipient').json_path).to eq('$.components.schemas.Recipient')
    end

    it 'describes the items of an array of objects' do
      lines = { 'type' => 'array', 'items' => object({ 'id' => { 'type' => 'string' } }) }
      profile = with_components({ 'Thing' => object({ 'lines' => lines }) })

      expect(profile.schema('Thing').field('lines').schema).to eq('Thing.properties.lines.items')
      expect(profile.schemas).to have_key('Thing.properties.lines.items')
    end

    it 'links nothing for an array of scalars' do
      field = field_for({ 'type' => 'array', 'items' => { 'type' => 'string' } })

      expect(field.schema).to be_nil
    end

    it 'stops on a schema that contains itself instead of recursing forever' do
      profile = nil
      child = { 'x-specgen-ref' => '#/components/schemas/Node', 'type' => 'object',
                'properties' => { 'child' => { 'type' => 'string' } } }

      expect { profile = with_components({ 'Node' => object({ 'child' => child }) }) }
        .not_to raise_error
      expect(profile.schemas.keys).to eq(['Node'])
      expect(profile.schema('Node').field('child').schema).to eq('Node')
    end
  end

  describe 'conditional requirement' do
    def recipient(extra = {})
      properties = { 'type' => { 'type' => 'string', 'enum' => %w[sbp card] },
                     'bank_code' => { 'type' => 'string' } }
      object(properties, required: ['type']).merge(extra)
    end

    def described(sentence, extra = {})
      node = recipient(extra)
      node['properties']['bank_code']['description'] = sentence
      node
    end

    it 'reads dependentRequired as a presence condition, with no doubt' do
      node = recipient({ 'dependentRequired' => { 'type' => ['bank_code'] } })
      profile = with_components({ 'R' => node }, oas31: true)
      condition = profile.schema('R').field('bank_code').required_when

      expect(condition).to have_attributes(field: 'type', equals: nil,
                                           origin: :dependent_required, confidence: 1.0)
      expect(condition.presence?).to be(true)
      expect(profile.warnings).to be_empty
    end

    it 'reads if/then natively in 3.1' do
      node = recipient({ 'if' => { 'properties' => { 'type' => { 'const' => 'sbp' } } },
                         'then' => { 'required' => ['bank_code'] } })
      profile = with_components({ 'R' => node }, oas31: true)
      condition = profile.schema('R').field('bank_code').required_when

      expect(condition).to have_attributes(field: 'type', equals: 'sbp', origin: :if_then,
                                           confidence: 1.0)
      expect(condition.formal?).to be(true)
      expect(profile.warnings).to be_empty
    end

    it 'reads the registered extension in 3.0, where if/then is forbidden' do
      test = { 'properties' => { 'type' => { 'enum' => %w[sbp] } } }
      node = recipient({ 'x-jsonschema-if' => test,
                         'x-jsonschema-then' => { 'required' => ['bank_code'] } })
      condition = with_components({ 'R' => node }).schema('R').field('bank_code').required_when

      expect(condition).to have_attributes(origin: :x_jsonschema_if, equals: ['sbp'])
      expect(condition.values).to eq(['sbp'])
    end

    it 'reports a negative branch, which the IR cannot express' do
      node = recipient({ 'if' => { 'properties' => { 'type' => { 'const' => 'sbp' } } },
                         'else' => { 'required' => ['bank_code'] } })
      profile = with_components({ 'R' => node }, oas31: true)

      expect(profile.schema('R').field('bank_code').required_when).to be_nil
      expect(profile.warnings.first).to have_attributes(code: :conditional_required_hint,
                                                        severity: :warning)
      expect(profile.warnings.first.message).to include('отрицательное условие')
    end

    it 'reads a hint out of prose as a heuristic, and offers the overlay that formalises it' do
      profile = with_components({ 'R' => described('БИК банка (обязателен для type=sbp)') })
      condition = profile.schema('R').field('bank_code').required_when
      warning = profile.warnings.first

      expect(condition).to have_attributes(field: 'type', equals: 'sbp',
                                           origin: :description_hint, confidence: 0.5)
      expect(condition.formal?).to be(false)
      expect(condition.evidence).to include('намёк в описании (equals)')
      expect(warning).to have_attributes(code: :conditional_required_hint, severity: :warning,
                                         json_path: '$.components.schemas.R')
      expect(warning.message).to include('`bank_code` выглядит условно обязательным (`type` = sbp)')
      expect(warning.suggested_overlay).to include('- target: "$.components.schemas.R"',
                                                   'x-jsonschema-if', 'const: sbp',
                                                   'required: [bank_code]')
    end

    it 'states the same doubt in English when the locale is switched' do
      SpecGen::Texts.locale = 'en'
      warning = with_components({ 'R' => described('required when type is card') }).warnings.first

      expect(warning.message).to include('`bank_code` looks conditionally required (`type` = card)')
      expect(warning.suggested_overlay).to include('- target: "$.components.schemas.R"',
                                                   'required: [bank_code]')
    end

    it 'offers native if/then in 3.1 instead of the extension' do
      profile = with_components({ 'R' => described('required when type is card') }, oas31: true)

      expect(profile.warnings.first.suggested_overlay).to include("    if:\n", "    then:\n")
    end

    it 'ignores a sentence whose subject is not a sibling property' do
      profile = with_components({ 'R' => described('required when minimum is 100') })

      expect(profile.schema('R').field('bank_code').required_when).to be_nil
      expect(profile.warnings).to be_empty
    end

    it 'prefers the formal condition when the schema states both' do
      node = described('обязателен для type=sbp', { 'dependentRequired' => {
                         'type' => ['bank_code']
                       } })
      profile = with_components({ 'R' => node }, oas31: true)

      expect(profile.schema('R').field('bank_code').required_when.origin).to eq(:dependent_required)
      expect(profile.warnings).to be_empty
    end
  end

  describe 'composition' do
    it 'merges the branches of allOf so no field is lost' do
      node = { 'allOf' => [object({ 'a' => { 'type' => 'string' } }, required: ['a']),
                           object({ 'b' => { 'type' => 'integer' } }, required: ['b'])] }
      schema = schema_for(node)

      expect(schema.fields.map(&:name)).to eq(%w[a b])
      expect(schema.required).to eq(%w[a b])
      expect(schema.fields.map(&:required?)).to eq([true, true])
    end

    it 'reports branches of allOf that disagree about a type' do
      node = { 'allOf' => [object({ 'a' => { 'type' => 'string' } }),
                           object({ 'a' => { 'type' => 'integer' } })] }
      profile = with_components({ 'Thing' => node })

      expect(profile.schema('Thing').field('a').type).to eq('string')
      expect(profile.warnings.first.message)
        .to include('ветки allOf расходятся в типе `a` (string и integer)')
    end

    it 'says plainly that oneOf variants are not decomposed' do
      node = { 'oneOf' => [object({ 'a' => { 'type' => 'string' } }),
                           object({ 'b' => { 'type' => 'string' } })] }
      profile = with_components({ 'Thing' => node })

      expect(codes(profile)).to include(:spec_element_unsupported)
      expect(profile.warnings.map(&:message).join)
        .to include('`oneOf` не раскладывается на варианты (их 2)')
    end
  end

  describe 'input the loader let through' do
    it 'reports an object schema with no properties' do
      profile = with_components({ 'Thing' => { 'type' => 'object' } })

      expect(profile.schema('Thing').fields).to be_empty
      expect(profile.warnings.first.message).to include('не объявляет свойств')
    end

    it 'says nothing about a scalar component with no properties' do
      profile = with_components({ 'Currency' => { 'type' => 'string', 'enum' => ['RUB'] } })

      expect(profile.schema('Currency').type).to eq('string')
      expect(profile.warnings).to be_empty
    end

    it 'skips a property that is not an object' do
      profile = with_components({ 'Thing' => object({ 'a' => 'string' }) })

      expect(profile.schema('Thing').fields).to be_empty
      expect(profile.warnings.first)
        .to have_attributes(code: :spec_element_unsupported,
                            json_path: '$.components.schemas.Thing.properties.a')
    end

    it 'reports a required list that is not a list' do
      node = { 'type' => 'object', 'required' => 'a',
               'properties' => { 'a' => { 'type' => 'string' } } }
      profile = with_components({ 'Thing' => node })

      expect(profile.schema('Thing').required).to eq([])
      expect(profile.warnings.map(&:message).join).to include('`required` должен быть списком')
    end

    it 'reports an array that declares no items' do
      profile = with_components({ 'Thing' => object({ 'lines' => { 'type' => 'array' } }) })

      expect(profile.schema('Thing').field('lines').schema).to be_nil
      expect(profile.warnings.map(&:message).join).to include('не объявлены `items`')
    end

    it 'reports a components.schemas that is not an object and does not raise' do
      profile = nil

      expect { profile = analyze({ 'components' => { 'schemas' => 'Payout' } }) }
        .not_to raise_error
      expect(profile.schemas).to be_empty
      expect(codes(profile)).to eq([:spec_element_unsupported])
    end

    it 'reports a body whose schema is not an object' do
      body = { 'content' => { 'application/json' => { 'schema' => 'Payout' } } }
      operation = { 'operationId' => 'createPayout', 'requestBody' => body }
      profile = analyze({ 'paths' => { '/payouts' => { 'post' => operation } } })

      expect(codes(profile)).to eq([:schema_unresolved])
    end
  end

  describe 'on the spec as shipped' do
    let(:profile) do
      document = SpecGen::SpecLoader.load(spec_fixture('novapay.yaml'))
      described_class.call(document: document, profile: SpecGen::IR::ProviderProfile.new,
                           rules: rules)
    end

    it 'describes every component and every inline body' do
      expect(profile.schemas.keys).to eq(%w[CreatePayoutRequest Recipient PayoutResponse
                                            PayoutError WebhookPayload ErrorResponse
                                            payoutWebhook.responses.200 getBalance.responses.200])
      expect(profile.schemas.values.sum { |schema| schema.fields.size }).to eq(31)
    end

    it 'reads the payout request with its units, currency and identifier limits' do
      schema = profile.schema('CreatePayoutRequest')

      expect(schema.required).to eq(%w[amount currency external_id recipient])
      expect(schema.field('amount'))
        .to have_attributes(type: 'integer', required: true, constraints: { minimum: 100_000 })
      expect(schema.field('currency').constraints).to eq(enum: ['RUB'])
      expect(schema.field('external_id').constraints).to eq(max_length: 64)
      expect(schema.field('recipient').schema).to eq('Recipient')
    end

    it 'reads the recipient, including the two conditions stated only in prose' do
      schema = profile.schema('Recipient')

      expect(schema.field('phone').constraints).to eq(pattern: '^7\d{10}$')
      expect(schema.field('bank_code').required_when)
        .to have_attributes(field: 'type', equals: 'sbp', origin: :description_hint,
                            confidence: 0.5)
      expect(schema.field('card_number').required_when)
        .to have_attributes(field: 'type', equals: 'card', origin: :description_hint)
      expect(schema.field('bank_code').required?).to be(false)
    end

    it 'reads the response statuses, the error codes and the timestamps' do
      expect(profile.schema('PayoutResponse').field('status').enum)
        .to eq(%w[pending processing completed failed cancelled])
      expect(profile.schema('PayoutError').field('code').enum.size).to eq(7)
      expect(profile.schema('PayoutResponse').field('created_at').format).to eq('date-time')
      expect(profile.schema('PayoutResponse').field('completed_at').format).to eq('date-time')
      expect(profile.schema('PayoutResponse').field('error').schema).to eq('PayoutError')
    end

    it 'warns twice, once per condition hiding in a description, and offers both overlays' do
      expect(profile.warnings.map(&:code)).to eq(%i[conditional_required_hint
                                                    conditional_required_hint])
      expect(profile.warnings.map(&:json_path).uniq).to eq(['$.components.schemas.Recipient'])
      expect(profile.warnings.map(&:suggested_overlay).join)
        .to include('required: [bank_code]').and include('required: [card_number]')
    end

    it 'leaves no field pointing at a schema nobody described' do
      named = profile.schemas.values.flat_map { |schema| schema.fields.map(&:schema) }.compact

      expect(named.uniq - profile.schemas.keys).to be_empty
    end
  end
end
