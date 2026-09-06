# frozen_string_literal: true

module SpecGen
  module Analyzers
    # Роль поля по его имени — общий reader для анализаторов, которым нужно
    # найти поле суммы, валюты, статуса или кода ошибки. Пересчитывается от
    # документа: чужой результат из профиля здесь не читается.
    #
    # Отвечает тем же и в том же порядке доверия, что матчеры полей. Сначала
    # словарь: точное совпадение нормализованного имени с синонимом
    # rules/roles.yml — уровень 2, источник :registry. Если словарь молчит об
    # этой роли во всём документе, спрашивается Matchers::Composite — тот же
    # композит из четырёх матчеров, который проставляет роли полей в IR, — и
    # ответом становится его лучший кандидат с насчитанной уверенностью.
    #
    # Почему без собственного порога. Матчеры отдают роль лучшему кандидату
    # даже ниже порога 0.6 (docs/PRINCIPLES.md, третий уровень доверия), и решение с
    # баллами всех кандидатов уже напечатано в report.md. Если после этого
    # UnitsAnalyzer скажет «поле суммы не найдено ни в одной схеме», отчёт
    # будет спорить сам с собой на соседних страницах — а умолчание о поле,
    # роль которого уже названа, и есть та самая молчаливая дыра. Поэтому
    # роль матчеров принимается целиком, но не выдаётся за словарную:
    # #temper понижает уверенность вывода до уверенности роли, и множитель по
    # полю `amt` (0.43) отличим в отчёте от множителя по полю `amount` (0.90).
    #
    # Почему словарь всё же старше. Роль, которую словарь нашёл хотя бы у
    # одного поля документа, эвристике не отдаётся: если провайдер назвал
    # поле `amount`, множитель считается по нему, а не по соседнему `amt`,
    # набравшему очки. Это то же правило, по которому Composite ставит
    # источник :registry выше арифметики, и оно же держит ответ дешёвым:
    # композит по всем именам документа считается только тогда, когда
    # словарю сказать нечего.
    #
    # Одно исключение сделано для кода ошибки. Голое `code` намеренно не
    # входит в синонимы роли error_code — так называют и код валюты, и код
    # банка. Поэтому код ошибки узнаётся структурно: токен имени из подсказок
    # `tokens` роли плюс родитель, чьи токены совпадают с подсказками
    # `parents` — `error.code`, `PayoutError.code`. Проверки те же, что у
    # NameMatcher и StructureMatcher, а композит остаётся запасным ответом и
    # здесь: у `Err.err` нет ни синонима, ни родителя из подсказок.
    class RoleLookup
      ERROR_CODE = :error_code

      # Что документ говорит об имени.
      #
      #   role        роль из IR::Roles::FIELD
      #   source      :overlay | :registry | :heuristic
      #   confidence  1.0 у overlay, уверенность справочника у словаря,
      #               насчитанная композитом у эвристики
      Hit = Struct.new(:role, :source, :confidence, keyword_init: true) do
        # @return [Boolean] роль насчитана, а не названа словарём или человеком
        def heuristic?
          source == :heuristic
        end
      end

      # @param rules [Rules::Registry] справочники целиком: композиту нужны не
      #   только роли, но и статусы, валюты и имена заголовков
      # @param data [Object] разрешённый документ
      def initialize(rules, data)
        @rules = rules
        @book = rules.roles
        @names = Matchers::NameMatcher.new(book: @book)
        @data = data
      end

      # @param name [String, nil] имя поля или параметра как написано
      # @return [Hit, nil]
      def hit(name)
        key = Rules::Normalizer.call(name.to_s)
        return declared[key] if declared.key?(key)

        role = @names.exact(name)
        return registry_hit(role) unless role.nil?

        found = counted[key]
        found if found && !dictionary_roles.include?(found.role)
      end

      # @param name [String, nil] имя поля или параметра как написано
      # @return [Symbol, nil] роль, которую имя несёт в этом документе
      def role_of(name)
        hit(name)&.role
      end

      # Ответ дешевле, чем #role_of: роль, названная словарём, отвечает без
      # композита — по ней проходит большинство спецификаций.
      # @param name [String]
      # @param role [Symbol]
      # @return [Boolean]
      def role?(name, role)
        key = Rules::Normalizer.call(name.to_s)
        return declared[key].role == role if declared.key?(key)

        exact = @names.exact(name)
        return exact == role unless exact.nil?
        return false if dictionary_roles.include?(role)

        counted[key]&.role == role
      end

      # Вывод, опирающийся на поле, роль которого насчитали матчеры, не может
      # быть увереннее самой роли. Словарное имя и имя из overlay не понижают
      # ничего: ради этого справочник и существует.
      # @param derived [IR::Derived] вывод анализатора по этому полю
      # @param name [String, nil] имя поля, по которому сделан вывод
      # @return [IR::Derived] тот же вывод или он же с уверенностью роли
      def temper(derived, name)
        return derived if name.nil? || derived.unknown?

        found = hit(name)
        return derived unless found&.heuristic?
        return derived if found.confidence >= derived.confidence

        IR::Derived.heuristic(derived.value, confidence: found.confidence,
                                             evidence: tempered(derived, name, found))
      end

      # Поле с кодом ошибки: точный синоним роли, токен `code` под
      # родителем-ошибкой или, когда ни того ни другого в документе нет,
      # ответ композита.
      # @param name [String] имя поля
      # @param parents [Array<String>] имена родителей: свойство, схема
      # @return [Boolean]
      def error_code?(name, parents)
        return true if @names.exact(name) == ERROR_CODE
        return true unless error_parent(name, parents).nil?

        !named_error_code? && role?(name, ERROR_CODE)
      end

      private

      def registry_hit(role)
        Hit.new(role: role, source: :registry, confidence: IR::Derived::REGISTRY_CONFIDENCE)
      end

      def tempered(derived, name, found)
        derived.evidence.to_s +
          Texts.t('analyzers.roles.tempered', name: name, role: found.role,
                                              confidence: format('%.2f', found.confidence))
      end

      # @return [String, nil] родитель-ошибка, если токен имени тоже совпал
      def error_parent(name, parents)
        return nil if @names.token(name, ERROR_CODE).nil?

        hit = Matchers::StructureMatcher.parent_hit(parents, @book.hints(ERROR_CODE)[:parents])
        hit&.first
      end

      # Документ уже называет поле кода ошибки словарём или структурой —
      # эвристике эту роль не отдаём, как и любую другую словарную.
      def named_error_code?
        return @named_error_code unless @named_error_code.nil?

        @named_error_code = SchemaIndex.new(@data).each_field.any? do |entry, name, _, _|
          @names.exact(name) == ERROR_CODE || !error_parent(name, [entry.name]).nil?
        end
      end

      # Роли, названные словарём, и роли, закреплённые расширением
      # x-specgen-role, — один дешёвый проход по именам документа.
      def scan
        @dictionary_roles = []
        @declared = {}
        SchemaIndex.new(@data).each_field do |_, name, node, _|
          role = @names.exact(name)
          @dictionary_roles << role unless role.nil?
          fixed = overlay_role(node[RoleSubjects::EXTENSION])
          @declared[Rules::Normalizer.call(name)] ||= overlay_hit(fixed) if fixed
        end
        @dictionary_roles.uniq!
      end

      def overlay_hit(role)
        Hit.new(role: role, source: :overlay, confidence: 1.0)
      end

      # @return [Array<Symbol>]
      def dictionary_roles
        scan if @dictionary_roles.nil?
        @dictionary_roles
      end

      # @return [Hash{String => Hit}] имена, роль которых задал человек
      def declared
        scan if @declared.nil?
        @declared
      end

      # Композит по каждому имени документа. Имя считается один раз, по
      # первому вхождению в порядке SchemaIndex — том же, в котором роли
      # проставляет SchemaAnalyzer, поэтому ответ совпадает с напечатанным в
      # отчёте.
      # @return [Hash{String => Hit, nil}]
      def counted
        @counted ||= count_names
      end

      def count_names
        composite = Matchers::Composite.new(rules: @rules)
        index = {}
        SchemaIndex.new(@data).each_field do |entry, name, node, path|
          key = Rules::Normalizer.call(name)
          index[key] = counted_hit(composite, entry, name, node, path) unless index.key?(key)
        end
        index
      end

      def counted_hit(composite, entry, name, node, path)
        listed = entry.node['required']
        subject = RoleSubjects.from_node(name: name, node: node, parent: entry.name,
                                         json_path: path,
                                         required: listed.is_a?(Array) && listed.include?(name))
        return nil if subject.container

        best = composite.call(subject).best
        best && Hit.new(role: best.role, source: best.source, confidence: best.confidence)
      end

      def overlay_role(value)
        return nil if value.nil?

        role = value.to_s.to_sym
        IR::Roles::FIELD.include?(role) ? role : nil
      end
    end
  end
end
