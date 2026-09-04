# frozen_string_literal: true

RSpec.describe SpecGen::SpecLoader::VersionDetector do
  def detect(data)
    described_class.call(data, file: 'x.yaml')
  end

  it 'classifies 3.0.x as :oas30' do
    expect(detect('openapi' => '3.0.3').to_h).to eq(version: '3.0.3', family: :oas30)
  end

  it 'classifies 3.1.x and 3.2.x as :oas31 (JSON Schema 2020-12)' do
    expect(detect('openapi' => '3.1.0').family).to eq(:oas31)
    expect(detect('openapi' => '3.2.0').family).to eq(:oas31)
  end

  it 'accepts a bare major.minor, which YAML may have parsed as a float' do
    expect(detect('openapi' => 3.0).to_h).to eq(version: '3.0', family: :oas30)
  end

  it 'rejects Swagger 2.0 with the location of the swagger key' do
    expect { detect('swagger' => '2.0') }.to raise_error(SpecGen::SpecLoadError) do |error|
      expect(error.path).to eq('$.swagger')
      expect(error.message).to include('x.yaml').and include('Swagger 2.0 не поддерживается')
    end
  end

  it 'rejects unknown versions with the location of the openapi key' do
    expect { detect('openapi' => '4.0.0') }.to raise_error(SpecGen::SpecLoadError) do |error|
      expect(error.path).to eq('$.openapi')
      expect(error.message).to include('версия OpenAPI "4.0.0" не поддерживается')
        .and include('3.0.x, 3.1.x, 3.2.x')
    end
  end

  it 'rejects documents without an openapi key' do
    expect { detect('title' => 'x') }.to raise_error(SpecGen::SpecLoadError) do |error|
      expect(error.path).to eq('$')
      expect(error.message).to include('это не документ OpenAPI')
    end
  end
end
