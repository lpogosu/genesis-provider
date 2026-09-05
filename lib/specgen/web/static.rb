# frozen_string_literal: true

module SpecGen
  module Web
    # Отдаёт собранный фронт из public/, если этот каталог есть.
    #
    # Каталога может не быть: фронт собирается отдельно и в репозиторий не
    # попадает, а сервер обязан подниматься и без него — тогда работает
    # только API.
    #
    # Ненайденный адрес получает index.html только если он похож на переход
    # по приложению, то есть у него нет расширения файла. Запрос
    # несуществующего `/chunk.js` обязан получить 404, а не index.html:
    # браузер попытается разобрать HTML как скрипт и упадёт с ошибкой,
    # которая не назовёт настоящую причину. Один неверный путь в сборке
    # искался бы полдня.
    #
    # Выход за пределы каталога закрыт сравнением развёрнутых путей: запрос
    # вида `/../../etc/passwd` не должен читать ничего за public/.
    class Static
      INDEX = 'index.html'
      TYPES = {
        '.css' => 'text/css; charset=utf-8', '.html' => 'text/html; charset=utf-8',
        '.ico' => 'image/x-icon', '.js' => 'text/javascript; charset=utf-8',
        '.json' => 'application/json; charset=utf-8', '.map' => 'application/json; charset=utf-8',
        '.png' => 'image/png', '.svg' => 'image/svg+xml; charset=utf-8',
        '.txt' => 'text/plain; charset=utf-8', '.woff2' => 'font/woff2'
      }.freeze
      DEFAULT_TYPE = 'application/octet-stream'

      # @param dir [String] каталог со статикой
      def initialize(dir)
        @dir = dir
      end

      # @param request [Rack::Request]
      # @return [Array, nil] ответ Rack либо nil, если отдавать нечего
      def call(request)
        return nil unless request.get? || request.head?
        return nil unless File.directory?(@dir)

        file = resolve(request.path_info)
        return nil if file.nil?

        Responses.file(File.binread(file), TYPES.fetch(File.extname(file).downcase, DEFAULT_TYPE))
      end

      private

      # @return [String, nil] существующий файл внутри каталога
      def resolve(path)
        file = inside(path)
        # Путь ведёт наружу: это не переход по приложению, а попытка
        # прочитать чужой файл. Отдавать в ответ на неё index.html значит
        # отвечать 200 на то, что мы отвергли, — пусть будет 404.
        return nil if file.nil?
        return file if File.file?(file)
        return nil unless navigation?(path)

        index = File.join(@dir, INDEX)
        File.file?(index) ? index : nil
      end

      # @param path [String]
      # @return [Boolean] адрес читается как переход по приложению, а не как
      #   запрос файла: у файла есть расширение, у перехода — нет
      def navigation?(path)
        File.extname(path).empty?
      end

      # Сам корень — законный адрес (`/` разворачивается именно в него и
      # означает главную страницу), всё, что развернулось за его пределы, —
      # нет.
      def inside(path)
        root = File.expand_path(@dir)
        full = File.expand_path(File.join(root, path))
        full == root || full.start_with?("#{root}#{File::SEPARATOR}") ? full : nil
      end
    end
  end
end
