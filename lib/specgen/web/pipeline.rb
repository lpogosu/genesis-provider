# frozen_string_literal: true

module SpecGen
  module Web
    # Прогон конвейера по одному запросу: загрузка, анализ и — для
    # /api/generate — генерация артефактов.
    #
    # Всё происходит во временном каталоге и синхронно. Во временном —
    # потому что веб-интерфейс не единственный пользователь машины: писать в
    # output/ он не имеет права, там лежит результат работы человека за
    # терминалом. Синхронно — потому что одна спецификация укладывается в
    # секунды, а очередь с потоками стоила бы дороже, чем экономит.
    #
    # Артефакты читаются обратно с диска, а не рендерятся в память: так по
    # сети уходят ровно те байты, которые записал бы CLI, вместе с
    # нормализацией переводов строк из Generators::Writer.
    class Pipeline
      # Язык подсветки для фронта; ключи — виды артефактов из Runner::ORDER.
      LANGUAGES = { service: 'ruby', integration: 'markdown', fixtures: 'json',
                    report: 'markdown' }.freeze
      DEFAULT_LANGUAGE = 'text'
      OVERLAY_FILE = 'overlay.yaml'
      OUTPUT_DIR = 'output'

      # @param params [Params] разобранное тело запроса
      # @param rules [Rules::Registry] уже загруженные справочники
      # @param catalog [Catalog] каталог спецификаций для spec_id
      def initialize(params:, rules:, catalog:)
        @params = params
        @rules = rules
        @catalog = catalog
      end

      # @return [Hash] provider, summary, warnings
      # @raise [SpecGen::Error]
      def analyze
        run(with_artifacts: false)
      end

      # @return [Hash] то же плюс artifacts в порядке Runner::ORDER
      # @raise [SpecGen::Error]
      def generate
        run(with_artifacts: true)
      end

      private

      attr_reader :params, :rules, :catalog

      def run(with_artifacts:)
        Dir.mktmpdir('specgen-web') do |tmp|
          options = options_for(tmp)
          document = SpecLoader.load(options[:spec], overlay: options[:overlay])
          profile = Analyzers::Runner.call(document: document, rules: rules, options: options)
          result = body(profile, document)
          next result unless with_artifacts

          result.merge(artifacts: artifacts(profile, document, options))
        end
      rescue SpecGen::Error => e
        raise renamed(e)
      end

      # Загруженная спецификация лежит во временном каталоге, но клиент
      # прислал её под своим именем: в сообщении об ошибке он должен увидеть
      # `acme.yaml`, а не путь во временном каталоге сервера.
      def renamed(error)
        return error unless params.upload?

        error.class.new(error.detail, file: params.filename, path: error.path)
      end

      def body(profile, document)
        naming = Generators::Naming.for(profile)
        { provider: naming.slug,
          summary: Summary.new(profile: profile, rules: rules, document: document,
                               naming: naming).to_h,
          warnings: warnings(profile) }
      end

      def artifacts(profile, document, options)
        Generators.call(profile: profile, rules: rules, document: document,
                        options: options).map do |artifact|
          content = File.binread(artifact.path).force_encoding(Encoding::UTF_8)
          { kind: artifact.kind, filename: artifact.file,
            language: LANGUAGES.fetch(artifact.kind, DEFAULT_LANGUAGE),
            lines: artifact.lines, bytes: content.bytesize, content: content }
        end
      end

      def warnings(profile)
        profile.sorted_warnings.map do |warning|
          { code: warning.code, severity: warning.severity, message: warning.message,
            json_path: warning.json_path, suggested_overlay: warning.suggested_overlay }
        end
      end

      # Имя провайдера по умолчанию — имя файла, как в пакетном прогоне:
      # заголовки чужих спецификаций бывают безымянными, а slug обязан
      # читаться как провайдер и в таблице, и в имени класса.
      def options_for(tmp)
        spec = spec_path(tmp)
        { spec: spec, provider: params.provider || File.basename(spec, File.extname(spec)),
          output: File.join(tmp, OUTPUT_DIR), overlay: overlay_path(tmp) }.compact
      end

      def spec_path(tmp)
        return catalog.path(params.spec_id) unless params.upload?

        write(File.join(tmp, params.filename), params.content)
      end

      def overlay_path(tmp)
        return nil if params.overlay.nil?

        write(File.join(tmp, OVERLAY_FILE), params.overlay)
      end

      def write(path, content)
        File.binwrite(path, content)
        path
      end
    end
  end
end
