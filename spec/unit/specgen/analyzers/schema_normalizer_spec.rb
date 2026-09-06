# frozen_string_literal: true

RSpec.describe SpecGen::Analyzers::SchemaNormalizer do
  def normalize(node)
    described_class.call(node)
  end

  def object(properties, required = [])
    { 'type' => 'object', 'properties' => properties, 'required' => required }
  end

  def messages(result)
    result.remarks.map(&:message).join(' ')
  end

  describe 'allOf' do
    it 'merges properties and takes the union of required, not the intersection' do
      node = { 'allOf' => [object({ 'a' => { 'type' => 'string' } }, %w[a]),
                           object({ 'b' => { 'type' => 'string' } }, %w[b])] }

      result = normalize(node)

      expect(result.node['properties'].keys).to eq(%w[a b])
      expect(result.node['required']).to eq(%w[a b])
      expect(result.node).not_to have_key('allOf')
    end

    it 'takes the keywords of a branch that the outer schema does not state itself' do
      node = { 'description' => 'outer',
               'allOf' => [{ 'type' => 'string', 'enum' => %w[RUB], 'description' => 'inner' }] }

      result = normalize(node)

      expect(result.node['type']).to eq('string')
      expect(result.node['enum']).to eq(%w[RUB])
      expect(result.node['description']).to eq('outer')
    end

    it 'leaves a scalar composition without an empty properties hash' do
      result = normalize({ 'allOf' => [{ 'type' => 'string' }] })

      expect(result.node).not_to have_key('properties')
    end

    it 'reports two branches that describe one property differently' do
      node = { 'allOf' => [object({ 'a' => { 'type' => 'string', 'maxLength' => 8 } }),
                           object({ 'a' => { 'type' => 'string', 'maxLength' => 12 } })] }

      result = normalize(node)

      expect(result.node['properties']['a']['maxLength']).to eq(8)
      expect(messages(result)).to include('описано в двух ветках')
    end

    it 'says nothing when both branches describe the property in the same words' do
      same = { 'type' => 'string' }
      result = normalize({ 'allOf' => [object({ 'a' => same }), object({ 'a' => same })] })

      expect(result.remarks).to be_empty
    end

    it 'does not touch the node it was given' do
      branch = object({ 'b' => { 'type' => 'string' } }, %w[b])
      node = { 'allOf' => [object({ 'a' => { 'type' => 'string' } })] }.merge('allOf' => [branch])
      before = Marshal.dump(node)

      normalize(node)

      expect(Marshal.dump(node)).to eq(before)
    end
  end

  describe 'oneOf and anyOf' do
    it 'becomes the only branch left after the null branch is dropped' do
      node = { 'oneOf' => [{ 'type' => 'string', 'enum' => %w[a] }, { 'type' => 'null' }] }

      result = normalize(node)

      expect(result.node['type']).to eq('string')
      expect(result.node['nullable']).to be(true)
      expect(result.remarks).to be_empty
    end

    it 'reads the 3.1 spelling of a null branch too' do
      result = normalize({ 'anyOf' => [{ 'type' => 'string' }, { 'type' => ['null'] }] })

      expect(result.node['type']).to eq('string')
      expect(result.node['nullable']).to be(true)
    end

    it 'keeps every variant property, none of them required, each tagged' do
      node = { 'anyOf' => [object({ 'a' => { 'type' => 'string' } }, %w[a]),
                           object({ 'b' => { 'type' => 'string' } }, %w[b])] }

      result = normalize(node)

      expect(result.node['properties'].keys).to eq(%w[a b])
      expect(result.node['required']).to be_nil
      expect(result.variants).to eq('a' => 'anyOf[0]', 'b' => 'anyOf[1]')
    end

    it 'unfolds a composition nested inside a variant' do
      inner = { 'allOf' => [object({ 'b' => { 'type' => 'string' } })] }
      node = { 'oneOf' => [object({ 'a' => { 'type' => 'string' } }), inner] }

      expect(normalize(node).node['properties'].keys).to eq(%w[a b])
    end
  end

  describe 'discriminator' do
    def union(mapping, branches)
      { 'discriminator' => { 'propertyName' => 'kind', 'mapping' => mapping },
        'oneOf' => branches }
    end

    def branch(component, properties, required)
      object(properties, required).merge('x-specgen-ref' => "#/components/schemas/#{component}")
    end

    it 'names the property that selects the variant and what each value requires' do
      node = union({ 'sbp' => '#/components/schemas/Sbp', 'card' => '#/components/schemas/Card' },
                   [branch('Sbp', { 'kind' => {}, 'phone' => {} }, %w[kind phone]),
                    branch('Card', { 'kind' => {}, 'pan' => {} }, %w[kind pan])])

      result = normalize(node)

      expect(result.conditions.keys).to eq(%w[phone pan])
      expect(result.conditions['phone'])
        .to have_attributes(field: 'kind', equals: 'sbp', origin: :discriminator, confidence: 1.0)
      expect(result.node['properties']['kind']['enum']).to eq(%w[sbp card])
      expect(result.node['required']).to eq(%w[kind])
    end

    it 'lists every value at which a field is required when several variants need it' do
      node = union({ 'sbp' => '#/components/schemas/Sbp', 'card' => '#/components/schemas/Card',
                     'wallet' => '#/components/schemas/Wallet' },
                   [branch('Sbp', { 'kind' => {}, 'holder' => {} }, %w[holder]),
                    branch('Card', { 'kind' => {}, 'holder' => {} }, %w[holder]),
                    branch('Wallet', { 'kind' => {} }, [])])

      expect(normalize(node).conditions['holder'].values).to eq(%w[sbp card])
    end

    it 'keeps a field required by every variant unconditional instead' do
      node = union({ 'sbp' => '#/components/schemas/Sbp', 'card' => '#/components/schemas/Card' },
                   [branch('Sbp', { 'kind' => {}, 'holder' => {} }, %w[holder]),
                    branch('Card', { 'kind' => {}, 'holder' => {} }, %w[holder])])

      result = normalize(node)

      expect(result.conditions).to be_empty
      expect(result.node['required']).to eq(%w[holder])
    end

    it 'falls back to the value the branch itself declares when there is no mapping' do
      node = { 'discriminator' => { 'propertyName' => 'kind' },
               'oneOf' => [object({ 'kind' => { 'const' => 'sbp' }, 'phone' => {} },
                                  %w[kind phone]),
                           object({ 'kind' => { 'const' => 'card' }, 'pan' => {} },
                                  %w[kind pan])] }

      conditions = normalize(node).conditions

      expect(conditions['phone'].equals).to eq('sbp')
      expect(conditions['pan'].equals).to eq('card')
    end

    it 'keeps the enum the spec wrote itself instead of the mapping keys' do
      node = union({ 'sbp' => '#/components/schemas/Sbp' },
                   [branch('Sbp', { 'kind' => { 'enum' => %w[SBP] }, 'phone' => {} },
                           %w[kind phone])] +
                   [branch('Card', { 'kind' => { 'enum' => %w[SBP] }, 'pan' => {} }, %w[kind pan])])

      expect(normalize(node).node['properties']['kind']['enum']).to eq(%w[SBP])
    end
  end

  describe 'input no spec should contain' do
    it 'stops at the depth limit instead of recursing forever' do
      node = { 'type' => 'object' }
      (described_class::MAX_DEPTH + 3).times { node = { 'allOf' => [node] } }

      result = normalize(node)

      expect(result.node).to be_a(Hash)
      expect(messages(result)).to include('вложены глубже')
    end

    it 'accepts anything that is not a schema object at all' do
      expect(normalize('строка').node).to eq({})
      expect(normalize(nil).node).to eq({})
    end

    it 'ignores branches that are not objects' do
      expect(normalize({ 'allOf' => ['no', object({ 'a' => {} })] }).node['properties'].keys)
        .to eq(%w[a])
    end
  end

  describe '.free_form?' do
    it 'is true for an object whose keys the spec never lists' do
      expect(described_class).to be_free_form({ 'type' => 'object' })
      expect(described_class).to be_free_form({ 'additionalProperties' => true })
      expect(described_class).to be_free_form({ 'patternProperties' => { '^x' => {} } })
    end

    it 'is false for a scalar and for an object that lists its properties' do
      expect(described_class).not_to be_free_form({ 'type' => 'string' })
      expect(described_class).not_to be_free_form(object({ 'a' => {} }))
      expect(described_class).not_to be_free_form({ 'type' => 'object',
                                                    'additionalProperties' => false,
                                                    'properties' => { 'a' => {} } })
    end
  end
end
