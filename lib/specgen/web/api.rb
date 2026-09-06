# frozen_string_literal: true

module SpecGen
  module Web
    # Пять действий API. Каждое возвращает структуру, а не HTTP-ответ:
    # заголовки, коды и конверт ошибки — дело App, здесь только данные.
    #
    # Справочники загружаются один раз на процесс: rules/ не меняются под
    # работающим сервером, а Rules.load валит прогон при первом же
    # противоречии в них — пусть это случится при первом запросе, а не при
    # каждом.
    class Api
      # @param specs_dir [String] каталог со спецификациями для демонстрации
      def initialize(specs_dir: Batch::DEFAULT_DIR)
        @specs_dir = specs_dir
      end

      # @return [Hash] жив ли сервер, версия генератора и язык сообщений
      def health
        { status: 'ok', version: SpecGen::VERSION, locale: Texts.locale }
      end

      # @return [Hash] спецификации каталога
      def specs
        catalog.to_h
      end

      # @param params [Params]
      # @return [Hash] provider, summary, warnings, artifacts
      def generate(params)
        pipeline(params).generate
      end

      # @param params [Params]
      # @return [Hash] provider, summary, warnings
      def analyze(params)
        pipeline(params).analyze
      end

      # Пакетный прогон по каталогу — та же таблица, что печатает
      # `./integrate --all`, включая строку с ошибкой вместо чисел.
      # @return [Hash]
      def batch
        Dir.mktmpdir('specgen-web') do |tmp|
          rows = Batch.new(dir: @specs_dir, rules: rules,
                           options: { output: File.join(tmp, Pipeline::OUTPUT_DIR) }).call
          { total: rows.size, generated: rows.count(&:ok?), rows: rows.map { |row| row_hash(row) } }
        end
      end

      private

      def pipeline(params)
        Pipeline.new(params: params, rules: rules, catalog: catalog)
      end

      def catalog
        Catalog.new(dir: @specs_dir, rules: rules)
      end

      def rules
        @rules ||= Rules.load
      end

      def row_hash(row)
        { file: row.file, provider: row.provider, operations: row.operations,
          operations_with_role: row.roles, coverage_percent: row.coverage,
          contract_coverage_percent: row.contract, warnings: row.warnings,
          artifacts: row.artifacts, error: row.error }
      end
    end
  end
end
