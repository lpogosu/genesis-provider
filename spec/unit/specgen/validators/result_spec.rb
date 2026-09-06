# frozen_string_literal: true

# Итог стадии проверки и одна её находка. Числа отсюда печатает раздел 1
# отчёта и кладёт в метрики артефакта, поэтому у них ровно один источник.
RSpec.describe SpecGen::Validators::Result do
  def finding(kind, subject = 'запрос x')
    SpecGen::Validators::Finding.new(kind: kind, subject: subject, json_path: '$.paths')
  end

  let(:mixed) do
    described_class.new([finding(:passed), finding(:passed), finding(:failed),
                         finding(:synthesized), finding(:unchecked)])
  end

  it 'gives five counters, one per kind plus the total' do
    expect(mixed.to_h).to eq(checks_passed: 2, checks_failed: 1, checks_synthesized: 1,
                             checks_unchecked: 1, checks_total: 5)
  end

  it 'keeps the four kind counters summing to the total' do
    counts = mixed.to_h
    kinds = SpecGen::Validators::Finding::KINDS.map { |kind| counts.fetch(:"checks_#{kind}") }
    expect(kinds.sum).to eq(counts[:checks_total])
  end

  it 'calls everything except a passed check a problem' do
    expect(mixed.problems.map(&:kind)).to eq(%i[failed synthesized unchecked])
    expect(mixed).to be_problems
  end

  # Ноль проверок — это «сверять было не с чем», а не «все прошли»: пустой
  # итог не имеет права выглядеть успехом.
  it 'reports nothing at all when there was nothing to compare' do
    empty = described_class.new
    expect(empty.total).to eq(0)
    expect(empty.findings).to be_empty
    expect(empty).not_to be_problems
    expect(empty.to_h).to eq(checks_passed: 0, checks_failed: 0, checks_synthesized: 0,
                             checks_unchecked: 0, checks_total: 0)
  end

  it 'never lets its findings be edited after the stage is over' do
    expect { mixed.findings << finding(:passed) }.to raise_error(FrozenError)
  end

  describe SpecGen::Validators::Finding do
    it 'refuses a kind the report has no meaning for' do
      expect { described_class.new(kind: :ok, subject: 'запрос x') }
        .to raise_error(ArgumentError, /passed/)
    end

    it 'knows only the four kinds the report explains' do
      expect(described_class::KINDS).to eq(%i[passed failed synthesized unchecked])
    end
  end
end
