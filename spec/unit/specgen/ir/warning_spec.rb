# frozen_string_literal: true

RSpec.describe SpecGen::IR::Warning do
  def warning(**overrides)
    described_class.new(code: :units_unknown, message: 'amount unit not derived', **overrides)
  end

  it 'defaults to :warning severity and no overlay suggestion' do
    expect(warning.to_h).to eq(code: :units_unknown, message: 'amount unit not derived',
                               json_path: nil, severity: :warning, suggested_overlay: nil)
  end

  it 'carries the JSONPath of the element the reader has to look at' do
    path = '$.components.schemas.CreatePayoutRequest.properties.amount'
    expect(warning(json_path: path).json_path).to eq(path)
  end

  it 'carries a ready-made overlay fragment when one can be offered' do
    fragment = "- target: \"$.components.schemas.Recipient\"\n  update:\n    dependentRequired: {}\n"
    expect(warning(suggested_overlay: fragment).fixable?).to be(true)
    expect(warning.fixable?).to be(false)
  end

  it 'marks only :error severity as blocking' do
    expect(warning(severity: :error).blocking?).to be(true)
    expect(warning(severity: :info).blocking?).to be(false)
  end

  it 'rejects a code outside the vocabulary, so typos cannot reach the report' do
    expect { warning(code: :units_are_weird) }
      .to raise_error(ArgumentError, /код предупреждения: неизвестное значение :units_are_weird/)
  end

  it 'rejects an unknown severity' do
    expect { warning(severity: :critical) }.to raise_error(ArgumentError, /серьёзность предупреждения: неизвестное значение/)
  end

  it 'requires a message a human can read' do
    expect { warning(message: '') }.to raise_error(ArgumentError, /текст предупреждения/)
  end

  it 'is frozen once recorded' do
    expect(warning).to be_frozen
  end

  describe 'ordering' do
    it 'sorts by severity, then location, then code, for byte-stable reports' do
      warnings = [
        warning(code: :status_unmapped, severity: :info, json_path: '$.b'),
        warning(code: :units_unknown, severity: :error, json_path: '$.z'),
        warning(code: :currency_unknown, severity: :warning, json_path: '$.a'),
        warning(code: :auth_unknown, severity: :warning, json_path: '$.a')
      ]
      expect(warnings.sort_by(&:sort_key).map(&:code))
        .to eq(%i[units_unknown auth_unknown currency_unknown status_unmapped])
    end
  end

  it 'prints severity, location and message as one report line' do
    line = warning(severity: :error, json_path: '$.paths').to_s
    expect(line).to eq('ERROR $.paths amount unit not derived')
  end
end
