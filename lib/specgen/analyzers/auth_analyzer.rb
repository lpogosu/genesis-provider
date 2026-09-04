# frozen_string_literal: true

module SpecGen
  module Analyzers
    # Заполняет IR::Auth: как сгенерированный сервис авторизует свои
    # запросы.
    #
    # Этот класс выбирает, *какую* схему использовать, а перевод её
    # оставляет AuthScheme, который спрашивает rules/auth.yml. Ни один из
    # них не знает схему по имени: провайдер, авторизующийся способом,
    # которого мы ещё не встречали, — это новая запись в справочнике, а не
    # ветка здесь.
    #
    # Спецификация может объявить несколько схем, а использовать одну.
    # Выбор посчитан, а не угадан: сколько операций требует каждую схему,
    # ничья разрешается порядком объявления, а `security: []` (входящий
    # вебхук) не голосует ни за что. Проигравшие схемы попадают в отчёт
    # вместе со своими JSONPath.
    #
    # Почему профиль всегда получает Auth, даже если спецификация не
    # объявляет ни одной схемы: `auth: nil` невозможно отличить от
    # «анализатор не запускался», тогда как `type: Derived.structural(:none)`
    # говорит, что спецификация прочитана и она действительно не просит
    # учётных данных. Всё остальное — нераспознанная схема, схема,
    # требуемая, но нигде не объявленная — это `Derived.unknown` плюс
    # блокирующее предупреждение, чтобы пробел не мог дойти до генератора
    # под видом открытого API.
    class AuthAnalyzer < Base
      # Заполняет `profile.auth`.
      # @return [IR::ProviderProfile] тот профиль, который был передан
      def call
        profile.auth = build_auth
        profile
      end

      private

      # @return [IR::Auth]
      def build_auth
        report_bad_security
        declared = declared_schemes
        report_undeclared(declared)
        chosen = requirements.winner(declared.keys)
        return no_declaration if chosen.nil?

        report_alternatives(declared, chosen)
        AuthScheme.call(name: chosen, declaration: declared[chosen], book: rules.auth,
                        profile: profile, asked_scopes: requirements.scopes_for(chosen))
      end

      # @return [SecurityRequirements]
      def requirements
        @requirements ||= SecurityRequirements.new(
          root: data['security'], root_path: json_path('security'),
          operations: operation_security
        )
      end

      # @return [Array<Array(Object, String)>] `security` каждой операции
      def operation_security
        each_operation.map do |path, http_method, operation|
          [operation['security'], json_path('paths', path, http_method, 'security')]
        end
      end

      def report_bad_security
        requirements.bad_paths.each do |path|
          warn_shape(path, Texts.t('analyzers.auth.security_shape'))
        end
      end

      # @return [Hash{String => Hash}] пригодные объявления, в порядке
      #   спецификации
      def declared_schemes
        components = data['components']
        schemes = components.is_a?(Hash) ? components['securitySchemes'] : nil
        return {} if schemes.nil?
        return warn_shape(schemes_path, shape_message('securitySchemes')) || {} unless
          schemes.is_a?(Hash)

        schemes.select { |name, declaration| usable?(name, declaration) }
      end

      # @return [Boolean]
      def usable?(name, declaration)
        return true if declaration.is_a?(Hash)

        warn_shape(scheme_path(name), Texts.t('analyzers.auth.scheme_shape', name: name))
        false
      end

      # Схема, которую операция требует, а `components` нигде не определяет.
      # Если больше ничего не объявлено, это блокирует генерацию; рядом с
      # схемой, которую мы всё же распознали, это противоречие, о котором
      # стоит сообщить.
      def report_undeclared(declared)
        missing = requirements.names - declared.keys
        return if missing.empty?

        profile.warn(:auth_unknown,
                     Texts.t('analyzers.auth.undeclared_message', names: missing.join(', ')),
                     json_path: schemes_path, severity: declared.empty? ? :error : :warning)
      end

      def report_alternatives(declared, chosen)
        rejected = declared.keys - [chosen]
        return if rejected.empty?

        listed = rejected.map { |name| "#{name} (#{scheme_path(name)})" }.join(', ')
        operations = Texts.plural(requirements.counts[chosen], 'operation')
        profile.warn(:auth_multiple_schemes,
                     Texts.t('analyzers.auth.multiple_schemes', total: declared.size,
                                                                chosen: chosen,
                                                                operations: operations,
                                                                ignored: listed),
                     json_path: schemes_path)
      end

      # Ничего пригодного не объявлено: либо спецификация действительно не
      # просит учётных данных, либо она требует схему, которую нигде не
      # определяет.
      # @return [IR::Auth]
      def no_declaration
        required = requirements.winner(requirements.names)
        return undeclared_auth(required) unless required.nil?

        profile.warn(:auth_absent, Texts.t('analyzers.auth.absent_message'),
                     json_path: schemes_path, severity: :info)
        IR::Auth.new(type: IR::Derived.structural(
          :none, evidence: Texts.t('analyzers.auth.absent_evidence')
        ))
      end

      # @return [IR::Auth]
      def undeclared_auth(name)
        evidence = Texts.t('analyzers.auth.undeclared_evidence', name: name)
        IR::Auth.new(scheme_name: name, json_path: scheme_path(name),
                     type: IR::Derived.unknown(evidence: evidence))
      end

      def schemes_path
        json_path('components', 'securitySchemes')
      end

      def scheme_path(name)
        json_path('components', 'securitySchemes', name)
      end

      def shape_message(key)
        Texts.t('analyzers.common.must_be_object', key: key)
      end

      def warn_shape(path, message)
        profile.warn(:spec_element_unsupported, message, json_path: path)
        nil
      end
    end
  end
end
