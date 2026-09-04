# frozen_string_literal: true

module SpecGen
  module Matchers
    # Формулировки предупреждений стадии матчеров и фрагмент overlay к ним.
    #
    # Обязательное и необязательное поле сообщают о себе по-разному: без
    # обязательного запрос не уйдёт, поэтому это предупреждение и поле
    # попадёт в код с TODO; необязательное будет пропущено, поэтому это
    # справка — одна строка в отчёте. Каждое предупреждение исправимо через
    # overlay расширением x-specgen-role, и ровно этот фрагмент предлагается.
    class Remarks
      EXTENSION = 'x-specgen-role'
      # Слот во фрагменте overlay, когда предложить нечего: значение вне
      # словаря ролей, которое читатель расширения отвергнет с
      # предупреждением, пока человек его не заменит.
      TODO = 'TODO'

      # @param decision [Decision] порог и текст кандидатов
      def initialize(decision:)
        @decision = decision
      end

      # @param subject [Subject]
      # @param candidate [Candidate] выбранный кандидат
      # @param result [Composite::Result]
      # @param doubt [Symbol] :low или :ambiguous
      # @return [Remark]
      def doubtful(subject, candidate, result, doubt)
        message = t(doubt, subject: subject_text(subject), role: candidate.role,
                           confidence: number(candidate.confidence),
                           threshold: number(@decision.threshold),
                           candidates: @decision.candidates_text(result),
                           consequence: consequence(subject, candidate.role))
        remark(:field_role_low_confidence, subject, message, candidate.role)
      end

      # @param subject [Subject]
      # @param evidence [String] почему роли нет
      # @return [Remark]
      def unknown(subject, evidence)
        key = subject.required? ? 'unknown_required' : 'unknown_optional'
        message = t(key, subject: subject_text(subject), shape: shape(subject), evidence: evidence)
        code = subject.required? ? :required_field_role_unknown : :field_role_unknown
        remark(code, subject, message, nil)
      end

      # @param subject [Subject] поле, у которого роль отняли
      # @param loss [Assigner::Loss] кому и с какой уверенностью она досталась
      # @param fallback [Candidate, nil] следующий кандидат проигравшего
      # @return [Remark]
      def conflict(subject, loss, fallback)
        message = t('conflict', subject: subject_text(subject), role: loss.lost.role,
                                score: number(loss.lost.confidence), winner: loss.winner,
                                winner_score: number(loss.confidence),
                                fallback: fallback_text(fallback))
        remark(:field_role_conflict, subject, message, fallback&.role)
      end

      # @param subject [Subject]
      # @param value [Object] что написано в x-specgen-role
      # @return [Remark]
      def overlay_bad(subject, value)
        message = t('overlay_bad', value: value.inspect, allowed: IR::Roles::FIELD.join(', '))
        Remark.new(code: :spec_element_unsupported, message: message, severity: :warning,
                   suggested_overlay: fragment(subject, nil))
      end

      private

      def remark(code, subject, message, role)
        Remark.new(code: code, message: message,
                   severity: subject.required? ? :warning : :info,
                   suggested_overlay: fragment(subject, role))
      end

      # @param role [Symbol, nil] роль в слоте; nil — слот TODO
      def fragment(subject, role)
        return nil if subject.json_path.nil?

        t('overlay_fragment', path: subject.json_path, role: role || TODO,
                              allowed: IR::Roles::FIELD.join(', '))
      end

      def fallback_text(fallback)
        return t('conflict_none') if fallback.nil?

        t('conflict_next', role: fallback.role, confidence: number(fallback.confidence))
      end

      def consequence(subject, role)
        t(subject.required? ? 'consequence_required' : 'consequence_optional', role: role)
      end

      def subject_text(subject)
        kind = subject.parameter? ? 'parameter' : 'field'
        need = subject.required? ? 'required' : 'optional'
        params = { name: subject.name }
        params[:location] = Texts.t("location.#{subject.location}") if subject.parameter?
        Texts.t("matchers.subject.#{need}_#{kind}", **params)
      end

      # @return [String] "string, format uuid, max_length 64"
      def shape(subject)
        parts = [subject.type || '?']
        parts << "format #{subject.format}" if subject.format
        parts.concat((subject.constraints || {}).map { |key, value| "#{key} #{value.inspect}" })
        parts.join(', ')
      end

      def number(value)
        format('%.2f', value.to_f)
      end

      def t(key, **params)
        Texts.t("matchers.warning.#{key}", **params)
      end
    end
  end
end
