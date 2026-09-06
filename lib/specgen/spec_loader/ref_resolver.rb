# frozen_string_literal: true

module SpecGen
  module SpecLoader
    # Заменяет каждый `$ref` в документе глубокой копией его цели.
    # Понимает локальные JSON Pointer (#/components/schemas/X), ссылки в
    # другие файлы относительно ссылающегося документа и ссылки внутри этих
    # файлов. Каждый развёрнутый объект помечается ключом `x-specgen-ref`,
    # чтобы дальние стадии всё ещё знали имя схемы. Цикл не отвергает
    # документ: рекурсивная схема — норма, поэтому на втором вхождении
    # остаётся заглушка, а цепочка ссылок попадает в `cycles` и оттуда в
    # отчёт. Ссылки в пустоту сообщаются вместе с JSONPath виноватого
    # `$ref`; глубина вложенности ограничена, поэтому патологический ввод
    # падает с сообщением, а не с переполнением стека.
    class RefResolver
      REF = '$ref'
      MARKER = 'x-specgen-ref'
      # Метка разомкнутого цикла на месте второго вхождения схемы.
      CYCLE = 'x-specgen-cycle'
      MAX_DEPTH = 256
      MISSING = JsonPointer::MISSING
      REMOTE = %r{\A[a-z][a-z0-9+.-]*://}i

      # Где стоит `$ref`: файл (абсолютным путём), путь ключей до самого
      # ключа `$ref` и строка ссылки.
      Site = Struct.new(:file, :keys, :ref)

      # @param data [Hash] исходный документ
      # @param file [String] путь этого документа; база для внешних ссылок
      # @param reader [#call] читает путь к файлу в Hash (по умолчанию Reader)
      def initialize(data, file:, reader: Reader.method(:read))
        @root = File.expand_path(file)
        @documents = { @root => data }
        @names = { @root => file }
        @reader = reader
        @stack = []
        @memo = {}
        @cycles = {}
      end

      # Разомкнутые циклы: цепочка ссылок → JSONPath того `$ref`, на котором
      # она замкнулась. Загрузчик кладёт их в Document, анализ превращает в
      # предупреждения.
      # @return [Hash{String => String}]
      attr_reader :cycles

      # @return [Hash] разрешённая глубокая копия; вход остаётся нетронутым
      # @raise [SpecParseError, SpecLoadError]
      def resolve
        resolve_node(@documents[@root], @root, [], 0)
      end

      # @return [Array<String>] загруженные внешние файлы, как они печатаются
      def external_files
        (@documents.keys - [@root]).map { |path| @names[path] }
      end

      private

      def resolve_node(node, file, keys, depth)
        check_depth(depth, file, keys)
        case node
        when Hash then resolve_hash(node, file, keys, depth)
        when Array then node.each_with_index.map do |value, i|
          resolve_node(value, file, keys + [i], depth + 1)
        end
        else node
        end
      end

      def resolve_hash(node, file, keys, depth)
        return resolve_ref(node, file, keys, depth) if node.key?(REF)

        node.to_h { |key, value| [key, resolve_node(value, file, keys + [key], depth + 1)] }
      end

      def resolve_ref(node, file, keys, depth)
        ref = node[REF]
        site = Site.new(file, keys + [REF], ref)
        unless ref.is_a?(String)
          fail_parse(Texts.t('spec_loader.ref.not_string', type: TypeName.of(ref)), site)
        end

        target_file, pointer = split(site)
        id = "#{target_file}##{pointer}"
        resolved = cut(id, site) || cached(id) || expand(id, target_file, pointer, site, depth)
        merge_siblings(resolved, node, ref)
      end

      # Разделяемая цель разворачивается один раз; каждое следующее
      # использование получает свою копию, чтобы дальние стадии могли менять
      # одно вхождение, не задевая остальные.
      def cached(id)
        deep_copy(@memo[id]) if @memo.key?(id)
      end

      def expand(id, target_file, pointer, site, depth)
        target = JsonPointer.fetch(document(target_file, site), pointer)
        missing = target.equal?(MISSING)
        fail_parse(Texts.t('spec_loader.ref.target_missing', ref: site.ref), site) if missing

        @stack.push(id)
        resolved = resolve_node(target, target_file, JsonPointer.keys(pointer), depth + 1)
        @stack.pop
        @memo[id] = resolved
      end

      def split(site)
        ref = site.ref
        location, fragment = ref.split('#', 2)
        pointer = fragment.to_s
        unless pointer.empty? || pointer.start_with?('/')
          fail_parse(Texts.t('spec_loader.ref.fragment', ref: ref), site)
        end
        fail_parse(Texts.t('spec_loader.ref.remote', ref: ref), site) if
          location.to_s.match?(REMOTE)

        base = File.dirname(site.file)
        [location.to_s.empty? ? site.file : File.expand_path(location, base), pointer]
      end

      # Рекурсивная схема — норма, а не патология: у Airwallex категория
      # отрасли содержит список таких же категорий, у Stripe так устроена
      # половина API. Отказываться от всей спецификации из-за этого значит
      # не уметь читать её вовсе, поэтому цикл размыкается: на втором
      # вхождении вместо развёрнутой копии остаётся заглушка с именем схемы
      # и без полей. Дальние стадии видят объект, о котором известно только
      # имя, — и говорят об этом в отчёте.
      #
      # @return [Hash, nil] заглушка; nil, если цикла нет
      def cut(id, site)
        start = @stack.index(id)
        return nil unless start

        chain = (@stack[start..] + [id]).map { |entry| display(entry) }.join(' -> ')
        @cycles[chain] ||= JsonPath.build(site.keys)
        { MARKER => site.ref, 'type' => 'object', CYCLE => chain }
      end

      def document(target_file, site)
        @documents[target_file] ||= load_external(target_file, site)
      end

      def load_external(target_file, site)
        @names[target_file] = display_path(target_file)
        @reader.call(target_file)
      rescue SpecLoadError => e
        raise SpecLoadError.new(external_message(target_file, site, e),
                                file: @names[site.file], path: JsonPath.build(site.keys))
      end

      # Ошибка внешнего файла пересказывается на месте ссылки: пользователь
      # правит `$ref` в своём документе, а место проблемы — в чужом.
      def external_message(target_file, site, error)
        detail = error.path ? "#{error.detail} (#{error.path})" : error.detail
        Texts.t('spec_loader.ref.external_unreadable', file: @names[target_file],
                                                       detail: detail, ref: site.ref)
      end

      def merge_siblings(resolved, node, ref)
        return resolved unless resolved.is_a?(Hash)

        resolved.merge(node.reject { |key, _| key == REF }).merge(MARKER => ref)
      end

      def check_depth(depth, file, keys)
        return if depth <= MAX_DEPTH

        fail_parse(Texts.t('spec_loader.ref.too_deep', max: MAX_DEPTH), Site.new(file, keys, nil))
      end

      def deep_copy(value)
        Marshal.load(Marshal.dump(value))
      end

      def display(id)
        path, pointer = id.split('#', 2)
        path == @root ? "##{pointer}" : "#{@names[path]}##{pointer}"
      end

      def display_path(path)
        base = "#{File.dirname(@root)}/"
        path.start_with?(base) ? path.delete_prefix(base) : path
      end

      def fail_parse(message, site)
        raise SpecParseError.new(message, file: @names[site.file], path: JsonPath.build(site.keys))
      end
    end
  end
end
