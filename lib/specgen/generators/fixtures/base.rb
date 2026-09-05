# frozen_string_literal: true

module SpecGen
  module Generators
    module Fixtures
      # Общее для презентеров fixtures.json: контекст сервиса, презентеры
      # сервиса (из них берутся заголовки, подпись и таблицы — те же, что в
      # коде), заглушки секретов и три значения `source`.
      #
      # Правило источника: тело, взятое из `examples` спецификации дословно,
      # — spec_example; собранное из `example` / `enum` / `default` свойств
      # схемы — schema_example; содержащее хоть одну заглушку по типу —
      # synthesized. Придуманное значение никогда не выдаётся за пример.
      class Base
        # Заглушки секретов: в фикстурах не бывает настоящих значений.
        STUB_PREFIX = 'test_'
        # Откуда взято тело фикстуры.
        SPEC_EXAMPLE = 'spec_example'
        SCHEMA_EXAMPLE = 'schema_example'
        SYNTHESIZED = 'synthesized'
        CONTENT_TYPE = 'Content-Type'
        # Выражение справочника rules/auth.yml, читающее секрет платформы.
        CREDENTIAL = /provider\.credentials\[:(\w+)\]/
        # Интерполяция внутри строкового литерала справочника.
        INTERPOLATION = /\#\{([^}]*)\}/
        IDENTIFIER = /\A[a-z_][a-z0-9_]*\z/
        QUOTED = /\A"(.*)"\z/m

        # Тело фикстуры вместе с происхождением.
        #   value   само тело, nil для операций без тела
        #   source  SPEC_EXAMPLE | SCHEMA_EXAMPLE | SYNTHESIZED
        #   name    имя примера спецификации или nil
        #   notes   пояснения, которые склеятся в ключ "_todo"
        Body = Struct.new(:value, :source, :name, :notes, keyword_init: true)

        # @param ctx [Service::Context]
        # @param parts [Hash{Symbol => Object}] презентеры сервиса
        def initialize(ctx, parts)
          @ctx = ctx
          @parts = parts
        end

        # @return [Hash{String => String}] ключ credentials → заглушка;
        #   список ключей тот же, что печатает INTEGRATION.md
        def credentials
          @credentials ||= @parts[:view].credential_keys.sort
                                        .to_h { |key| [key, "#{STUB_PREFIX}#{key}"] }
        end

        private

        attr_reader :ctx, :parts

        # @param key [String] ключ под generators.fixtures
        # @return [String]
        def t(key, **params)
          Texts.t("generators.fixtures.#{key}", **params)
        end

        # @return [Values]
        def values
          @values ||= Values.new(ctx)
        end

        # @return [Signing]
        def signing
          @signing ||= Signing.new(parts[:signature], secret)
        end

        # @return [String] секрет-заглушка подписи уведомлений
        def secret
          credentials.fetch(parts[:signature].value(:secret_key).to_s, '')
        end

        # @return [Hash{String => String}] заголовки авторизации со
        #   заглушками вместо секретов
        def auth_headers
          @auth_headers ||= build_auth_headers
        end

        def build_auth_headers
          authorization = parts[:authorization]
          return {} unless authorization.recognised? && !authorization.query?

          param = ctx.profile.auth.param_name.to_s
          authorization.entry[:headers].to_h do |name, expression|
            [name.gsub(Rules::AuthBook::PARAM_NAME, param), header_value(expression)]
          end
        end

        # Значение заголовка авторизации из выражения справочника: секрет
        # заменяется заглушкой, простая интерполяция раскрывается. Выражение,
        # которое считает код (Basic, HMAC, OAuth2), в фикстуре раскрыть
        # нечем — тогда заглушка и строка в "_todo".
        # @return [String]
        def header_value(expression)
          text = expression.gsub(CREDENTIAL) { stub_for(Regexp.last_match(1)) }
          return text if text.match?(IDENTIFIER)

          inner = text[QUOTED, 1]
          return computed_stub if inner.nil?

          inner.gsub(INTERPOLATION) { resolved(Regexp.last_match(1)) }
        end

        # Подстановка уже раскрыта — берём её; выражение, которое считает
        # код, раскрыть нечем.
        def resolved(content)
          content.match?(IDENTIFIER) ? content : computed_stub
        end

        def computed_stub
          @auth_computed = true
          stub_for(parts[:authorization].credential_keys.first)
        end

        # @return [Boolean] значение заголовка авторизации собирает код
        #   сервиса, в фикстуре стоит заглушка
        def auth_computed?
          auth_headers
          @auth_computed == true
        end

        def stub_for(key)
          credentials.fetch(key.to_s, "#{STUB_PREFIX}#{key}")
        end

        # @param examples [Hash{String => Object}] примеры спецификации
        # @param schema_name [String, nil] имя схемы тела
        # @param note [String] что написать, если примера в спецификации нет
        # @return [Body]
        def body_from(examples, schema_name, note)
          return spec_body(*examples.first) unless examples.empty?
          return Body.new(value: nil, source: SPEC_EXAMPLE, notes: []) if schema_name.nil?

          built = values.body(schema_name)
          redact(Body.new(value: built.value, notes: [note],
                          source: built.synthesized ? SYNTHESIZED : SCHEMA_EXAMPLE))
        end

        def spec_body(name, value)
          redact(Body.new(value: Values.dup_value(value), source: SPEC_EXAMPLE, name: name,
                          notes: []))
        end

        # Значение, похожее на настоящий секрет провайдера, заменяется
        # заглушкой, и тело перестаёт быть примером из спецификации.
        def redact(body)
          value, changed = Values.redact(body.value, "#{STUB_PREFIX}api_key")
          return body unless changed

          Body.new(value: value, source: SYNTHESIZED, name: body.name,
                   notes: body.notes + [t('secret_redacted')])
        end

        # @param body [Body]
        # @return [Hash] хвост любой фикстуры: имя примера, происхождение и
        #   пояснения; ключи в фиксированном порядке
        def tail(body, notes = [])
          all = (body.notes + notes).uniq
          result = {}
          result['example_name'] = body.name if named?(body)
          result['source'] = body.source
          result['_todo'] = all.join(' ') unless all.empty?
          result
        end

        def named?(body)
          !body.name.nil? && body.name != IR::Response::DEFAULT_EXAMPLE
        end
      end
    end
  end
end
