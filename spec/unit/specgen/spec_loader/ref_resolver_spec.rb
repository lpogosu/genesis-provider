# frozen_string_literal: true

RSpec.describe SpecGen::SpecLoader::RefResolver do
  def resolve(data, reader: ->(path) { raise SpecGen::SpecLoadError.new('нет файла', file: path) })
    described_class.new(data, file: 'mem.yaml', reader: reader).resolve
  end

  let(:money) { { 'type' => 'object', 'properties' => { 'amount' => { 'type' => 'integer' } } } }

  it 'replaces a local $ref with a deep copy of its target' do
    data = { 'a' => { '$ref' => '#/components/schemas/Money' }, 'components' => { 'schemas' => { 'Money' => money } } }
    resolved = resolve(data)
    expect(resolved['a']).to eq(money.merge('x-specgen-ref' => '#/components/schemas/Money'))
    expect(resolved['a']['properties']).not_to equal(data['components']['schemas']['Money']['properties'])
  end

  it 'leaves the input untouched' do
    data = { 'a' => { '$ref' => '#/m' }, 'm' => money }
    resolve(data)
    expect(data['a']).to eq('$ref' => '#/m')
  end

  it 'lets sibling keys of a $ref override the target (OAS 3.1 summary/description)' do
    data = { 'a' => { '$ref' => '#/m', 'description' => 'overridden' }, 'm' => money.merge('description' => 'original') }
    expect(resolve(data)['a']['description']).to eq('overridden')
  end

  it 'gives every use of a shared target its own copy' do
    data = { 'a' => { '$ref' => '#/m' }, 'b' => { '$ref' => '#/m' }, 'm' => money }
    resolved = resolve(data)
    resolved['a']['properties']['amount']['type'] = 'string'
    expect(resolved['b']['properties']['amount']['type']).to eq('integer')
  end

  it 'unescapes ~1 and ~0 in JSON Pointers' do
    data = { 'a' => { '$ref' => '#/paths/~1payouts/post' }, 'paths' => { '/payouts' => { 'post' => { 'x' => 1 } } } }
    expect(resolve(data)['a']).to include('x' => 1)
  end

  it 'indexes into arrays' do
    data = { 'a' => { '$ref' => '#/list/1' }, 'list' => [{ 'n' => 0 }, { 'n' => 1 }] }
    expect(resolve(data)['a']).to include('n' => 1)
  end

  it 'rejects a $ref that is not a string' do
    data = { 'a' => { '$ref' => 42 } }
    expect { resolve(data) }.to raise_error(SpecGen::SpecParseError, /должен иметь тип string, а не number/)
  end

  it 'rejects a fragment that is not a JSON Pointer' do
    data = { 'a' => { '$ref' => '#components/schemas/Money' } }
    expect { resolve(data) }.to raise_error(SpecGen::SpecParseError, %r{должен быть JSON Pointer и начинаться с '/'})
  end

  # Рекурсивная схема — норма: у Airwallex категория отрасли содержит список
  # таких же категорий, у Stripe так устроена половина API. Отвергать из-за
  # этого весь документ значило бы не уметь его читать.
  it 'cuts a self-referencing schema instead of rejecting the document' do
    data = { 'm' => { 'type' => 'object',
                      'properties' => { 'name' => { 'type' => 'string' },
                                        'child' => { '$ref' => '#/m' } } } }
    resolver = described_class.new(data, file: 'spec.yaml')
    child = resolver.resolve['m']['properties']['child']

    # Первое вхождение разворачивается целиком, второе — заглушка с именем
    # схемы и без полей: рекурсия обрывается на известной глубине.
    expect(child['properties'].keys).to eq(%w[name child])
    expect(child['properties']['child']).to eq('x-specgen-ref' => '#/m', 'type' => 'object',
                                               'x-specgen-cycle' => '#/m -> #/m')
    expect(resolver.cycles).to eq('#/m -> #/m' => "$.m.properties.child['$ref']")
  end

  it 'loads external files through the reader, relative to the referencing file' do
    external = { 'defs' => { 'Money' => money } }
    seen = []
    reader = lambda do |path|
      seen << path
      external
    end
    data = { 'a' => { '$ref' => 'lib/common.yaml#/defs/Money' } }
    resolved = described_class.new(data, file: 'specs/main.yaml', reader: reader)
    expect(resolved.resolve['a']).to include('type' => 'object')
    expect(seen).to eq([File.expand_path('specs/lib/common.yaml')])
    expect(resolved.external_files).to eq(['lib/common.yaml'])
  end

  it 'resolves refs inside an external file against that file, not the root' do
    external = { 'defs' => { 'Money' => { 'currency' => { '$ref' => '#/defs/Currency' } }, 'Currency' => { 'type' => 'string' } } }
    data = { 'a' => { '$ref' => 'common.yaml#/defs/Money' }, 'defs' => { 'Currency' => { 'type' => 'root-would-be-wrong' } } }
    resolved = resolve(data, reader: ->(_path) { external })
    expect(resolved['a']['currency']['type']).to eq('string')
  end

  it 'retells the failure of an external file at the $ref that pulled it in' do
    data = { 'a' => { '$ref' => 'common.yaml#/defs/Money' } }
    expect { resolve(data) }.to raise_error(SpecGen::SpecLoadError) do |error|
      expect(error.message).to include('common.yaml').and include('нет файла')
      expect(error.path).to eq("$.a['$ref']")
    end
  end

  # Данные примера — не описание схемы. Публичный API Square держит в примере
  # ответа сетевой адрес под ключом `$ref`; развернуть его нельзя, и попытка
  # валила чтение всей спецификации.
  describe 'example payloads are data, not references' do
    it 'leaves a $ref inside example untouched' do
      data = { 'a' => { 'example' => { '$ref' => 'https://cdn.example/types#some.String' } } }
      expect(resolve(data)['a']['example']).to eq('$ref' => 'https://cdn.example/types#some.String')
    end

    it 'leaves a $ref inside the value of an Example Object untouched' do
      data = { 'a' => { 'examples' => { 'ok' => { 'value' => { '$ref' => 'https://cdn.example/x#y' } } } } }
      expect(resolve(data)['a']['examples']['ok']['value']).to eq('$ref' => 'https://cdn.example/x#y')
    end

    it 'still resolves a reference to a shared Example Object' do
      shared = { 'summary' => 'ok', 'value' => { 'id' => 1 } }
      data = { 'a' => { 'examples' => { 'ok' => { '$ref' => '#/components/examples/Ok' } } },
               'components' => { 'examples' => { 'Ok' => shared } } }
      expect(resolve(data)['a']['examples']['ok']).to include('summary' => 'ok')
    end

    it 'leaves a $ref inside default and enum untouched' do
      data = { 'a' => { 'default' => { '$ref' => 'nowhere' }, 'enum' => [{ '$ref' => 'nowhere' }] } }
      resolved = resolve(data)
      expect(resolved['a']['default']).to eq('$ref' => 'nowhere')
      expect(resolved['a']['enum'].first).to eq('$ref' => 'nowhere')
    end
  end

  # Верное сообщение о неверной причине хуже молчания: человек чинит фрагмент,
  # а ссылка сетевая.
  describe 'the reported cause of a bad reference' do
    it 'names the network location, not the shape of the fragment' do
      data = { 'a' => { '$ref' => 'https://cdn.example/types#some.String' } }
      expect { resolve(data) }.to raise_error(SpecGen::SpecParseError, /http/)
    end

    it 'still names the fragment when the reference is local' do
      data = { 'a' => { '$ref' => '#not-a-pointer' } }
      expect { resolve(data) }.to raise_error(SpecGen::SpecParseError, /not-a-pointer/)
    end
  end
end
