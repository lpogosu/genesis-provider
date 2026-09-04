# frozen_string_literal: true

module SpecGen
  module Rules
    # Собирает всё, что не так со справочниками, и поднимает ошибку один раз,
    # чтобы прогон сообщил обо всех конфликтах, а не о первом. Справочники —
    # наши собственные данные: проблема здесь не пользовательский ввод, а
    # наша ошибка, которую надо починить до релиза, и загрузка обязана
    # остановиться, а не тихо оставить первый из двух синонимов.
    class Problems
      # Одна проблема в одном справочнике.
      Issue = Struct.new(:file, :path, :message) do
        # @return [String] "roles.yml в $.roles.amount.names[2]: сообщение"
        def to_s
          at = path && Texts.t('rules.problems.at', path: path)
          where = [file && File.basename(file), at].compact.join(' ')
          where.empty? ? message.to_s : "#{where}: #{message}"
        end
      end

      # @return [Array<Issue>] в порядке обнаружения
      attr_reader :issues

      def initialize
        @issues = []
      end

      # @param message [String] что не так, одной фразой
      # @param file [String, nil] справочник, в котором проблема
      # @param path [String, nil] JSONPath элемента, вызвавшего проблему
      # @return [void]
      def add(message, file: nil, path: nil)
        @issues << Issue.new(file, path, message)
        nil
      end

      # @return [Boolean]
      def any?
        !@issues.empty?
      end

      # @raise [RulesError] со списком всех проблем, если есть хотя бы одна
      # @return [void]
      def raise!
        return unless any?

        raise RulesError, [headline, *@issues.map { |issue| "  #{issue}" }].join("\n")
      end

      private

      def headline
        Texts.t('rules.problems.headline', count: issues.size)
      end
    end
  end
end
