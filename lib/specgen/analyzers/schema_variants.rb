# frozen_string_literal: true

module SpecGen
  module Analyzers
    # Ветки `oneOf`/`anyOf`, которые не свелись к одной.
    #
    # Выбросить их нельзя: поля вариантов исчезли бы из IR, а вместе с ними
    # и половина запроса. Слить как сумму тоже нельзя: провайдер не
    # принимает поля двух вариантов вместе. Поэтому свойства всех веток
    # попадают в схему, безусловно обязательным не становится ни одно, и
    # каждое помнит имя своего варианта.
    #
    # `discriminator` превращает неоднозначность в факт уровня 1: он
    # называет поле, которое выбирает вариант, а `mapping` — значение этого
    # поля для каждой ветки. Отсюда условная обязательность без единой
    # догадки, тот же вход для ветки `case request_method`, что даёт
    # `dependentRequired`.
    class SchemaVariants
      KEYWORD = 'discriminator'
      PROPERTY = 'propertyName'
      MAPPING = 'mapping'

      # @return [Hash] схема со свойствами всех веток
      attr_reader :node
      # @return [Hash{String => String}] свойство => имя варианта
      attr_reader :variants
      # @return [Hash{String => IR::RequiredWhen}] свойство => условие ветки
      attr_reader :conditions
      # @return [Array<SchemaNormalizer::Remark>]
      attr_reader :remarks

      # @param node [Hash] схема без ключевого слова выбора
      # @param branches [Array<Hash>] нормализованные ветки, без `null`
      # @param keyword [String] "oneOf" или "anyOf"
      def initialize(node:, branches:, keyword:)
        @source = node
        @branches = branches
        @keyword = keyword
        @variants = {}
        @remarks = []
        @property = property_name
        @keys = @property ? @branches.map { |branch| mapped(branch) } : []
        @labels = labels
        @conditions = read_discriminator
        @node = spread
      end

      private

      # Имя варианта: значение дискриминатора, если он назвал ветку, иначе
      # имя компоненты, иначе место ветки. Порядок веток — порядок
      # спецификации, поэтому имя устойчиво между прогонами.
      def labels
        @branches.each_with_index.map do |branch, index|
          @keys[index] || SchemaNaming.component_of(branch) || "#{@keyword}[#{index}]"
        end
      end

      def property_name
        found = @source[KEYWORD]
        return nil unless found.is_a?(Hash)

        name = found[PROPERTY]
        name.is_a?(String) && !name.empty? ? name : nil
      end

      # Ветка ищется в `mapping` по имени своей компоненты, а если
      # `mapping` не объявлен — по значению самого поля-дискриминатора
      # внутри ветки (`const` либо enum из одного значения).
      def mapped(branch)
        return nil if @property.nil?

        component = SchemaNaming.component_of(branch)
        key, = mapping.find { |_, target| target.to_s.split('/').last == component } if component
        key || own_value(branch)
      end

      def mapping
        found = @source[KEYWORD]
        listed = found.is_a?(Hash) ? found[MAPPING] : nil
        listed.is_a?(Hash) ? listed : {}
      end

      def own_value(branch)
        body = branch['properties'].is_a?(Hash) ? branch['properties'][@property] : nil
        return nil unless body.is_a?(Hash)

        value = body.key?('const') ? body['const'] : single(body['enum'])
        value.is_a?(String) ? value : nil
      end

      def single(enum)
        enum.first if enum.is_a?(Array) && enum.size == 1
      end

      # Условная обязательность каждого варианта, сразу в виде IR: назвать
      # её может только тот, кто видел ветки, — после слияния в схеме об
      # этом не написано нигде. Само поле-дискриминатор в список не входит:
      # оно обязательно всегда, а не при своём значении.
      def read_discriminator
        listed = {}
        @branches.each_with_index do |branch, index|
          key = @keys[index]
          next if key.nil?

          (list(branch['required']) - common - [@property]).each do |field|
            (listed[field] ||= []) << key
          end
        end
        note_discriminator unless listed.empty?
        listed.to_h { |field, keys| [field, required_when(field, keys)] }
      end

      def required_when(field, keys)
        IR::RequiredWhen.new(field: @property, origin: :discriminator,
                             equals: keys.size == 1 ? keys.first : keys,
                             evidence: Texts.t('analyzers.schema.condition.discriminator',
                                               field: field, trigger: @property,
                                               value: keys.join(' | ')))
      end

      # Свойство, обязательное в каждой ветке, обязательно и в схеме: какой
      # бы вариант провайдер ни выбрал, без него запрос не уйдёт. Это вывод
      # уровня 1, а не догадка, поэтому условием он не становится.
      def common
        @common ||= @branches.map { |branch| list(branch['required']) }.reduce(:&) || []
      end

      # Свойства всех веток в одной схеме. `required` веток не объединяется:
      # обязательное в одном варианте не обязательно в другом, и превращать
      # его в безусловное значило бы соврать генератору.
      def spread
        merged = @source[KEYWORD] ? @source.except(KEYWORD) : @source.dup
        note_variants if @conditions.empty?
        fill(merged, 'properties', declare(collect))
        fill(merged, 'required', list(merged['required']) | common)
        merged
      end

      def collect
        properties = @source['properties'].is_a?(Hash) ? @source['properties'].dup : {}
        @branches.each_with_index { |branch, index| take(properties, branch, @labels[index]) }
        properties
      end

      def fill(node, key, value)
        node[key] = value unless value.empty?
      end

      def take(properties, branch, label)
        listed = branch['properties']
        return unless listed.is_a?(Hash)

        listed.each do |name, schema|
          key = name.to_s
          next if properties.key?(key)

          properties[key] = schema
          @variants[key] = label
        end
      end

      # Поле-дискриминатор получает значения вариантов как `enum`, если
      # спецификация не объявила их сама: без них ветку `case` по способу
      # выплаты собрать не из чего.
      def declare(properties)
        return properties if @keys.empty? || @keys.any?(&:nil?)

        body = properties[@property]
        return properties unless body.is_a?(Hash) && !body.key?('enum') && !body.key?('const')

        properties.merge(@property => body.merge('enum' => @keys.uniq))
      end

      def note_discriminator
        remark(Texts.t('analyzers.schema.variants_discriminated',
                       keyword: @keyword, count: @branches.size, property: @property,
                       values: @keys.compact.uniq.join(', ')))
      end

      def note_variants
        remark(Texts.t('analyzers.schema.variants_decomposed', keyword: @keyword,
                                                               count: @branches.size,
                                                               names: @labels.join(', ')))
      end

      def list(value)
        value.is_a?(Array) ? value.grep(String) : []
      end

      def remark(message)
        @remarks << SchemaNormalizer::Remark.new(code: :spec_element_unsupported,
                                                 message: message, severity: :info)
      end
    end
  end
end
