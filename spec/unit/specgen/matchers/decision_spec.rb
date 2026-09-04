# frozen_string_literal: true

# The threshold and the margin come from the shipped rules/roles.yml; the
# candidates are built by hand so that the two doubts can be told apart.
RSpec.describe SpecGen::Matchers::Decision do
  let(:rules) { SpecGen::Rules.load }
  let(:decision) { described_class.new(book: rules.roles) }

  def candidate(role, confidence, source = :heuristic)
    SpecGen::Matchers::Candidate.new(role: role, points: confidence * 14, total: 14.0, votes: [],
                                     source: source, confidence: confidence)
  end

  def result(*candidates)
    SpecGen::Matchers::Composite::Result.new(candidates: candidates, total: 14.0)
  end

  it 'has no doubt about a confident leader with a distant runner-up' do
    listed = result(candidate(:amount, 0.8), candidate(:currency, 0.3))

    expect(decision.doubt(listed.best, listed)).to be_nil
  end

  it 'calls a leader below the threshold low, whatever the runner-up' do
    listed = result(candidate(:amount, 0.5), candidate(:currency, 0.1))

    expect(decision.doubt(listed.best, listed)).to eq(:low)
  end

  it 'calls two confident candidates within the margin ambiguous' do
    listed = result(candidate(:amount, 0.7), candidate(:currency, 0.65))

    expect(decision.doubt(listed.best, listed)).to eq(:ambiguous)
    expect(decision.candidates_text(listed)).to eq('amount 0.70, currency 0.65')
  end

  it 'compares confidences, so a dictionary hit is questioned only by an almost certain rival' do
    moderate = result(candidate(:error_code, 0.9, :registry), candidate(:status, 0.5))
    strong = result(candidate(:error_code, 0.9, :registry), candidate(:status, 0.85))

    expect(decision.doubt(moderate.best, moderate)).to be_nil
    expect(decision.doubt(strong.best, strong)).to eq(:ambiguous)
  end

  it 'judges a demoted candidate by its own position in the ranking' do
    listed = result(candidate(:amount, 0.9, :registry), candidate(:currency, 0.5))

    expect(decision.doubt(listed.runner_up, listed)).to eq(:low)
  end
end
