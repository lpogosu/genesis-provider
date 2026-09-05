# frozen_string_literal: true

module SpecGen
  module Generators
    # Общее для всех генераторов: загрузить templates/<TEMPLATE>, отрендерить
    # ERB в контексте объекта-представления и записать результат.
    #
    # Наследник объявляет TEMPLATE и KIND и реализует #file_name и #view.
    # Представление — единственное, что видит шаблон: это и есть граница
    # «шаблон читает IR, а не спецификацию». ERB работает с `trim_mode: '-'`,
    # поэтому строки `<%- -%>` не оставляют пустых строк в выводе.
    class Base
      TEMPLATE = nil
      KIND = nil

      # @param profile [IR::ProviderProfile]
      # @param rules [Rules::Registry]
      # @param options [Hash] опции CLI
      # @param naming [Naming] имена файла и класса
      # @param writer [Writer] куда писать
      # @param artifacts [Array<Artifact>] уже записанные артефакты этого
      #   прогона; их перечисляет report.md, остальным генераторам не нужны
      def initialize(profile:, rules:, options:, naming:, writer:, artifacts: [])
        @profile = profile
        @rules = rules
        @options = options
        @naming = naming
        @writer = writer
        @artifacts = artifacts
      end

      # Рендерит шаблон и пишет артефакт.
      # @return [Artifact]
      # @raise [GenerationError]
      def call
        content = render
        path = writer.write(file_name, content)
        Artifact.new(kind: self.class::KIND, file: file_name, path: path,
                     lines: content.count("\n"))
      end

      # @return [String] отрендеренный текст артефакта
      # @raise [GenerationError] шаблон не отрендерился; сообщение называет
      #   шаблон и место ошибки, стектрейс до пользователя не доходит
      def render
        erb = ERB.new(File.read(template_path, encoding: 'UTF-8'), trim_mode: '-')
        erb.filename = template_path
        erb.result(view.template_binding)
      rescue SpecGen::Error
        raise
      rescue StandardError, SyntaxError => e
        raise GenerationError.new(Texts.t('generators.template_failed', error: describe(e)),
                                  file: template_path)
      end

      private

      attr_reader :profile, :rules, :options, :naming, :writer, :artifacts

      # @return [String] имя файла артефакта внутри каталога вывода
      def file_name
        raise NotImplementedError
      end

      # @return [Object] объект-представление, отвечающий на #template_binding
      def view
        raise NotImplementedError
      end

      def template_path
        File.join(SpecGen::TEMPLATES_DIR, self.class::TEMPLATE)
      end

      def describe(error)
        place = error.backtrace&.first.to_s.sub("#{SpecGen::ROOT}/", '')
        "#{error.class}: #{error.message} (#{place})"
      end
    end
  end
end
