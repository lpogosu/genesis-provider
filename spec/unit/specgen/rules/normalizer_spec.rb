# frozen_string_literal: true

RSpec.describe SpecGen::Rules::Normalizer do
  describe '.call' do
    {
      'bank_code' => 'bank_code',
      'bankCode' => 'bank_code',
      'BankCode' => 'bank_code',
      'X-Bank-BIC' => 'x_bank_bic',
      'bank code' => 'bank_code',
      'Bank.Code' => 'bank_code',
      'HTTPStatusCode' => 'http_status_code',
      '__amount__' => 'amount',
      'amount2' => 'amount2',
      :amount => 'amount',
      '---' => '',
      nil => ''
    }.each do |input, expected|
      it "turns #{input.inspect} into #{expected.inspect}" do
        expect(described_class.call(input)).to eq(expected)
      end
    end
  end

  describe '.tokens' do
    it 'splits a normalized name into words' do
      expect(described_class.tokens('X-Bank-BIC')).to eq(%w[x bank bic])
    end

    it 'returns nothing for a name that normalizes away' do
      expect(described_class.tokens('***')).to eq([])
    end
  end
end
