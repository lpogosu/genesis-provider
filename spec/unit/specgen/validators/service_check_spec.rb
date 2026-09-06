# frozen_string_literal: true

require 'tmpdir'

# Прогон собранного класса на настоящих артефактах: конвейер пишет
# service.rb и fixtures.json, после чего класс исполняется с подменённой
# платформой и подменённым клиентом. Мокать здесь нечего — проверяется
# именно тот файл, который увидит человек.
#
# Половина примеров портит записанный класс ровно в одном месте и требует,
# чтобы прогон это заметил: проверка, которая ничего не ловит, хуже её
# отсутствия.
RSpec.describe SpecGen::Validators::ServiceCheck do
  include Fixtures

  # Прогон конвейера целиком.
  # @return [Array(IR::ProviderProfile, Rules::Registry, String, String)]
  def generate(path, dir)
    rules = SpecGen::Rules.load
    document = SpecGen::SpecLoader.load(path)
    options = { output: dir }
    profile = SpecGen::Analyzers::Runner.call(document: document, rules: rules, options: options)
    artifacts = SpecGen::Generators.call(profile: profile, rules: rules, document: document,
                                         options: options)
    [profile, rules, artifact(artifacts, :service), artifact(artifacts, :fixtures)]
  end

  def artifact(artifacts, kind)
    artifacts.find { |item| item.kind == kind }.path
  end

  def exercise(profile, rules, service, fixtures)
    described_class.new(profile: profile, rules: rules, service_file: service,
                        fixtures_file: fixtures).call
  end

  # Класс с одной правкой: пример меняет ровно одно обстоятельство и смотрит,
  # изменился ли от этого вердикт.
  def broken_source(dir, service, name)
    source = File.read(service, encoding: 'UTF-8')
    path = File.join(dir, "#{name}_service.rb")
    File.binwrite(path, yield(source))
    path
  end

  def failed(result)
    result.findings.select { |finding| finding.kind == :failed }
  end

  def messages(result)
    failed(result).map { |finding| "#{finding.subject}: #{finding.message}" }
  end

  describe 'the class generated from novapay.yaml' do
    before(:all) do
      @dir = Dir.mktmpdir('specgen-run')
      @profile, @rules, @service, @fixtures = generate(spec_fixture('novapay.yaml'), @dir)
      @result = exercise(@profile, @rules, @service, @fixtures)
    end

    after(:all) { FileUtils.remove_entry(@dir) }

    it 'loads, answers every call and matches every fixture' do
      expect(messages(@result)).to be_empty
      expect(@result.count(:passed)).to eq(@result.total)
    end

    it 'checks more than the four contract methods' do
      expect(@result.total).to be > 30
      expect(@result.count(:unchecked)).to be_zero
    end

    # Каждая находка называет метод и то, что проверялось: по отчёту должно
    # быть видно, где смотреть, без чтения кода проверки.
    it 'names the method and the aspect in every subject' do
      expect(@result.findings).to all(satisfy { |finding| finding.subject.start_with?('прогон: ') })
    end

    it 'exercises the four contract methods and the operations outside the contract' do
      subjects = @result.findings.map(&:subject).join("\n")
      expect(subjects).to include('check_conditions', 'create_request', 'fetch_status',
                                  'process_callback', 'cancel', 'balance')
    end

    it 'catches a path that no longer matches the fixture' do
      path = broken_source(@dir, @service, 'path') { |text| text.sub('/payouts"', '/payoutz"') }
      expect(messages(exercise(@profile, @rules, path, @fixtures)).join("\n"))
        .to include('POST /payouts')
    end

    it 'catches an authorization header that is no longer sent' do
      source = broken_source(@dir, @service, 'auth') do |text|
        text.sub("{ 'X-API-Key' => provider.credentials[:api_key] }", '{}')
      end
      expect(messages(exercise(@profile, @rules, source, @fixtures)).join("\n"))
        .to include('X-API-Key')
    end

    it 'catches a required field dropped from the request body' do
      source = broken_source(@dir, @service, 'body') do |text|
        text.sub("        external_id: operation.id,\n", '')
      end
      expect(messages(exercise(@profile, @rules, source, @fixtures)).join("\n"))
        .to include('external_id')
    end

    it 'catches a status translated into the wrong internal status' do
      source = broken_source(@dir, @service, 'status') do |text|
        text.sub("'completed' => :approved", "'completed' => :rejected")
      end
      expect(messages(exercise(@profile, @rules, source, @fixtures)).join("\n"))
        .to include('approve_operation')
    end

    it 'catches an error code mapped to the wrong platform failure' do
      source = broken_source(@dir, @service, 'error') do |text|
        text.sub('401 => :unauthorized', '401 => :forbidden')
      end
      expect(messages(exercise(@profile, @rules, source, @fixtures)).join("\n"))
        .to include(':unauthorized', ':forbidden')
    end

    # Класс, который не грузится, не даёт проверить ничего: одна находка о
    # загрузке и ни одной о вызовах — иначе отчёт был бы полон следствий
    # одной причины.
    it 'reports the loading of a class that is not there and stops' do
      source = broken_source(@dir, @service, 'absent') { "class Broken\nend\n" }
      result = exercise(@profile, @rules, source, @fixtures)
      expect(result.total).to eq(1)
      expect(result.findings.first.subject).to include('загрузка класса')
      expect(result.findings.first.kind).to eq(:failed)
    end

    it 'reports a class that does not parse as one finding about loading' do
      source = broken_source(@dir, @service, 'syntax') { |text| "#{text}\nend\n" }
      result = exercise(@profile, @rules, source, @fixtures)
      expect(result.total).to eq(1)
      expect(result.findings.first.message).to include('SyntaxError')
    end
  end

  # Спецификация без вебхуков: проверять уведомления нечем, и это «не
  # проверено» с причиной, а не падение и не «не прошло».
  describe 'a specification without webhooks' do
    before(:all) do
      @dir = Dir.mktmpdir('specgen-run-deposit')
      @result = exercise(*generate(spec_fixture('depositbank.yaml'), @dir))
    end

    after(:all) { FileUtils.remove_entry(@dir) }

    it 'skips the notification checks with a reason instead of failing them' do
      callback = @result.findings.select { |item| item.subject.include?('process_callback') }
      expect(callback).not_to be_empty
      expect(callback.map(&:kind).uniq).to eq([:unchecked])
      expect(callback.first.message).to include('вебхук')
    end

    it 'still exercises creation and polling' do
      expect(failed(@result)).to be_empty
      expect(@result.count(:passed)).to be > 10
    end
  end
end
