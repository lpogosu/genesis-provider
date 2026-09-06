# frozen_string_literal: true

require 'json'
require 'tmpdir'

# Стадия проверки на настоящем прогоне: спецификация читается с диска,
# генератор пишет fixtures.json, и сверяется именно записанный файл. Мокать
# здесь нечего — генератор остаётся чистой функцией от файла, а единственный
# способ доказать, что запрос правильный, — прогнать его через схему той же
# спецификации.
RSpec.describe SpecGen::Validators::FixtureCheck do
  include Fixtures

  # Прогон конвейера целиком: проверяется тот файл, который увидит человек.
  def generate(path, dir)
    rules = SpecGen::Rules.load
    document = SpecGen::SpecLoader.load(path)
    options = { output: dir }
    profile = SpecGen::Analyzers::Runner.call(document: document, rules: rules, options: options)
    artifacts = SpecGen::Generators.call(profile: profile, rules: rules, document: document,
                                         options: options)
    [document, profile, artifacts.find { |item| item.kind == :fixtures }.path]
  end

  # Только разбор: пример сам решает, какие фикстуры подставить.
  def analyze(path)
    rules = SpecGen::Rules.load
    document = SpecGen::SpecLoader.load(path)
    [document, SpecGen::Analyzers::Runner.call(document: document, rules: rules, options: {})]
  end

  def check(document, profile, file)
    described_class.new(document: document, profile: profile, fixtures_file: file).call
  end

  def written(dir, fixtures)
    path = File.join(dir, 'written.json')
    File.binwrite(path, JSON.generate(fixtures))
    path
  end

  def fixtures_of(file)
    JSON.parse(File.read(file, encoding: 'UTF-8'))
  end

  # Записанные фикстуры с одной правкой: пример меняет ровно одно
  # обстоятельство и смотрит, изменился ли от этого вердикт.
  def patched(dir, file)
    fixtures = fixtures_of(file)
    yield fixtures
    path = File.join(dir, 'patched.json')
    File.binwrite(path, JSON.generate(fixtures))
    path
  end

  def entry(fixtures, part, name)
    fixtures.fetch(part).find { |item| item['name'] == name }
  end

  def finding(result, part, name)
    subject = SpecGen::Texts.t("validators.subject_#{part}", name: name)
    result.findings.find { |item| item.subject == subject }
  end

  # Та же спецификация без схемы тела уведомления. Единственное изменение —
  # схемы больше нет; всё остальное на месте, включая сами фикстуры.
  def without_body_schema(document, path)
    data = Marshal.load(Marshal.dump(document.data))
    data.dig('paths', path).each_value do |item|
      item['requestBody']&.delete('content') if item.is_a?(Hash)
    end
    SpecGen::SpecLoader::Document.new(file: document.file, version: document.version,
                                      family: document.family, raw: document.raw, data: data)
  end

  before(:all) do
    @dir = Dir.mktmpdir('specgen-checks')
    @document, @profile, @file = generate(spec_fixture('novapay.yaml'), @dir)
    @result = check(@document, @profile, @file)
  end

  after(:all) { FileUtils.remove_entry(@dir) }

  describe 'a body the specification itself offers as an example' do
    it 'passes the schema of its own operation and says where that schema is' do
      found = finding(@result, :request, 'createPayout')
      expect(found).to be_passed
      expect(found.message).to be_nil
      expect(found.json_path).to end_with(".requestBody.content['application/json'].schema")
    end

    it 'is not counted at all when the specification promised no body' do
      request = entry(fixtures_of(@file), 'requests', 'getPayoutStatus')
      expect(request['body']).to be_nil
      expect(request['source']).to eq('spec_example')
      expect(finding(@result, :request, 'getPayoutStatus')).to be_nil
    end
  end

  describe 'a body quoted from the specification that its own schema rejects' do
    it 'fails and names the field and the schema keyword that rejected it' do
      found = finding(@result, :response, 'createPayout 401')
      expect(found.kind).to eq(:failed)
      expect(found).to be_problem
      expect(found.message).to include('error.code', 'enum')
      expect(found.json_path).to include("responses['401']")
    end

    # Вердикт решает происхождение тела, а не его значение: то же тело с тем
    # же расхождением перестаёт быть спором спецификации с самой собой, как
    # только известно, что тело собрал генератор, а не процитировала спека.
    it 'turns into a synthesized finding once the body is ours and not quoted' do
      file = patched(@dir, @file) do |fixtures|
        entry(fixtures, 'responses', 'createPayout 401')['source'] = 'synthesized'
      end
      found = finding(check(@document, @profile, file), :response, 'createPayout 401')
      expect(found.kind).to eq(:synthesized)
      expect(found.message).to eq(finding(@result, :response, 'createPayout 401').message)
    end
  end

  describe 'a body the generator assembled itself' do
    it 'is allowed to miss the enum: the negative notification is negative on purpose' do
      found = finding(@result, :notification, 'webhook unknown_event')
      expect(entry(fixtures_of(@file), 'notifications', 'webhook unknown_event')['source'])
        .to eq('synthesized')
      expect(found.kind).to eq(:synthesized)
      expect(found.message).to include('event', 'enum')
    end

    it 'is allowed to miss a pattern as well' do
      file = patched(@dir, @file) do |fixtures|
        request = entry(fixtures, 'requests', 'createPayout')
        request['source'] = 'synthesized'
        request['body']['recipient']['phone'] = 'not a phone'
      end
      found = finding(check(@document, @profile, file), :request, 'createPayout')
      expect(found.kind).to eq(:synthesized)
      expect(found.message).to include('recipient.phone', 'pattern')
    end

    # Обратная сторона того же правила: стоит объявить это тело примером
    # спецификации — и то же расхождение становится находкой, которую надо
    # читать глазами.
    it 'would be a failure if the same body were offered as an example of the spec' do
      file = patched(@dir, @file) do |fixtures|
        entry(fixtures, 'notifications', 'webhook unknown_event')['source'] = 'spec_example'
      end
      found = finding(check(@document, @profile, file), :notification, 'webhook unknown_event')
      expect(found.kind).to eq(:failed)
    end
  end

  describe 'a body the specification promised but never described' do
    let(:bare) do
      <<~YAML
        openapi: 3.0.3
        info: { title: Bare API, version: "0.1" }
        paths:
          /transfers:
            post:
              operationId: createTransfer
              requestBody:
                content:
                  application/json:
                    schema:
                      type: object
                      properties:
                        amount: { type: integer }
              responses:
                "200": { description: ok }
      YAML
    end

    it 'is left unchecked instead of counted as passed or failed' do
      Dir.mktmpdir('specgen-checks-bare') do |dir|
        path = File.join(dir, 'bare.yaml')
        File.binwrite(path, bare)
        document, profile, file = generate(path, dir)
        found = finding(check(document, profile, file), :response, 'createTransfer 200')
        expect(found.kind).to eq(:unchecked)
        expect(found.message).to eq(SpecGen::Texts.t('validators.body_undeclared'))
        expect(found.json_path).to eq("$.paths['/transfers'].post.responses['200']")
      end
    end
  end

  describe 'a notification with no schema to check it against' do
    it 'is unchecked and points at the webhook instead of a schema that is not there' do
      webhook = @profile.webhooks.first
      document = without_body_schema(@document, webhook.path)
      found = finding(check(document, @profile, @file), :notification, 'webhook payout.completed')
      expect(found.kind).to eq(:unchecked)
      expect(found.message).to eq(SpecGen::Texts.t('validators.schema_undeclared'))
      expect(found.json_path).to eq(webhook.json_path)
    end

    # Уведомления сверяются схемой вебхука профиля. Нет вебхука — нет и
    # схемы, и стадия молчит: ноль проверок честнее выдуманной. Запрос рядом
    # проверяется как обычно — молчит именно уведомление.
    it 'is not judged at all when the specification declares no webhook' do
      Dir.mktmpdir('specgen-checks-31') do |dir|
        document, profile = analyze(spec_fixture('depositbank.yaml'))
        expect(profile.webhooks).to be_empty
        file = written(dir, 'requests' => [{ 'name' => 'createDeposit', 'source' => 'synthesized',
                                             'body' => { 'currency_code' => 'JPY' } }],
                            'notifications' => [{ 'name' => 'invented', 'source' => 'spec_example',
                                                  'body' => { 'event' => 'deposit.settled' } }])
        result = check(document, profile, file)
        expect(finding(result, :notification, 'invented')).to be_nil
        expect(result.findings.map(&:kind)).to eq([:synthesized])
      end
    end
  end

  describe 'an artifact that cannot be read as JSON' do
    it 'raises a ValidationError of our own hierarchy naming the file' do
      broken = File.join(@dir, 'broken.json')
      File.binwrite(broken, "{\n  \"requests\": [\n")
      expect { check(@document, @profile, broken) }.to raise_error(SpecGen::ValidationError) do |error|
        expect(error.file).to eq(broken)
        expect(error.to_s).to include(broken)
        expect(error.detail).to include('JSON')
      end
    end
  end

  # Профиль иногда собирают в обход загрузчика, а фикстуры может отключить
  # флаг: сверять тогда не с чем, и это не ошибка.
  describe 'the stage entry point without something to compare' do
    it 'returns an empty result when the profile came without a specification' do
      result = SpecGen::Validators.check(document: nil, profile: @profile, fixtures_file: @file)
      expect(result.total).to eq(0)
      expect(result.findings).to be_empty
      expect(result).not_to be_problems
    end

    it 'returns an empty result when no fixtures were written' do
      result = SpecGen::Validators.check(document: @document, profile: @profile, fixtures_file: nil)
      expect(result.total).to eq(0)
      expect(result).not_to be_problems
    end
  end
end
