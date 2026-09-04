# frozen_string_literal: true

require 'thor'

module SpecGen
  # Command-line entry point behind `./integrate`. Parses arguments, checks
  # that the flags make sense together and hands over to the pipeline. Holds
  # no knowledge about specs or providers.
  #
  # Exit codes: 0 success, 1 error (or warnings under --strict), 2 usage.
  class CLI < Thor
    EXIT_ERROR = 1
    EXIT_USAGE = 2
    SUPPORTED_LANGS = %w[ruby].freeze

    package_name 'integrate'
    default_command :generate
    check_unknown_options!
    map %w[-v --version] => :version
    # Thor 1.5 ships a built-in `tree` command; it only clutters our help.
    remove_command :tree

    # Thor asks for this explicitly; without it argument errors exit with 0.
    def self.exit_on_failure?
      true
    end

    # Run the CLI. Usage mistakes and generator errors become one line on
    # stderr with a distinct exit status; the user never sees a stack trace.
    def self.start(given_args = ARGV, config = {})
      shell = config[:shell] || Thor::Base.shell.new
      super(given_args, config.merge(shell: shell, debug: true))
    rescue Thor::Error => e
      shell.error("usage: #{e.message}")
      exit(EXIT_USAGE)
    rescue SpecGen::Error => e
      shell.error("error: #{e.message}")
      exit(EXIT_ERROR)
    end

    desc 'generate --spec FILE [options]',
         'Generate integration artifacts from an OpenAPI spec (default command)'
    long_desc <<~DESC
      Reads an OpenAPI 3.x specification of a payment provider and writes four
      artifacts into the output directory: <provider>_service.rb,
      INTEGRATION.md, fixtures.json and report.md.

      Either --spec or --all is required.
    DESC
    method_option :spec, type: :string, aliases: '-s',
                         desc: 'Path to the OpenAPI spec (YAML or JSON)'
    method_option :provider, type: :string, aliases: '-p',
                             desc: 'Provider name; derived from info.title when omitted'
    method_option :lang, type: :string, default: 'ruby',
                         desc: 'Target language (only ruby is supported)'
    method_option :overlay, type: :string,
                            desc: 'OpenAPI Overlay 1.0.0 file with manual overrides'
    method_option :output, type: :string, default: 'output', aliases: '-o',
                           desc: 'Output directory'
    method_option :with_mock, type: :boolean, default: false,
                              desc: 'Also generate a mock provider server from the same spec'
    method_option :fix, type: :boolean, default: false,
                        desc: 'Write an overlay skeleton with a TODO slot for every ambiguity'
    method_option :strict, type: :boolean, default: false,
                           desc: 'Exit with status 1 when the report contains warnings'
    method_option :all, type: :boolean, default: false,
                        desc: 'Run on every spec in spec/fixtures/specs and print a summary'
    def generate
      validate_generate_options!
      # Fails here, before a single spec is read, when anything under rules/
      # is inconsistent: a synonym two roles claim must never reach a
      # payment request, and a startup error is the cheapest place to say so.
      Rules.load
      not_implemented('generate')
    end

    desc 'diff', 'Show integration-relevant differences between two versions of a spec'
    method_option :old, type: :string, required: true, desc: 'Previous spec version'
    method_option :new, type: :string, required: true, desc: 'New spec version'
    def diff
      not_implemented('diff')
    end

    desc 'version', 'Print the generator version'
    def version
      say "integrate #{SpecGen::VERSION}"
    end

    private

    def validate_generate_options!
      no_target = options[:spec].nil? && !options[:all]
      raise Thor::Error, 'either --spec or --all is required' if no_target
      raise SpecLoadError.new('spec file not found', file: options[:spec]) if missing_spec?
      return if SUPPORTED_LANGS.include?(options[:lang])

      raise Thor::Error,
            "--lang #{options[:lang]} is not supported (supported: #{SUPPORTED_LANGS.join(', ')})"
    end

    def missing_spec?
      options[:spec] && !File.file?(options[:spec])
    end

    def not_implemented(command)
      raise Error, "`#{command}` is not implemented yet (skeleton build #{SpecGen::VERSION})"
    end
  end
end
