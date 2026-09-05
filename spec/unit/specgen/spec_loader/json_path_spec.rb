# frozen_string_literal: true

RSpec.describe SpecGen::SpecLoader::JsonPath do
  it 'uses dot notation for identifier-like keys' do
    expect(described_class.build(%w[components schemas Recipient])).to eq('$.components.schemas.Recipient')
  end

  it 'uses bracket notation for keys with special characters, as Overlay targets do' do
    expect(described_class.build(['paths', '/payouts', 'post', 'responses', '201', 'content', 'application/json']))
      .to eq("$.paths['/payouts'].post.responses['201'].content['application/json']")
  end

  it 'uses index notation for array positions' do
    expect(described_class.build(['servers', 0, 'url'])).to eq('$.servers[0].url')
  end

  it 'escapes quotes and backslashes inside bracketed keys' do
    expect(described_class.build(["it's"])).to eq("$['it\\'s']")
    expect(described_class.build(['a\\b'])).to eq("$['a\\\\b']")
  end

  it 'returns the root for an empty key list' do
    expect(described_class.build([])).to eq('$')
  end

  # Разбор — обратная операция к сборке, и это граница поддерживаемого
  # подмножества JSONPath: цели overlay мы сами же и печатаем, поэтому
  # разбирать обязаны ровно то, что печатаем.
  describe '.parse' do
    it 'round-trips every path the builder can produce' do
      [[], %w[components schemas Recipient], ['paths', '/payouts', 'post'],
       ['paths', '/payouts', 'post', 'responses', '409'], ['servers', 0, 'url'],
       ['components', 'schemas', 'error_details-2'], ["it's"], ['a\\b']].each do |keys|
        expect(described_class.parse(described_class.build(keys))).to eq(keys)
      end
    end

    it 'reads double quotes too, as RFC 9535 allows them' do
      expect(described_class.parse('$.paths["/payouts"].post')).to eq(['paths', '/payouts', 'post'])
    end

    it 'refuses syntax outside the subset instead of guessing what it meant' do
      ['$..schemas', '$.paths.*.get', "$.paths[?@.name=='x']", '$[*]', '$.a[]', 'components.schemas',
       '$.', '$.a b'].each do |expression|
        expect(described_class.parse(expression)).to be_nil, "#{expression.inspect} was parsed"
      end
    end
  end
end
