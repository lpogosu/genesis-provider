# frozen_string_literal: true

module SpecGen
  module Matchers
    # Присваивает роли группе полей одной схемы или параметрам одной
    # операции: считает кандидатов, разводит конфликты, формулирует
    # предупреждения.
    #
    # Порядок доверия — как везде в IR: расширение x-specgen-role из overlay
    # побеждает всё и не оспаривается; поле-контейнер (объект, массив) роли
    # не получает — роли получают его вложенные поля, и это не пробел, а
    # устройство модели; остальное решает Composite.
    #
    # Одна роль на два поля одной схемы — конфликт, а не совпадение: две
    # суммы в одном объекте означают, что одна из них не сумма операции.
    # Роль остаётся у поля с большей уверенностью (при равенстве — у
    # первого по порядку схемы), второе получает следующего кандидата или
    # остаётся без роли, и в обоих случаях об этом сказано. Роли из overlay в
    # конфликт не вступают: человек так решил. Роли из `repeatable`
    # rules/roles.yml конфликтом не считаются.
    class Assigner
      # Решение по одному полю.
      #
      #   derived  IR::Derived роли
      #   remarks  [Remark] то, о чём анализатор должен предупредить
      Outcome = Struct.new(:derived, :remarks, keyword_init: true)

      # Проигранный конфликт: кому и с какой уверенностью отдана роль.
      # Снимок на момент конфликта: победитель позже может сам проиграть
      # другому полю, и его текущий кандидат уже не тот, что выиграл.
      Loss = Struct.new(:winner, :confidence, :lost, keyword_init: true)

      # Рабочее состояние одного поля на время разводки конфликтов.
      #
      #   result   Composite::Result или nil у контейнера и роли из overlay
      #   index    позиция выбранного кандидата в ранжировании
      #   fixed    роль из x-specgen-role, не оспаривается
      #   lost_to  Loss после конфликта, иначе nil
      Slot = Struct.new(:subject, :result, :index, :fixed, :lost_to, :remarks,
                        keyword_init: true) do
        # @return [Candidate, nil] кандидат, на котором стоит выбор
        def candidate
          result&.candidates&.[](index)
        end

        # @return [Symbol, nil] роль, на которую поле сейчас претендует
        def role
          fixed || candidate&.role
        end

        # @return [Float] уверенность претензии: overlay не оспаривается
        def confidence
          fixed ? 1.0 : candidate&.confidence.to_f
        end
      end

      # @param rules [Rules::Registry]
      def initialize(rules:)
        @book = rules.roles
        @composite = Composite.new(rules: rules)
        @decision = Decision.new(book: @book)
        @remarks = Remarks.new(decision: @decision)
      end

      # @param subjects [Array<Subject>] поля одной схемы или параметры одной
      #   операции, в порядке спецификации
      # @return [Array<Outcome>] по одному на поле, в том же порядке
      def call(subjects)
        slots = subjects.map { |subject| slot_for(subject) }
        resolve(slots)
        slots.map { |slot| outcome(slot) }
      end

      private

      def slot_for(subject)
        slot = Slot.new(subject: subject, index: 0, remarks: [])
        overlay = subject.overlay
        if overlay.nil? || subject.container
          slot.result = @composite.call(subject) unless subject.container
        elsif IR::Roles::FIELD.include?(overlay.to_s.to_sym)
          slot.fixed = overlay.to_s.to_sym
        else
          slot.remarks << @remarks.overlay_bad(subject, overlay)
          slot.result = @composite.call(subject)
        end
        slot
      end

      # Каждый шаг отдаёт роль одному из двух претендентов и двигает второго
      # к следующему кандидату; индексы только растут, поэтому цикл конечен.
      def resolve(slots)
        loop do
          winner, loser = clash(slots)
          break if winner.nil?

          loser.lost_to = Loss.new(winner: winner.subject.name, confidence: winner.confidence,
                                   lost: loser.candidate)
          loser.index += 1
        end
      end

      # @return [Array(Slot, Slot), nil] победитель и проигравший
      def clash(slots)
        claimed = {}
        slots.each do |slot|
          role = slot.role
          next if role.nil? || @book.repeatable?(role)

          other = claimed[role]
          claimed[role] = slot if other.nil?
          next if other.nil? || (other.fixed && slot.fixed)

          return rank(other, slot)
        end
        nil
      end

      def rank(first, second)
        return [first, second] if first.fixed
        return [second, first] if second.fixed

        first.confidence >= second.confidence ? [first, second] : [second, first]
      end

      def outcome(slot)
        derived = if slot.fixed then overlay_derived(slot.fixed)
                  elsif slot.subject.container then container_derived(slot.subject)
                  elsif slot.result.none? then unknown(slot, t('no_signal'))
                  elsif slot.candidate.nil? then demoted_out(slot)
                  else
                    chosen(slot)
                  end
        Outcome.new(derived: derived, remarks: slot.remarks)
      end

      def overlay_derived(role)
        IR::Derived.overlay(role, evidence: t('overlay', role: role))
      end

      def container_derived(subject)
        IR::Derived.unknown(evidence: t('container', type: subject.type || 'object'))
      end

      def unknown(slot, evidence)
        slot.remarks << @remarks.unknown(slot.subject, evidence)
        IR::Derived.unknown(evidence: evidence)
      end

      def demoted_out(slot)
        slot.remarks << @remarks.conflict(slot.subject, slot.lost_to, nil)
        IR::Derived.unknown(evidence: demoted_text(slot.lost_to))
      end

      def chosen(slot)
        candidate = slot.candidate
        prefix = slot.lost_to && demoted_text(slot.lost_to)
        report(slot, candidate)
        @decision.derive(candidate, slot.result, prefix: prefix)
      end

      def report(slot, candidate)
        if slot.lost_to
          slot.remarks << @remarks.conflict(slot.subject, slot.lost_to, candidate)
        elsif (doubt = @decision.doubt(candidate, slot.result))
          slot.remarks << @remarks.doubtful(slot.subject, candidate, slot.result, doubt)
        end
      end

      def demoted_text(loss)
        t('demoted', role: loss.lost.role, winner: loss.winner,
                     score: format('%.2f', loss.confidence))
      end

      def t(key, **params)
        Texts.t("matchers.evidence.#{key}", **params)
      end
    end
  end
end
