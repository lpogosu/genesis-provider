# frozen_string_literal: true

require 'tmpdir'

RSpec.describe SpecGen::Batch do
  include Fixtures

  def rules
    @rules ||= SpecGen::Rules.load
  end

  # Минимальная, но полноценная спецификация: своё имя операции, свой статус
  # и свой сервер, чтобы у каждой из них был свой провайдер и своё покрытие.
  def spec_for(name)
    <<~YAML
      openapi: 3.0.3
      info: { title: #{name} API, version: '1.0' }
      servers: [{ url: https://sandbox.#{name}.example/v1 }]
      paths:
        /payouts:
          post:
            operationId: create#{name.capitalize}Payout
            requestBody:
              required: true
              content:
                application/json:
                  schema:
                    type: object
                    required: [amount, currency]
                    properties:
                      amount: { type: integer, example: 100000 }
                      currency: { type: string, enum: [RUB] }
            responses:
              '201':
                description: ok
                content:
                  application/json:
                    schema:
                      type: object
                      properties:
                        id: { type: string }
                        status: { type: string, enum: [pending, completed] }
    YAML
  end

  def write_specs(dir, names)
    names.each { |name| File.binwrite(File.join(dir, "#{name}.yaml"), spec_for(name)) }
  end

  describe 'a directory of specifications' do
    it 'generates a full set of artifacts for each one, in file order' do
      Dir.mktmpdir('specgen-batch') do |dir|
        specs = File.join(dir, 'specs')
        Dir.mkdir(specs)
        write_specs(specs, %w[bravo alpha])
        rows = described_class.new(dir: specs, rules: rules,
                                   options: { output: File.join(dir, 'out') }).call

        expect(rows.map(&:file)).to eq(%w[alpha.yaml bravo.yaml])
        expect(rows.map(&:provider)).to eq(%w[alpha bravo])
        expect(rows).to all(have_attributes(operations: 1, roles: 1, artifacts: 4))
        expect(rows.first.coverage).to be_between(1, 100)
      end
    end

    it 'writes each provider into its own directory, so nothing overwrites anything' do
      Dir.mktmpdir('specgen-batch') do |dir|
        specs = File.join(dir, 'specs')
        Dir.mkdir(specs)
        write_specs(specs, %w[alpha bravo])
        described_class.new(dir: specs, rules: rules,
                            options: { output: File.join(dir, 'out') }).call

        expect(Dir.glob(File.join(dir, 'out', '*', '*_service.rb')).map { |p| File.basename(p) })
          .to contain_exactly('alpha_service.rb', 'bravo_service.rb')
      end
    end

    it 'keeps going when one specification cannot be read, and says why in its row' do
      Dir.mktmpdir('specgen-batch') do |dir|
        specs = File.join(dir, 'specs')
        Dir.mkdir(specs)
        write_specs(specs, %w[alpha])
        File.binwrite(File.join(specs, 'broken.yaml'), "openapi: 3.0.3\npaths: [not, a, map]\n")
        rows = described_class.new(dir: specs, rules: rules,
                                   options: { output: File.join(dir, 'out') }).call

        expect(rows.map(&:ok?)).to eq([true, false])
        expect(rows.last).to have_attributes(file: 'broken.yaml', coverage: nil)
        expect(rows.last.error).to include('broken.yaml')
      end
    end

    it 'reaches specifications in nested directories and names them by the relative path' do
      Dir.mktmpdir('specgen-batch') do |dir|
        specs = File.join(dir, 'specs')
        Dir.mkdir(specs)
        Dir.mkdir(File.join(specs, 'real'))
        File.binwrite(File.join(specs, 'real', 'alpha.yaml'), spec_for('alpha'))
        rows = described_class.new(dir: specs, rules: rules,
                                   options: { output: File.join(dir, 'out') }).call

        expect(rows.map(&:file)).to eq([File.join('real', 'alpha.yaml')])
      end
    end

    it 'refuses an empty or missing directory instead of reporting an empty run' do
      Dir.mktmpdir('specgen-batch') do |dir|
        empty = described_class.new(dir: dir, rules: rules)
        missing = described_class.new(dir: File.join(dir, 'nope'), rules: rules)

        expect { empty.call }.to raise_error(SpecGen::SpecLoadError, /спецификаций/)
        expect { missing.call }.to raise_error(SpecGen::SpecLoadError)
      end
    end
  end

  describe 'the shipped specifications' do
    it 'runs the whole spec/fixtures/specs directory without a single failure' do
      Dir.mktmpdir('specgen-batch') do |dir|
        rows = described_class.new(dir: described_class::DEFAULT_DIR, rules: rules,
                                   options: { output: dir }).call

        expect(rows).not_to be_empty
        expect(rows.reject(&:ok?)).to be_empty
        expect(rows.map(&:file)).to include('novapay.yaml')
      end
    end
  end
end
