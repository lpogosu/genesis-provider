# frozen_string_literal: true

module SpecGen
  module Analyzers
    # Одна объявленная схема авторизации, переведённая в IR::Auth.
    #
    # Перевод не несёт знания ни об одной конкретной схеме: объявление
    # уходит в rules/auth.yml через AuthBook, а то, что вернулось — тип,
    # место, ключи учётных данных, параметр, который несёт учётные данные, —
    # копируется в IR, а обоснованием служит имя записи справочника. Всё,
    # чего справочник не покрывает (незнакомая схема, поток OAuth2 без
    # tokenUrl, apiKey без имени), становится предупреждением, а не
    # выдуманным значением.
    class AuthScheme
      # @param kwargs [Hash] см. #initialize
      # @return [IR::Auth]
      def self.call(**)
        new(**).call
      end

      # @param name [String] ключ внутри components.securitySchemes
      # @param declaration [Hash] схема авторизации, как её написала спецификация
      # @param book [Rules::AuthBook] справочник, распознающий схемы
      # @param profile [IR::ProviderProfile] принимает предупреждения
      # @param asked_scopes [Array<String>] scopes, запрошенные операциями
      def initialize(name:, declaration:, book:, profile:, asked_scopes: [])
        @name = name
        @declaration = declaration
        @book = book
        @profile = profile
        @asked_scopes = asked_scopes
        @path = SpecLoader::JsonPath.build(['components', 'securitySchemes', name])
      end

      # @return [IR::Auth] с типом «не выведено», если в справочнике нет
      #   записи для этой схемы
      def call
        entry, flow = match
        return unknown if entry.nil?

        build(entry, flow)
      end

      private

      attr_reader :name, :declaration, :book, :profile, :path

      # Решать, какой поток OAuth2 поддержан, оставлено справочнику: каждый
      # объявленный поток предлагается ему в порядке спецификации, побеждает
      # первый, с которым совпала запись.
      # @return [Array(Hash, String), Array(nil, nil)] запись и имя потока
      def match
        flows = declaration['flows']
        return [book.scheme_for(declaration), nil] unless flows.is_a?(Hash)

        flows.each_key do |flow|
          entry = book.scheme_for(declaration, flow: flow)
          return [entry, flow] unless entry.nil?
        end
        [nil, nil]
      end

      # @return [IR::Auth]
      def build(entry, flow)
        param_name = book.param_name_for(entry, declaration)
        note_query_risk(entry)
        missing_param_name if param_name.nil? && book.spec_names_param?(entry)
        IR::Auth.new(scheme_name: name, type: type_of(entry), location: entry[:location],
                     param_name: param_name, credential_keys: credential_keys(entry),
                     token_url: token_url(entry, flow), scopes: scopes,
                     json_path: path)
      end

      # @return [IR::Derived] тип, названный вместе с записью справочника и
      #   теми фактами спецификации, которые её выбрали
      def type_of(entry)
        facts = entry[:match].map { |key, value| "#{key}=#{value}" }.join(', ')
        IR::Derived.registry(entry[:ir_type],
                             evidence: Texts.t('analyzers.auth.type_evidence',
                                               entry: entry_name(entry), facts: facts))
      end

      # @return [IR::Derived]
      def credential_keys(entry)
        keys = entry[:credential_keys]
        IR::Derived.registry(keys,
                             evidence: Texts.t('analyzers.auth.credentials_evidence',
                                               entry: entry_name(entry),
                                               keys: keys.join(', ')))
      end

      # @return [String, nil] эндпоинт токена, если запись его требует
      def token_url(entry, flow)
        return nil unless entry[:token_url_required]

        url = flow_body(flow)['tokenUrl']
        return url if url.is_a?(String) && !url.strip.empty?

        warn(:auth_unknown, Texts.t('analyzers.auth.token_url_missing', flow: flow),
             at: "#{path}.flows#{SpecLoader::JsonPath.segment(flow)}", severity: :error)
        nil
      end

      # Scopes, которые схема объявляет в своих потоках, плюс те, что
      # запросили операции; отсортированы, чтобы два прогона давали один и
      # тот же код.
      # @return [Array<String>]
      def scopes
        (declared_scopes | @asked_scopes).sort
      end

      # @return [Array<String>]
      def declared_scopes
        flows = declaration['flows']
        return [] unless flows.is_a?(Hash)

        flows.each_value.flat_map { |body| scopes_of(body) }
      end

      # @return [Array<String>]
      def scopes_of(body)
        scopes = body.is_a?(Hash) ? body['scopes'] : nil
        scopes.is_a?(Hash) ? scopes.keys.map(&:to_s) : []
      end

      # @return [Hash] объект потока, пустой, если в спецификации его нет
      def flow_body(flow)
        flows = declaration['flows']
        body = flows.is_a?(Hash) ? flows[flow] : nil
        body.is_a?(Hash) ? body : {}
      end

      # rules/auth.yml документирует риск учётных данных в query-строке;
      # отчёт его повторяет, потому что так выбрал провайдер.
      def note_query_risk(entry)
        return unless entry[:location] == :query

        warn(:auth_key_in_query, Texts.t('analyzers.auth.key_in_query'), severity: :info)
      end

      def missing_param_name
        warn(:auth_unknown, Texts.t('analyzers.auth.param_name_missing', name: name),
             severity: :error)
      end

      # @return [IR::Auth]
      def unknown
        overlay = Texts.t('analyzers.auth.unknown_overlay', path: path.inspect)
        warn(:auth_unknown, Texts.t('analyzers.auth.scheme_unknown_message', name: name),
             severity: :error, overlay: overlay)
        evidence = Texts.t('analyzers.auth.scheme_unknown_evidence', name: name)
        IR::Auth.new(scheme_name: name, json_path: path,
                     type: IR::Derived.unknown(evidence: evidence))
      end

      def entry_name(entry)
        book.name_of(entry).inspect
      end

      def warn(code, message, at: path, severity: :warning, overlay: nil)
        profile.warn(code, message, json_path: at, severity: severity, suggested_overlay: overlay)
      end
    end
  end
end
