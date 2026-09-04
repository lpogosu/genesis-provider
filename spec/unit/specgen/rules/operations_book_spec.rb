# frozen_string_literal: true

RSpec.describe SpecGen::Rules::OperationsBook do
  include RulesFixtures

  def operations(patch = {})
    load_rules('operations.yml' => rule('operations.yml').merge(patch)).operations
  end

  def patched(&)
    document = rule('operations.yml')
    yield document
    document
  end

  def error_for(&)
    rules_error('operations.yml' => patched(&))
  end

  describe 'reading the dictionary' do
    it 'describes every operation role but :unmapped, in dictionary order' do
      expect(operations.roles).to eq(SpecGen::IR::Roles::OPERATION - [:unmapped])
    end

    it 'hands the matcher its weights and thresholds as numbers' do
      book = operations

      expect(book.weight(:operation_id)).to eq(5)
      expect(book.scoring(:minimum)).to eq(0.4)
      expect(book.scoring(:floor)).to eq(5.0)
    end

    it 'normalizes the words, so a spelling in a spec cannot miss the entry' do
      book = operations('roles' => patched { |doc| doc['roles']['balance']['nouns'] = ['Account-Balance'] }['roles'])

      expect(book.entry(:balance)[:nouns]).to eq(['account_balance'])
    end

    it 'keeps the shape of an entry the matcher relies on' do
      entry = operations.entry(:webhook)

      expect(entry).to include(http_methods: [:post], request_body: true, unsecured: true,
                               tail_parameter: false)
    end

    it 'leaves request_body nil when the role does not care either way' do
      book = operations('roles' => patched { |doc| doc['roles']['cancel'].delete('request_body') }['roles'])

      expect(book.entry(:cancel)[:request_body]).to be_nil
    end
  end

  describe 'guarding the data' do
    it 'refuses a role outside IR::Roles::OPERATION' do
      message = error_for { |doc| doc['roles']['refund'] = { 'verbs' => ['refund'] } }

      expect(message).to include('роль операции: неизвестное значение "refund"')
    end

    it 'refuses to leave a role undescribed, so the matcher can never silently lose one' do
      message = error_for { |doc| doc['roles'].delete('balance') }

      expect(message).to include('нет записи для balance')
    end

    it 'refuses a role with no word to match on' do
      message = error_for do |doc|
        doc['roles']['balance'] = { 'http_methods' => ['get'], 'request_body' => false }
      end

      expect(message).to include('роль balance не перечисляет ни одного слова для сопоставления')
    end

    it 'refuses a weight of zero, which would switch a signal off in silence' do
      expect(error_for { |doc| doc['weights']['tag'] = 0 })
        .to include('вес сигнала tag должен быть больше нуля')
    end

    it 'refuses a signal it does not know' do
      expect(error_for { |doc| doc['weights']['vibes'] = 3 })
        .to include('неизвестные ключи vibes').and include('$.weights')
    end

    it 'refuses a threshold outside 0..1 and a floor of zero' do
      expect(error_for { |doc| doc['scoring']['minimum'] = 2 })
        .to include('порог minimum: ожидается число в диапазоне 0.0..1.0')
      expect(error_for { |doc| doc['scoring']['floor'] = 0 })
        .to include('порог floor: ожидается число больше нуля')
    end

    it 'refuses an HTTP method the IR does not know' do
      expect(error_for { |doc| doc['roles']['cancel']['http_methods'] = ['fly'] })
        .to include('HTTP-метод: неизвестное значение "fly"')
    end
  end
end
