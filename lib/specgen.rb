# frozen_string_literal: true

require_relative 'specgen/version'
require_relative 'specgen/errors'
require_relative 'specgen/texts'
require_relative 'specgen/spec_loader'
require_relative 'specgen/ir'
require_relative 'specgen/rules'
require_relative 'specgen/analyzers'
require_relative 'specgen/reporter'

# Generator of payment-provider integrations from OpenAPI specifications.
#
# The pipeline has one stage per directory under lib/specgen/:
#
#   SpecLoader → OverlayApplier → Analyzers → IR → Generators → Validators → Reporter
#
# The core is provider-neutral. It works with endpoint and field *roles* and
# reads its dictionaries from rules/. Anything specific to one provider lives
# in rules/ (data) or in an OpenAPI Overlay file, never in lib/.
module SpecGen
  # Repository root, resolved from this file so the CLI works from any
  # working directory.
  ROOT = File.expand_path('..', __dir__).freeze
  # Dictionaries: field roles, status synonyms, ISO 4217, signature profiles.
  RULES_DIR = File.join(ROOT, 'rules').freeze
  # ERB templates, one per generated artifact.
  TEMPLATES_DIR = File.join(ROOT, 'templates').freeze
  # Тексты для человека по языкам: locales/<код>/<стадия>.yml.
  LOCALES_DIR = File.join(ROOT, 'locales').freeze
end
