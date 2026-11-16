require "json"
require "pathname"

module ReactiveAdmin
  module Ui
    # The client build that ships inside the gem (`rake package`), so a host needs no Node toolchain. It is built
    # for one gem version and one manifest `schema_version`, recorded in `INFO`; `Assets` serves it only while both
    # still match. It refers to its own files relatively, so it works under any `ui.asset_prefix`.
    module PackagedClient
      Error = Class.new(StandardError)

      DIR = Pathname(File.expand_path("../../../vendor/client", __dir__))
      INFO = "reactiveadmin-client.json".freeze
      SCHEMA_SOURCE = "src/lib/manifestCache.ts".freeze

      @verdicts = {}

      module_function

      def dir = DIR

      def info(dir = DIR)
        JSON.parse(dir.join(INFO).read)
      rescue SystemCallError, JSON::ParserError
        nil
      end

      def expected = {"gem_version" => VERSION, "schema_version" => Manifest::SCHEMA_VERSION}

      # Memoized: the gem's files don't change while a process runs.
      def usable?(dir = DIR)
        @verdicts.fetch(dir) { @verdicts[dir] = verify(dir) }
      end

      def reset! = @verdicts.clear

      def verify(dir)
        return false unless dir.join("manifest.json").exist?

        found = info(dir)
        return false unless found
        return true if found == expected

        warn_mismatch(found)
        false
      end

      # The release build: Vite writes into the gem, then the stamp names what it was built for. The schema version
      # is read from the client's source, so a client that disagrees with the gem fails here, not in a browser.
      def build!(dir: DIR, **options)
        build = ClientBuild.new(out: dir, root: dir.parent.parent, **options)
        build.call
        schema = build.source.join(SCHEMA_SOURCE).read[/SCHEMA_VERSION\s*=\s*(\d+)/, 1]&.to_i
        raise Error, "No SCHEMA_VERSION in #{SCHEMA_SOURCE}" unless schema
        raise Error, "The client expects manifest schema_version #{schema}, the gem serves #{Manifest::SCHEMA_VERSION}" unless schema == Manifest::SCHEMA_VERSION

        dir.join(INFO).write(JSON.pretty_generate(expected) + "\n")
        dir
      end

      def warn_mismatch(found)
        message = "[reactiveadmin] ignoring the packaged client: built for #{found}, this gem needs #{expected}"
        (defined?(Rails) && Rails.logger) ? Rails.logger.warn(message) : Kernel.warn(message)
      end
    end
  end
end
