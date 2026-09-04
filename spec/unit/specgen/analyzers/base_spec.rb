# frozen_string_literal: true

RSpec.describe SpecGen::Analyzers::Base do
  def document(data = {})
    SpecGen::SpecLoader::Document.new(file: 'api.yaml', version: '3.0.3', family: :oas30,
                                      raw: data, data: data)
  end

  # The smallest analyzer there can be: it only reports what the base class
  # handed it, which is exactly the contract the real analyzers rely on.
  let(:probe) do
    Class.new(described_class) do
      def call
        [data, json_path('servers', 0, 'url'), option(:provider)]
      end
    end
  end

  it 'builds and runs the analyzer in one call' do
    result = probe.call(document: document('servers' => []), profile: SpecGen::IR::ProviderProfile.new,
                        rules: nil, options: { provider: 'acmepay' })

    expect(result).to eq([{ 'servers' => [] }, '$.servers[0].url', 'acmepay'])
  end

  it 'reads an option whether Thor spelled the key as a string or a test as a symbol' do
    result = probe.call(document: document, profile: SpecGen::IR::ProviderProfile.new,
                        rules: nil, options: { 'provider' => 'acmepay' })

    expect(result.last).to eq('acmepay')
  end

  it 'hands back an empty document rather than raising when the root is not a mapping' do
    result = probe.call(document: document(['not a mapping']), profile: SpecGen::IR::ProviderProfile.new,
                        rules: nil)

    expect(result.first).to eq({})
  end

  it 'refuses to run the base class, which analyzes nothing of its own' do
    expect { described_class.call(document: document, profile: SpecGen::IR::ProviderProfile.new, rules: nil) }
      .to raise_error(NotImplementedError, /обязан реализовать #call/)
  end
end
