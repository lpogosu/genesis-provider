# frozen_string_literal: true

RSpec.describe SpecGen::Rules::ErrorsBook do
  include RulesFixtures

  def errors(patch = {})
    load_rules('errors.yml' => rule('errors.yml').merge(patch)).errors
  end

  def error_for
    document = rule('errors.yml')
    yield document
    rules_error('errors.yml' => document)
  end

  describe 'reading the dictionary' do
    it 'answers an exact HTTP code before its class, and names what matched' do
      book = errors

      expect(book.action_for_status(401)).to eq([:alert, '401'])
      expect(book.action_for_status(404)).to eq([:reject, '4xx'])
      expect(book.action_for_status(503)).to eq([:retry_backoff, '5xx'])
      expect(book.action_for_status(301)).to be_nil
    end

    it 'answers the first pattern that matches the normalised code, in dictionary order' do
      book = errors

      expect(book.rule_for_code('Rate-Limit-Exceeded').name).to eq('rate_limit')
      expect(book.rule_for_code('insufficient_balance').action).to eq(:escalate)
      expect(book.rule_for_code('recipient_not_found').action).to eq(:reject)
      expect(book.rule_for_code('np_err_17')).to be_nil
    end

    it 'hands the analyzer the defaults it must warn with' do
      book = errors

      expect(book.default_action).to eq(:reject)
      expect(book.default_confidence).to eq(0.3)
      expect(book.pattern_confidence).to eq(0.8)
      expect(book).to be_retry_after('retry-after')
      expect(book).not_to be_retry_after('X-RateLimit-Reset')
    end
  end

  describe 'guarding the data' do
    it 'refuses dedup as an action, which only the schema comparison may derive' do
      message = error_for { |doc| doc['http']['codes'][409] = 'dedup' }

      expect(message).to include("$.http.codes['409']").and include('неизвестное значение "dedup"')
    end

    it 'refuses an HTTP class that is not 1xx..5xx and a status outside 100..599' do
      expect(error_for { |doc| doc['http']['classes']['6xx'] = 'reject' })
        .to include('класс HTTP-кодов: ожидается 1xx..5xx, получено: "6xx"')
      expect(error_for { |doc| doc['http']['codes'][999] = 'reject' })
        .to include('HTTP-код: ожидается целое число 100..599, получено: 999')
    end

    it 'refuses a missing default action and a confidence outside 0..1' do
      expect(error_for { |doc| doc.delete('default_action') }).to include('действие по ошибке')
      expect(error_for { |doc| doc['pattern_confidence'] = 1.5 })
        .to include('уверенность pattern_confidence: ожидается число в диапазоне 0.0..1.0')
    end

    it 'refuses an empty pattern list and a pattern that does not compile' do
      expect(error_for { |doc| doc['codes'] = [] }).to include('список codes')
      expect(error_for { |doc| doc['codes'][0]['pattern'] = '(?<x' })
        .to include('$.codes[0].pattern').and include('не компилируется')
    end

    it 'refuses a pattern entry without a name or with an unknown action' do
      expect(error_for { |doc| doc['codes'][0].delete('name') }).to include('имя шаблона')
      expect(error_for { |doc| doc['codes'][0]['action'] = 'panic' })
        .to include('$.codes[0].action').and include('неизвестное значение "panic"')
    end
  end
end
