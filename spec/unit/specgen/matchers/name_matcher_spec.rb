# frozen_string_literal: true

# The shipped dictionaries: synonyms, tokens and generic words are data, and
# a matcher checked against a stub of names only would prove nothing about
# the dictionary the tool ships with.
RSpec.describe SpecGen::Matchers::NameMatcher do
  let(:rules) { SpecGen::Rules.load }
  # The header dictionary is keyed the way Rules::Normalizer spells the
  # header: X-Acme-Sig -> x_acme_sig.
  let(:matcher) do
    described_class.new(book: rules.roles,
                        headers: { 'x_acme_sig' => [:signature, 'signatures.yml'] })
  end

  def subject_named(name, parents: [])
    SpecGen::Matchers::Subject.new(name: name, parents: parents)
  end

  def votes(name, parents: [])
    matcher.call(subject_named(name, parents: parents))
  end

  describe 'the dictionary step' do
    it 'matches a synonym exactly, whatever the spelling, with one vote and no others' do
      %w[sum Sum SUM payoutAmount payout-amount].each do |name|
        listed = votes(name)

        expect(listed.size).to eq(1)
        expect(listed.first).to have_attributes(role: :amount, score: 1.0, kind: :synonym)
        expect(listed.first).to be_dictionary
      end
    end

    it 'maps sum to amount by the dictionary, where a string metric never would' do
      expect(SpecGen::Matchers::Levenshtein.similarity('sum', 'amount')).to be < 0.2
      expect(votes('sum').first).to have_attributes(role: :amount, kind: :synonym)
      expect(votes('sum').first.evidence).to include('синоним роли amount (rules/roles.yml)')
    end

    it 'reads a known signature header from the header dictionary' do
      vote = votes('X-Acme-Sig').first

      expect(vote).to have_attributes(role: :signature, kind: :header, score: 1.0)
      expect(vote.evidence).to include('известный заголовок из signatures.yml')
    end

    it 'exposes the exact lookup RoleLookup delegates to' do
      expect(matcher.exact('bic')).to eq(:bank_code)
      expect(matcher.exact('xref_tag_9')).to be_nil
      expect(matcher.exact(nil)).to be_nil
    end
  end

  describe 'the token step' do
    it 'votes with a strong token from the hints of the role' do
      vote = votes('payout_amt').find { |v| v.role == :amount }

      expect(vote).to have_attributes(kind: :token, score: 1.0)
      expect(vote.evidence).to include('токен `amt`')
    end

    it 'marks a generic token such as code as weak, so it needs a parent to count' do
      vote = votes('country_code').find { |v| v.role == :error_code }

      expect(vote).to have_attributes(kind: :weak_token)
      expect(vote).to be_weak_token
      expect(vote).not_to be_identifying
    end
  end

  describe 'a synonym the parent forbids' do
    it 'gives no dictionary vote to state inside an address, where it means a region' do
      banned = votes('state', parents: %w[BillingAddress])
      allowed = votes('state', parents: %w[TransferResource])

      # The name still votes, but only as a weak signal: the role, if it is
      # assigned at all, becomes a heuristic below the threshold and lands in
      # the report instead of passing as a dictionary fact.
      expect(banned.map(&:kind)).not_to include(:synonym)
      expect(banned.find { |vote| vote.role == :status }.score).to be < allowed.first.score
    end

    it 'keeps the dictionary vote for the same name in a payment schema' do
      vote = votes('state', parents: %w[TransferResource]).find { |v| v.role == :status }

      expect(vote.kind).to eq(:synonym)
    end

    it 'gives no dictionary vote to type inside an error body' do
      banned = votes('type', parents: %w[ErrorEnvelope])

      expect(banned.map(&:kind)).not_to include(:synonym)
      expect(banned.find { |vote| vote.role == :recipient_type }.score).to be < 1.0
    end

    it 'keeps the dictionary vote for type under the recipient' do
      vote = votes('type', parents: %w[Recipient]).find { |v| v.role == :recipient_type }

      expect(vote.kind).to eq(:synonym)
    end
  end

  describe 'the overlap step' do
    it 'scores the share of tokens in common with the closest synonym' do
      vote = votes('recipient_phone_no').find { |v| v.role == :recipient_phone }

      expect(vote.kind).to eq(:overlap)
      expect(vote.score).to be_within(0.01).of(0.8 * (2.0 / 3))
      expect(vote.evidence).to include('общие токены с синонимом `recipient_phone`: recipient, phone (67%)')
    end

    it 'ignores an overlap made only of generic words' do
      expect(votes('debug_id')).to be_empty
      expect(votes('full_name')).to be_empty
      expect(votes('method')).to be_empty
    end
  end

  describe 'the Levenshtein step' do
    it 'catches a typo of a synonym with a score that alone stays below the threshold' do
      vote = votes('amout').find { |v| v.role == :amount }

      expect(vote.kind).to eq(:levenshtein)
      expect(vote.score).to be < 0.5
      expect(vote.evidence).to include('похоже на синоним `amount`')
    end

    it 'does not compare names shorter than the minimum length' do
      expect(votes('amo')).to be_empty
    end
  end

  it 'votes for nothing when the name says nothing' do
    expect(votes('xref_tag_9')).to be_empty
  end
end
