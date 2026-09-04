# frozen_string_literal: true

require 'tmpdir'
require 'psych'

RSpec.describe SpecGen::SpecLoader do
  include Fixtures

  # Every bad input must fail with (1) a class from our hierarchy, (2) the
  # file name in the message and (3) the location of the problem. A file
  # that cannot be opened at all has no location inside it: path is nil.
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
                     path: /\Aline \d+, column \d+\z/, message: /YAML syntax error/)
    end

    it 'broken JSON → SpecLoadError naming the parser problem' do
      expect_failure(bad_fixture('broken.json'), SpecGen::SpecLoadError,
                     path: /\A(line \d+, column \d+)?\z/, message: /JSON syntax error/)
    end

    it 'cyclic $ref → SpecParseError showing the cycle' do
      expect_failure(bad_fixture('cyclic_ref.yaml'), SpecGen::SpecParseError,
                     path: /\A\$\.components\.schemas\.B\['\$ref'\]\z/,
                     message: %r{cyclic \$ref: #/components/schemas/A -> #/components/schemas/B -> #/components/schemas/A})
    end

    it 'dangling $ref → SpecParseError at the $ref that points nowhere' do
      expect_failure(bad_fixture('dangling_ref.yaml'), SpecGen::SpecParseError,
                     path: %r{\A\$\.paths\['/payouts'\]\.post\.requestBody\.content\['application/json'\]\.schema\['\$ref'\]\z},
                     message: %r{\$ref target not found: #/components/schemas/Missing})
    end

    it 'empty file → SpecLoadError' do
      expect_failure(bad_fixture('empty.yaml'), SpecGen::SpecLoadError, path: /\A\$\z/, message: /file is empty/)
    end

    it 'whitespace-only file → SpecLoadError' do
      expect_failure(bad_fixture('whitespace.yaml'), SpecGen::SpecLoadError, path: /\A\$\z/, message: /file is empty/)
    end

    it 'comment-only file → SpecLoadError' do
      expect_failure(bad_fixture('comment_only.yaml'), SpecGen::SpecLoadError,
                     path: /\A\$\z/, message: /contains no document/)
    end

    it 'not an OpenAPI document → SpecLoadError listing what was found' do
      expect_failure(bad_fixture('not_openapi.yaml'), SpecGen::SpecLoadError,
                     path: /\A\$\z/, message: /not an OpenAPI document.*top-level keys: version, services/)
    end

    it 'array at the root → SpecLoadError' do
      expect_failure(bad_fixture('array_root.yaml'), SpecGen::SpecLoadError,
                     path: /\A\$\z/, message: /root must be an object, got array/)
    end

    it 'Swagger 2.0 → SpecLoadError with a conversion hint' do
      expect_failure(bad_fixture('swagger2.yaml'), SpecGen::SpecLoadError,
                     path: /\A\$\.swagger\z/, message: /Swagger 2\.0 is not supported.*swagger2openapi/)
    end

    it 'unsupported OpenAPI version → SpecLoadError' do
      expect_failure(bad_fixture('unsupported_version.yaml'), SpecGen::SpecLoadError,
                     path: /\A\$\.openapi\z/, message: /unsupported OpenAPI version "4\.0\.0"/)
    end

    it 'missing paths → SpecParseError' do
      expect_failure(bad_fixture('no_paths.yaml'), SpecGen::SpecParseError,
                     path: /\A\$\.paths\z/, message: /`paths` is missing/)
    end

    it 'empty paths → SpecParseError' do
      expect_failure(bad_fixture('empty_paths.yaml'), SpecGen::SpecParseError,
                     path: /\A\$\.paths\z/, message: /`paths` is empty/)
    end

    it 'unknown schema type → SpecParseError at the type keyword of the definition' do
      expect_failure(bad_fixture('unknown_type.yaml'), SpecGen::SpecParseError,
                     path: /\A\$\.components\.schemas\.Payout\.properties\.amount\.type\z/,
                     message: /unknown schema type "money"/)
    end

    it 'remote $ref → SpecParseError, the generator never touches the network' do
      expect_failure(bad_fixture('remote_ref.yaml'), SpecGen::SpecParseError,
                     path: /schema\['\$ref'\]\z/, message: /remote \$ref is not supported/)
    end

    it 'missing external file → SpecLoadError at the $ref in the main document' do
      expect_failure(bad_fixture('external_missing.yaml'), SpecGen::SpecLoadError,
                     path: /schema\['\$ref'\]\z/,
                     message: /referenced file nowhere\.yaml could not be loaded: file not found/)
    end

    it 'broken external file → SpecLoadError with the external file and its line' do
      expect_failure(bad_fixture('external_broken/main.yaml'), SpecGen::SpecLoadError,
                     path: /schema\['\$ref'\]\z/,
                     message: /referenced file common\.yaml could not be loaded: YAML syntax error.*line \d+, column \d+/)
    end

    it 'missing file → SpecLoadError' do
      expect_failure(bad_fixture('does_not_exist.yaml'), SpecGen::SpecLoadError,
                     path: nil, message: /file not found/)
    end

    it 'directory instead of a file → SpecLoadError' do
      expect_failure(File.dirname(bad_fixture('empty.yaml')), SpecGen::SpecLoadError,
                     path: nil, message: /directory/)
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
                       path: /\A\$\.components\.schemas\.S\d+/, message: /nesting deeper than 256 levels/)
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
