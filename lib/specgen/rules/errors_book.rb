# frozen_string_literal: true

module SpecGen
  module Rules
    # Политика действий по ошибкам провайдера: HTTP-код или шаблон имени кода
    # → одно из IR::Roles::ERROR_ACTION.
    #
    # Действие — это данные, а не ветка в ErrorAnalyzer: точные коды, классы
    # кодов и шаблоны имён лежат в rules/errors.yml, анализатор только
    # спрашивает. Дедупликацию (:dedup) справочник не выдаёт намеренно: она
    # узнаётся по совпадению схем ответов, то есть структурно, и загрузчик
    # отказывает файлу, который пытается назначить её по коду.
    class ErrorsBook < Book
      FILE = 'errors.yml'
      # Всё, кроме dedup: её выводит анализатор по схеме, не справочник.
      ACTIONS = (IR::Roles::ERROR_ACTION - [:dedup]).freeze
      CLASS = /\A[1-5]xx\z/
      STATUS_RANGE = (100..599)
      FRACTION = (0.0..1.0)

      # Один шаблон имени кода.
      #
      #   name    для строки обоснования
      #   regexp  сравнивается с нормализованным кодом
      #   action  одно из ACTIONS
      Rule = Struct.new(:name, :regexp, :action, keyword_init: true)

      # @return [Symbol, nil] действие, когда не совпало ничего
      attr_reader :default_action
      # @return [Float, nil] уверенность действия по умолчанию
      attr_reader :default_confidence
      # @return [Float, nil] уверенность правила по шаблону имени
      attr_reader :pattern_confidence
      # @return [String, nil] имя заголовка с паузой до повтора
      attr_reader :retry_after_header
      # @return [Array<Rule>] шаблоны в порядке приоритета
      attr_reader :patterns

      # @param code [Integer] HTTP-код
      # @return [Array(Symbol, String), nil] действие и запись, которая
      #   совпала: "401" или "4xx"
      def action_for_status(code)
        exact = @codes[code]
        return [exact, code.to_s] if exact

        klass = "#{code / 100}xx"
        @classes[klass] && [@classes[klass], klass]
      end

      # @param code [String] код ошибки провайдера как написан
      # @return [Rule, nil] первый совпавший шаблон
      def rule_for_code(code)
        normalized = Normalizer.call(code)
        patterns.find { |rule| rule.regexp.match?(normalized) }
      end

      # @param header [String] имя заголовка ответа
      # @return [Boolean] это заголовок паузы до повтора
      def retry_after?(header)
        !@retry_after_header.nil? && Normalizer.call(header) == Normalizer.call(@retry_after_header)
      end

      private

      def build
        @default_action = symbol_in(data['default_action'], ACTIONS, noun(:error_action),
                                    path('default_action'))
        @default_confidence = fraction('default_confidence')
        @pattern_confidence = fraction('pattern_confidence')
        @retry_after_header = text(data['retry_after_header'], noun(:retry_after_header),
                                   path('retry_after_header'))
        load_http
        @patterns = load_patterns.freeze
      end

      def fraction(key)
        value = data[key]
        return value.to_f if value.is_a?(Numeric) && FRACTION.cover?(value)

        fault('errors.confidence', path(key), key: key, range: FRACTION, got: describe(value))
      end

      def load_http
        http = section('http')
        classes = mapping(http['classes'], noun(:http_classes), path('http', 'classes'))
        codes = mapping(http['codes'], noun(:http_codes), path('http', 'codes'), required: false)
        @classes = load_classes(classes)
        @codes = load_codes(codes)
      end

      def load_classes(listed)
        listed.filter_map do |key, action|
          at = path('http', 'classes', key.to_s)
          next fault('errors.bad_class', at, key: key.inspect) unless key.to_s.match?(CLASS)

          value = symbol_in(action, ACTIONS, noun(:error_action), at)
          [key.to_s, value] if value
        end.to_h.freeze
      end

      def load_codes(listed)
        listed.filter_map do |key, action|
          at = path('http', 'codes', key.to_s)
          code = Integer(key.to_s, exception: false)
          good = !code.nil? && STATUS_RANGE.cover?(code)
          next fault('errors.bad_status', at, key: key.inspect) unless good

          value = symbol_in(action, ACTIONS, noun(:error_action), at)
          [code, value] if value
        end.to_h.freeze
      end

      def load_patterns
        listed = data['codes']
        at = path('codes')
        unless listed.is_a?(Array) && !listed.empty?
          fault('checks.list', at, what: noun(:list, key: 'codes'), got: describe(listed))
          return []
        end

        listed.each_with_index.filter_map { |body, index| rule(body, "#{at}[#{index}]") }
      end

      def rule(body, at)
        fields = mapping(body, noun(:error_pattern), at)
        name = text(fields['name'], noun(:pattern_name), "#{at}.name")
        regexp = pattern(fields['pattern'], noun(:pattern), "#{at}.pattern")
        action = symbol_in(fields['action'], ACTIONS, noun(:error_action), "#{at}.action")
        return nil if name.nil? || regexp.nil? || action.nil?

        Rule.new(name: name, regexp: regexp, action: action).freeze
      end
    end
  end
end
