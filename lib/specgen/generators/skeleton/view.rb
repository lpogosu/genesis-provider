# frozen_string_literal: true

module SpecGen
  module Generators
    # Заготовка overlay: слот на каждое предупреждение, у которого есть
    # готовый фрагмент переопределения.
    #
    # Модуль назван Skeleton, а не Overlay, намеренно: SpecGen::Overlay —
    # стадия применения переопределений, и одноимённый вложенный модуль
    # внутри Generators перехватывал бы её имя при разрешении констант.
    module Skeleton
      # Представление для templates/overlay.yaml.erb.
      #
      # Главное правило файла: инструмент не пишет живой строкой то, что
      # выбрал за человека. Overlay читается как уровень 1 доверия — всё, что
      # в нём написано, становится фактом с уверенностью 1.00, и эвристика с
      # уверенностью 0.5, попав туда живой строкой, перестала бы быть
      # эвристикой, а предупреждение исчезло бы, не будучи решённым. Поэтому
      # каждый слот закомментирован вместе со своими кандидатами, и
      # раскомментировать выбор обязан человек.
      class View
        # Префикс комментария; ровно два знака, чтобы человек снимал их
        # одним движением и получал готовую строку YAML.
        COMMENT = '# '
        # Действие-якорь: документ Overlay 1.0.0 обязан объявить хотя бы одно
        # действие, а все слоты закомментированы. Якорь ничего не решает за
        # человека — он лишь помечает спецификацию расширением, которого в
        # ней не было, поэтому не спорит с ней и не рождает предупреждений.
        ANCHOR_TARGET = '$.info'
        ANCHOR_KEY = 'x-specgen-overlay'
        ANCHOR_VALUE = 'skeleton'
        # Ширина строки комментария вместе с префиксом.
        WIDTH = Markdown::WIDTH
        # Цель действия в первой строке фрагмента: по ней слоты, спорящие за
        # один узел спецификации, узнают друг о друге.
        TARGET = /\A-\s*target:\s*(.+)\z/

        # Один слот: неоднозначность и фрагмент, который её закрывает.
        Slot = Struct.new(:head, :message, :fragment, keyword_init: true)

        # @param profile [IR::ProviderProfile]
        # @param naming [Naming]
        def initialize(profile:, naming:)
          @profile = profile
          @naming = naming
        end

        # @return [Binding] контекст рендеринга ERB
        def template_binding
          binding
        end

        # @return [String] заголовок документа overlay; ровно тот, который
        #   обещает читателю раздел «Как собрать overlay» в report.md
        def title
          t('title', provider: @naming.slug)
        end

        # @return [Array<String>] шапка файла: что это, что с ним делать,
        #   какой командой вернуть и почему слоты закомментированы
        def header
          blocks = [wrap(t('header_what', spec: spec_file)), wrap(t('header_how')), [command],
                    wrap(t('header_trust')), wrap(t('header_anchor'))]
          blocks.flat_map { |block| block + [''] }[0..-2]
        end

        # @return [Array<String>] строки YAML единственного живого действия
        def anchor
          ["- target: \"#{ANCHOR_TARGET}\"",
           "  description: #{t('anchor_description')}",
           '  update:',
           "    #{ANCHOR_KEY}: #{ANCHOR_VALUE}"]
        end

        # Порядок слотов — порядок предупреждений профиля (срочность, место,
        # код), поэтому два прогона на одной спецификации дают один файл.
        # Одинаковые фрагменты схлопываются: два предупреждения об одном и
        # том же значении статуса адресуют один узел и лечатся одной правкой.
        # @return [Array<Slot>]
        def slots
          @slots ||= fixable.each_with_index.map { |warning, index| slot(warning, index) }
        end

        # @return [Array<String>] строки перед слотами или сообщение об их
        #   отсутствии
        def intro
          key = slots.empty? ? 'no_slots' : 'slots_intro'
          wrap(t(key, count: Texts.plural(slots.size, 'slot')))
        end

        # @param lines [Array<String>] строки YAML
        # @return [Array<String>] они же комментарием; пустая строка
        #   становится голым `#`, иначе в файле остаются хвостовые пробелы
        def comment(lines)
          lines.map { |line| line.to_s.empty? ? COMMENT.strip : "#{COMMENT}#{line}" }
        end

        # @return [String] имя файла заготовки
        def file_name
          @naming.overlay_file_name
        end

        # @return [String] имя файла спецификации, как его показывают отчёты
        def spec_file
          @profile.info&.spec_file || '-'
        end

        private

        # @return [Array<IR::Warning>] предупреждения с фрагментом, по одному
        #   на фрагмент
        def fixable
          @fixable ||= @profile.sorted_warnings.select(&:fixable?).uniq(&:suggested_overlay)
        end

        # Заголовок слота — номер, код предупреждения и адрес элемента: три
        # машинных признака, по которым слот находится в report.md.
        def slot(warning, index)
          head = ["#{index + 1}. #{warning.code}", warning.json_path].compact.join(' — ')
          Slot.new(head: head, message: wrap(warning.message) + shared_note(index),
                   fragment: fragment_of(warning))
        end

        # Два действия с одной целью сливаются рекурсивно, и одноимённый ключ
        # переживает только последнее: раскомментировав оба слота на схему
        # `Recipient`, человек молча потерял бы одно из двух условий. Молчать
        # об этом нельзя — а склеить за него нельзя тем более, потому что
        # склейка и есть выбор.
        # @return [Array<String>] строки предупреждения или пусто
        def shared_note(index)
          mine = targets[index]
          return [] if mine.nil?

          same = targets.each_index.reject { |other| other == index || targets[other] != mine }
          return [] if same.empty?

          wrap(t('slot_shared', count: Texts.plural(same.size, 'slot'),
                                slots: same.map { |other| other + 1 }.join(', ')))
        end

        # @return [Array<String, nil>] цель каждого слота в порядке слотов
        def targets
          @targets ||= fixable.map do |warning|
            fragment_of(warning).filter_map { |line| line[TARGET, 1] }.first
          end
        end

        def fragment_of(warning)
          warning.suggested_overlay.lines.map(&:chomp)
        end

        # Команда возврата печатается отступом, а не в тексте локали: так её
        # можно скопировать из файла целиком.
        def command
          "  ./integrate --spec #{spec_file} --provider #{@naming.slug} --overlay #{file_name}"
        end

        def wrap(text)
          Ruby.wrap(text.to_s.gsub(/\s+/, ' ').strip, WIDTH - COMMENT.size)
        end

        def t(key, **params)
          Texts.t("generators.overlay.#{key}", **params)
        end
      end
    end
  end
end
