# frozen_string_literal: true

require 'tmpdir'

# Цикл, ради которого стадия и написана: инструмент печатает в report.md
# фрагмент overlay под каждой неоднозначностью, человек собирает из
# фрагментов файл, отдаёт его флагом `--overlay` — и предупреждение
# исчезает, а решение становится формальным. Отчёт и overlay обязаны быть
# одним механизмом, а не двумя несвязанными фичами, и проверяется это на
# настоящей выданной спецификации, а не на выдуманном фрагменте.
RSpec.describe 'the report → overlay → rerun cycle' do
  include Fixtures
  include CliRunner

  let(:rules) { SpecGen::Rules.load }
  let(:spec) { spec_fixture('novapay.yaml') }

  def analyze(overlay: nil)
    document = SpecGen::SpecLoader.load(spec, overlay: overlay)
    profile = SpecGen::Analyzers::Runner.call(document: document, rules: rules,
                                              options: { provider: 'novapay' })
    [profile, document]
  end

  def report_of(dir, overlay: nil)
    profile, document = analyze(overlay: overlay)
    artifacts = SpecGen::Generators.call(profile: profile, rules: rules, document: document,
                                         options: { provider: 'novapay', output: dir })
    File.read(artifacts.find { |artifact| artifact.kind == :report }.path, encoding: 'utf-8')
  end

  # Ровно то, что делает читатель отчёта: берёт фрагменты из раздела
  # «Неоднозначности» и вставляет их подряд под ключ `actions`, как велит
  # напечатанная там же инструкция «Как собрать overlay».
  def assemble(report, about)
    section = report.split(/^## 3\. /).last.split(/^## 4\. /).first
    fragments = section.scan(/```yaml\n(.*?)```/m).map { |found| found.first.rstrip }
    fragment = fragments.find { |text| text.match?(about) }
    "overlay: 1.0.0\ninfo:\n  title: novapay disambiguation\n  version: 1.0.0\nactions:\n#{fragment}\n"
  end

  def write(dir, name, text)
    path = File.join(dir, name)
    File.binwrite(path, text)
    path
  end

  def conditions_of(profile)
    profile.schema('Recipient').fields.select(&:conditionally_required?)
  end

  it 'closes the loop: the fragment the report printed applies as it stands' do
    Dir.mktmpdir('specgen-cycle') do |dir|
      report = report_of(dir)
      hints = analyze.first.warnings.count { |w| w.code == :conditional_required_hint }
      expect(report).to include('conditional_required_hint')
      expect(hints).to be > 1

      overlay = write(dir, 'novapay.overlay.yaml', assemble(report, /bank_code/))
      profile, = analyze(overlay: overlay)

      # Фрагмент был один, поэтому и закрылась одна неоднозначность: overlay
      # применяется дословно, а не «примерно то, что имелось в виду».
      expect(profile.warnings.count { |w| w.code == :conditional_required_hint }).to eq(hints - 1)
      condition = profile.schema('Recipient').field('bank_code').required_when
      expect(condition.origin).to eq(:x_jsonschema_if)
      expect(condition.confidence).to eq(1.0)
      expect(condition.equals).to eq('sbp')
    end
  end

  # One action states both conditions: `then` names the requisite for the
  # value under test, `else` the requisite for the only value left, since
  # `Recipient.type` is an enum of exactly two.
  it 'reads the overlay if/then/else, both conditions formal and both hints gone' do
    before, = analyze
    expect(before.warnings.map(&:code)).to include(:conditional_required_hint)
    expect(conditions_of(before).map { |field| field.required_when.origin }.uniq)
      .to eq([:description_hint])

    after, = analyze(overlay: File.join(Fixtures::ROOT, 'overlays', 'novapay.yaml'))

    expect(after.warnings.map(&:code)).not_to include(:conditional_required_hint)
    expect(conditions_of(after).map(&:name)).to contain_exactly('bank_code', 'card_number')
    conditions_of(after).each do |field|
      expect(field.required_when).to have_attributes(origin: :x_jsonschema_if, confidence: 1.0,
                                                     field: 'type')
      expect(field.required_when).to be_formal
    end
    expect(conditions_of(after).map { |field| field.required_when.equals }).to eq(%w[sbp card])
  end

  # Переопределённое человеком видно там же, где сказано, из чего собран
  # сервис: иначе читатель отчёта считает написанное свойством спецификации.
  it 'lists the applied actions in section 1 of the report, and only when there were any' do
    Dir.mktmpdir('specgen-cycle') do |dir|
      overlay = File.join(Fixtures::ROOT, 'overlays', 'novapay.yaml')
      section = report_of(dir, overlay: overlay).split(/^## 2\. /).first

      expect(section).to include('OpenAPI Overlay 1.0.0', 'novapay.yaml', 'NovaPay disambiguation')
      expect(section).to include('| `$.components.schemas.Recipient` | слияние `update` |')
      expect(section).to match(/Условная обязательность/)
      expect(report_of(dir).split(/^## 2\. /).first).not_to include('OpenAPI Overlay 1.0.0')
    end
  end

  it 'leaves a run without --overlay untouched: no overlay on the document, hints in place' do
    profile, document = analyze

    expect(document.overlay).to be_nil
    expect(profile.warnings.map(&:code)).to include(:conditional_required_hint)
    expect(profile.warnings.map(&:code)).not_to include(:overlay_conflict, :overlay_target_missing)
  end

  describe 'where the stage stands in the pipeline' do
    def overlay_for(dir, action)
      write(dir, 'o.yaml', "overlay: 1.0.0\ninfo:\n  title: t\n  version: 1.0.0\nactions:\n#{action}")
    end

    it 'applies before $ref resolution, so one component change reaches every use of it' do
      Dir.mktmpdir('specgen-cycle') do |dir|
        overlay = overlay_for(dir, <<~YAML)
          - target: "$.components.schemas.Recipient"
            update:
              dependentRequired:
                type: [bank_code]
        YAML
        document = SpecGen::SpecLoader.load(spec, overlay: overlay)

        expect(document.raw['components']['schemas']['Recipient']).to have_key('dependentRequired')
        body = document.paths['/payouts']['post']['requestBody']['content']['application/json']
        expect(body['schema']['properties']['recipient']).to have_key('dependentRequired')
      end
    end

    it 'is checked by the structure validator afterwards: an overlay cannot smuggle a broken schema' do
      Dir.mktmpdir('specgen-cycle') do |dir|
        overlay = overlay_for(dir, <<~YAML)
          - target: "$.components.schemas.Recipient.properties.phone"
            update:
              type: strng
        YAML

        expect { SpecGen::SpecLoader.load(spec, overlay: overlay) }
          .to raise_error(SpecGen::SpecParseError, /неизвестный тип схемы "strng"/)
      end
    end

    it 'reports a stale target instead of blocking the run' do
      Dir.mktmpdir('specgen-cycle') do |dir|
        overlay = overlay_for(dir, "- target: \"$.components.schemas.Sender\"\n  update:\n    x: 1\n")
        profile, document = analyze(overlay: overlay)

        expect(document.overlay.misses).to eq(['$.components.schemas.Sender'])
        warning = profile.warnings.find { |w| w.code == :overlay_target_missing }
        expect(warning.severity).to eq(:warning)
        expect(profile.operations).not_to be_empty
      end
    end
  end

  describe 'the command line' do
    it 'says what the overlay did instead of saying it is ignored' do
      Dir.mktmpdir('specgen-cli') do |dir|
        result = run_cli('--spec', spec, '--provider', 'novapay', '--output', dir,
                         '--overlay', File.join(Fixtures::ROOT, 'overlays', 'novapay.yaml'))

        expect(result.status).to eq(0)
        expect(result.stdout).to match(/Overlay .*novapay\.yaml: применено 1 действие/)
        expect(result.stdout).not_to include('не применяется')
      end
    end

    it 'refuses a broken overlay with one line and exit code 1, never a backtrace' do
      Dir.mktmpdir('specgen-cli') do |dir|
        result = run_cli('--spec', spec, '--provider', 'novapay', '--output', dir,
                         '--overlay', File.join(Fixtures::ROOT, 'overlays', 'bad', 'not_overlay.yaml'))

        expect(result.status).to eq(1)
        expect(result.stderr).to match(/ошибка: .*not_overlay\.yaml, \$: это не документ OpenAPI Overlay/)
        expect(result.stderr.lines.size).to eq(1)
      end
    end

    it 'refuses --overlay together with --all: an overlay targets one specification' do
      result = run_cli('--all', '--overlay', File.join(Fixtures::ROOT, 'overlays', 'novapay.yaml'))

      expect(result.status).to eq(2)
      expect(result.stderr).to match(/--overlay применяется к одной спецификации/)
    end
  end
end
