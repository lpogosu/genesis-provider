# frozen_string_literal: true

RSpec.describe SpecGen::Generators::Naming do
  def names(raw)
    naming = described_class.new(raw)
    [naming.slug, naming.file_name, naming.class_name, naming.env_name]
  end

  it 'turns a plain slug into a file, a class and an ENV name' do
    expect(names('novapay')).to eq(%w[novapay novapay_service.rb NovapayService NOVAPAY_BASE_URL])
  end

  it 'keeps snake_case words apart in the class name' do
    expect(names('acme_pay')).to eq(%w[acme_pay acme_pay_service.rb AcmePayService ACME_PAY_BASE_URL])
  end

  it 'cleans a title with spaces, punctuation and mixed case' do
    expect(names('Adyen Payout API (v68)!')).to eq(
      %w[adyen_payout_api_v68 adyen_payout_api_v68_service.rb AdyenPayoutApiV68Service ADYEN_PAYOUT_API_V68_BASE_URL]
    )
  end

  it 'transliterates Cyrillic and drops accents instead of producing an invalid identifier' do
    expect(names('ЮKassa')[2]).to eq('YukassaService')
    expect(names('Café Pay')[0]).to eq('cafe_pay')
  end

  it 'never starts an identifier with a digit' do
    expect(names('1pay')).to eq(%w[p1pay p1pay_service.rb P1payService P1PAY_BASE_URL])
  end

  it 'falls back to a neutral name when nothing usable remains' do
    expect(names(nil)[0]).to eq('provider')
    expect(names('!!!')[2]).to eq('ProviderService')
  end

  it 'produces a valid Ruby constant for every input' do
    ['', 'x-y', '  ', '中文', 'ПлатёжБанк', '9-9'].each do |raw|
      expect(described_class.new(raw).class_name).to match(/\A[A-Z][A-Za-z0-9]*\z/)
    end
  end

  it 'takes the name from the profile info' do
    profile = SpecGen::IR::ProviderProfile.new(
      info: SpecGen::IR::Info.new(name: SpecGen::IR::Derived.structural('demo', evidence: '--provider'),
                                  oas_version: '3.0.3', oas_family: :oas30)
    )
    expect(described_class.for(profile).class_name).to eq('DemoService')
    expect(described_class.for(SpecGen::IR::ProviderProfile.new).slug).to eq('provider')
  end
end
