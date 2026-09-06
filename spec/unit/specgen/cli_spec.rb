# frozen_string_literal: true

require 'tmpdir'

RSpec.describe SpecGen::CLI do
  include CliRunner

  let(:novapay) { File.join(SpecGen::ROOT, 'spec', 'fixtures', 'specs', 'novapay.yaml') }
  let(:overlay) { File.join(SpecGen::ROOT, 'spec', 'fixtures', 'overlays', 'novapay.yaml') }

  describe '--help' do
    it 'lists every command and exits with 0' do
      result = run_cli('--help')
      expect(result.status).to eq(0)
      expect(result.stdout).to include('generate').and include('analyze').and include('diff')
    end
  end

  describe 'analyze' do
    it 'prints what the analyzers recognised and exits with 0' do
      result = run_cli('analyze', '--spec', novapay)
      expect(result.status).to eq(0)
      expect(result.stderr).to be_empty
      expect(result.stdout).to include('5 операций, 8 схем, 31 поле')
        .and include('create_payout')
        .and include('Авторизация: ApiKeyAuth -> api_key, заголовок X-API-Key')
        .and include('Предупреждения: 18')
    end

    it 'takes --provider as the name and marks it as stated, not derived' do
      result = run_cli('analyze', '--spec', novapay, '--provider', 'demo')
      expect(result.stdout).to include('Провайдер: demo (задано явно 1.00)')
    end

    it 'speaks English with --locale en, keeping identifiers untouched' do
      result = run_cli('analyze', '--spec', novapay, '--locale', 'en')
      expect(result.status).to eq(0)
      expect(result.stdout).to include('Parsing spec... novapay.yaml')
        .and include('Provider: novapay (heuristic 0.80)')
        .and include('create_payout')
    end

    it 'rejects an unknown locale as a usage error and names the supported ones' do
      result = run_cli('analyze', '--spec', novapay, '--locale', 'xx')
      expect(result.status).to eq(described_class::EXIT_USAGE)
      expect(result.stderr).to include('xx').and include('en, ru')
    end

    it 'adds evidence lines with --explain' do
      plain = run_cli('analyze', '--spec', novapay).stdout
      explained = run_cli('analyze', '--spec', novapay, '--explain').stdout
      expect(plain).not_to include('= запись rules/auth.yml')
      expect(explained).to include('= запись rules/auth.yml "api_key_header"')
    end

    it 'requires --spec' do
      result = run_cli('analyze')
      expect(result.status).to eq(described_class::EXIT_USAGE)
      expect(result.stderr).to include('--spec')
    end

    it 'reports a missing spec file with its path and without a stack trace' do
      result = run_cli('analyze', '--spec', 'nope.yaml')
      expect(result.status).to eq(described_class::EXIT_ERROR)
      expect(result.stderr).to include('nope.yaml').and include('не найден')
      expect(result.stderr).not_to include('.rb:')
    end

    it 'turns a broken spec into one line with the location, not a stack trace' do
      broken = File.join(SpecGen::ROOT, 'spec', 'fixtures', 'bad', 'broken_yaml.yaml')
      result = run_cli('analyze', '--spec', broken)
      expect(result.status).to eq(described_class::EXIT_ERROR)
      expect(result.stderr).to include('broken_yaml.yaml').and include('строка 8')
      expect(result.stderr).not_to include('.rb:')
      expect(result.stdout).to be_empty
    end
  end

  describe 'generate' do
    around do |example|
      Dir.mktmpdir('specgen-cli') do |dir|
        @out = dir
        example.run
      end
    end

    it 'is the default command, so `integrate --spec FILE` writes the service and exits with 0' do
      result = run_cli('--spec', novapay, '--provider', 'novapay', '--output', @out)
      expect(result.status).to eq(0)
      expect(result.stderr).to be_empty
      expect(result.stdout).to include('Генерация сервиса... ok (').and include('novapay_service.rb')
        .and include('Предупреждения: 18')
      expect(File.file?(File.join(@out, 'novapay_service.rb'))).to be(true)
    end

    # Форма вывода взята из описания кейса: сначала «Parsing spec... Found N
    # endpoints», авторизация и подпись вебхука, и только потом строки о
    # записанных файлах. Без преамбулы человек видит четыре «ok» и не знает,
    # разобрал инструмент пять операций или одну.
    it 'says what it understood in the spec before it says what it wrote' do
      result = run_cli('--spec', novapay, '--provider', 'novapay', '--output', @out)
      lines = result.stdout.lines.map(&:chomp)

      expect(lines[0]).to include('novapay.yaml').and include('OpenAPI 3.0.3').and include('5 операций')
      expect(lines[1]).to include('POST /payouts').and include('GET /balance')
      expect(lines[2]).to include('Авторизация').and include('X-API-Key')
      expect(lines[3]).to include('X-NovaPay-Signature')
      expect(lines[4]).to start_with('Генерация сервиса')
    end

    it 'with --strict writes the files first and only then exits with 1 because of warnings' do
      result = run_cli('generate', '--spec', novapay, '--provider', 'novapay', '--output', @out, '--strict')
      expect(result.status).to eq(described_class::EXIT_ERROR)
      expect(result.stderr).to include('--strict')
      expect(File.file?(File.join(@out, 'novapay_service.rb'))).to be(true)
    end

    it 'speaks English with --locale en' do
      result = run_cli('generate', '--spec', novapay, '--output', @out, '--locale', 'en')
      expect(result.status).to eq(0)
      expect(result.stdout).to include('Generating service... ok (')
    end

    it 'requires --spec or --all' do
      result = run_cli('generate')
      expect(result.status).to eq(described_class::EXIT_USAGE)
      expect(result.stderr).to include('--spec или --all')
    end

    it 'reports a missing spec file with its path and without a stack trace' do
      result = run_cli('generate', '--spec', 'nope.yaml')
      expect(result.status).to eq(described_class::EXIT_ERROR)
      expect(result.stderr).to include('nope.yaml').and include('не найден')
      expect(result.stderr).not_to include('.rb:')
    end

    it 'rejects unsupported target languages' do
      result = run_cli('generate', '--spec', novapay, '--lang', 'python')
      expect(result.status).to eq(described_class::EXIT_USAGE)
      expect(result.stderr).to include('python')
    end

    it 'rejects unknown switches instead of ignoring them' do
      result = run_cli('generate', '--spec', novapay, '--overlya', 'x.yaml')
      expect(result.status).to eq(described_class::EXIT_USAGE)
      expect(result.stderr).to include('--overlya')
    end

    it 'accepts every documented flag and applies the overlay it was handed' do
      result = run_cli('generate', '--spec', novapay, '--provider', 'demo', '--lang', 'ruby',
                       '--overlay', overlay, '--output', @out,
                       '--fix', '--strict')
      expect(result.stderr).not_to include('использование:')
      expect(result.stdout).to include('Overlay').and include('demo_service.rb')
    end

    it 'refuses a specification handed in place of an overlay instead of ignoring the flag' do
      result = run_cli('generate', '--spec', novapay, '--provider', 'demo', '--output', @out,
                       '--overlay', novapay)

      expect(result.status).to eq(described_class::EXIT_ERROR)
      expect(result.stderr).to include('это не документ OpenAPI Overlay')
      expect(result.stdout).to be_empty
    end

    it 'runs every specification of a directory and prints one summary table' do
      result = run_cli('generate', '--all', '--specs', File.dirname(novapay), '--output', @out)

      expect(result.status).to eq(0)
      expect(result.stdout).to include('Пакетный прогон', 'novapay.yaml', 'Покрытие')
      expect(result.stdout).to match(/Итого: \d+ спецификаци\S*, сгенерировано \d+ из \d+/)
    end

    it 'reports a specification it could not read as a row, and keeps the run going' do
      broken = File.join(@out, 'specs', 'broken.yaml')
      FileUtils.mkdir_p(File.dirname(broken))
      FileUtils.cp(novapay, File.join(File.dirname(broken), 'novapay.yaml'))
      File.binwrite(broken, "openapi: 3.0.3\npaths: [not, a, map]\n")
      result = run_cli('generate', '--all', '--specs', File.dirname(broken),
                       '--output', File.join(@out, 'batch'))

      expect(result.status).to eq(0)
      expect(result.stdout).to include('не разобрана', 'Не разобрано:', 'broken.yaml')
    end
  end

  describe 'diff' do
    let(:version_two) do
      File.join(SpecGen::ROOT, 'spec', 'fixtures', 'good', 'novapay_v2.yaml')
    end

    it 'requires --old and --new' do
      result = run_cli('diff')
      expect(result.status).to eq(described_class::EXIT_USAGE)
      expect(result.stderr).to include('--old').and include('--new')
    end

    it 'says that one specification against itself changes nothing, and exits with 0' do
      result = run_cli('diff', '--old', novapay, '--new', novapay)
      expect(result.status).to eq(0)
      expect(result.stderr).to be_empty
      expect(result.stdout).to include('Изменений нет')
    end

    it 'groups what the next version changed and counts what it costs' do
      result = run_cli('diff', '--old', novapay, '--new', version_two)
      expect(result.status).to eq(0)
      expect(result.stdout).to include('операция появилась: retryPayout')
        .and include('статус исчез: completed = approved')
        .and include('заголовок подписи: X-NovaPay-Signature -> X-Signature')
        .and include('параметр появился: X-Client-Id')
        .and include('Изменений: 10, из них меняют сервис: 10')
    end

    # --strict здесь значит не «есть предупреждения», а «есть изменения,
    # из-за которых сервис надо перегенерировать»: ровно это и нужно знать
    # сборке, которая следит за версией чужой спецификации.
    it 'with --strict exits with 1 when a change alters the generated service' do
      result = run_cli('diff', '--old', novapay, '--new', version_two, '--strict')
      expect(result.status).to eq(described_class::EXIT_ERROR)
      expect(result.stderr).to include('--strict')
      expect(result.stdout).to include('Изменений: 10')
    end

    it 'takes an overlay per version and shows only what the overlay made formal' do
      result = run_cli('diff', '--old', novapay, '--new', novapay, '--overlay-new', overlay,
                       '--strict')
      expect(result.status).to eq(0)
      expect(result.stdout).to include('Сравнение: novapay.yaml -> novapay.yaml + novapay.yaml')
        .and include('источник условия: description_hint -> x_jsonschema_if')
        .and include('из них меняют сервис: 0')
    end

    it 'speaks English with --locale en' do
      result = run_cli('diff', '--old', novapay, '--new', version_two, '--locale', 'en')
      expect(result.stdout).to include('Comparing: novapay.yaml -> novapay_v2.yaml')
        .and include('changes the generated service')
    end

    it 'reports a missing version with its path and without a stack trace' do
      result = run_cli('diff', '--old', novapay, '--new', 'nope.yaml')
      expect(result.status).to eq(described_class::EXIT_ERROR)
      expect(result.stderr).to include('nope.yaml').and include('не найден')
      expect(result.stderr).not_to include('.rb:')
    end
  end

  describe 'version' do
    it 'prints the version via --version' do
      expect(run_cli('--version').stdout).to include(SpecGen::VERSION)
    end
  end

  it 'rejects unknown commands with a usage error' do
    result = run_cli('frobnicate')
    expect(result.status).to eq(described_class::EXIT_USAGE)
    expect(result.stderr).to include('frobnicate')
  end
end
