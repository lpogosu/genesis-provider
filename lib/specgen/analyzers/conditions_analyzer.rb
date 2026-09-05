# frozen_string_literal: true

module SpecGen
  module Analyzers
    # Заполняет profile.conditions: другие условия взаимодействия с
    # провайдером — не форму запроса, а его границы. Пауза перед повтором,
    # минимальная сумма, допустимые статусы для отмены, длина и формат
    # идентификаторов, необязательный заголовок идемпотентности.
    #
    # Не путать с ConditionReader и Rules::ConditionsBook#match: те — про
    # условную обязательность поля («код банка обязателен при таком-то типе
    # получателя», IR::RequiredWhen). Здесь IR::Condition — факт о границах, который
    # INTEGRATION.md перечисляет, а сервис проверяет до запроса или учитывает
    # после ответа. Лексика ограничения отмены по статусу лежит в той же
    # книге, секцией status_restriction.
    #
    # Ограничения полей берутся только из тел исходящих запросов — того, что
    # сервис отправляет, — и только у полей, чьё имя точный синоним роли
    # (RoleLookup): ограничение поля без роли матчеры увидят позже. Само
    # ограничение хранится как написано, пересчёт суммы в мажорные единицы —
    # дело генератора вместе с Units: анализаторы независимы.
    class ConditionsAnalyzer < Base
      AMOUNT = :amount
      STATUS = :status
      CANCEL = :cancel
      WEBHOOK = :webhook
      # RFC 6585: Too Many Requests — операция ограничена по частоте.
      RATE_LIMITED = 429
      # Ключевое слово ограничения поля суммы → вид условия.
      AMOUNT_KINDS = { minimum: :min_amount, exclusive_minimum: :min_amount,
                       maximum: :max_amount, exclusive_maximum: :max_amount }.freeze
      # Ключевое слово ограничения любого поля с ролью → вид условия.
      FIELD_KINDS = { max_length: :field_max_length, pattern: :field_pattern,
                      enum: :field_enum }.freeze
      MAX_DEPTH = 8
      STATUSES_GROUP = Rules::ConditionsBook::STATUSES_GROUP

      # Заполняет `profile.conditions`.
      # @return [IR::ProviderProfile] тот профиль, который был передан
      def call
        @lookup = RoleLookup.new(rules, data)
        @index = SchemaIndex.new(data)
        @seen = {}
        each_operation { |path, verb, node| operation(path, verb, node) }
        profile
      end

      private

      # Ответы входящего вебхука пишем мы, его тело присылает провайдер —
      # условий взаимодействия там нет.
      def operation(path, verb, node)
        role = role_of(path, verb, node)
        return if role == WEBHOOK

        key = operation_key(path, verb, node)
        at = json_path(Operations::PATHS, path, verb)
        responses(node, key, at)
        idempotency(path, node, key, at)
        restriction(node, key, at) if role == CANCEL
        request_fields(node, key)
      end

      def responses(node, key, at)
        listed = node['responses']
        return unless listed.is_a?(Hash)

        listed.each do |status, response|
          code = Integer(status.to_s, exception: false)
          next if code.nil?

          where = "#{at}.responses#{SpecLoader::JsonPath.segment(status.to_s)}"
          rate_limited(key, code, where) if code == RATE_LIMITED
          retry_after(key, code, response, where)
        end
      end

      def rate_limited(key, code, where)
        add(:rate_limited, key, nil, structural(code, 'rate_limited_evidence', status: code), where)
      end

      def retry_after(key, code, response, where)
        headers = response.is_a?(Hash) ? response['headers'] : nil
        return unless headers.is_a?(Hash)

        header = headers.keys.find { |name| rules.errors.retry_after?(name.to_s) }
        return if header.nil?

        value = structural(code, 'retry_after_evidence', status: code, header: header)
        add(:retry_after, key, nil, value, where)
      end

      def idempotency(path, node, key, at)
        header = header_parameters(path, node, at).find do |parameter|
          parameter.location == :header && rules.idempotency.alias?(parameter.name)
        end
        return if header.nil? || header.required?

        value = structural(header.name, 'idempotency_optional_evidence', header: header.name)
        add(:idempotency_optional, key, nil, value, header.json_path)
      end

      def header_parameters(path, node, at)
        item = data[Operations::PATHS][path]
        ParameterReader.new(shared: item.is_a?(Hash) ? item['parameters'] : nil,
                            own: node['parameters'], own_path: "#{at}.parameters",
                            shared_path: json_path(Operations::PATHS, path, 'parameters')).call
      end

      # Слова описания, совпавшие со значениями enum поля статуса. Слово без
      # известного статуса условием не становится.
      def restriction(node, key, at)
        sentence = [node['summary'], node['description']].grep(String).join("\n")
        found = rules.conditions.match_restriction(sentence)
        return if found.nil?

        hint, match = found
        statuses = known_statuses(match[STATUSES_GROUP])
        return unclear(key, at, match[0]) if statuses.empty?

        add(:cancel_status_restriction, key, nil, restriction_value(hint, match, statuses),
            "#{at}.description")
      end

      def restriction_value(hint, match, statuses)
        evidence = t('restriction_evidence', pattern: hint.name, sentence: match[0].strip.inspect,
                                             statuses: statuses.join(', '))
        IR::Derived.heuristic(statuses, confidence: rules.conditions.restriction_confidence,
                                        evidence: evidence)
      end

      # @return [Array<String>] значения enum полей статуса, названные в тексте,
      #   в написании спецификации
      def known_statuses(tail)
        words = Rules::Normalizer.tokens(tail)
        status_values.select { |value| words.include?(Rules::Normalizer.call(value)) }
      end

      def status_values
        @status_values ||= @index.each_field.flat_map do |_, name, node, _|
          @lookup.role?(name, STATUS) && node['enum'].is_a?(Array) ? node['enum'].grep(String) : []
        end.uniq
      end

      def unclear(key, at, sentence)
        profile.warn(:condition_unclear,
                     t('unclear_message', key: key, sentence: sentence.strip.inspect),
                     json_path: "#{at}.description")
      end

      def request_fields(node, key)
        body = node['requestBody']
        return unless body.is_a?(Hash)

        content = body['content']
        schema = ContentReader.body(content, ContentReader.media_type(content))['schema']
        entry = @index.entry(SchemaNaming.name_for(schema, [key, 'requestBody']))
        walk(entry, key, [], 0) if entry
      end

      def walk(entry, key, visited, depth)
        return if depth > MAX_DEPTH || visited.include?(entry.name)

        visited << entry.name
        @index.fields(entry).each do |name, node, path|
          field(name, node, path, key)
          nested = @index.nested(entry, name, node)
          walk(nested, key, visited, depth + 1) if nested
        end
      end

      def field(name, node, path, key)
        role = @lookup.role_of(name)
        return if role.nil?

        kinds = role == AMOUNT ? AMOUNT_KINDS.merge(FIELD_KINDS.except(:enum)) : FIELD_KINDS
        ConstraintReader.call(node).each do |keyword, raw|
          kind = kinds[keyword]
          next if kind.nil?

          value = structural(raw, 'constraint_evidence', keyword: keyword, value: raw.inspect,
                                                         name: name, role: role)
          add(kind, key, name, value, path)
        end
      end

      def structural(value, key, **params)
        IR::Derived.structural(value, evidence: t(key, **params))
      end

      # Одно условие на место и вид: поле, до которого дошли из двух запросов,
      # записывается один раз.
      def add(kind, operation, field, value, json_path)
        return if @seen.key?([json_path, kind])

        @seen[[json_path, kind]] = true
        profile.conditions << IR::Condition.new(kind: kind, operation: operation, field: field,
                                                value: value, json_path: json_path)
      end

      def t(key, **params)
        Texts.t("analyzers.condition.#{key}", **params)
      end
    end
  end
end
