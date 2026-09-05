# frozen_string_literal: true

RSpec.describe SpecGen::Overlay::Target do
  let(:document) do
    {
      'openapi' => '3.0.3',
      'servers' => [{ 'url' => 'https://sandbox.example.com' }, { 'url' => 'https://api.example.com' }],
      'paths' => {
        '/payouts' => {
          'post' => {
            'operationId' => 'createPayout',
            'parameters' => [{ 'name' => 'Idempotency-Key', 'in' => 'header' }],
            'responses' => { '200' => { 'description' => 'ok' }, '409' => { 'description' => 'dup' } }
          }
        }
      },
      'components' => { 'schemas' => { 'Recipient' => { 'properties' => { 'phone' => { 'type' => 'string' } } } } }
    }
  end

  def resolve(expression)
    described_class.parse(expression).resolve(document)
  end

  describe 'the supported subset of JSONPath' do
    it 'resolves a component schema by dotted name' do
      expect(resolve('$.components.schemas.Recipient')).to eq(document['components']['schemas']['Recipient'])
    end

    it 'resolves a property of a component schema' do
      expect(resolve('$.components.schemas.Recipient.properties.phone')).to eq('type' => 'string')
    end

    it 'resolves an operation through a bracketed path key' do
      expect(resolve("$.paths['/payouts'].post")['operationId']).to eq('createPayout')
    end

    it 'resolves a response through a bracketed status code' do
      expect(resolve("$.paths['/payouts'].post.responses['409']")).to eq('description' => 'dup')
    end

    it 'resolves an array element by index' do
      expect(resolve('$.servers[1].url')).to eq('https://api.example.com')
    end

    it 'accepts double quotes as RFC 9535 does, though our own reports print single ones' do
      expect(resolve('$.paths["/payouts"].post.responses["200"]')).to eq('description' => 'ok')
    end

    it 'resolves the whole document for a bare root' do
      expect(resolve('$')).to be(document)
      expect(described_class.parse('$')).to be_root
    end

    it 'reads an index against an object as a string key, since loaded keys are strings' do
      expect(resolve("$.paths['/payouts'].post.responses[409]")).to eq('description' => 'dup')
    end
  end

  describe 'a target that resolves to nothing' do
    it 'reports a missing key as MISSING, not as nil' do
      expect(resolve('$.components.schemas.Missing')).to be(described_class::MISSING)
    end

    it 'reports an index past the end of an array as MISSING' do
      expect(resolve('$.servers[7]')).to be(described_class::MISSING)
    end

    it 'reports a walk through a scalar as MISSING' do
      expect(resolve('$.openapi.title')).to be(described_class::MISSING)
    end

    it 'tells a missing node from a node that is legitimately nil' do
      document['components']['schemas']['Recipient']['description'] = nil
      expect(resolve('$.components.schemas.Recipient.description')).to be_nil
    end
  end

  describe 'syntax outside the subset' do
    it 'refuses recursive descent, wildcards, filters and slices' do
      ['$..schemas', '$.paths.*.get', "$.paths[?@.name=='x']", '$.servers[0:2]', 'paths.post', '']
        .each { |expression| expect(described_class.parse(expression)).to be_nil }
    end
  end

  describe '#container' do
    it 'returns the node that holds the target and the key inside it' do
      parent, key = described_class.parse('$.components.schemas.Recipient').container(document)
      expect(parent).to be(document['components']['schemas'])
      expect(key).to eq('Recipient')
    end

    it 'returns the array and the index for an array element' do
      parent, key = described_class.parse('$.servers[0]').container(document)
      expect(parent).to be(document['servers'])
      expect(key).to eq(0)
    end

    it 'has nothing to return for the root: nothing contains the document' do
      expect(described_class.parse('$').container(document)).to be_nil
    end
  end
end
