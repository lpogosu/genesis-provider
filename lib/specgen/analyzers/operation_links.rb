# frozen_string_literal: true

module SpecGen
  module Analyzers
    # Link Object OpenAPI 3.x: единственное место, где спецификация может
    # сказать формально, какая операция читает то, что создала другая.
    #
    # Механизм штатный и почти никем не используемый (ни одна из десяти
    # спецификаций каталога его не объявляет), но он снимает догадку целиком:
    # ссылка `links: { status: { operationId: getPayout, parameters: {
    # payout_id: "$response.body#/id" } } }` в ответе создания говорит и то,
    # какая операция опрашивает статус, и то, какое поле ответа держит
    # идентификатор. Поэтому она — первый уровень доверия и побеждает любую
    # эвристику связывания.
    #
    # Ссылки на `#/components/links/...` сюда доезжают уже развёрнутыми:
    # `$ref` разрешает загрузчик. Цель адресуется двумя способами, оба
    # поддержаны: `operationId` и `operationRef` (JSON Pointer на
    # `$.paths[путь][метод]`, с экранированием ~1 и ~0).
    class OperationLinks
      # Одна прочитанная связь.
      #
      #   from        ключ операции-продюсера (Operation#key)
      #   to          ключ операции-консьюмера
      #   name        имя ссылки в отображении `links`
      #   parameters  {имя параметра => выражение вида "$response.body#/id"}
      #   status      код ответа, в котором объявлена ссылка
      #   json_path   место ссылки в спецификации
      Link = Struct.new(:from, :to, :name, :parameters, :status, :json_path, keyword_init: true)

      POINTER = %r{\A#/paths/(?<path>[^/]+)/(?<method>[a-z]+)\z}
      LINKS = 'links'

      # @param data [Hash] разрешённый документ
      def initialize(data)
        @data = data.is_a?(Hash) ? data : {}
        @problems = []
      end

      # Места, где ссылка объявлена, но прочитать её нельзя.
      # @return [Array<Array(String, String)>] сообщение и JSONPath
      attr_reader :problems

      # @return [Array<Link>] в порядке спецификации
      def call
        index
        links = []
        Operations.each(@data) do |path, http_method, node|
          from = IR::Operation.key_for(node['operationId'], http_method, path)
          each_declared(node, path, http_method) do |name, body, status, at|
            link = read(from, name, body, status, at)
            links << link if link
          end
        end
        links
      end

      private

      # @yieldparam name, body, status, at
      def each_declared(node, path, http_method)
        responses = node['responses']
        return unless responses.is_a?(Hash)

        responses.each do |status, body|
          listed = body.is_a?(Hash) ? body[LINKS] : nil
          next unless listed.is_a?(Hash)

          at = SpecLoader::JsonPath.build(['paths', path, http_method, 'responses', status.to_s,
                                           LINKS])
          listed.each { |name, link| yield(name.to_s, link, status.to_s, at) }
        end
      end

      def read(from, name, body, status, at)
        at = "#{at}#{SpecLoader::JsonPath.segment(name)}"
        return note(Texts.t('analyzers.link.shape', name: name), at) unless body.is_a?(Hash)

        to = target(body, at)
        return nil if to.nil?

        parameters = body['parameters']
        Link.new(from: from, to: to, name: name, status: status, json_path: at,
                 parameters: parameters.is_a?(Hash) ? parameters : {})
      end

      # @return [String, nil] ключ операции-цели
      def target(body, at)
        id = body['operationId']
        return by_id(id, at) if id.is_a?(String)

        ref = body['operationRef']
        return by_ref(ref, at) if ref.is_a?(String)

        note(Texts.t('analyzers.link.target_missing'), at)
      end

      def by_id(id, at)
        key = @by_id[id.strip]
        key || note(Texts.t('analyzers.link.unknown_operation', id: id.inspect), at)
      end

      # operationRef адресует операцию JSON Pointer'ом; внешний документ мы
      # не открываем, как и в остальных `$ref` без сети.
      def by_ref(ref, at)
        match = POINTER.match(ref)
        return note(Texts.t('analyzers.link.unknown_ref', ref: ref.inspect), at) if match.nil?

        path = match[:path].gsub('~1', '/').gsub('~0', '~')
        key = @by_endpoint[[path, match[:method]]]
        key || note(Texts.t('analyzers.link.unknown_ref', ref: ref.inspect), at)
      end

      def index
        @by_id = {}
        @by_endpoint = {}
        Operations.each(@data) do |path, http_method, node|
          key = IR::Operation.key_for(node['operationId'], http_method, path)
          id = node['operationId']
          @by_id[id.strip] = key if id.is_a?(String) && !id.strip.empty?
          @by_endpoint[[path, http_method]] = key
        end
      end

      def note(message, at)
        @problems << [message, at]
        nil
      end
    end
  end
end
