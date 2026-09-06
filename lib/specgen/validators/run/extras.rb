# frozen_string_literal: true

module SpecGen
  module Validators
    module Run
      # Операции вне контракта: отмена, баланс, подтверждение, возврат и всё,
      # чему не нашлось роли. У каждой свой публичный метод, и от него
      # требуется то же, что от методов контракта: вызвать клиента по адресу
      # своей операции и не упасть.
      #
      # Проверка нужна именно здесь: методов вне контракта тем больше, чем
      # крупнее чужая спецификация (у одной из публичных их больше сотни), и
      # ошибка в них не видна ни одному другому сценарию.
      class Extras < Base
        # @return [Array<Finding>]
        def call
          parts[:extras].entries.map { |operation, method| check(operation, method) }
        end

        private

        def check(operation, method)
          self.method_name = method.name
          aspect = t('aspect_call', verb: verb(operation), path: path_of(operation))
          result, error = attempt(operation, method)
          return crashed(aspect, error) if error
          return unchecked(aspect, refusal(result)) if refused?(result)

          verify(aspect) { judge.request(**target(operation)) }
        end

        def attempt(operation, method)
          client.reply(operation: operation.key, status: status_of(operation))
          invoke(method.name, *args(method))
        end

        # Метод без параметров контракт не получает: у операции без пути с
        # параметрами и без тела запроса аргументов нет.
        def args(method)
          method.params.empty? ? [] : [operation]
        end

        def target(operation)
          { verb: operation.http_method, template: operation.path, path: path_of(operation) }
        end

        def path_of(operation)
          fixture = fixtures.request(operation.key)
          (fixture && fixture['path']) || operation.path
        end

        def verb(operation)
          operation.http_method.to_s.upcase
        end

        def status_of(operation)
          parts[:http].success_codes(operation).first
        end

        # Метод, отказавший до запроса, клиента не звал, и это не ошибка: так
        # ведёт себя отмена в статусе, которого спецификация не разрешает.
        # Прогон говорит об этом «не проверено», а не «не прошло».
        def refused?(result)
          client.calls.empty? && result.respond_to?(:success?) && !result.success?
        end

        def refusal(result)
          t('run_refused', code: result.code.inspect, key: result.key.inspect)
        end
      end
    end
  end
end
