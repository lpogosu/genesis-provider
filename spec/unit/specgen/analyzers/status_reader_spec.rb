# frozen_string_literal: true

# On the shipped dictionaries: the reading rules of rules/statuses.yml only
# make sense against the real vocabulary, and the values below are literal
# enum members of public provider specifications (Open Banking UK, Adyen
# Transfers, Lithic, Mastercard Open Banking Connect).
RSpec.describe SpecGen::Analyzers::StatusReader do
  let(:rules) { SpecGen::Rules.load }
  let(:reader) { described_class.new(book: rules.statuses) }

  def read(value)
    reader.call(value)
  end

  describe 'a name whose meaning is carried by its head' do
    it 'reads Accepted* and Awaiting* of Open Banking UK as in_progress' do
      %w[AcceptedTechnicalValidation AcceptedCustomerProfile AcceptedWithoutPosting
         AwaitingAuthorisation AwaitingFurtherAuthorisation PendingCancellationRequest].each do |value|
        result = read(value)

        expect(result.kind).to eq(:head)
        expect(result.derived.value).to eq(:in_progress)
        expect(result.derived.confidence).to eq(rules.statuses.tail_confidence)
        expect(result.derived.evidence).to include('голова')
      end
    end

    it 'prefers the tail to the head, so a completed settlement is not left in polling' do
      expect(read('AcceptedSettlementCompleted')).to have_attributes(kind: :tail)
      expect(read('AcceptedSettlementCompleted').derived.value).to eq(:approved)
      expect(read('InitiationFailed').derived.value).to eq(:rejected)
    end

    it 'refuses a head that would reject an operation whose cancellation was refused' do
      expect(read('RejectedCancellationRequest').kind).to eq(:unknown)
      expect(read('RejectedCancellationRequest').derived).to be_unknown
    end
  end

  describe 'a suffix that does not change the outcome' do
    it 'strips it and reads what is left' do
      result = read('capturedExternally')

      expect(result.kind).to eq(:suffix)
      expect(result.derived.value).to eq(:approved)
      expect(result.derived.confidence).to eq(rules.statuses.tail_confidence)
    end

    it 'still refuses an ambiguous remainder' do
      expect(read('refundedExternally').kind).to eq(:ambiguous)
      expect(read('refundedExternally').derived).to be_unknown
    end
  end

  describe 'an enum that mixes statuses with booking types' do
    it 'says the value names a type of operation instead of guessing an outcome' do
      %w[bankTransfer atmWithdrawal fee miscCost invoiceDeduction reserveAdjustment].each do |value|
        result = read(value)

        expect(result.kind).to eq(:not_status)
        expect(result.derived).to be_unknown
        expect(result.derived.evidence).to include('тип операции')
      end
    end

    it 'is not counted as read, so it cannot pull a field into the role of the event field' do
      expect(read('bankTransfer')).not_to be_read
    end

    it 'reads the status half of the same enum as usual' do
      expect(read('capturePending').derived.value).to eq(:in_progress)
      expect(read('authAdjustmentRefused').derived.value).to eq(:rejected)
    end
  end

  describe 'the case of the value' do
    it 'reads one word in every spelling the corpus contains' do
      %w[completed Completed COMPLETED].each do |value|
        expect(read(value)).to have_attributes(kind: :canonical)
        expect(read(value).derived).to have_attributes(value: :approved, confidence: 1.0)
      end
    end
  end

  describe 'the canon, which no widening may touch' do
    it 'keeps the five statuses of the case description at full confidence' do
      { 'pending' => :in_progress, 'processing' => :in_progress, 'completed' => :approved,
        'failed' => :rejected, 'cancelled' => :rejected }.each do |status, internal|
        expect(read(status)).to have_attributes(kind: :canonical)
        expect(read(status).derived).to have_attributes(value: internal, confidence: 1.0,
                                                        source: :registry)
      end
    end

    it 'still refuses a partial result and still names the candidate it rejected' do
      result = read('PART_DONE')

      expect(result.kind).to eq(:partial)
      expect(result.derived).to be_unknown
      expect(result.derived.evidence).to include('done').and include('part')
    end
  end
end
