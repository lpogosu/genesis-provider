# frozen_string_literal: true

RSpec.describe SpecGen::Reporter::BatchLines do
  def row(file, contract, coverage: 40)
    SpecGen::Batch::Row.new(file: file, provider: file.sub('.yaml', ''), operations: 3, roles: 3,
                            coverage: coverage, contract: contract, warnings: 1, artifacts: 4)
  end

  def median_of(rows)
    described_class.new(rows, dir: 'specs').lines.grep(/Медиана/).first
  end

  # Сводка показывает разброс первой колонки, и читатель делает из него
  # вывод об инструменте, хотя разброс описывает спецификации. Медиана
  # второй колонки отвечает на этот вопрос до того, как он задан.
  it 'adds one line with the median of the in-contract column' do
    rows = [row('a.yaml', 46), row('b.yaml', 98), row('c.yaml', 72), row('d.yaml', 80)]
    expect(median_of(rows)).to include('76 %')
  end

  it 'takes the middle value when the number of specifications is odd' do
    rows = [row('a.yaml', 46), row('b.yaml', 98), row('c.yaml', 72)]
    expect(median_of(rows)).to include('72 %')
  end

  # Медиана, а не среднее: одна спецификация с сотней чужих операций не
  # должна двигать итог прогона.
  it 'is not moved by a single specification full of foreign resources' do
    rows = [row('a.yaml', 80), row('b.yaml', 84), row('c.yaml', 88), row('d.yaml', 2)]
    expect(median_of(rows)).to include('82 %')
  end

  it 'ignores the specifications that were not parsed at all' do
    rows = [row('a.yaml', 80), SpecGen::Batch::Row.new(file: 'b.yaml', error: 'нечитаемо')]
    expect(median_of(rows)).to include('80 %')
  end

  it 'says nothing when the run parsed nothing' do
    rows = [SpecGen::Batch::Row.new(file: 'b.yaml', error: 'нечитаемо')]
    expect(median_of(rows)).to be_nil
  end
end
