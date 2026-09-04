# frozen_string_literal: true

module SpecGen
  module Reporter
    # What the analyzers recognised in one spec, as a screen of text.
    #
    # This is the live demonstration of the analysis stage and the seed of
    # the final CLI output: one line per fact, the derivation source and
    # confidence next to every inferred value, and with `explain` the
    # evidence sentence each decision rests on - the same sentence a
    # report.md line is built from. Nothing here reads the spec; the profile
    # is the only input, so the screen cannot show anything the generators
    # would not also see.
    class Summary
      INDENT = Format::INDENT

      # @param profile [IR::ProviderProfile] filled by the analyzers
      # @param document [SpecLoader::Document] for the file name and version
      # @param explain [Boolean] print the evidence behind every derived value
      def initialize(profile, document, explain: false)
        @profile = profile
        @document = document
        @explain = explain
      end

      # @return [String] the whole summary, LF line endings
      def render
        "#{sections.flatten.join("\n")}\n"
      end

      # @param io [IO] where to print
      # @return [void]
      def print_to(io)
        io.write(render)
      end

      private

      attr_reader :profile, :document, :explain

      def sections
        [header, identity, servers, auth, '',
         OperationLines.new(profile, explain: explain).lines, '',
         SchemaLines.new(profile, explain: explain).lines, '',
         warnings]
      end

      def header
        "Parsing spec... #{File.basename(document.file)}: OpenAPI #{document.version}, " \
          "#{counts.join(', ')}"
      end

      def counts
        fields = profile.schemas.each_value.sum { |schema| schema.fields.size }
        [Format.count(profile.operations.size, 'operation'),
         Format.count(profile.schemas.size, 'schema'),
         Format.count(fields, 'field')]
      end

      def identity
        info = profile.info
        return ['Provider: not analysed'] if info.nil?

        lines = ["Provider: #{Format.derived(info.name)}", *evidence(info.name)]
        lines << "Base URL: ENV #{info.base_url_env.value}" if info.base_url_env&.known?
        lines
      end

      def servers
        return ['Servers: none declared'] if profile.servers.empty?

        width = profile.servers.map { |server| environment(server).size }.max
        ['Servers:'] + profile.servers.flat_map do |server|
          ["#{INDENT}#{environment(server).ljust(width)}  #{server.url}",
           *evidence(server.environment, depth: 2)]
        end
      end

      def environment(server)
        server.environment.known? ? server.environment.value.to_s : 'unknown'
      end

      def auth
        auth = profile.auth
        return ['Auth: not analysed'] if auth.nil?
        return ['Auth: none declared in the spec'] if auth.none?
        return ["Auth: #{auth.scheme_name} -> unknown", *evidence(auth.type)] if auth.type.unknown?

        ["Auth: #{auth.scheme_name} -> #{auth.type.value} in #{where(auth)}, " \
         "credentials: #{auth.credential_keys&.value.to_a.join(', ')}",
         *evidence(auth.type)]
      end

      def where(auth)
        [auth.location, auth.param_name].compact.join(' ')
      end

      def warnings
        grouped = profile.warnings_by_severity
        counts = IR::Warning::SEVERITIES.map { |severity| "#{grouped[severity].size} #{severity}" }
        ["Warnings: #{profile.warnings.size} (#{counts.join(', ')})"] +
          profile.sorted_warnings.flat_map { |warning| warning_lines(warning) }
      end

      def warning_lines(warning)
        lines = ["#{INDENT}#{warning.severity.to_s.upcase.ljust(7)} #{warning.json_path}",
                 "#{INDENT * 5}#{warning.message}"]
        return lines unless explain && warning.fixable?

        lines + ["#{INDENT * 5}overlay:"] +
          warning.suggested_overlay.lines.map { |line| "#{INDENT * 6}#{line.chomp}" }
      end

      def evidence(derived, depth: 1)
        Format.evidence(derived, explain: explain, depth: depth)
      end
    end
  end
end
