# frozen_string_literal: true

module SpecGen
  module Web
    # Минимальный HTTP-сервер на stdlib: принимает соединение, собирает
    # окружение Rack, зовёт приложение и печатает ответ.
    #
    # Почему свой, а не rackup. В Rack 3 команда `rackup` и WEBrick — это
    # отдельные гемы, которых нет ни в Gemfile проекта, ни в Ruby 3.4; новый
    # гем здесь добавлять нельзя. Своих ста строк на демонстрационный сервер
    # хватает: он нужен, чтобы поднять API одной командой в образе и на
    # чистой машине. config.ru при этом остаётся рабочим — под любым
    # сторонним Rack-сервером, если он появится.
    #
    # Соединение обслуживается в своём потоке и закрывается после ответа:
    # keep-alive не нужен, пакетный прогон занимает секунды, и висящее
    # соединение не должно блокировать соседний запрос.
    class Server
      DEFAULT_HOST = '0.0.0.0'
      DEFAULT_PORT = 9292
      # Строка ответа: код и причина. Всё, чего нет в таблице, печатается
      # без причины — она нужна человеку в логе, а не клиенту.
      REASONS = {
        200 => 'OK', 204 => 'No Content', 400 => 'Bad Request', 404 => 'Not Found',
        413 => 'Content Too Large', 422 => 'Unprocessable Content',
        500 => 'Internal Server Error'
      }.freeze

      Request = Struct.new(:verb, :target, :headers, :body)

      # @param app [#call] Rack-приложение
      # @param host [String]
      # @param port [Integer]
      # @param logger [IO] куда писать строку старта и неожиданные ошибки
      def initialize(app, host: DEFAULT_HOST, port: DEFAULT_PORT, logger: $stdout)
        @app = app
        @host = host
        @port = port
        @logger = logger
      end

      # Слушает порт, пока процесс не остановят.
      # @return [void]
      def start
        server = TCPServer.new(@host, @port)
        @logger.puts("specgen web: http://#{@host}:#{@port}")
        loop { accept(server) }
      rescue Interrupt
        @logger.puts('specgen web: остановлен')
      ensure
        server&.close
      end

      private

      def accept(server)
        socket = server.accept
        Thread.new { serve(socket) }
      end

      def serve(socket)
        request = read(socket)
        write(socket, *@app.call(env(request))) unless request.nil?
      rescue StandardError => e
        @logger.puts("specgen web: #{e.class}: #{e.message}")
      ensure
        close(socket)
      end

      # @return [Request, nil] nil, если клиент закрыл соединение молча
      def read(socket)
        line = socket.gets("\r\n")
        return nil if line.nil?

        verb, target, = line.strip.split
        headers = read_headers(socket)
        length = headers['content-length'].to_i
        Request.new(verb, target.to_s, headers, length.positive? ? socket.read(length) : '')
      end

      def read_headers(socket)
        headers = {}
        while (line = socket.gets("\r\n")) && line != "\r\n"
          name, value = line.strip.split(':', 2)
          headers[name.to_s.downcase] = value.to_s.strip
        end
        headers
      end

      def env(request)
        path, _, query = request.target.partition('?')
        base(request, path, query).merge(request.headers.to_h { |name, value| [cgi(name), value] })
                                  .compact
      end

      def base(request, path, query)
        { 'REQUEST_METHOD' => request.verb, 'SCRIPT_NAME' => '',
          'PATH_INFO' => Rack::Utils.unescape_path(path), 'QUERY_STRING' => query,
          'SERVER_NAME' => @host, 'SERVER_PORT' => @port.to_s, 'SERVER_PROTOCOL' => 'HTTP/1.1',
          'rack.url_scheme' => 'http', 'rack.input' => StringIO.new(request.body),
          'rack.errors' => @logger, 'CONTENT_TYPE' => request.headers['content-type'],
          'CONTENT_LENGTH' => request.headers['content-length'] }
      end

      def cgi(name)
        "HTTP_#{name.upcase.tr('-', '_')}"
      end

      def write(socket, status, headers, body)
        socket.write("HTTP/1.1 #{status} #{REASONS.fetch(status, '')}\r\n")
        headers.each do |name, value|
          Array(value).each { |item| socket.write("#{name}: #{item}\r\n") }
        end
        socket.write("connection: close\r\n\r\n")
        body.each { |chunk| socket.write(chunk) }
        body.close if body.respond_to?(:close)
      end

      def close(socket)
        socket.close
      rescue IOError, SystemCallError
        nil
      end
    end
  end
end
