# frozen_string_literal: true

require 'tmpdir'

RSpec.describe SpecGen::Texts do
  describe '.supported' do
    it 'lists every locale directory that ships' do
      expect(described_class.supported).to eq(%w[en ru])
    end
  end

  describe '.locale' do
    it 'is Russian unless told otherwise' do
      described_class.locale = nil
      saved = ENV.delete('SPECGEN_LOCALE')
      begin
        expect(described_class.locale).to eq('ru')
      ensure
        ENV['SPECGEN_LOCALE'] = saved if saved
      end
    end

    it 'follows SPECGEN_LOCALE when no locale was set explicitly' do
      described_class.locale = nil
      saved = ENV.fetch('SPECGEN_LOCALE', nil)
      ENV['SPECGEN_LOCALE'] = 'en'
      begin
        expect(described_class.locale).to eq('en')
      ensure
        saved ? ENV['SPECGEN_LOCALE'] = saved : ENV.delete('SPECGEN_LOCALE')
      end
    end

    it 'rejects a locale that has no directory, naming the ones that do' do
      expect { described_class.locale = 'xx' }
        .to raise_error(SpecGen::LocaleError, /"xx".*en, ru/)
    end
  end

  describe '.t' do
    it 'returns the Russian text by default and the English one on request' do
      expect(described_class.t('summary.operations')).to eq('Операции:')
      described_class.locale = 'en'
      expect(described_class.t('summary.operations')).to eq('Operations:')
    end

    it 'fills %{placeholders} from keyword arguments' do
      expect(described_class.t('summary.base_url', env: 'ACME_BASE_URL'))
        .to eq('Базовый URL: переменная окружения ACME_BASE_URL')
    end

    it 'treats a missing key as our bug, not as text to print' do
      expect { described_class.t('summary.no_such_key') }
        .to raise_error(SpecGen::LocaleError, /no_such_key/)
    end

    it 'treats a missing placeholder value as our bug too' do
      expect { described_class.t('summary.base_url') }
        .to raise_error(SpecGen::LocaleError, /base_url/)
    end
  end

  describe '.plural' do
    it 'picks the Russian form by the last digits' do
      expect([1, 2, 5, 11, 21, 22, 25, 101, 111].map { |n| described_class.plural(n, 'operation') })
        .to eq(['1 операция', '2 операции', '5 операций', '11 операций', '21 операция',
                '22 операции', '25 операций', '101 операция', '111 операций'])
    end

    it 'picks the English form by one versus everything else' do
      described_class.locale = 'en'
      expect([0, 1, 2].map { |n| described_class.plural(n, 'field') })
        .to eq(['0 fields', '1 field', '2 fields'])
    end
  end

  describe 'completeness of the shipped locales' do
    let(:lib_sources) { Dir.glob(File.join(SpecGen::ROOT, 'lib', '**', '*.rb')).map { |f| File.read(f) } }

    # Формы множественного числа у языков разные (ru: one/few/many, en:
    # one/other), поэтому они сравниваются отдельно, по существительным.
    it 'gives every locale exactly the same keys, plural forms aside' do
      without_plural = ->(code) { described_class.keys(code).reject { |k| k.start_with?('plural.') } }
      expect(without_plural.call('en')).to eq(without_plural.call('ru'))
    end

    it 'has a text for every static key the code asks for' do
      asked = lib_sources.flat_map { |src| src.scan(/Texts\.t\(\s*['"]([a-z_][a-z0-9_.]*)['"]/).flatten }
      missing = asked.uniq - described_class.keys('ru')
      expect(missing).to be_empty, "keys used in lib/ but absent from locales/ru: #{missing.inspect}"
    end

    it 'has every plural form for every noun the code counts' do
      nouns = lib_sources.flat_map { |src| src.scan(/Texts\.plural\([^,]+,\s*['"]([a-z_]+)['"]/).flatten }
      expect(nouns).not_to be_empty
      nouns.uniq.each do |noun|
        expect(described_class.keys('ru')).to include("plural.#{noun}.one", "plural.#{noun}.few",
                                                      "plural.#{noun}.many")
        expect(described_class.keys('en')).to include("plural.#{noun}.one", "plural.#{noun}.other")
      end
    end
  end

  describe 'loading' do
    # Моки недоступны в around-хуках, поэтому временный каталог подменяется
    # в before и убирается в after.
    before do
      @dir = Dir.mktmpdir
      stub_const('SpecGen::LOCALES_DIR', @dir)
      described_class.reset!
    end

    after do
      described_class.reset!
      FileUtils.remove_entry(@dir)
    end

    it 'refuses a key defined in two files of one locale, naming the second file' do
      Dir.mkdir(File.join(SpecGen::LOCALES_DIR, 'xx'))
      File.write(File.join(SpecGen::LOCALES_DIR, 'xx', 'a.yml'), "greeting: hi\n")
      File.write(File.join(SpecGen::LOCALES_DIR, 'xx', 'b.yml'), "greeting: hello\n")
      described_class.locale = 'xx'

      expect { described_class.t('greeting') }
        .to raise_error(SpecGen::LocaleError, /"greeting".*b\.yml/)
    end

    it 'merges the files of one locale into one flat table' do
      Dir.mkdir(File.join(SpecGen::LOCALES_DIR, 'xx'))
      File.write(File.join(SpecGen::LOCALES_DIR, 'xx', 'a.yml'), "cli:\n  hello: hi\n")
      File.write(File.join(SpecGen::LOCALES_DIR, 'xx', 'b.yml'), "summary:\n  bye: bye\n")
      described_class.locale = 'xx'

      expect(described_class.keys('xx')).to eq(%w[cli.hello summary.bye])
    end
  end
end
