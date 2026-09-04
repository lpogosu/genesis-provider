# frozen_string_literal: true

# The stage that gives fields and parameters their roles: SchemaAnalyzer and
# OperationAnalyzer calling Matchers::Assigner while they read the document.
# On the shipped dictionaries, because the fixture dictionaries carry names
# only and the point here is what the shipped data does to a spec.
RSpec.describe 'field roles through the analyzers' do
  include Fixtures

  let(:rules) { SpecGen::Rules.load }

  # Positional only: a keyword parameter would swallow the braceless
  # string-keyed hash the callers pass.
  def document_for(data)
    SpecGen::SpecLoader::Document.new(file: 'provider_api.yaml', version: '3.0.3', family: :oas30,
                                      raw: data, data: data)
  end

  def schemas(components)
    profile = SpecGen::IR::ProviderProfile.new
    SpecGen::Analyzers::SchemaAnalyzer.call(document: document_for('components' => { 'schemas' => components }),
                                            profile: profile, rules: rules)
    profile
  end

  def operation(path, node)
    profile = SpecGen::IR::ProviderProfile.new
    SpecGen::Analyzers::OperationAnalyzer.call(document: document_for('paths' => { path => node }),
                                               profile: profile, rules: rules)
    profile
  end

  def object(properties, required = [])
    { 'type' => 'object', 'properties' => properties, 'required' => required }
  end

  describe 'fields of a schema' do
    it 'reads a phone by its pattern when the name is contact' do
      field = schemas('Recipient' => object({ 'contact' => { 'type' => 'string', 'pattern' => '^7\d{10}$' } }))
              .schema('Recipient').field('contact')

      expect(field.role.value).to eq(:recipient_phone)
      expect(field.role.source).to eq(:heuristic)
      expect(field.role.evidence).to include('constraint 4.0 (pattern дословно совпадает с шаблоном роли)')
    end

    it 'assigns sum through the dictionary and leaves xref_tag_9 alone, with the right warnings' do
      profile = schemas('Thing' => object({ 'sum' => { 'type' => 'integer' },
                                            'xref_tag_9' => { 'type' => 'string' } }, ['xref_tag_9']),
                        'Other' => object({ 'payout_amt' => { 'type' => 'integer' } }))

      expect(profile.schema('Thing').field('sum').role).to have_attributes(value: :amount, source: :registry)
      expect(profile.schema('Thing').field('xref_tag_9').role).to be_unknown
      expect(profile.schema('Other').field('payout_amt').role).to have_attributes(value: :amount, source: :heuristic)
      expect(profile.schema('Other').field('payout_amt').role.confidence).to be_within(0.01).of(0.43)
      expect(profile.warnings.map { |w| [w.code, w.severity] })
        .to contain_exactly(%i[required_field_role_unknown warning], %i[field_role_low_confidence info])
      expect(profile.warnings.map(&:json_path))
        .to include('$.components.schemas.Thing.properties.xref_tag_9',
                    '$.components.schemas.Other.properties.payout_amt')
    end

    it 'reads x-specgen-role as an overlay decision' do
      field = schemas('Thing' => object({ 'foo' => { 'type' => 'string', 'x-specgen-role' => 'external_id' } }))
              .schema('Thing').field('foo')

      expect(field.role).to have_attributes(value: :external_id, source: :overlay)
    end

    it 'resolves one role claimed by two fields of one schema and says so' do
      profile = schemas('Thing' => object({ 'transaction_id' => { 'type' => 'string' },
                                            'payment_id' => { 'type' => 'string' } }))

      expect(profile.schema('Thing').field('transaction_id').role.value).to eq(:provider_operation_id)
      expect(profile.schema('Thing').field('payment_id').role).to be_unknown
      expect(profile.warnings.first)
        .to have_attributes(code: :field_role_conflict,
                            json_path: '$.components.schemas.Thing.properties.payment_id')
    end
  end

  describe 'parameters of an operation' do
    let(:profile) do
      operation('/payouts/{payout_id}',
                'post' => { 'operationId' => 'cancelPayout',
                            'parameters' => [
                              { 'name' => 'payout_id', 'in' => 'path', 'schema' => { 'type' => 'string' } },
                              { 'name' => 'Idempotency-Key', 'in' => 'header',
                                'schema' => { 'type' => 'string', 'format' => 'uuid' } },
                              { 'name' => 'X-Acme-Signature', 'in' => 'header', 'required' => true,
                                'schema' => { 'type' => 'string' } },
                              { 'name' => 'expand', 'in' => 'query', 'schema' => { 'type' => 'string' } }
                            ] })
    end
    let(:parameters) { profile.operations.first.parameters.to_h { |p| [p.name, p.role] } }

    it 'gives a path id, an idempotency header and a signature header their roles' do
      expect(parameters['payout_id']).to have_attributes(value: :provider_operation_id, source: :registry)
      expect(parameters['payout_id'].evidence).to include('расположение параметра — путь')
      expect(parameters['Idempotency-Key']).to have_attributes(value: :idempotency_key, source: :registry)
      expect(parameters['Idempotency-Key'].evidence).to include('format uuid')
      expect(parameters['X-Acme-Signature']).to have_attributes(value: :signature, source: :heuristic)
      expect(parameters['X-Acme-Signature'].confidence).to be >= 0.6
    end

    it 'reports a parameter without a role as a parameter, not a field' do
      expect(parameters['expand']).to be_unknown
      warning = profile.warnings.find { |w| w.code == :field_role_unknown }

      expect(warning.message).to include('необязательный параметр `expand` (query)')
      expect(warning.json_path).to eq("$.paths['/payouts/{payout_id}'].post.parameters[3]")
    end
  end

  describe 'on the spec as shipped' do
    let(:document) { SpecGen::SpecLoader.load(spec_fixture('novapay.yaml')) }

    def run
      SpecGen::Analyzers::Runner.call(document: document, rules: rules)
    end

    it 'gives every parameter of the shipped spec a role from the dictionaries' do
      roles = run.operations.flat_map(&:parameters).to_h { |p| [p.name, [p.role.value, p.role.source]] }

      expect(roles).to eq('Idempotency-Key' => %i[idempotency_key registry],
                          'payout_id' => %i[provider_operation_id registry],
                          'X-NovaPay-Signature' => %i[signature registry])
    end

    it 'gives the same profile on every run' do
      expect(run.to_h).to eq(run.to_h)
    end
  end
end
