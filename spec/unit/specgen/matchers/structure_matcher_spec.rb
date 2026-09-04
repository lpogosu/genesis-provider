# frozen_string_literal: true

# On the shipped dictionaries: the parent words and locations of a role are
# data, and the fixture dictionaries carry names only.
RSpec.describe SpecGen::Matchers::StructureMatcher do
  let(:rules) { SpecGen::Rules.load }
  let(:matcher) { described_class.new(book: rules.roles) }

  def votes(attributes)
    matcher.call(SpecGen::Matchers::Subject.new(name: 'x', **attributes))
  end

  it 'votes for the roles whose parent hints share a token with the parent, schema or property' do
    expect(votes(parents: ['PayoutError']).map(&:role))
      .to include(:error_code, :error_message, :provider_operation_id)
    expect(votes(parents: ['Thing.properties.recipient']).map(&:role))
      .to include(:recipient_type, :recipient_phone, :bank_code, :bank_name, :card_number)
  end

  it 'names the parent and the token in the evidence' do
    vote = votes(parents: ['PayoutError']).find { |v| v.role == :error_code }

    expect(vote.evidence).to include('родитель `PayoutError`').and include('токен `error`')
  end

  it 'votes by location for header and path parameters' do
    expect(votes(location: :header).map(&:role)).to contain_exactly(:idempotency_key, :signature)
    expect(votes(location: :path).map(&:role)).to eq([:provider_operation_id])
    expect(votes(location: :query)).to be_empty
  end

  it 'never identifies a role on its own' do
    expect(votes(parents: ['Recipient'], location: :header)).to all(satisfy { |v| !v.identifying? })
  end

  it 'offers the parent check RoleLookup uses for error codes' do
    words = rules.roles.hints(:error_code)[:parents]

    expect(described_class.parent_hit(%w[details PayoutError], words)).to eq(%w[PayoutError error])
    expect(described_class.parent_hit(['Currency'], words)).to be_nil
  end
end
