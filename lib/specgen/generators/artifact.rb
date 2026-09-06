# frozen_string_literal: true

module SpecGen
  module Generators
    # Один записанный артефакт: что это, куда легло и сколько в нём строк.
    # Ровно то, что CLI печатает строкой «Генерация сервиса... ok (412
    # строк)».
    #
    #   kind     :service | :integration | :fixtures | :report
    #   file     имя файла, например "acmepay_service.rb"
    #   path     полный путь записанного файла
    #   lines    число строк
    #   metrics  числа, которые генератор уже посчитал для своего артефакта и
    #            которые нужны снаружи: пакетный прогон берёт отсюда покрытие,
    #            чтобы не считать его второй раз и не разбирать markdown
    Artifact = Struct.new(:kind, :file, :path, :lines, :metrics, keyword_init: true)

    # Поиск по метрикам прогона.
    class Artifact
      # Числа прогона собранного класса среди артефактов прогона: их считает
      # генератор отчёта, а печатают CLI и веб. Знание о том, где они лежат,
      # живёт здесь, а не у каждого читателя.
      #
      # @param artifacts [Array<Artifact>]
      # @return [Hash, nil] nil, если прогона не было
      def self.run_metrics(artifacts)
        artifacts.filter_map(&:metrics).find { |item| item[:run_total].to_i.positive? }
      end
    end
  end
end
