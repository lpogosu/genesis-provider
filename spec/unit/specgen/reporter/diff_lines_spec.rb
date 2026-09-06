# frozen_string_literal: true

RSpec.describe SpecGen::Reporter::DiffLines do
  def change(kind, **rest)
    SpecGen::Diff::Change.build(kind, json_path: '$.x', **rest)
  end

  def render(changes)
    described_class.new(changes, old: 'novapay.yaml', new: 'novapay_v2.yaml').lines
  end

  it 'says that nothing changed, and says it under the same heading' do
    expect(render([])).to eq(['Сравнение: novapay.yaml -> novapay_v2.yaml', 'Изменений нет'])
  end

  it 'groups the changes by area, in the order of the fixed list' do
    lines = render([change(:condition_added, after: 'min_amount = 100000'),
                    change(:operation_added, after: 'retryPayout')])
    expect(lines[1..-2].grep(/^[А-ЯЁ]/)).to eq(['Операции', 'Условия взаимодействия'])
  end

  # Появление показывает одно значение, а переход — пару: иначе «заголовок
  # подписи: X-Signature» читалось бы как «заголовок появился», хотя на самом
  # деле он сменился.
  it 'prints one value for an arrival and a pair for a transition' do
    lines = render([change(:status_added, after: 'succeeded = approved'),
                    change(:status_internal_changed, before: 'paid = approved',
                                                     after: 'paid = in_progress')])
    expect(lines).to include(a_string_including('статус появился: succeeded = approved'))
      .and include(a_string_including('внутренний статус: paid = approved -> paid = in_progress'))
  end

  it 'shows a value that is gone as a dash, not as an empty place' do
    lines = render([change(:signature_encoding_changed, before: :hex, after: nil)])
    expect(lines).to include(a_string_including('кодирование подписи: hex -> —'))
  end

  it 'prints the address of every change under it' do
    lines = render([change(:operation_added, json_path: "$.paths['/retry'].post",
                                             after: 'retryPayout')])
    expect(lines).to include("      $.paths['/retry'].post")
  end

  # Пометка стоит у каждого изменения, а не только у тех, что меняют сервис:
  # читателю нужно и «что перегенерировать», и «почему вот это не надо».
  it 'marks what each change costs' do
    lines = render([change(:operation_added, after: 'retryPayout'),
                    change(:idempotency_required_changed, before: :optional, after: :required),
                    change(:condition_added, after: 'idempotency_optional = Idempotency-Key',
                                             impact: :info)])
    expect(lines.grep(/меняет сгенерированный сервис/).size).to eq(1)
    expect(lines.grep(/меняет документацию и фикстуры/).size).to eq(1)
    expect(lines.grep(/видно только в отчёте/).size).to eq(1)
  end

  it 'ends with both counts, because the second one answers the actual question' do
    lines = render([change(:operation_added, after: 'a'), change(:operation_added, after: 'b'),
                    change(:idempotency_required_changed, before: :optional, after: :required)])
    expect(lines.last).to eq('Изменений: 3, из них меняют сервис: 2')
  end

  it 'joins a list value with commas instead of printing it as Ruby' do
    lines = render([change(:auth_credentials_changed, before: %w[api_key], after: %w[key secret])])
    expect(lines).to include(a_string_including('api_key -> key, secret'))
  end

  it 'speaks English on request, leaving the values of the specification untouched' do
    SpecGen::Texts.locale = 'en'
    lines = render([change(:status_added, after: 'succeeded = approved')])
    expect(lines.first).to eq('Comparing: novapay.yaml -> novapay_v2.yaml')
    expect(lines).to include(a_string_including('status appeared: succeeded = approved')
      .and(a_string_including('changes the generated service')))
  end

  # Словарь видов открыт для дополнения, и текст к нему пишется в двух
  # локалях сразу. Забытый ключ падает в рантайме на чужой спецификации, а
  # здесь — на своей.
  it 'has a text for every kind, area and impact in both locales' do
    keys = SpecGen::Diff::Change::KINDS.keys.map { |kind| "diff.kind.#{kind}" } +
           SpecGen::Diff::Change::AREAS.map { |area| "diff.area.#{area}" } +
           SpecGen::Diff::Change::IMPACTS.map { |impact| "diff.impact.#{impact}" }
    %w[ru en].each do |locale|
      expect(keys - SpecGen::Texts.keys(locale)).to be_empty, locale
    end
  end
end
