# frozen_string_literal: true

module SpecGen
  module Diff
    # Запросы операций контракта: поля тела (вместе с вложенными схемами) и
    # параметры — заголовки, путь, query.
    #
    # Параметры входят в раздел вместе с полями тела намеренно: и то и другое
    # сгенерированный сервис кладёт в исходящий запрос, и новый обязательный
    # заголовок — такое же изменение формы запроса, как новое обязательное
    # поле. Операция, которая появилась или исчезла целиком, здесь молчит:
    # о ней уже сказал раздел «операции», и повторять её поля построчно
    # значило бы утопить настоящие изменения.
    class Fields < Area
      private

      def compare
        each_element(contract(old), contract(new)) do |_key, was, now|
          next if was.nil? || now.nil?

          compare_parameters(was, now)
          compare_body(was, now)
        end
      end

      def contract(profile)
        profile.operations.select(&:contract?).to_h { |operation| [operation.key, operation] }
      end

      def compare_parameters(was, now)
        each_element(parameters(was), parameters(now)) do |_key, before, after|
          if before.nil?
            appeared(:parameter_added, after, after.name, parameter_state(after))
          elsif after.nil?
            vanished(:parameter_removed, before, before.name, parameter_state(before))
          else
            compare_parameter(before, after)
          end
        end
      end

      def parameters(operation)
        operation.parameters.to_h do |parameter|
          ["#{parameter.location} #{parameter.name}", parameter]
        end
      end

      def compare_parameter(before, after)
        at = after.json_path
        changed(:parameter_required_changed, parameter_state(before), parameter_state(after),
                json_path: at)
        changed(:parameter_role_changed, value_of(before.role), value_of(after.role),
                json_path: at)
      end

      def compare_body(was, now)
        each_element(RequestFields.call(old, was), RequestFields.call(new, now)) do |name, b, a|
          if b.nil?
            appeared(:field_added, a, name, field_state(a))
          elsif a.nil?
            vanished(:field_removed, b, name, field_state(b))
          else
            compare_field(b, a)
          end
        end
      end

      def compare_field(before, after)
        at = after.json_path
        changed(:field_role_changed, value_of(before.role), value_of(after.role), json_path: at)
        changed(:field_requirement_changed, field_state(before), field_state(after), json_path: at)
        compare_condition(before.required_when, after.required_when, at)
      end

      # Переход «условие есть — условия нет» уже сказан обязательностью,
      # поэтому здесь сравниваются только два условия между собой.
      def compare_condition(before, after, at)
        return if before.nil? || after.nil?

        changed(:field_condition_changed, condition(before), condition(after), json_path: at)
        changed(:field_condition_origin_changed, before.origin, after.origin, json_path: at)
      end

      def condition(required_when)
        Change.pair(required_when.field, required_when.equals)
      end

      def parameter_state(parameter)
        parameter.required? ? :required : :optional
      end

      def field_state(field)
        return :required if field.required?
        return :conditional if field.conditionally_required?

        :optional
      end

      # Необязательный элемент без роли в payload не идёт: по
      # docs/PRINCIPLES.md он остаётся строкой отчёта, а увидеть его можно
      # только в документации и фикстурах.
      def impact_of(element, state)
        state == :optional && value_of(element.role).nil? ? :docs : :code
      end

      def appeared(kind, element, name, state)
        add(kind, json_path: element.json_path, after: name, impact: impact_of(element, state))
      end

      def vanished(kind, element, name, state)
        add(kind, json_path: element.json_path, before: name, impact: impact_of(element, state))
      end
    end
  end
end
