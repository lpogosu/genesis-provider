# frozen_string_literal: true

RSpec.describe SpecGen::CLI do
  include CliRunner

  let(:novapay) { File.join(SpecGen::ROOT, 'spec', 'fixtures', 'specs', 'novapay.yaml') }

  describe '--help' do
    it 'lists both commands and exits with 0' do
      result = run_cli('--help')
      expect(result.status).to eq(0)
      expect(result.stdout).to include('generate').and include('diff')
    end
  end

  describe 'generate' do
    it 'is the default command, so `integrate --spec FILE` works' do
      result = run_cli('--spec', novapay)
      expect(result.stderr).to include('`generate` is not implemented yet')
    end

    it 'requires --spec or --all' do
      result = run_cli('generate')
      expect(result.status).to eq(described_class::EXIT_USAGE)
      expect(result.stderr).to include('--spec or --all')
    end

    it 'reports a missing spec file with its path and without a stack trace' do
      result = run_cli('generate', '--spec', 'nope.yaml')
      expect(result.status).to eq(described_class::EXIT_ERROR)
      expect(result.stderr).to include('nope.yaml').and include('not found')
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
      expect(result.stderr).to include('not implemented')
      expect(result.stderr).not_to include('usage:')
    end

    it 'accepts --all without --spec' do
      result = run_cli('generate', '--all')
      expect(result.stderr).to include('not implemented')
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
      expect(result.stderr).to include('`diff` is not implemented yet')
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
