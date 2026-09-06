# frozen_string_literal: true

module SpecGen
  module Generators
    # Артефакт №5, только по флагу --fix: <provider>.overlay.yaml — заготовка
    # переопределений из templates/overlay.yaml.erb.
    #
    # Ровно тот файл, который раздел «Как собрать overlay» в report.md
    # предлагает собрать руками: тот же заголовок, тот же ключ `actions`, те
    # же фрагменты. Инструмент собирает его сам, но выбор между кандидатами
    # оставляет человеку — все слоты закомментированы (Skeleton::View).
    #
    # Проверка результата:
    #   ./integrate --spec <файл> --overlay output/<provider>.overlay.yaml
    class OverlayGenerator < Base
      TEMPLATE = 'overlay.yaml.erb'
      KIND = :overlay

      # Артефакт необязательный: без --fix его нет, и вывод прогона
      # побайтово прежний.
      # @param options [Hash] опции CLI, ключи строками или символами
      # @return [Boolean]
      def self.enabled?(options)
        !!(options[:fix] || options['fix'])
      end

      private

      def file_name
        naming.overlay_file_name
      end

      def view
        Skeleton::View.new(profile: profile, naming: naming)
      end
    end
  end
end
