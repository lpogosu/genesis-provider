# frozen_string_literal: true

module SpecGen
  module Analyzers
    # Заполняет IR::Info и IR::Server: кто провайдер, каким диалектом
    # OpenAPI он описан и какой из его хостов — песочница.
    #
    # Формально спецификация не сообщает ничего из этого. `info.title` — это
    # маркетинговая проза, `servers[].description` — свободная подпись,
    # поэтому каждое значение либо взято из командной строки (задано явно),
    # либо прочитано из слов (эвристика, несущая обоснование, которое
    # печатает report.md).
    #
    # Имя провайдера — единственное, что нельзя выдумывать молча: оно
    # определяет имя класса, имя файла и переменную окружения, из которой
    # берётся базовый URL. Если ни --provider, ни заголовок ничего не дали,
    # профиль получает «не выведено» и блокирующее предупреждение, а не
    # правдоподобную догадку.
    class InfoAnalyzer < Base
      # Слова, которые описывают API, а не называют провайдера. Словарь
      # индустрии, а не имена провайдеров: здесь нет ничего, принадлежащего
      # одной компании, и заголовок из одних таких слов не даёт имени.
      COMMON_WORDS = %w[
        api apis rest restful http https openapi swagger spec specification
        service services integration integrations gateway platform
        payment payments payout payouts payin payins deposit deposits refund refunds
        open public partner merchant provider
        sandbox staging production docs documentation reference mock demo test version
      ].freeze

      # "v1", "v2.1": метка версии в заголовке, никогда не имя.
      VERSION_WORD = /\Av\d+(\.\d+)*\z/
      # Граница слова для slug. Только ASCII: slug становится константой
      # Ruby и именем файла.
      NON_SLUG = /[^a-z0-9]+/
      # Всё, чего не может содержать имя переменной окружения POSIX.
      NON_ENV = /[^A-Z0-9]/
      ENV_SUFFIX = '_BASE_URL'

      # Одно слово, оставшееся после отбрасывания общего словаря, читается
      # как имя бренда; несколько слов означают, что заголовок сказал
      # больше, чем имя.
      SINGLE_WORD_CONFIDENCE = 0.8
      MULTI_WORD_CONFIDENCE = 0.6

      # Заполняет `profile.info` и `profile.servers`.
      # @return [IR::ProviderProfile] тот профиль, который был передан
      def call
        profile.info = build_info
        profile.servers.concat(build_servers)
        profile
      end

      private

      # @return [IR::Info]
      def build_info
        name = provider_name
        IR::Info.new(name: name, title: info_text('title'), spec_version: info_text('version'),
                     oas_version: document.version, oas_family: document.family,
                     base_url_env: base_url_env(name), spec_file: spec_file)
      end

      # --provider важнее прозы: человека, назвавшего провайдера, заголовок
      # никогда не переспрашивает.
      # @return [IR::Derived]
      def provider_name
        name_from_option || name_from_title || unknown_name
      end

      # @return [IR::Derived, nil]
      def name_from_option
        given = option(:provider)
        slug = slugify(given)
        return nil if slug.empty?

        IR::Derived.structural(slug, evidence: Texts.t('analyzers.info.name_from_option',
                                                       given: given))
      end

      # @return [IR::Derived, nil]
      def name_from_title
        title = info_text('title')
        words = title.nil? ? [] : meaningful_words(title)
        return nil if words.empty?

        slug = words.join('_')
        evidence = Texts.t('analyzers.info.name_from_title', title: title.inspect, slug: slug)
        IR::Derived.heuristic(slug, confidence: title_confidence(words), evidence: evidence)
      end

      # @return [IR::Derived]
      def unknown_name
        profile.warn(:provider_name_unknown, Texts.t('analyzers.info.name_unknown_message'),
                     json_path: json_path('info', 'title'), severity: :error)
        IR::Derived.unknown(evidence: Texts.t('analyzers.info.name_unknown_evidence'))
      end

      # Сгенерированный сервис читает базовый URL из переменной окружения, а
      # не из литерала, поэтому профиль несёт имя переменной. Оно ровно
      # настолько же достоверно, как имя провайдера, из которого построено, и
      # не более.
      # @param name [IR::Derived] имя провайдера
      # @return [IR::Derived]
      def base_url_env(name)
        return IR::Derived.unknown(evidence: Texts.t('analyzers.info.base_url_env_unknown')) if
          name.unknown?

        variable = name.value.upcase.gsub(NON_ENV, '_') + ENV_SUFFIX
        evidence = Texts.t('analyzers.info.base_url_env_evidence',
                           suffix: ENV_SUFFIX, name: name.value.inspect)
        IR::Derived.new(value: variable, source: name.source, confidence: name.confidence,
                        evidence: evidence)
      end

      # @return [Array<IR::Server>] по одному на пригодный элемент, в порядке
      #   спецификации
      def build_servers
        entries = data['servers']
        return no_servers(entries) unless entries.is_a?(Array) && !entries.empty?

        entries.each_with_index.filter_map { |entry, index| build_server(entry, index) }
      end

      # @return [Array] пустой, чтобы у вызывающего была одна ветка кода
      def no_servers(entries)
        key = entries.nil? ? 'servers_absent' : 'servers_malformed'
        profile.warn(:spec_element_unsupported, Texts.t("analyzers.info.#{key}"),
                     json_path: json_path('servers'),
                     suggested_overlay: Texts.t('analyzers.info.servers_overlay'))
        []
      end

      # @return [IR::Server, nil] nil для элемента без пригодного url
      def build_server(entry, index)
        path = json_path('servers', index)
        url = entry.is_a?(Hash) ? entry['url'] : nil
        return skipped_server(path) unless url.is_a?(String) && !url.strip.empty?

        description = scalar(entry['description'])
        IR::Server.new(url: url, environment: environment(url, description, path),
                       description: description, json_path: path)
      end

      # @return [nil]
      def skipped_server(path)
        profile.warn(:spec_element_unsupported, Texts.t('analyzers.info.server_url_missing'),
                     json_path: path)
        nil
      end

      # @return [IR::Derived] окружение или «не выведено» с предупреждением
      def environment(url, description, path)
        EnvironmentDetector.call(url: url, description: description) ||
          unknown_environment(path)
      end

      # @return [IR::Derived] «не выведено», предупреждение уже записано
      def unknown_environment(path)
        profile.warn(:server_environment_unknown,
                     Texts.t('analyzers.info.environment_unknown_message'),
                     json_path: path, severity: :info,
                     suggested_overlay: Texts.t('analyzers.info.environment_overlay',
                                                path: path))
        IR::Derived.unknown(evidence: Texts.t('analyzers.info.environment_unknown_evidence'))
      end

      # Сводит имя к идентификатору, по которому названы сгенерированный
      # класс и файл. В отличие от Rules::Normalizer, camelCase намеренно
      # *не* разбивается: бренд, написанный одним словом, одним словом и
      # остаётся, поэтому заголовок «AcmePay» даёт "acmepay", а не
      # "acme_pay".
      # @return [String] пустая строка, если ничего пригодного не осталось
      def slugify(text)
        words_of(text).join('_')
      end

      # @return [Array<String>] слова заголовка, которые могли бы назвать
      #   провайдера
      def meaningful_words(title)
        words_of(title).reject do |word|
          COMMON_WORDS.include?(word) || word.match?(VERSION_WORD)
        end
      end

      # @return [Float]
      def title_confidence(words)
        words.one? ? SINGLE_WORD_CONFIDENCE : MULTI_WORD_CONFIDENCE
      end

      # @return [Array<String>] ASCII-слова в нижнем регистре
      def words_of(text)
        text.to_s.downcase.split(NON_SLUG).reject(&:empty?)
      end

      # @return [String, nil] basename — та форма, которую показывают отчёты
      def spec_file
        file = document.file
        file.nil? ? nil : File.basename(file.to_s)
      end

      # @return [String, nil] значение ключа из `info`, nil если его нет или
      #   он не скаляр
      def info_text(key)
        section = data['info']
        scalar(section.is_a?(Hash) ? section[key] : nil)
      end

      # @return [String, nil] скаляры как есть, структуры игнорируются
      def scalar(value)
        return nil unless value.is_a?(String) || value.is_a?(Numeric) || value.is_a?(Symbol)

        text = value.to_s.strip
        text.empty? ? nil : text
      end
    end
  end
end
