# frozen_string_literal: true

module SpecGen
  module Rules
    # Секции `vetoes` и `pairing` rules/operations.yml: отсечки формы и
    # правила связывания операций в пару «создание — опрос статуса».
    #
    # Подмешивается в OperationsBook. Отделено от голосования, потому что
    # отвечает на другой вопрос: голоса говорят, на что операция похожа, а
    # эти две секции — может ли она вообще играть такую роль и с какой
    # другой операцией она связана. Обе секции необязательны: справочник без
    # них даёт прежнее поведение матчера, а не отказ загрузки.
    module OperationTuning
      # Отсечки формы: роль, которую операция не может играть, сколько бы
      # голосов она ни набрала.
      VETOES = %i[domain_nouns http_method list_response].freeze
      # Вес каждого правила связывания.
      PAIRING_WEIGHTS = %i[link container path_prefix schema resource].freeze
      # Ключи секции `pairing`.
      PAIRING = %i[weights depth_penalty resource_priority].freeze
      EMPTY_VETO = { roles: [], ignore: [] }.freeze

      # Отсечка: роли, которых она касается, и слова, которыми она проверяет.
      # @param kind [Symbol] один из VETOES
      # @return [Hash] :roles и, у отсечки по форме ответа, :ignore
      def veto(kind)
        @vetoes.fetch(kind, EMPTY_VETO)
      end

      # @param key [Symbol] один из PAIRING_WEIGHTS, :depth_penalty или
      #   :resource_priority
      # @return [Float, Array<String>] вес правила, штраф или список слов
      def pairing(key)
        @pairing[key]
      end

      private

      def load_vetoes
        listed = section('vetoes', required: false)
        report_unknown(listed.keys.map(&:to_sym) - VETOES, VETOES, path('vetoes'))
        VETOES.to_h { |kind| [kind, veto_entry(kind, listed[kind.to_s])] }.freeze
      end

      def veto_entry(kind, body)
        return EMPTY_VETO if body.nil?

        at = path('vetoes', kind)
        fields = mapping(body, noun(:role_body, role: kind), at)
        { roles: veto_roles(fields['roles'], "#{at}.roles"),
          ignore: words(fields['ignore'], :ignore, at) }.freeze
      end

      def veto_roles(value, at)
        listed = string_list(value, noun(:list, key: 'roles'), at, required: false)
        listed.each_with_index.filter_map do |name, index|
          symbol_in(name, OperationsBook::ROLES, noun(:operation_role), "#{at}[#{index}]")
        end.freeze
      end

      def load_pairing
        body = section('pairing', required: false)
        report_unknown(body.keys.map(&:to_sym) - PAIRING, PAIRING, path('pairing'))
        pairing_weights(body['weights']).merge(
          depth_penalty: fraction(body['depth_penalty'] || 0.0, :depth_penalty,
                                  path('pairing', 'depth_penalty')),
          resource_priority: words(body['resource_priority'], :resource_priority, path('pairing'))
        ).freeze
      end

      def pairing_weights(listed)
        at = path('pairing', 'weights')
        weights = mapping(listed, noun(:list, key: 'weights'), at, required: false)
        report_unknown(weights.keys.map(&:to_sym) - PAIRING_WEIGHTS, PAIRING_WEIGHTS, at)
        PAIRING_WEIGHTS.to_h do |key|
          value = weights[key.to_s]
          next [key, 0.0] if value.nil?

          [key, integer(value, noun(:weight_of, signal: key), path('pairing', 'weights', key),
                        range: (0..)).to_f]
        end
      end
    end
  end
end
