# frozen_string_literal: true

require 'tmpdir'
require 'yaml'

RSpec.describe SpecGen::Generators::OverlayGenerator do
  include Fixtures

  # Один прогон конвейера: анализ спецификации и запись артефактов.
  # @return [Array(Array<SpecGen::Generators::Artifact>, SpecGen::IR::ProviderProfile)]
  def generate(spec, dir, provider:, fix: false, overlay: nil)
    rules = SpecGen::Rules.load
    document = SpecGen::SpecLoader.load(spec, overlay: overlay)
    options = { provider: provider, output: dir, fix: fix }
    profile = SpecGen::Analyzers::Runner.call(document: document, rules: rules, options: options)
    artifacts = SpecGen::Generators.call(profile: profile, rules: rules, document: document,
                                         options: options)
    [artifacts, profile]
  end

  def skeleton(spec, dir, provider:)
    artifacts, profile = generate(spec, dir, provider: provider, fix: true)
    artifact = artifacts.find { |item| item.kind == :overlay }
    [File.read(artifact.path, encoding: 'UTF-8'), artifact, profile]
  end

  # Слот, снятый с комментария так же, как это сделал бы человек: два первых
  # знака долой, остальное — готовый YAML.
  def uncomment(text, head)
    lines = text.split("\n")
    from = lines.index { |line| line.start_with?("# #{head}") }
    lines.each_with_index.map do |line, index|
      inside = index > from && line.match?(/\A# (- target|\s)/)
      inside ? line[2..] : line
    end.join("\n")
  end

  describe 'the skeleton for broken.yaml' do
    before(:all) do
      @dir = Dir.mktmpdir('specgen-fix')
      @text, @artifact, @profile = skeleton(File.join(Fixtures::ROOT, 'specs', 'broken.yaml'),
                                            @dir, provider: 'broken')
    end

    after(:all) { FileUtils.remove_entry(@dir) }

    it 'is written as the fifth artifact named after the provider' do
      expect(@artifact.file).to eq('broken.overlay.yaml')
      expect(File.exist?(File.join(@dir, 'broken.overlay.yaml'))).to be(true)
    end

    it 'is the document the report promises: overlay 1.0.0 with an actions key' do
      data = YAML.safe_load(@text)
      expect(data['overlay']).to eq('1.0.0')
      expect(data['info']).to include('title' => 'broken disambiguation', 'version' => '1.0.0')
      expect(data['actions']).to be_an(Array)
    end

    it 'offers a slot for every ambiguous status the tool refused to decide' do
      expect(@text).to include('NOTOK: in_progress  # in_progress | approved | rejected')
      expect(@text).to include('IN_REVIEW: in_progress')
      expect(@text).to include('PART_DONE: in_progress')
    end

    it 'leaves every decision commented out, so no guess becomes a fact' do
      actions = YAML.safe_load(@text)['actions']
      expect(actions.size).to eq(1)
      expect(actions.first['target']).to eq(SpecGen::Generators::Skeleton::View::ANCHOR_TARGET)
      expect(actions.first['update']).to eq('x-specgen-overlay' => 'skeleton')
    end

    it 'names the code and the place of every slot, and says how to hand the file back' do
      expect(@text).to include('# 1. error_action_unknown — $.components.schemas.Err')
      expect(@text).to include('./integrate --spec broken.yaml --provider broken ' \
                               '--overlay broken.overlay.yaml')
    end

    it 'warns when several slots address one target instead of letting them overwrite' do
      expect(@text).to match(/Внимание: ту же цель адресует ещё/)
    end

    it 'renders byte for byte the same on a second run' do
      Dir.mktmpdir('specgen-fix-again') do |dir|
        again, = skeleton(File.join(Fixtures::ROOT, 'specs', 'broken.yaml'), dir,
                          provider: 'broken')
        expect(again).to eq(@text)
      end
    end
  end

  describe 'the round trip' do
    # Заготовка обязана быть пригодной на вход: иначе флаг обещает то, чего
    # инструмент не принимает обратно.
    %w[broken.yaml novapay.yaml cardpay.yaml].each do |name|
      it "feeds #{name} back through --overlay without new warnings" do
        Dir.mktmpdir('specgen-fix-trip') do |dir|
          provider = File.basename(name, '.yaml')
          text, artifact, before = skeleton(spec_fixture(name), dir, provider: provider)
          expect { YAML.safe_load(text) }.not_to raise_error

          _, after = generate(spec_fixture(name), dir, provider: provider, overlay: artifact.path)
          expect(after.warnings.size).to eq(before.warnings.size)
        end
      end
    end

    it 'closes the warning whose slot a human uncommented' do
      Dir.mktmpdir('specgen-fix-edit') do |dir|
        spec = spec_fixture('novapay.yaml')
        text, _, before = skeleton(spec, dir, provider: 'novapay')
        edited = File.join(dir, 'edited.overlay.yaml')
        File.binwrite(edited, uncomment(text, '2. conditional_required_hint'))

        _, after = generate(spec, dir, provider: 'novapay', overlay: edited)
        hint = ->(profile) { profile.warnings.count { |w| w.code == :conditional_required_hint } }
        expect(hint.call(after)).to eq(hint.call(before) - 1)
      end
    end
  end

  describe 'without the flag' do
    it 'writes the same four artifacts and no skeleton' do
      Dir.mktmpdir('specgen-nofix') do |dir|
        artifacts, = generate(spec_fixture('novapay.yaml'), dir, provider: 'novapay')
        expect(artifacts.map(&:kind)).to eq(%i[service integration fixtures report])
        expect(Dir.glob(File.join(dir, '*.overlay.yaml'))).to be_empty
      end
    end
  end

  describe 'a specification with nothing to fix' do
    it 'still writes a valid overlay document and says the slots are empty' do
      profile = SpecGen::IR::ProviderProfile.new
      naming = SpecGen::Generators::Naming.new('demo')
      text = SpecGen::Generators::Skeleton::View.new(profile: profile, naming: naming)
      rendered = ERB.new(File.read(File.join(SpecGen::TEMPLATES_DIR, 'overlay.yaml.erb'),
                                   encoding: 'UTF-8'), trim_mode: '-')
                    .result(text.template_binding)

      expect(YAML.safe_load(rendered)['actions'].size).to eq(1)
      expect(rendered).to include('Слотов нет')
    end
  end
end
