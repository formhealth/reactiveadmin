require "fileutils"
require "json"
require "stringio"

module ReactiveAdmin
  # Real response shapes as JSON files for Storybook and MSW: the manifest, and per resource its
  # meta, first index page, a show page, and the new and edit forms, rendered as `config.doctor_user`
  # and scrubbed of record data (see Scrubber). Output names resources and counts, never values.
  module Fixtures
    autoload :Scrubber, "reactive_admin/fixtures/scrubber"

    Error = Class.new(StandardError)
    SampleFailed = Class.new(Error)
    Result = Struct.new(:files, :skipped, :kept)

    SEED_ENV = "REACTIVEADMIN_FIXTURES_SEED".freeze
    SEED_FILE = "tmp/reactiveadmin_fixtures_seed".freeze
    SECTIONS = {meta: :reactiveadmin_meta, index: :index, show: :show, new: :new, edit: :edit}.freeze
    KINDS = {meta: :meta, index: :index, show: :show, new: :form, edit: :form}.freeze

    module_function

    # resources: route keys, or nil for every resource the user's manifest lists. Returns the
    # scrubbed files as {relative path => payload}, the sections left out with the reason, and the
    # host-written strings kept verbatim.
    def record(user: ReactiveAdmin.config.doctor_user&.call, resources: nil, scrubber: nil)
      raise Error, "set config.doctor_user (-> { a user }) to render the payloads as" unless user

      Rails.application.reload_routes_unless_loaded
      ApiGuards.with_channel(:session) do
        ActiveRecord::Base.while_preventing_writes { Recorder.new(user, scrubber || Scrubber.new(seed:, vocabulary:, routes: route_segments)).call(resources) }
      end
    end

    # The app's private seed: REACTIVEADMIN_FIXTURES_SEED, else a random one kept in tmp/ (created on first run), so the
    # same machine records the same fakes and nobody without the seed can undo them. Never commit it.
    def seed
      ENV[SEED_ENV].presence || begin
        path = Rails.root.join(SEED_FILE)
        restrict(path) if path.exist?
        (path.read.strip.presence if path.exist?) || SecureRandom.hex(32).tap do |seed|
          FileUtils.mkdir_p(path.dirname)
          File.open(path, File::WRONLY | File::CREAT | File::TRUNC, 0o600) { it.write(seed) }
        end
      end
    end

    # Anyone who can read the seed can undo the fakes.
    def restrict(path)
      return unless path.stat.mode.anybits?(0o077)

      warn "reactiveadmin: #{SEED_FILE} was readable by others; restricted it to its owner"
      path.chmod(0o600)
    end

    def write(result, dir)
      stale(result).each { FileUtils.rm_f(File.join(dir, it)) }
      result.files.each do |path, payload|
        file = File.join(dir, path)
        FileUtils.mkdir_p(File.dirname(file))
        File.write(file, "#{JSON.pretty_generate(payload)}\n")
      end
    end

    # Files an earlier recording of these resources left that this one no longer produces.
    def stale(result)
      keys = result.files.keys.filter_map { File.dirname(it) unless it == "_manifest.json" } | result.skipped.map(&:first)
      keys.flat_map { |key| SECTIONS.keys.map { "#{key}/#{it}.json" } } - result.files.keys
    end

    # The literal segments of the admin's own routes: structure, never record data.
    def route_segments
      prefixes = ["/#{ReactiveAdmin.config.namespace}", Paths.api("/#{ReactiveAdmin.config.namespace}")].map { Regexp.escape(it) }
      Rails.application.routes.routes.map { it.path.spec.to_s }.grep(/\A(?:#{prefixes.join("|")})(?:[\/(]|\z)/).flat_map { it.split(/[\/()]/) }.grep(/\A[\w-]+\z/).uniq
    end

    # Enum names are schema, so they stay readable in the fixtures, but only as choices of their own attribute.
    def vocabulary = Registry.resources.to_h { [Registry.route_key(it), it.resource_class.try(:defined_enums).to_h.transform_values(&:keys)] }

    class Recorder
      def initialize(user, scrubber)
        @user = user
        @scrubber = scrubber
      end

      def call(keys)
        manifest = fetch(Struct.new(:controller).new(ManifestController), :show)
        known = manifest["resources"].pluck("key")
        keys = Array(keys).presence || known
        unknown = keys - known
        raise Error, "unknown resources: #{unknown.join(", ")} (known: #{known.join(", ")})" if unknown.any?

        entries = [["_manifest.json", :manifest, manifest]]
        skipped = []
        keys.each { |key| resource(Registry.resources.find { Registry.route_key(it) == key }, key, entries, skipped) }
        Result.new(entries.map(&:first).zip(@scrubber.scrub_all(entries.map { it.drop(1) })).to_h, skipped, @scrubber.kept)
      end

      private

      def resource(config, key, entries, skipped)
        rows = nil
        SECTIONS.each do |section, action|
          if (reason = unavailable(config, section, rows))
            skipped << [key, section, reason]
            next
          end
          payload = fetch(config, action, **arguments(config, section, rows))
          rows = payload["rows"] if section == :index
          entries << ["#{key}/#{section}.json", KINDS.fetch(section), payload, key]
        rescue SampleFailed => e
          skipped << [key, section, e.message]
        end
      end

      def unavailable(config, section, rows)
        return if section == :meta

        action = (section == :new) ? :new : section
        return "not routed" unless Registry.actions(config).include?(action)
        return "nested under a parent" if Paths.nested?(config) || !Registry.top_level_actions(config).include?(action)
        return "api guard" if ApiGuards.with_channel(:session) { ApiGuards.denies?(config, action) }

        "no records" if %i[show edit].include?(section) && rows.blank?
      end

      def arguments(config, section, rows)
        case section
        when :show, :edit then {path_params: {id: rows.first["id"]}}
        when :new then {path_params: Paths.parent_params(config, config.resource_class.first)}
        else {}
        end
      end

      def fetch(config, action, path_params: {}, query: {})
        status, payload = Doctor::Sample.new(config, @user).call(action, path_params:, query:)
        raise SampleFailed, "#{status} #{payload["code"]}" unless status == 200

        payload
      end
    end

    # The rake task's driver.
    module CLI
      module_function

      def run(resources: nil, out_dir: nil, out: $stdout)
        keys = resources.to_s.split(/[\s+]+/).reject { it.empty? || it == "all" }
        dir = Rails.root.join(out_dir.presence || "tmp/reactiveadmin/fixtures")
        result = Fixtures.record(resources: keys)
        Fixtures.write(result, dir)
        out.puts "wrote #{result.files.size} files to #{dir.relative_path_from(Rails.root)}"
        result.skipped.each { |key, section, reason| out.puts "skipped #{key} #{section}: #{reason}" }
        return if result.kept.empty?

        out.puts "warning: kept #{result.kept.size} host-written strings verbatim; check none quotes a record:"
        result.kept.each { out.puts "  #{it.inspect}" }
      end
    end
  end
end
