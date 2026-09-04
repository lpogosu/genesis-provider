# frozen_string_literal: true

module SpecGen
  module SpecLoader
    # Replaces every `$ref` in a document with a deep copy of its target.
    # Handles local JSON Pointers (#/components/schemas/X), references into
    # other files relative to the referencing document, and refs inside those
    # files. Each expanded object is tagged with `x-specgen-ref` so later
    # stages still know the schema's name. Cycles and dangling pointers are
    # reported with the JSONPath of the offending `$ref`; nesting is capped
    # so pathological input fails with a message, not a stack overflow.
    class RefResolver
      REF = '$ref'
      MARKER = 'x-specgen-ref'
      MAX_DEPTH = 256
      MISSING = JsonPointer::MISSING
      REMOTE = %r{\A[a-z][a-z0-9+.-]*://}i

      # Where a `$ref` sits: the file (absolute), the key path of the `$ref`
      # key itself, and the reference string.
      Site = Struct.new(:file, :keys, :ref)

      # @param data [Hash] raw document
      # @param file [String] path of that document; base for external refs
      # @param reader [#call] loads a file path into a Hash (default: Reader)
      def initialize(data, file:, reader: Reader.method(:read))
        @root = File.expand_path(file)
        @documents = { @root => data }
        @names = { @root => file }
        @reader = reader
        @stack = []
        @memo = {}
      end

      # @return [Hash] resolved deep copy; the input is left untouched
      # @raise [SpecParseError, SpecLoadError]
      def resolve
        resolve_node(@documents[@root], @root, [], 0)
      end

      # @return [Array<String>] external files that were loaded, as displayed
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
        fail_parse("$ref must be a string, got #{TypeName.of(ref)}", site) unless ref.is_a?(String)

        target_file, pointer = split(site)
        id = "#{target_file}##{pointer}"
        detect_cycle(id, site)
        resolved = cached(id) || expand(id, target_file, pointer, site, depth)
        merge_siblings(resolved, node, ref)
      end

      # Shared targets are expanded once; every further use gets its own copy
      # so that later stages can mutate one occurrence without touching others.
      def cached(id)
        deep_copy(@memo[id]) if @memo.key?(id)
      end

      def expand(id, target_file, pointer, site, depth)
        target = JsonPointer.fetch(document(target_file, site), pointer)
        fail_parse("$ref target not found: #{site.ref}", site) if target.equal?(MISSING)

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
          fail_parse("$ref fragment must be a JSON Pointer starting with '/': #{ref}", site)
        end
        if location.to_s.match?(REMOTE)
          fail_parse("remote $ref is not supported, the generator makes no network calls: #{ref}",
                     site)
        end

        base = File.dirname(site.file)
        [location.to_s.empty? ? site.file : File.expand_path(location, base), pointer]
      end

      def detect_cycle(id, site)
        start = @stack.index(id)
        return unless start

        chain = (@stack[start..] + [id]).map { |entry| display(entry) }.join(' -> ')
        fail_parse("cyclic $ref: #{chain}", site)
      end

      def document(target_file, site)
        @documents[target_file] ||= load_external(target_file, site)
      end

      def load_external(target_file, site)
        @names[target_file] = display_path(target_file)
        @reader.call(target_file)
      rescue SpecLoadError => e
        location = e.path ? " (#{e.path})" : ''
        raise SpecLoadError.new("referenced file #{@names[target_file]} could not be loaded: " \
                                "#{e.detail}#{location}, referenced as #{site.ref}",
                                file: @names[site.file], path: JsonPath.build(site.keys))
      end

      def merge_siblings(resolved, node, ref)
        return resolved unless resolved.is_a?(Hash)

        resolved.merge(node.reject { |key, _| key == REF }).merge(MARKER => ref)
      end

      def check_depth(depth, file, keys)
        return if depth <= MAX_DEPTH

        fail_parse("nesting deeper than #{MAX_DEPTH} levels, probably a runaway $ref chain",
                   Site.new(file, keys, nil))
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
