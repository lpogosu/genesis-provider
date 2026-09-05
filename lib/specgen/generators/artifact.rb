# frozen_string_literal: true

module SpecGen
  module Generators
    # Один записанный артефакт: что это, куда легло и сколько в нём строк.
    # Ровно то, что CLI печатает строкой «Генерация сервиса... ok (412
    # строк)».
    #
    #   kind   :service | :integration | :fixtures | :report
    #   file   имя файла, например "acmepay_service.rb"
    #   path   полный путь записанного файла
    #   lines  число строк
    Artifact = Struct.new(:kind, :file, :path, :lines, keyword_init: true)
  end
end
