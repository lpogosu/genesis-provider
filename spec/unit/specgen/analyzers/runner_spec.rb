# frozen_string_literal: true

RSpec.describe SpecGen::Analyzers::Runner do
  include Fixtures

  let(:rules) { SpecGen::Rules.load }
  let(:document) { SpecGen::SpecLoader.load(spec_fixture('novapay.yaml')) }

  def run(options = {})
    described_class.call(document: document, rules: rules, options: options)
  end

  it 'runs every analyzer and returns one filled profile' do
    profile = run

    expect(profile.info).not_to be_nil
    expect(profile.auth).not_to be_nil
    expect(profile.operations.size).to eq(5)
    expect(profile.schemas.size).to eq(8)
  end

  it 'lists every analyzer exactly once, so a new one cannot run twice or be forgotten' do
    expect(described_class::ORDER.uniq).to eq(described_class::ORDER)
    expect(described_class::ORDER).to all(be < SpecGen::Analyzers::Base)
  end

  it 'hands string-keyed options through, the way Thor delivers them' do
    profile = run('provider' => 'demo')

    expect(profile.info.name.value).to eq('demo')
    expect(profile.info.name.source).to eq(:structural)
  end

  it 'gives the same profile on every run' do
    expect(run.to_h).to eq(run.to_h)
  end
end
