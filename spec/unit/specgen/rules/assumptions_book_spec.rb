# frozen_string_literal: true

RSpec.describe SpecGen::Rules::AssumptionsBook do
  include RulesFixtures

  def assumptions(patch = {})
    load_rules('assumptions.yml' => rule('assumptions.yml').merge(patch)).assumptions
  end

  def error_for
    document = rule('assumptions.yml')
    yield document
    rules_error('assumptions.yml' => document)
  end

  describe 'reading the dictionary' do
    it 'keeps every entry in dictionary order with its number, text and source' do
      book = assumptions

      expect(book.all.map(&:id)).to eq([1, 2])
      expect(book.find(1).text).to include('описанию кейса')
      expect(book.find(1).source).to eq('описание кейса')
      expect(book.find(1)).to be_active
    end

    it 'documents only active entries marked for the integration guide' do
      expect(assumptions.documented.map(&:id)).to eq([1])
    end

    it 'drops a withdrawn entry from the documented list but keeps it in the book' do
      book = assumptions('assumptions' => [
                           rule('assumptions.yml')['assumptions'].first.merge(
                             'status' => 'withdrawn', 'replaced_by' => 'реальный класс платформы'
                           )
                         ])

      expect(book.documented).to be_empty
      expect(book.find(1).replaced_by).to eq('реальный класс платформы')
    end

    it 'treats a missing status as active and a missing documented flag as true' do
      book = assumptions('assumptions' => [{ 'id' => 3, 'text' => 'x', 'source' => 'y' }])

      expect(book.documented.map(&:id)).to eq([3])
    end
  end

  describe 'refusing a bad dictionary' do
    it 'rejects a number used twice, naming the first entry' do
      message = error_for { |doc| doc['assumptions'][1]['id'] = 1 }

      expect(message).to include('$.assumptions[1].id').and include('дважды')
      expect(message).to include('$.assumptions[0]')
    end

    it 'rejects a withdrawn entry that does not say what replaced it' do
      message = error_for { |doc| doc['assumptions'][0]['status'] = 'withdrawn' }

      expect(message).to include('$.assumptions[0].replaced_by').and include('replaced_by')
    end

    it 'rejects an entry without a source: an assumption without one is a guess' do
      message = error_for { |doc| doc['assumptions'][0].delete('source') }

      expect(message).to include('$.assumptions[0].source').and include('источник допущения')
    end

    it 'rejects a status outside the vocabulary' do
      message = error_for { |doc| doc['assumptions'][0]['status'] = 'maybe' }

      expect(message).to include('$.assumptions[0].status').and include('active, withdrawn')
    end
  end
end
