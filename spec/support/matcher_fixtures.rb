# frozen_string_literal: true

# Секция `matchers` фикстурного rules/roles.yml: веса и пороги композитного
# матчера полей — те же числа, что в поставке, чтобы примеры про арифметику
# баллов совпадали с rules/roles.yml. Живёт отдельно от RulesFixtures только
# ради длины того модуля.
module RulesFixtures
  MATCHERS = {
    'weights' => { 'name' => 5, 'constraint' => 4, 'structure' => 4, 'type' => 1 },
    'scoring' => { 'threshold' => 0.6, 'margin' => 0.1, 'ceiling' => 0.95 },
    'name' => { 'token' => 1.0, 'overlap' => 0.8, 'min_overlap' => 0.5, 'levenshtein' => 0.5,
                'min_similarity' => 0.8, 'min_length' => 4,
                'generic_tokens' => %w[code id name type value] },
    'constraint' => { 'pattern' => 1.0, 'example' => 0.6, 'enum' => 1.0, 'min_enum_share' => 0.5,
                      'length' => 0.3, 'bounds' => 0.3 },
    'structure' => { 'parent' => 1.0, 'location' => 1.0 },
    'type' => { 'format' => 1.0, 'compatible' => 1.0 },
    'repeatable' => []
  }.freeze
end
