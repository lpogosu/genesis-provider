# frozen_string_literal: true

# On the shipped dictionaries: the types and formats a role accepts are data.
RSpec.describe SpecGen::Matchers::TypeMatcher do
  let(:rules) { SpecGen::Rules.load }
  let(:matcher) { described_class.new(book: rules.roles) }

  def votes(type, format = nil)
    matcher.call(SpecGen::Matchers::Subject.new(name: 'x', type: type, format: format))
  end

  it 'votes for the roles whose format matches, with the format as evidence' do
    listed = votes('string', 'date-time')

    expect(listed.select { |v| v.kind == :format }.map(&:role)).to eq(%i[created_at completed_at])
    expect(listed.find { |v| v.role == :created_at }.evidence).to include('format date-time')
  end

  it 'votes for every role compatible with the type, as confirmation only' do
    listed = votes('integer')

    expect(listed.map(&:role)).to include(:amount, :external_id, :provider_operation_id)
    expect(listed.map(&:role)).not_to include(:recipient_phone, :card_number)
    expect(listed).to all(satisfy { |vote| !vote.identifying? })
  end

  it 'says nothing about a field without type or format' do
    expect(votes(nil)).to be_empty
  end

  it 'lets a string amount through, because some providers send amounts as strings' do
    expect(votes('string').map(&:role)).to include(:amount)
  end
end
