# frozen_string_literal: true

require 'tmpdir'
require 'psych'

RSpec.describe SpecGen::SpecLoader do
  include Fixtures

  # Любой плохой ввод обязан падать с (1) классом из нашей иерархии,
  # (2) именем файла в сообщении и (3) местом проблемы. У файла, который не
  # удалось открыть вообще, места внутри нет: path равен nil.
  def expect_failure(file, klass, path:, message:)
    expect { described_class.load(file) }.to raise_error(klass) do |error|
      expect(error.file).to eq(file)
      path.nil? ? expect(error.path).to(be_nil) : expect(error.path).to(match(path))
      expect(error.message).to include(File.basename(file)).and match(message)
    end
  end

  def refs_in(node)
    case node
    when Hash then node.key?('$ref') ? [node['$ref']] : node.values.flat_map { |v| refs_in(v) }
    when Array then node.flat_map { |v| refs_in(v) }
    else []
    end
  end

  describe 'bad input' do
    it 'broken YAML → SpecLoadError with line and column' do
      expect_failure(bad_fixture('broken_yaml.yaml'), SpecGen::SpecLoadError,
                     path: /\Aстрока \d+, столбец \d+\z/, message: /ошибка синтаксиса YAML/)
    end

    it 'broken JSON → SpecLoadError naming the parser problem' do
      expect_failure(bad_fixture('broken.json'), SpecGen::SpecLoadError,
                     path: /\A(строка \d+, столбец \d+)?\z/, message: /ошибка синтаксиса JSON/)
    end

    it 'cyclic $ref → SpecParseError showing the cycle' do
      expect_failure(bad_fixture('cyclic_ref.yaml'), SpecGen::SpecParseError,
                     path: /\A\$\.components\.schemas\.B\['\$ref'\]\z/,
                     message: %r{циклический .\$ref.: #/components/schemas/A -> #/components/schemas/B -> #/components/schemas/A})
    end

    it 'dangling $ref → SpecParseError at the $ref that points nowhere' do
      expect_failure(bad_fixture('dangling_ref.yaml'), SpecGen::SpecParseError,
                     path: %r{\A\$\.paths\['/payouts'\]\.post\.requestBody\.content\['application/json'\]\.schema\['\$ref'\]\z},
                     message: %r{цель .\$ref. не найдена: #/components/schemas/Missing})
    end

    it 'empty file → SpecLoadError' do
      expect_failure(bad_fixture('empty.yaml'), SpecGen::SpecLoadError, path: /\A\$\z/, message: /файл пуст/)
    end

    it 'whitespace-only file → SpecLoadError' do
      expect_failure(bad_fixture('whitespace.yaml'), SpecGen::SpecLoadError, path: /\A\$\z/, message: /файл пуст/)
    end

    it 'comment-only file → SpecLoadError' do
      expect_failure(bad_fixture('comment_only.yaml'), SpecGen::SpecLoadError,
                     path: /\A\$\z/, message: /не содержит документа/)
    end

    it 'not an OpenAPI document → SpecLoadError listing what was found' do
      expect_failure(bad_fixture('not_openapi.yaml'), SpecGen::SpecLoadError,
                     path: /\A\$\z/, message: /это не документ OpenAPI.*ключи верхнего уровня: version, services/)
    end

    it 'array at the root → SpecLoadError' do
      expect_failure(bad_fixture('array_root.yaml'), SpecGen::SpecLoadError,
                     path: /\A\$\z/, message: /корень документа должен иметь тип object, а не array/)
    end

    it 'Swagger 2.0 → SpecLoadError with a conversion hint' do
      expect_failure(bad_fixture('swagger2.yaml'), SpecGen::SpecLoadError,
                     path: /\A\$\.swagger\z/, message: /Swagger 2\.0 не поддерживается.*swagger2openapi/)
    end

    it 'unsupported OpenAPI version → SpecLoadError' do
      expect_failure(bad_fixture('unsupported_version.yaml'), SpecGen::SpecLoadError,
                     path: /\A\$\.openapi\z/, message: /версия OpenAPI "4\.0\.0" не поддерживается/)
    end

    it 'missing paths → SpecParseError' do
      expect_failure(bad_fixture('no_paths.yaml'), SpecGen::SpecParseError,
                     path: /\A\$\.paths\z/, message: /нет секции .paths./)
    end

    it 'empty paths → SpecParseError' do
      expect_failure(bad_fixture('empty_paths.yaml'), SpecGen::SpecParseError,
                     path: /\A\$\.paths\z/, message: /секция .paths. пуста/)
    end

    it 'unknown schema type → SpecParseError at the type keyword of the definition' do
      expect_failure(bad_fixture('unknown_type.yaml'), SpecGen::SpecParseError,
                     path: /\A\$\.components\.schemas\.Payout\.properties\.amount\.type\z/,
                     message: /неизвестный тип схемы "money"/)
    end

    it 'remote $ref → SpecParseError, the generator never touches the network' do
      expect_failure(bad_fixture('remote_ref.yaml'), SpecGen::SpecParseError,
                     path: /schema\['\$ref'\]\z/, message: /по сети не поддерживается/)
    end

    it 'missing external file → SpecLoadError at the $ref in the main document' do
      expect_failure(bad_fixture('external_missing.yaml'), SpecGen::SpecLoadError,
                     path: /schema\['\$ref'\]\z/,
                     message: /не удалось загрузить файл nowhere\.yaml.*файл не найден/)
    end

    it 'broken external file → SpecLoadError with the external file and its line' do
      expect_failure(bad_fixture('external_broken/main.yaml'), SpecGen::SpecLoadError,
                     path: /schema\['\$ref'\]\z/,
                     message: /не удалось загрузить файл common\.yaml.*ошибка синтаксиса YAML.*строка \d+, столбец \d+/)
    end

    it 'missing file → SpecLoadError' do
      expect_failure(bad_fixture('does_not_exist.yaml'), SpecGen::SpecLoadError,
                     path: nil, message: /файл не найден/)
    end

    it 'directory instead of a file → SpecLoadError' do
      expect_failure(File.dirname(bad_fixture('empty.yaml')), SpecGen::SpecLoadError,
                     path: nil, message: /каталог/)
    end

    it 'says the same in English when the locale is switched' do
      SpecGen::Texts.locale = 'en'
      expect_failure(bad_fixture('no_paths.yaml'), SpecGen::SpecParseError,
                     path: /\A\$\.paths\z/, message: /at \$\.paths: .paths. is missing/)
    end
  end

  describe 'deeply nested $ref' do
    def chain_spec(dir, length)
      schemas = (0...length).to_h { |i| ["S#{i}", { '$ref' => "#/components/schemas/S#{i + 1}" }] }
      schemas["S#{length}"] = { 'type' => 'string', 'maxLength' => 3 }
      doc = {
        'openapi' => '3.0.3', 'info' => { 'title' => 'Chain', 'version' => '1' },
        'paths' => { '/x' => { 'get' => { 'responses' => { '200' => {
          'description' => 'ok',
          'content' => { 'application/json' => { 'schema' => { '$ref' => '#/components/schemas/S0' } } }
        } } } } },
        'components' => { 'schemas' => schemas }
      }
      File.join(dir, "chain#{length}.yaml").tap { |file| File.write(file, Psych.dump(doc)) }
    end

    it 'resolves a chain of 50 references' do
      Dir.mktmpdir do |dir|
        document = described_class.load(chain_spec(dir, 50))
        schema = document.paths['/x']['get']['responses']['200']['content']['application/json']['schema']
        expect(schema).to include('type' => 'string', 'maxLength' => 3)
        expect(refs_in(document.data)).to be_empty
      end
    end

    it 'stops a runaway chain of 300 references with a message instead of a stack overflow' do
      Dir.mktmpdir do |dir|
        expect_failure(chain_spec(dir, 300), SpecGen::SpecParseError,
                       path: /\A\$\.components\.schemas\.S\d+/, message: /вложенность глубже 256 уровней/)
      end
    end
  end

  describe 'good input' do
    let(:novapay) { described_class.load(spec_fixture('novapay.yaml')) }

    it 'detects the OpenAPI version and family' do
      expect([novapay.version, novapay.family, novapay.oas31?]).to eq(['3.0.3', :oas30, false])
      expect(novapay.external_files).to eq([])
    end

    it 'resolves every $ref and tags the expansions with the original pointer' do
      schema = novapay.paths['/payouts']['post']['requestBody']['content']['application/json']['schema']
      expect(schema['x-specgen-ref']).to eq('#/components/schemas/CreatePayoutRequest')
      expect(schema['required']).to eq(%w[amount currency external_id recipient])
      expect(schema.dig('properties', 'recipient', 'x-specgen-ref')).to eq('#/components/schemas/Recipient')
      expect(schema.dig('properties', 'recipient', 'properties', 'type', 'enum')).to eq(%w[sbp card])
      expect(refs_in(novapay.data)).to be_empty
    end

    it 'resolves shared responses and parameters from components' do
      post = novapay.paths['/payouts']['post']
      expect(post['parameters'][0]).to include('name' => 'Idempotency-Key', 'x-specgen-ref' => '#/components/parameters/IdempotencyKey')
      expect(post['responses']['400']).to include('description' => 'Некорректный запрос')
      expect(post['responses']['429'].dig('headers', 'Retry-After', 'schema', 'type')).to eq('integer')
    end

    it 'keeps the raw document intact for overlays' do
      raw_schema = novapay.raw.dig('paths', '/payouts', 'post', 'requestBody', 'content', 'application/json', 'schema')
      expect(raw_schema).to eq('$ref' => '#/components/schemas/CreatePayoutRequest')
      expect(refs_in(novapay.raw).size).to be > 10
    end

    it 'follows references into other files, relative to the referencing file' do
      document = described_class.load(good_fixture('external/main.yaml'))
      schema = document.paths['/payouts']['post']['requestBody']['content']['application/json']['schema']
      expect(schema['x-specgen-ref']).to eq('common.yaml#/components/schemas/Money')
      expect(schema.dig('properties', 'currency')).to include('type' => 'string', 'minLength' => 3)
      created = document.paths['/payouts']['post']['responses']['201']
      expect(created.dig('content', 'application/json', 'schema', 'properties', 'money', 'properties', 'amount', 'type')).to eq('integer')
      expect([document.family, document.external_files]).to eq([:oas31, ['common.yaml']])
    end

    it 'reads JSON as well as YAML' do
      document = described_class.load(good_fixture('minimal.json'))
      schema = document.paths['/payouts']['post']['requestBody']['content']['application/json']['schema']
      expect(schema).to include('type' => 'object', 'x-specgen-ref' => '#/components/schemas/Payout')
    end

    it 'turns unquoted YAML response codes into strings and accepts `openapi: 3.0`' do
      document = described_class.load(good_fixture('unquoted_codes.yaml'))
      expect(document.paths['/status']['get']['responses'].keys).to eq(%w[200 default])
      expect(document.version).to eq('3.0')
    end
  end
end
