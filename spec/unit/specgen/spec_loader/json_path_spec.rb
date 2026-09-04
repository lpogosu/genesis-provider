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
end
