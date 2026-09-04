# frozen_string_literal: true

module SpecGen
  module Reporter
    # Что анализаторы распознали в одной спецификации — одним экраном текста.
    #
    # Это живая демонстрация стадии анализа и зерно финального вывода CLI:
    # одна строка на факт, рядом с каждым выведенным значением — источник и
    # уверенность, а с `explain` — обоснование, на котором решение держится;
    # та же фраза, из которой потом собирается строка report.md. Здесь ничего
    # не читается из спецификации: единственный вход — профиль, поэтому экран
    # не может показать ничего, чего не увидят генераторы.
    class Summary
      INDENT = Format::INDENT

      # @param profile [IR::ProviderProfile] заполненный анализаторами
      # @param document [SpecLoader::Document] ради имени файла и версии
      # @param explain [Boolean] печатать обоснование под каждым значением
      def initialize(profile, document, explain: false)
        @profile = profile
        @document = document
        @explain = explain
      end

      # @return [String] вся сводка, переводы строк LF
      def render
        "#{sections.flatten.join("\n")}\n"
      end

      # @param io [IO] куда печатать
      # @return [void]
      def print_to(io)
        io.write(render)
      end

      private

      attr_reader :profile, :document, :explain

      def sections
        [header, identity, servers, auth, facts, '',
         OperationLines.new(profile, explain: explain).lines, '',
         SchemaLines.new(profile, explain: explain).lines, '',
         warnings]
      end

      # Выведенные факты: единицы, статусы, карта ошибок и остальное, что
      # анализаторы части 2 узнали о провайдере.
      def facts
        [DerivationLines.new(profile, explain: explain).lines,
         ErrorLines.new(profile, explain: explain).lines,
         ConditionLines.new(profile, explain: explain).lines]
      end

      def header
        Texts.t('summary.header', file: File.basename(document.file), version: document.version,
                                  counts: counts.join(', '))
      end

      def counts
        fields = profile.schemas.each_value.sum { |schema| schema.fields.size }
        [Texts.plural(profile.operations.size, 'operation'),
         Texts.plural(profile.schemas.size, 'schema'),
         Texts.plural(fields, 'field')]
      end

      def identity
        info = profile.info
        return [Texts.t('summary.provider_not_analysed')] if info.nil?

        lines = [Texts.t('summary.provider', value: Format.derived(info.name)),
                 *evidence(info.name)]
        lines << Texts.t('summary.base_url', env: info.base_url_env.value) if
          info.base_url_env&.known?
        lines
      end

      def servers
        return [Texts.t('summary.servers_none')] if profile.servers.empty?

        width = profile.servers.map { |server| environment(server).size }.max
        [Texts.t('summary.servers')] +
          profile.servers.flat_map { |server| server_lines(server, width) }
      end

      def server_lines(server, width)
        ["#{INDENT}#{environment(server).ljust(width)}  #{server.url}",
         *evidence(server.environment, depth: 2)]
      end

      def environment(server)
        key = server.environment.known? ? server.environment.value : :unknown
        Texts.t("environment.#{key}")
      end

      def auth
        auth = profile.auth
        return [Texts.t('summary.auth_not_analysed')] if auth.nil?
        return [Texts.t('summary.auth_none')] if auth.none?

        [auth_line(auth), *evidence(auth.type)]
      end

      def auth_line(auth)
        return Texts.t('summary.auth_unknown', scheme: auth.scheme_name) if auth.type.unknown?

        Texts.t('summary.auth', scheme: auth.scheme_name, type: auth.type.value,
                                where: where(auth), keys: credential_keys(auth))
      end

      def where(auth)
        location = auth.location && Texts.t("location.#{auth.location}")
        [location, auth.param_name].compact.join(' ')
      end

      def credential_keys(auth)
        auth.credential_keys&.value.to_a.join(', ')
      end

      def warnings
        grouped = profile.warnings_by_severity
        counts = IR::Warning::SEVERITIES.map do |severity|
          Texts.plural(grouped[severity].size, severity.to_s)
        end
        [Texts.t('summary.warnings', total: profile.warnings.size, counts: counts.join(', '))] +
          profile.sorted_warnings.flat_map { |warning| warning_lines(warning) }
      end

      def warning_lines(warning)
        lines = ["#{INDENT}#{severity_label(warning.severity)} #{warning.json_path}",
                 "#{INDENT * 5}#{warning.message}"]
        return lines unless explain && warning.fixable?

        lines + ["#{INDENT * 5}#{Texts.t('summary.overlay')}"] +
          warning.suggested_overlay.lines.map { |line| "#{INDENT * 6}#{line.chomp}" }
      end

      def severity_label(severity)
        Texts.t("severity.#{severity}").ljust(severity_width)
      end

      def severity_width
        @severity_width ||= IR::Warning::SEVERITIES.map { |s| Texts.t("severity.#{s}").size }.max
      end

      def evidence(derived, depth: 1)
        Format.evidence(derived, explain: explain, depth: depth)
      end
    end
  end
end
