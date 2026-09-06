# frozen_string_literal: true

# Компиляция схем спецификации валидатором JSON Schema. Диалект выбирается
# по версии OpenAPI, а не по содержимому схемы: у 3.1 это JSON Schema
# 2020-12, у 3.0 — диалект OpenAPI 3.0.
RSpec.describe SpecGen::Validators::Schemas do
  include Fixtures

  # Путь до схемы тела запроса на создание депозита в разрешённом документе.
  def deposit_keys
    ['paths', '/deposits', 'post', 'requestBody', 'content', 'application/json', 'schema']
  end

  # Тело из примера самой спецификации: перевод в иенах, домашний перевод.
  def deposit_body
    { 'deposit_amount' => 125_000.0, 'currency_code' => 'JPY',
      'client_reference' => 'ORD-2026-000417', 'purpose_code' => 'trade_settlement',
      'value_date' => '2026-09-14',
      'remitter' => { 'settlement_type' => 'domestic', 'zengin_bank_code' => '0005',
                      'branch_code' => '123', 'account_number' => '1234567',
                      'account_holder_kana' => 'ヤマダ タロウ' } }
  end

  def document_of(document, family)
    SpecGen::SpecLoader::Document.new(file: document.file, version: document.version,
                                      family: family, raw: document.raw, data: document.data)
  end

  def errors(schema, body)
    schema.validate(body).to_a.map { |error| [error['data_pointer'], error['type']] }
  end

  before(:all) { @document = SpecGen::SpecLoader.load(spec_fixture('depositbank.yaml')) }

  it 'knows a dialect for both families of OpenAPI and takes it from the document' do
    expect(described_class::META.keys).to eq(%i[oas30 oas31])
    expect(@document.family).to eq(:oas31)
    expect(described_class::META.values).to all(be_a(URI::Generic))
  end

  it 'compiles a schema of an OpenAPI 3.1 document and passes its own example' do
    schema = described_class.new(@document).at(deposit_keys)
    expect(schema).to be_a(JSONSchemer::Schema)
    expect(errors(schema, deposit_body)).to be_empty
  end

  # Самое дорогое доказательство диалекта: `dependentRequired` — ключевое
  # слово JSON Schema 2020-12, которого в диалекте 3.0 нет. Одно и то же
  # тело и одна и та же схема дают разный вердикт только из-за семейства
  # версии, объявленного документом.
  it 'enforces dependentRequired under 3.1 and ignores it under the 3.0 dialect' do
    body = deposit_body
    body['remitter']['intermediary_swift'] = 'CHASUS33'
    oas31 = described_class.new(@document).at(deposit_keys)
    oas30 = described_class.new(document_of(@document, :oas30)).at(deposit_keys)
    expect(errors(oas31, body)).to eq([['/remitter/intermediary_swift', 'dependentRequired']])
    expect(errors(oas30, body)).to be_empty
  end

  it 'has nothing to compile when the specification declares no schema there' do
    schemas = described_class.new(@document)
    expect(schemas.at(nil)).to be_nil
    expect(schemas.at(%w[paths /nowhere post])).to be_nil
    expect(schemas.at(%w[paths /deposits post operationId])).to be_nil
  end

  # Одна схема встречается у нескольких фикстур: на больших спецификациях
  # это разница между секундами и минутами.
  it 'compiles the same schema once and hands out the same object afterwards' do
    schemas = described_class.new(@document)
    expect(schemas.at(deposit_keys)).to be(schemas.at(deposit_keys))
  end

  # В разрешённом документе `$ref` уже подставлены, и адресовать ветку
  # `oneOf` дискриминатору нечем: валидатор спотыкается на первой же такой
  # схеме, поэтому ключ снимается, а тело проверяет сам `oneOf`.
  describe 'a schema that carries a discriminator' do
    let(:data) do
      { 'components' => { 'schemas' => { 'Thing' => {
        'oneOf' => [{ 'type' => 'object', 'required' => ['card'],
                      'properties' => { 'kind' => { 'const' => 'card' },
                                        'card' => { 'type' => 'string' } } },
                    { 'type' => 'object', 'required' => ['phone'],
                      'properties' => { 'kind' => { 'const' => 'phone' },
                                        'phone' => { 'type' => 'string' } } }],
        'discriminator' => { 'propertyName' => 'kind' }
      } } } }
    end

    let(:schema) do
      document = SpecGen::SpecLoader::Document.new(
        file: 'inline.yaml', version: '3.1.0', family: :oas31, raw: data, data: data
      )
      described_class.new(document).at(%w[components schemas Thing])
    end

    it 'compiles anyway and still makes the body match one of the branches' do
      expect(errors(schema, 'kind' => 'card', 'card' => '4111111111111111')).to be_empty
      expect(errors(schema, 'kind' => 'card', 'phone' => '79001234567')).not_to be_empty
    end
  end
end
