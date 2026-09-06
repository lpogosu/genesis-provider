# frozen_string_literal: true

require 'tmpdir'
require 'yaml'

RSpec.describe SpecGen::Generators::ReportGenerator do
  include Fixtures

  let(:sections) do
    ['## 1. Сводка', '## 2. Покрытие спецификации', '## 3. Неоднозначности',
     '## 4. Операции вне контракта и без роли', '## 5. Противоречия в самой спецификации',
     '## 6. Справки', '## 7. Что доделать руками']
  end

  def generate(spec, dir, provider: nil)
    rules = SpecGen::Rules.load
    document = SpecGen::SpecLoader.load(spec)
    options = { provider: provider, output: dir }.compact
    profile = SpecGen::Analyzers::Runner.call(document: document, rules: rules, options: options)
    artifacts = SpecGen::Generators.call(profile: profile, rules: rules, document: document, options: options)
    artifact = artifacts.find { |item| item.kind == :report }
    [File.read(artifact.path, encoding: 'UTF-8'), artifact, artifacts]
  end

  def headings(text)
    text.lines.grep(/\A## /).map(&:chomp)
  end

  # Строка раздела 2 с обеими цифрами покрытия.
  def coverage_line(text)
    text[/^\*\*Покрытие: .+$/]
  end

  # @return [Array(Integer, Integer)] проценты: от всей спеки и в границах контракта
  def percentages(text)
    coverage_line(text).scan(/(\d+) %/).flatten.map(&:to_i)
  end

  # @return [Array(Integer, Integer, Integer, Integer)] покрыто, найдено, покрыто, в границах
  def figures(text)
    coverage_line(text).scan(/\((\d+) из (\d+)/).flatten.map(&:to_i)
  end

  # Подраздел «Что не покрыто и почему» раздела 2.
  def gaps_section(text)
    text.split('### Что не покрыто и почему').last.split('## 3.').first
  end

  # Фрагменты overlay из раздела 3 склеиваются в один документ ровно так, как
  # велит сам отчёт: под ключ actions, без правки отступов.
  def overlay_document(text)
    fragments = text.scan(/^  ```yaml\n(.*?)^  ```$/m).flatten
    body = fragments.map { |fragment| fragment.gsub(/^  /, '') }.join
    "overlay: 1.0.0\ninfo:\n  title: t\n  version: 1.0.0\nactions:\n#{body}"
  end

  describe 'the report for novapay.yaml' do
    before(:all) do
      @dir = Dir.mktmpdir('specgen-report')
      @text, @artifact, @artifacts = generate(File.join(Fixtures::ROOT, 'specs', 'novapay.yaml'),
                                              @dir, provider: 'novapay')
    end

    after(:all) { FileUtils.remove_entry(@dir) }

    it 'is written as report.md last, after the three artifacts it describes' do
      expect(@artifact.file).to eq('report.md')
      expect(SpecGen::Generators::Runner::ORDER.last).to be(described_class)
      expect(@artifacts.map(&:kind)).to eq(%i[service integration fixtures report])
    end

    it 'carries the seven sections in order' do
      expect(headings(@text)).to eq(sections)
    end

    it 'lists every written artifact with its line count' do
      expect(@text).to include('| `novapay_service.rb` |', '| `INTEGRATION.md` |',
                               '| `fixtures.json` |', '| `report.md` |')
      expect(@text).to match(/\| `novapay_service\.rb` \|[^|]+\| \d+ \|/)
    end

    it 'reports coverage as a percentage with the formula named' do
      expect(@text).to match(/\*\*Покрытие: \d+ %\ \(\d+ из \d+ элементов\)\./)
      expect(@text).to include('доля покрытых элементов от всех')
    end

    it 'prints the in-contract figure next to the overall one' do
      expect(@text).to match(/\*\*Покрытие: \d+ % \(\d+ из \d+ элементов\)\. /)
      expect(@text).to match(/В границах контракта: \d+ % \(\d+ из \d+\)\.\*\*/)
    end

    # Из знаменателя второй цифры вычитается только непокрытое, поэтому она
    # не бывает ниже первой, а её знаменатель — ниже покрытого.
    it 'never lets the in-contract figure fall below the overall one' do
      overall, in_contract = percentages(@text)
      covered, total, covered_again, in_scope = figures(@text)
      expect(in_contract).to be >= overall
      expect(covered_again).to eq(covered)
      expect(in_scope).to be_between(covered, total)
    end

    # Вторая цифра принимается только вместе со списком вычтенного: иначе
    # читатель вправе счесть её подкруткой.
    it 'explains the smaller denominator with an explicit list of what is left out' do
      section = @text.split('## 2.').last.split('### Что не покрыто').first
      expect(section).to include('Знаменатель второй цифры меньше первого на',
                                 '**Поля тел ответов и уведомлений** —',
                                 'Больше не вычтено ничего')
      expect(section).to match(/\*\*Поля тел ответов и уведомлений\*\* — \d+: роль поля/)
    end

    it 'puts both coverage figures into the metrics of the artifact' do
      metrics = @artifact.metrics
      expect(metrics[:coverage_percent]).to be_a(Integer)
      expect(metrics[:contract_coverage_percent]).to be_a(Integer)
      expect(metrics[:contract_total]).to be_between(metrics[:covered], metrics[:total])
      expect(metrics[:contract_coverage_percent]).to be >= metrics[:coverage_percent]
    end

    it 'places every warning of the profile into exactly one section' do
      paths = @text.scan(/^-? ?\*?\*?`(\$[^`]+)`/).flatten
      profile_paths = warnings_of_novapay.map(&:json_path).uniq
      expect(profile_paths - paths).to be_empty
    end

    it 'keeps the contradictions of the spec in section 5' do
      section = @text.split('## 5.').last.split('## 6.').first
      expect(section).to include('error_code_undeclared', 'error_code_unused',
                                 'undeclared_status_code')
    end

    it 'shows the operations outside the contract in section 4 with their methods' do
      section = @text.split('## 4.').last.split('## 5.').first
      expect(section).to include('`cancelPayout`', '`getBalance`', '`cancel(operation)`',
                                 '`balance()`')
    end

    it 'offers a ready overlay fragment for the conditional requirement hints' do
      expect(@text).to include('x-jsonschema-if', 'const: card', 'const: sbp',
                               'required: [bank_code]', 'required: [card_number]')
    end

    it 'glues its overlay fragments into a valid OpenAPI Overlay 1.0.0 document' do
      document = YAML.safe_load(overlay_document(@text))
      expect(document['overlay']).to eq('1.0.0')
      expect(document['actions']).to be_an(Array)
      expect(document['actions']).to all(include('target'))
      expect(document['actions'].size).to be >= 3
    end

    it 'ends with a numbered checklist of what is left to do by hand' do
      section = @text.split('## 7.').last
      expect(section).to match(/^1\. \S/)
      expect(section).to match(/Итого: \d+ пункт/)
    end

    # Одна цифра покрытия отвечает на вопрос, которого никто не задавал:
    # непокрытое надо разложить на «чужое», «устройство метрики» и «моя
    # работа», иначе читатель принимает всё непокрытое за провал разбора.
    it 'splits what is not covered into three named buckets' do
      line = gaps_section(@text)[/Непокрыто[^*]+/].gsub(/\s+/, ' ')
      expect(line).to match(/Непокрыто \d+: вне контракта \d+, структурных исключений \d+/)
      expect(line).to match(/требует ручной работы \d+/)
      counts = line.scan(/(\d+)/).flatten.map(&:to_i)
      expect(counts.first).to eq(counts[1..3].sum)
    end

    # Корзина ручной работы — единственная, адресованная человеку, поэтому
    # она идёт первой и целиком: оборванный список не отвечает на вопрос
    # «что мне доделать руками».
    it 'lists the manual bucket first and in full' do
      section = gaps_section(@text)
      manual = section.index('**Требует ручной работы')
      expect(manual).to be < section.index('**Вне контракта')
      expect(manual).to be < section.index('**Структурные исключения метрики')
      declared = section[/Требует ручной работы — (\d+)\./, 1].to_i
      listed = section[manual...section.index('**Вне контракта')].scan(/^- `/).size
      expect(listed).to eq(declared)
    end

    # Остальные две корзины сворачиваются: число, измерения и по нескольку
    # примеров. Свёртка ничего не прячет — корзина каждого элемента
    # вычислена из его причины.
    it 'folds the other two buckets into counts with examples' do
      section = gaps_section(@text)
      expect(section).to match(/\*\*Вне контракта — \d+\.\*\* Ресурсы спецификации/)
      expect(section).to match(/\*\*Поля тел ответов и уведомлений\*\* — \d+[:,]/)
      expect(section.scan(/^- \*\*[^*]+\*\* — \d+, например: /).size).to be >= 1
    end

    def warnings_of_novapay
      rules = SpecGen::Rules.load
      document = SpecGen::SpecLoader.load(File.join(Fixtures::ROOT, 'specs', 'novapay.yaml'))
      SpecGen::Analyzers::Runner.call(document: document, rules: rules,
                                      options: { provider: 'novapay' }).warnings
    end
  end

  describe 'the section every warning code belongs to' do
    let(:classifier) { SpecGen::Generators::Report::Warnings }

    it 'assigns exactly one section to every code of the model' do
      SpecGen::IR::Warning::CODES.each do |code|
        section = classifier.section_for(code)
        expect(classifier::SECTIONS).to include(section), "#{code} has no section"
      end
    end

    it 'never puts a code into two section lists at once' do
      both = classifier::CONTRADICTIONS & classifier::NOTES
      expect(both).to be_empty
    end

    it 'only classifies codes that exist in the model' do
      known = SpecGen::IR::Warning::CODES
      expect(classifier::CONTRADICTIONS - known).to be_empty
      expect(classifier::NOTES - known).to be_empty
      expect(classifier::BOOKS.keys - known).to be_empty
      expect(classifier::CROSS_REFERENCE.keys - known).to be_empty
    end

    it 'has its own "what the tool did" text for every code in both locales' do
      SpecGen::Texts.supported.each do |locale|
        keys = SpecGen::Texts.keys(locale)
        SpecGen::IR::Warning::CODES.each do |code|
          expect(keys).to include("generators.report.action_#{code}"),
                          "#{locale}: no action text for #{code}"
        end
      end
    end

    it 'names a rules book for every code it can close with one' do
      classifier::BOOKS.each_value do |book|
        expect(SpecGen::Rules::Registry::BOOKS.keys).to include(book.to_sym)
      end
    end
  end

  describe 'a profile without any warnings' do
    let(:profile) do
      name = SpecGen::IR::Derived.structural('quiet', evidence: 'тест')
      info = SpecGen::IR::Info.new(name: name, oas_version: '3.0.3', oas_family: :oas30)
      SpecGen::IR::ProviderProfile.new(info: info)
    end

    let(:text) do
      Dir.mktmpdir('specgen-quiet') do |dir|
        rules = SpecGen::Rules.load
        artifacts = SpecGen::Generators.call(profile: profile, rules: rules,
                                             options: { output: dir })
        File.read(artifacts.last.path, encoding: 'UTF-8')
      end
    end

    it 'still writes all seven sections' do
      expect(headings(text)).to eq(sections)
    end

    it 'says that nothing was found instead of leaving a section empty' do
      expect(text.scan('Ничего не найдено').size).to be >= 3
      expect(text).to include('Непокрытых элементов нет')
    end

    it 'reports full coverage of an empty specification without dividing by zero' do
      expect(text).to include('**Покрытие: 100 % (0 из 0 элементов). ' \
                              'В границах контракта: 100 % (0 из 0).**')
    end

    # Спецификация, из которой контракту не досталось ничего, — единственный
    # случай нулевого знаменателя у второй цифры: делить на него нельзя.
    it 'keeps the in-contract figure whole when the contract can use nothing' do
      coverage = SpecGen::Generators::Report::View
                 .new(profile: profile, rules: SpecGen::Rules.load,
                      naming: SpecGen::Generators::Naming.for(profile)).coverage
      expect(coverage.in_scope_total).to eq(0)
      expect(coverage.in_scope_percent).to eq(100)
      expect(text).to include('в этой спецификации нет ни одного элемента')
    end

    it 'says there is nothing to cover instead of claiming 100 % in an empty dimension' do
      expect(text).not_to match(/\| 0 \| 0 \| 100 % \|/)
      expect(text.scan('| 0 | 0 | нечего покрывать |').size).to eq(7)
    end
  end

  describe SpecGen::Generators::Report::Gap do
    # Корзина вычисляется из причины таблицей, а не назначается на месте:
    # причина без строки в таблице означала бы пропуск, увиденный только
    # глазами читателя отчёта.
    it 'has a bucket for every reason the locale can print' do
      keys = YAML.load_file('locales/ru/generators.yml')['generators']['report'].keys
      reasons = keys.select { |key| key.start_with?('gap_') }.map(&:to_sym)
      expect(reasons).not_to be_empty
      expect(reasons - described_class::BUCKETS.keys).to be_empty
    end

    it 'knows only the three buckets of the report' do
      expect(described_class::BUCKETS.values.uniq.sort).to eq(described_class::ORDER.sort)
      expect(described_class::ORDER).to include(described_class::MAIN)
      expect(described_class::FOLDED).not_to include(described_class::MAIN)
    end

    # Элемент чужого ресурса не становится пробелом интеграции от того, что
    # причина у него та же: контракт до этого ресурса не доходит вовсе.
    it 'sends anything outside the contract to its own bucket whatever the reason' do
      gap = described_class.new(element: 'x', reason_key: :gap_field_required_todo, foreign: true)
      expect(gap.bucket).to eq(:out_of_contract)
      expect(gap).not_to be_manual
    end

    it 'keeps the same reason inside the contract as manual work' do
      gap = described_class.new(element: 'x', reason_key: :gap_field_required_todo)
      expect(gap.bucket).to eq(:manual)
      expect(gap).to be_manual
    end

    # Новый вид пропуска лучше показать человеку лишний раз, чем спрятать в
    # корзину «это не ваша забота».
    it 'treats a reason absent from the table as manual work' do
      expect(described_class.new(element: 'x', reason_key: :gap_brand_new).bucket).to eq(:manual)
    end
  end

  describe SpecGen::Generators::Report::Dimension do
    it 'has no percentage at all when nothing of the kind was found' do
      empty = described_class.new(key: 'statuses', total: 0, covered: 0, gaps: [])
      expect(empty).to be_empty
      expect(empty.percent).to be_nil
      expect(empty.percent_text).to eq('нечего покрывать')
    end

    it 'takes what the contract cannot use out of its own denominator only' do
      dimension = described_class.new(key: 'response_fields', total: 4, covered: 1,
                                      gaps: [%w[a b]], out_of_scope: 3)
      expect(dimension.excluded).to eq(3)
      expect(dimension.in_scope_total).to eq(1)
      expect(dimension.percent).to eq(25)
    end

    it 'counts nothing as out of contract when the count was not given' do
      dimension = described_class.new(key: 'statuses', total: 3, covered: 2, gaps: [%w[a b]])
      expect(dimension.excluded).to eq(0)
      expect(dimension.in_scope_total).to eq(3)
    end

    it 'rounds the share of covered elements when there is something to cover' do
      dimension = described_class.new(key: 'statuses', total: 3, covered: 2, gaps: [%w[a b]])
      expect(dimension).not_to be_empty
      expect(dimension.percent).to eq(67)
      expect(dimension.percent_text).to eq('67 %')
    end
  end
end
