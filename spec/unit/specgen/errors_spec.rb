# frozen_string_literal: true

RSpec.describe SpecGen::Error do
  it 'is the root of the hierarchy' do
    expect(described_class.superclass).to eq(StandardError)
  end

  it 'has one subclass per pipeline stage that can fail on user input' do
    stages = [SpecGen::SpecLoadError, SpecGen::SpecParseError, SpecGen::GenerationError]
    expect(stages).to all(be < described_class)
  end

  it 'prefixes the message with file and JSONPath when both are known' do
    error = SpecGen::SpecParseError.new('paths is missing', file: 'x.yaml', path: '$.paths')
    expect(error.message).to eq('x.yaml at $.paths: paths is missing')
  end

  it 'prefixes the message with the file alone when the path is unknown' do
    error = SpecGen::SpecLoadError.new('not valid YAML', file: 'x.yaml')
    expect(error.message).to eq('x.yaml: not valid YAML')
  end

  it 'keeps a bare message when no location is known' do
    expect(SpecGen::GenerationError.new('template failed').message).to eq('template failed')
  end

  it 'exposes file and path separately for the reporter' do
    error = described_class.new('boom', file: 'x.yaml', path: '$.info')
    expect([error.file, error.path]).to eq(['x.yaml', '$.info'])
  end
end
