# frozen_string_literal: true

module SpecGen
  module Analyzers
    # Заполняет profile.idempotency: как провайдер защищает создание выплаты
    # от повтора и что он отвечает на дубль.
    #
    # Заголовок ищется среди параметров-заголовков операций — своих и
    # унаследованных от path item — по алиасам rules/idempotency.yml
    # (черновик IETF draft-ietf-httpapi-idempotency-key-header и имена из
    # индустрии). Найденный заголовок — структурный факт; стратегия ключа —
    # из справочника. Спецификация может пометить заголовок необязательным,
    # и это записывается как есть: отправлять ли ключ всё равно, решает
    # send_when_optional справочника, и обоснование об этом говорит.
    #
    # Главное — успешный путь дедупликации, который узнаёт общий DedupReader:
    # ответ с кодом конфликта, чья схема совпадает со схемой успеха. Есть —
    # в профиль попадает код («dedup on 409»); нет — предупреждение
    # idempotency_dedup_unclear, потому что без него сгенерированный сервис
    # при повторе не отличит дубль от ошибки. Заголовка нет нигде —
    # idempotency_header_missing: повтор после сетевого сбоя создаст вторую
    # выплату, и молчать об этом нельзя.
    class IdempotencyAnalyzer < Base
      # Операция, принимающая заголовок идемпотентности.
      Hit = Struct.new(:key, :name, :required, :json_path, :node, :at, keyword_init: true)
      # Роли операций, которым заголовок нужен в первую очередь — цель
      # заготовки overlay, когда заголовка нет.
      CREATING = %i[create_payout create_deposit].freeze
      SUCCESS = '2'

      # Заполняет `profile.idempotency`.
      # @return [IR::ProviderProfile] тот профиль, который был передан
      def call
        hits = each_operation.filter_map { |path, verb, node| hit(path, verb, node) }
        return absent if hits.empty?

        profile.idempotency = build(hits)
        profile
      end

      private

      def hit(path, verb, node)
        at = json_path(Operations::PATHS, path, verb)
        header = parameters(path, node, at).find do |parameter|
          parameter.location == :header && rules.idempotency.alias?(parameter.name)
        end
        return nil if header.nil?

        Hit.new(key: operation_key(path, verb, node), name: header.name, required: header.required?,
                json_path: header.json_path, node: node, at: at)
      end

      # @return [Array<IR::Parameter>] свои и унаследованные от path item
      def parameters(path, node, at)
        item = data[Operations::PATHS][path]
        ParameterReader.new(shared: item.is_a?(Hash) ? item['parameters'] : nil,
                            own: node['parameters'], own_path: "#{at}.parameters",
                            shared_path: json_path(Operations::PATHS, path, 'parameters')).call
      end

      def build(hits)
        chosen = choose(hits)
        required = hits.any?(&:required)
        IR::Idempotency.new(header: header_of(chosen, hits, required), strategy: strategy,
                            required: required, operations: hits.map(&:key),
                            conflict_status: conflict(hits, chosen), json_path: chosen.json_path)
      end

      # Спецификация может объявить несколько известных имён сразу. Порядок
      # обхода операций тут не судья: у Moov PayGate он отдавал победу
      # заголовку трассировки, который уникален на каждый повтор. Судит
      # список priority в rules/idempotency.yml, а при равенстве — кто
      # встретился раньше.
      def choose(hits)
        ranked = hits.each_with_index.min_by do |hit, index|
          [rules.idempotency.rank(hit.name), index]
        end
        best = ranked.first
        ambiguous(hits, best) if distinct(hits).size > 1
        best
      end

      # @return [Array<String>] имена заголовков без учёта регистра и
      #   разделителей, в порядке первой встречи
      def distinct(hits)
        hits.map(&:name).uniq { |name| Rules::Normalizer.call(name) }
      end

      # Выбор между двумя заголовками — догадка, и молчать о ней нельзя даже
      # когда справочник назвал победителя уверенно. Готового overlay здесь
      # нет намеренно: лечится это порядком в rules/idempotency.yml, куда и
      # отправляет отчёт (Report::Warnings::BOOKS).
      def ambiguous(hits, best)
        winner = Rules::Normalizer.call(best.name)
        rejected = distinct(hits).reject { |name| Rules::Normalizer.call(name) == winner }
        profile.warn(:idempotency_header_ambiguous,
                     t('ambiguous_message', header: best.name, others: rejected.join(', ')),
                     json_path: best.json_path, severity: :info)
      end

      def header_of(first, hits, required)
        evidence = t('header_evidence', header: first.name, operations: hits.map(&:key).join(', '))
        evidence += t('optional_note') if !required && rules.idempotency.send_when_optional?
        IR::Derived.structural(first.name, evidence: evidence)
      end

      def strategy
        value = rules.idempotency.default_strategy
        IR::Derived.registry(value, evidence: t('strategy_evidence', strategy: value))
      end

      def conflict(hits, first)
        status = rules.idempotency.conflict_status
        hits.each do |hit|
          result = DedupReader.new(node: hit.node, key: hit.key, conflict_status: status,
                                   at: hit.at).call
          next unless result&.dedup

          evidence = "#{hit.key}: #{DedupReader.evidence(result)}"
          return IR::Derived.structural(result.status, evidence: evidence)
        end
        unclear(first, hits, status)
      end

      def unclear(first, hits, status)
        ref = "#/components/schemas/#{success_schema(first) || 'TODO'}"
        fragment = t('dedup_overlay', path: first.at, status: status, ref: ref)
        profile.warn(:idempotency_dedup_unclear,
                     t('dedup_unclear_message', header: first.name, status: status),
                     json_path: first.at, suggested_overlay: fragment)
        IR::Derived.unknown(evidence: t('dedup_unknown', operations: hits.map(&:key).join(', '),
                                                         status: status))
      end

      # @return [String, nil] имя схемы первого ответа 2xx операции
      def success_schema(hit)
        responses = hit.node['responses']
        return nil unless responses.is_a?(Hash)

        code, response = responses.find do |status, body|
          status.to_s.start_with?(SUCCESS) && body.is_a?(Hash)
        end
        return nil if code.nil?

        content = response['content']
        media = ContentReader.media_type(content)
        ContentReader.schema_name(content, media, [hit.key, 'responses', code])
      end

      def absent
        profile.idempotency = nil
        target = creating_operation_path || json_path(Operations::PATHS)
        fragment = t('missing_overlay', path: target, header: rules.idempotency.canonical_header)
        profile.warn(:idempotency_header_missing,
                     t('missing_message', aliases: rules.idempotency.aliases.join(', ')),
                     json_path: target, suggested_overlay: fragment)
        profile
      end

      # Операция создания — та, где ключ идемпотентности стоит денег.
      def creating_operation_path
        each_operation do |path, verb, node|
          next unless CREATING.include?(role_of(path, verb, node))

          return json_path(Operations::PATHS, path, verb)
        end
        nil
      end

      def t(key, **params)
        Texts.t("analyzers.idempotency.#{key}", **params)
      end
    end
  end
end
