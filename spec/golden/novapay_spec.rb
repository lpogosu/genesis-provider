# frozen_string_literal: true

require 'tmpdir'

# Golden-тест: артефакты из novapay.yaml сравниваются байт-в-байт с эталоном
# в spec/fixtures/golden/novapay/. Эталон обновляется только явно:
#
#   SPECGEN_UPDATE_GOLDEN=1 bundle exec rspec spec/golden
#
# Второй пример — детерминированность: две генерации подряд в разные
# каталоги дают одинаковые байты.
RSpec.describe 'golden artifacts for novapay.yaml' do
  include Fixtures

  def golden_dir
    File.join(Fixtures::ROOT, 'golden', 'novapay')
  end

  def generate(dir)
    rules = SpecGen::Rules.load
    document = SpecGen::SpecLoader.load(spec_fixture('novapay.yaml'))
    options = { provider: 'novapay', output: dir }
    profile = SpecGen::Analyzers::Runner.call(document: document, rules: rules, options: options)
    SpecGen::Generators.call(profile: profile, rules: rules, document: document, options: options)
  end

  def read(path)
    File.binread(path)
  end

  it 'matches the golden files byte for byte' do
    Dir.mktmpdir('specgen-golden') do |dir|
      artifacts = generate(dir)
      if ENV['SPECGEN_UPDATE_GOLDEN'] == '1'
        FileUtils.mkdir_p(golden_dir)
        artifacts.each { |artifact| File.binwrite(File.join(golden_dir, artifact.file), read(artifact.path)) }
      end

      golden = Dir.glob(File.join(golden_dir, '*'))
      expect(golden).not_to be_empty, 'no golden files: run SPECGEN_UPDATE_GOLDEN=1 bundle exec rspec spec/golden'
      golden.each do |expected|
        actual = File.join(dir, File.basename(expected))
        expect(File.file?(actual)).to be(true), "#{File.basename(expected)} was not generated"
        expect(read(actual)).to eq(read(expected)), "#{File.basename(expected)} differs from the golden file"
      end
    end
  end

  it 'keeps the golden files LF-only with a single trailing newline' do
    Dir.glob(File.join(golden_dir, '*')).each do |path|
      content = read(path)
      expect(content).not_to include("\r")
      expect(content).to end_with("\n")
      expect(content).not_to end_with("\n\n")
    end
  end

  it 'is deterministic: two runs into different directories produce identical bytes' do
    Dir.mktmpdir('specgen-a') do |first|
      Dir.mktmpdir('specgen-b') do |second|
        a = generate(first)
        b = generate(second)
        expect(a.map(&:file)).to eq(b.map(&:file))
        a.zip(b).each { |x, y| expect(read(x.path)).to eq(read(y.path)) }
      end
    end
  end
end
