# frozen_string_literal: true

module SpecGen
  module Validators
    module Run
      # Что именно считать несовпадением. Каждый метод отвечает строкой о
      # расхождении либо nil, если всё сошлось; находку из этого делает
      # сценарий.
      #
      # Судья отделён от сценариев, потому что одно и то же расхождение
      # («ожидался отказ, получен успех») встречается в создании, опросе и
      # колбэке, а формулировка у него должна быть одна: читатель отчёта
      # сравнивает строки глазами.
      class Judge
        # Сколько знаков значения показывать в сообщении: тела чужих
        # спецификаций длиннее любого разумного отчёта.
        MAX_VALUE = 60
        # Параметр пути без группы захвата: со скобкой захвата String#split
        # вернул бы и сами имена параметров, а нам нужны только литералы.
        PATH_HOLE = /\{[^}]*\}/

        # @param client [FakeClient]
        # @param platform [Platform]
        # @param contract [Rules::ContractBook]
        # @param base_url [String] адрес, с которым собраны фикстуры
        def initialize(client:, platform:, contract:, base_url:)
          @client = client
          @platform = platform
          @contract = contract
          @base_url = base_url.to_s
        end

        # Единственный вызов клиента по нужному адресу и методу.
        # @param verb [Symbol, String] метод HTTP
        # @param template [String] шаблон пути операции со скобками
        # @param path [String] путь из фикстуры запроса, для сообщения
        # @return [String, nil]
        def request(verb:, template:, path:)
          calls = @client.calls
          return t('run_no_calls') if calls.empty?
          return t('run_many_calls', count: calls.size) if calls.size > 1

          addressed(calls.first, verb, template, path)
        end

        # @param name [String] имя заголовка
        # @param expected [Object] значение из фикстуры запроса
        # @return [String, nil]
        def header(name, expected)
          sent = @client.calls.first&.headers
          return t('run_no_calls') if sent.nil?

          found = sent.find { |key, _value| key.to_s.casecmp?(name.to_s) }
          return t('run_header_missing', header: name, sent: sent.keys.join(', ')) if found.nil?
          return nil if same?(expected, found.last)

          t('run_header_mismatch', header: name, expected: show(expected), actual: show(found.last))
        end

        # Тело запроса содержит всё, что обещает фикстура. Сравнение
        # подмножеством: сервис вправе отправить больше (служебные поля), но
        # не меньше.
        #
        # Отсутствующий ключ — расхождение только у обязательного поля.
        # Необязательное поле без роли в payload не идёт по правилу самого
        # генератора (docs/PRINCIPLES.md, «Что генерируем при неполной
        # спеке»), и объявлять здесь ошибкой то, что там объявлено решением,
        # значило бы спорить с собственной документацией.
        #
        # @param expected [Hash] тело фикстуры запроса
        # @param required [Array<String>] пути обязательных полей через точку
        # @return [String, nil]
        def body(expected, required: [])
          return t('run_no_calls') if @client.calls.empty?

          @required = required
          subset(expected, @client.calls.first&.payload, nil)
        end

        # @param outcome [Platform::Outcome, nil]
        # @return [String, nil]
        def success(outcome)
          return t('run_no_outcome') if outcome.nil?
          return nil if outcome.success?

          t('run_expected_success', code: show(outcome.code), key: show(outcome.key))
        end

        # @param outcome [Platform::Outcome, nil]
        # @param code [String, Symbol, nil] ожидаемый код платформы
        # @param key [String, nil] ожидаемый ключ локализации
        # @return [String, nil]
        def failure(outcome, code: nil, key: nil)
          return t('run_no_outcome') if outcome.nil?
          return t('run_expected_failure', code: symbol(code)) if outcome.success?
          return code_problem(outcome, code) if code && outcome.code.to_s != code.to_s
          return nil if key.nil? || outcome.key.to_s == key.to_s

          t('run_failure_key', expected: show(key), actual: show(outcome.key))
        end

        # Хелпер, который обязан был перевести операцию во внутренний статус.
        # in_progress не меняет операцию — значит, не должен звать никого.
        # @param internal [String, Symbol] внутренний статус
        # @return [String, nil]
        def helper(internal)
          expected = @contract.helper_for_status(internal.to_s.to_sym)
          called = @platform.status_calls
          return extra(called) if expected.nil?
          return nil if called == [expected]

          t('run_helper_wrong', expected: expected, actual: called.join(', '))
        end

        # @param outcome [Platform::Outcome, nil]
        # @param expected [Object] идентификатор из примера ответа
        # @return [String, nil]
        def result_id(outcome, expected)
          value = outcome&.result
          id = identifier(value)
          return t('run_result_missing', actual: show(value)) if id.nil?
          return nil if same?(expected, id)

          t('run_result_mismatch', expected: show(expected), actual: show(id))
        end

        private

        # Единственный вызов клиента: сначала адрес начинается с BASE_URL,
        # потом совпадают метод и форма пути.
        def addressed(call, verb, template, path)
          return t('run_base_url', expected: @base_url, actual: call.url) unless rooted?(call)
          return nil if call.verb.to_s == verb.to_s && tail(call).match?(pattern(template))

          t('run_call_mismatch', expected: "#{verb.to_s.upcase} #{path}", actual: actual(call))
        end

        # Идентификатор внутри результата: контракт заворачивает его сколь
        # угодно глубоко (`success(result: { id: … })`), а платформе важно
        # само значение. Разворачиваем, пока вложен один хеш.
        def identifier(value)
          return nil unless value.is_a?(Hash)

          found = value.values.first
          found.is_a?(Hash) ? identifier(found) : found
        end

        # Код отказа платформы печатается символом с обеих сторон: в фикстуре
        # он строка JSON, в коде — символ Ruby, и разное написание одного и
        # того же читалось бы как разница.
        def code_problem(outcome, code)
          t('run_failure_code', expected: symbol(code), actual: symbol(outcome.code))
        end

        def symbol(value)
          value.nil? ? show(nil) : show(value.to_s.to_sym)
        end

        def extra(called)
          called.empty? ? nil : t('run_helper_extra', called: called.join(', '))
        end

        def rooted?(call)
          @base_url.empty? || call.url.to_s.start_with?(@base_url)
        end

        def tail(call)
          call.url.to_s.delete_prefix(@base_url)
        end

        def actual(call)
          "#{call.verb.to_s.upcase} #{tail(call)}"
        end

        # Шаблон пути со скобками — это проверка формы адреса, а не значения
        # параметра: значение сервис берёт из операции, и оно уже проверено
        # тем, что операция собрана из той же фикстуры.
        def pattern(template)
          parts = template.to_s.split(PATH_HOLE, -1).map { |part| Regexp.escape(part) }
          Regexp.new("\\A#{parts.join('[^/]*')}(\\?.*)?\\z")
        end

        def subset(expected, sent, prefix)
          return t('run_body_not_hash', actual: show(sent)) unless sent.is_a?(Hash)

          expected.each do |key, value|
            at = [prefix, key].compact.join('.')
            problem = entry(sent, key, value, at)
            return problem if problem
          end
          nil
        end

        def entry(sent, key, value, at)
          pair = sent.find { |name, _item| name.to_s == key.to_s }
          return missing(at) if pair.nil?
          return subset(value, pair.last, at) if value.is_a?(Hash)
          return nil if same?(value, pair.last)

          t('run_body_mismatch', key: at, expected: show(value), actual: show(pair.last))
        end

        def missing(at)
          @required.to_a.include?(at) ? t('run_body_missing', key: at) : nil
        end

        # Целое и дробное с одним значением — одно и то же значение: сравнение
        # идёт рациональными, а не с плавающей точкой (Lint/FloatComparison).
        def same?(expected, actual)
          return true if expected == actual
          return Rational(expected) == Rational(actual) if numbers?(expected, actual)

          !expected.nil? && !actual.nil? && expected.to_s == actual.to_s
        end

        def numbers?(expected, actual)
          [expected, actual].all? { |value| value.is_a?(Integer) || value.is_a?(Float) } &&
            [expected, actual].none? { |value| value.is_a?(Float) && !value.finite? }
        end

        def show(value)
          text = value.inspect
          text.length > MAX_VALUE ? "#{text[0, MAX_VALUE]}…" : text
        end

        def t(key, **params)
          Texts.t("validators.#{key}", **params)
        end
      end
    end
  end
end
