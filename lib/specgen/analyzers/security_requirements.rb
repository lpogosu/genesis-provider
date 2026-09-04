# frozen_string_literal: true

module SpecGen
  module Analyzers
    # Какую схему авторизации операции действительно требуют — посчитано, а
    # не предположено.
    #
    # Спецификация может объявить в `components.securitySchemes` несколько
    # схем, а использовать одну. Подсчёт следует правилу OpenAPI: `security`
    # самой операции заменяет объявленный на уровне документа, а пустой
    # список — это осознанное «здесь без учётных данных» (обычный случай —
    # входящий вебхук), поэтому он не голосует ни за что и никогда не
    # означает «API открыт».
    #
    # Ничья разрешается порядком объявления схем: устойчивый ответ дороже
    # хитрого, потому что сгенерированный сервис обязан выходить
    # байт-в-байт одинаковым на каждом прогоне.
    class SecurityRequirements
      # @return [Hash{String => Integer}] сколько операций требует каждую
      #   схему, в порядке первой встречи
      attr_reader :counts
      # @return [Array<String>] JSONPath значений `security` такой формы, о
      #   которой вызывающий должен предупредить
      attr_reader :bad_paths

      # @param root [Object] `security` документа, nil если его нет
      # @param root_path [String] его JSONPath
      # @param operations [Array<Array(Object, String)>] по операции: её
      #   собственный `security` (nil, если она его не объявляет) и его JSONPath
      def initialize(root:, root_path:, operations: [])
        @counts = Hash.new(0)
        @scopes = {}
        @bad_paths = []
        count_all(list(root, root_path), operations)
      end

      # Схема, которую требует больше всего операций.
      # @param names [Array<String>] кандидаты, в порядке объявления
      # @return [String, nil] nil, если кандидатов нет
      def winner(names)
        return nil if names.empty?

        names.each_with_index.min_by { |name, index| [-counts[name], index] }.first
      end

      # @param name [String] имя схемы
      # @return [Array<String>] scopes, которые операции у неё запросили
      def scopes_for(name)
        @scopes.fetch(name, [])
      end

      # @return [Array<String>] все имена схем, которые требует хоть одна
      #   операция
      def names
        counts.keys
      end

      private

      # Операция без собственного `security` наследует корневой.
      def count_all(root, operations)
        required = operations.map { |security, path| security.nil? ? root : list(security, path) }
        required = [root] if required.empty?
        required.each { |entries| count(entries) }
      end

      def count(entries)
        entries.each do |entry|
          entry.each do |name, asked|
            key = name.to_s
            @counts[key] += 1
            @scopes[key] = scopes_for(key) | Array(asked).grep(String)
          end
        end
      end

      def list(value, path)
        return [] if value.nil?
        return bad(path) unless value.is_a?(Array)

        entries = value.grep(Hash)
        @bad_paths << path unless entries.size == value.size
        entries
      end

      def bad(path)
        @bad_paths << path
        []
      end
    end
  end
end
