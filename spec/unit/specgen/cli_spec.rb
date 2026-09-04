# frozen_string_literal: true

RSpec.describe SpecGen::CLI do
  include CliRunner

  let(:novapay) { File.join(SpecGen::ROOT, 'spec', 'fixtures', 'specs', 'novapay.yaml') }

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
        .and include('Предупреждения: 4')
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
      expect(plain).not_to include('= rules/auth.yml')
      expect(explained).to include('= rules/auth.yml entry "api_key_header"')
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
      expect(result.stderr).to include('broken_yaml.yaml').and include('line 8')
      expect(result.stderr).not_to include('.rb:')
      expect(result.stdout).to be_empty
    end
  end

  describe 'generate' do
    it 'is the default command, so `integrate --spec FILE` works' do
      result = run_cli('--spec', novapay)
      expect(result.stderr).to include('команда `generate` ещё не реализована')
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

    it 'accepts every documented flag' do
      result = run_cli('generate', '--spec', novapay, '--provider', 'demo', '--lang', 'ruby',
                       '--overlay', novapay, '--output', 'tmp/out',
                       '--with-mock', '--fix', '--strict')
      expect(result.stderr).to include('ещё не реализована')
      expect(result.stderr).not_to include('использование:')
    end

    it 'accepts --all without --spec' do
      result = run_cli('generate', '--all')
      expect(result.stderr).to include('ещё не реализована')
    end
  end

  describe 'diff' do
    it 'requires --old and --new' do
      result = run_cli('diff')
      expect(result.status).to eq(described_class::EXIT_USAGE)
      expect(result.stderr).to include('--old').and include('--new')
    end

    it 'accepts two spec versions' do
      result = run_cli('diff', '--old', novapay, '--new', novapay)
      expect(result.stderr).to include('команда `diff` ещё не реализована')
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
