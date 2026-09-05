# frozen_string_literal: true

RSpec.describe SpecGen::Analyzers::StatusAnalyzer do
  include Fixtures
  include RulesFixtures

  # The fixture dictionary: canon pending/completed/failed, synonyms paid,
  # declined and queued, and on_hold as the one ambiguous word.
  let(:rules) { load_rules }

  def analyze(data)
    document = SpecGen::SpecLoader::Document.new(file: 'provider_api.yaml', version: '3.0.3',
                                                 family: :oas30, raw: data, data: data)
    described_class.call(document: document, profile: SpecGen::IR::ProviderProfile.new,
                         rules: rules)
  end

  def with_status(property, examples = {})
    schema = { 'type' => 'object', 'properties' => { 'status' => property } }
    response = { 'description' => 'ok', 'content' => { 'application/json' => { 'schema' => schema }.merge(examples) } }
    analyze('openapi' => '3.0.3',
            'paths' => { '/payouts/{id}' => { 'get' => { 'operationId' => 'getPayoutStatus',
                                                         'responses' => { '200' => response } } } })
  end

  def mapping_of(profile, status)
    profile.status_map.find { |mapping| mapping.provider_status == status }
  end

  describe 'the canon and the synonyms' do
    let(:profile) { with_status('type' => 'string', 'enum' => %w[pending paid declined]) }

    it 'maps the canon of the case with full confidence and names the canon' do
      mapping = mapping_of(profile, 'pending')

      expect(mapping.internal).to have_attributes(value: :in_progress, source: :registry, confidence: 1.0)
      expect(mapping.internal.evidence).to eq('канон кейса: pending -> in_progress')
      expect(mapping.json_path)
        .to eq("$.paths['/payouts/{id}'].get.responses['200'].content['application/json'].schema.properties.status.enum[0]")
    end

    it 'maps a synonym with the dictionary confidence and names the dictionary' do
      mapping = mapping_of(profile, 'paid')

      expect(mapping.internal).to have_attributes(value: :approved, source: :registry, confidence: 0.9)
      expect(mapping.internal.evidence).to eq('синоним rules/statuses.yml: paid -> approved')
      expect(mapping_of(profile, 'declined').internal.value).to eq(:rejected)
    end

    it 'keeps the enum order and warns about nothing' do
      expect(profile.status_map.map(&:provider_status)).to eq(%w[pending paid declined])
      expect(profile.warnings).to be_empty
    end

    it 'reads case and separators the way the dictionary does' do
      profile = with_status('type' => 'string', 'enum' => ['PENDING', 'In Progress'])

      expect(mapping_of(profile, 'PENDING').internal.value).to eq(:in_progress)
      expect(mapping_of(profile, 'In Progress').internal).to be_unknown
    end
  end

  describe 'statuses it refuses to guess' do
    it 'leaves an ambiguous status unknown, explains the ambiguity and offers an overlay' do
      profile = with_status('type' => 'string', 'enum' => %w[pending on_hold])
      mapping = mapping_of(profile, 'on_hold')
      warning = profile.warnings.first

      expect(mapping.internal).to be_unknown
      expect(mapping.internal.evidence).to include('on_hold неоднозначен', 'заморозка')
      expect(warning).to have_attributes(code: :status_unmapped, severity: :warning)
      expect(warning.json_path).to end_with('.status.enum[1]')
      expect(warning.message).to include('выберите внутренний статус (in_progress | approved | rejected) в overlay')
      expect(warning.suggested_overlay).to include('x-specgen-status-map:', 'on_hold: in_progress')
      expect(warning.suggested_overlay).to include('- target: "$.paths[\'/payouts/{id}\'].get.responses[\'200\']')
    end

    it 'leaves a status it has never seen unknown, and says where to add it' do
      profile = with_status('type' => 'string', 'enum' => %w[pending frobnicated])

      expect(mapping_of(profile, 'frobnicated').internal).to be_unknown
      expect(profile.warnings.first.message)
        .to include('frobnicated не найден ни в каноне, ни среди синонимов rules/statuses.yml',
                    'добавьте синоним в справочник')
    end

    it 'says the same in English when the locale is switched' do
      SpecGen::Texts.locale = 'en'
      profile = with_status('type' => 'string', 'enum' => %w[on_hold])

      expect(profile.warnings.first.message).to include('status on_hold is ambiguous', 'pick the internal status')
    end
  end

  describe 'the overlay extension' do
    it 'lets x-specgen-status-map decide an ambiguous status, with overlay as the source' do
      profile = with_status('type' => 'string', 'enum' => %w[on_hold],
                            'x-specgen-status-map' => { 'on_hold' => 'in_progress' })
      mapping = mapping_of(profile, 'on_hold')

      expect(mapping.internal).to have_attributes(value: :in_progress, source: :overlay, confidence: 1.0)
      expect(mapping.internal.evidence).to eq('x-specgen-status-map: on_hold -> in_progress')
      expect(profile.warnings).to be_empty
    end

    it 'rejects an internal status outside the vocabulary and keeps the warning' do
      profile = with_status('type' => 'string', 'enum' => %w[on_hold],
                            'x-specgen-status-map' => { 'on_hold' => 'frozen' })

      expect(mapping_of(profile, 'on_hold').internal).to be_unknown
      expect(profile.warnings.first.message).to include('неизвестное значение "frozen"')
    end
  end

  describe 'examples' do
    it 'adds a status that appears only in an example, and reports the contradiction' do
      profile = with_status({ 'type' => 'string', 'enum' => %w[pending] },
                            { 'example' => { 'id' => 'x', 'status' => 'paid' } })

      expect(profile.status_map.map(&:provider_status)).to eq(%w[pending paid])
      expect(mapping_of(profile, 'paid').internal.value).to eq(:approved)
      expect(mapping_of(profile, 'paid').json_path).to end_with(".content['application/json'].example.status")
      expect(profile.warnings.map(&:code)).to eq([:status_missing_from_enum])
      expect(profile.warnings.first.message).to include('статус paid встречается в примере')
    end

    it 'finds a status nested inside an example object' do
      examples = { 'examples' => { 'done' => { 'value' => { 'data' => { 'status' => 'completed' } } } } }
      profile = with_status({ 'type' => 'string' }, examples)

      expect(mapping_of(profile, 'completed').internal.value).to eq(:approved)
      expect(mapping_of(profile, 'completed').json_path).to end_with('.examples.done.value.data.status')
    end

    it 'does not record the same status twice when two schemas declare the same enum' do
      enum = { 'type' => 'string', 'enum' => %w[pending completed] }
      one = { 'type' => 'object', 'properties' => { 'status' => enum } }
      two = { 'type' => 'object', 'properties' => { 'status' => enum, 'event' => { 'type' => 'string' } } }
      profile = analyze('openapi' => '3.0.3', 'components' => { 'schemas' => { 'One' => one, 'Two' => two } },
                        'paths' => {})

      expect(profile.status_map.map(&:provider_status)).to eq(%w[pending completed])
      expect(profile.status_map.first.json_path).to eq('$.components.schemas.One.properties.status.enum[0]')
    end
  end

  describe 'input the loader let through' do
    it 'reports a spec with no status field at all as a contract gap' do
      profile = analyze('openapi' => '3.0.3',
                        'components' => { 'schemas' => { 'Thing' => { 'type' => 'object',
                                                                      'properties' => { 'x' => { 'type' => 'string' } } } } },
                        'paths' => {})

      expect(profile.status_map).to be_empty
      expect(profile.warnings.first).to have_attributes(code: :contract_gap, json_path: '$.components.schemas')
      expect(profile.warnings.first.message).to include('fetch_status и process_callback')
    end

    it 'reports an enum that is not a list instead of raising' do
      profile = with_status('type' => 'string', 'enum' => 'pending')

      expect(profile.status_map).to be_empty
      expect(profile.warnings.map(&:code)).to include(:spec_element_unsupported)
    end

    it 'skips enum entries that are not strings' do
      profile = with_status('type' => 'string', 'enum' => [1, nil, 'pending'])

      expect(profile.status_map.map(&:provider_status)).to eq(['pending'])
    end
  end

  # A compound name and a status field the dictionary cannot name: both need
  # the shipped dictionaries, which the fixture ones deliberately lack.
  describe 'names the dictionary cannot read' do
    let(:shipped) { SpecGen::Rules.load }

    def with_shipped(properties)
      schema = { 'type' => 'object', 'properties' => properties }
      response = { 'description' => 'ok',
                   'content' => { 'application/json' => { 'schema' => schema } } }
      document = SpecGen::SpecLoader::Document.new(
        file: 'provider_api.yaml', version: '3.0.3', family: :oas30,
        raw: {}, data: { 'openapi' => '3.0.3',
                         'paths' => { '/t/{id}' => { 'get' => { 'operationId' => 'getState',
                                                                'responses' => { '200' => response } } } } }
      )
      described_class.call(document: document, profile: SpecGen::IR::ProviderProfile.new,
                           rules: shipped)
    end

    it 'reads the status enum of a field only the matchers could name, at the role confidence' do
      profile = with_shipped('st' => { 'type' => 'string', 'enum' => %w[WAITING DONE] })

      expect(profile.status_map.map(&:provider_status)).to eq(%w[WAITING DONE])
      expect(mapping_of(profile, 'DONE').internal)
        .to have_attributes(value: :approved, source: :heuristic)
      expect(mapping_of(profile, 'DONE').internal.confidence).to be < 0.6
      expect(profile.warnings.map(&:code)).not_to include(:contract_gap)
    end

    it 'refuses to read PART_DONE as DONE, and names the modifier that stopped it' do
      profile = with_shipped('st' => { 'type' => 'string', 'enum' => %w[DONE PART_DONE] })
      mapping = mapping_of(profile, 'PART_DONE')
      warning = profile.warnings.find { |item| item.code == :status_unmapped }

      expect(mapping.internal).to be_unknown
      expect(warning.message).to include('PART_DONE', 'part', 'modifiers rules/statuses.yml')
      expect(warning.suggested_overlay).to include('x-specgen-status-map')
    end

    it 'still reads a compound name whose leading words are not modifiers, with less confidence' do
      profile = with_shipped('status' => { 'type' => 'string',
                                           'enum' => %w[DONE authAdjustmentRefused] })
      mapping = mapping_of(profile, 'authAdjustmentRefused')

      expect(mapping.internal).to have_attributes(value: :rejected, source: :heuristic)
      expect(mapping.internal.confidence).to eq(shipped.statuses.tail_confidence)
      expect(mapping.internal.evidence).to include('refused')
    end

    it 'still strips an event address separated by a dot, silently and at full confidence' do
      profile = with_shipped('status' => { 'type' => 'string',
                                           'enum' => ['payout.completed'] })
      mapping = mapping_of(profile, 'payout.completed')

      expect(mapping.internal).to have_attributes(value: :approved, confidence: 1.0)
      expect(profile.warnings).to be_empty
    end
  end

  describe 'on the spec as shipped' do
    let(:profile) do
      document = SpecGen::SpecLoader.load(spec_fixture('novapay.yaml'))
      described_class.call(document: document, profile: SpecGen::IR::ProviderProfile.new,
                           rules: SpecGen::Rules.load)
    end

    it 'maps all five statuses through the canon, once each, and warns about nothing' do
      expect(profile.status_map.map(&:provider_status))
        .to eq(%w[pending processing completed failed cancelled])
      expect(profile.status_map.map { |mapping| mapping.internal.value })
        .to eq(%i[in_progress in_progress approved rejected rejected])
      expect(profile.status_map.map { |mapping| mapping.internal.confidence }).to all(eq(1.0))
      expect(profile.status_map.first.json_path)
        .to eq('$.components.schemas.PayoutResponse.properties.status.enum[0]')
      expect(profile.warnings).to be_empty
    end
  end
end
