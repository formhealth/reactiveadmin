module ReactiveAdmin
  module Ui
    # The built client: a Vite production build (`rake reactiveadmin:client:build`) whose `manifest.json` names
    # the hashed files the shell loads. Served from `config.ui.client_assets`, by the host's static files or,
    # when it has none, by `Server`.
    module Assets
      ENTRY = "index.html".freeze
      TOGGLE = "src/classic/uiToggle.ts".freeze
      Tags = Data.define(:script, :styles, :preloads)

      module_function

      def root
        dir = Ui.settings.client_assets
        dir = dir.call if dir.respond_to?(:call)
        Pathname(dir || Rails.root.join("public/reactiveadmin"))
      end

      def prefix = Ui.settings.asset_prefix.to_s.chomp("/")

      # Read again when the file changes, so a deploy needs no restart.
      def manifest
        path = root.join("manifest.json")
        stamp = [path, path.mtime]
        return @manifest if @stamp == stamp

        @stamp = stamp
        @manifest = JSON.parse(path.read)
      rescue SystemCallError, JSON::ParserError
        @stamp = @manifest = nil
      end

      def ready? = !manifest&.dig(ENTRY, "file").nil?

      def tags
        manifest = self.manifest or return
        entry = manifest.fetch(ENTRY)
        chunks = chunks(manifest, ENTRY)
        Tags.new(script: url(entry.fetch("file")),
          styles: chunks.flat_map { manifest.dig(it, "css") || [] }.uniq.map { url(it) },
          preloads: (chunks - [ENTRY]).filter_map { manifest.dig(it, "file") }.map { url(it) })
      end

      # The classic dashboard's switch: a second entry of the same build.
      def toggle_script
        file = manifest&.dig(TOGGLE, "file")
        url(file) if file
      end

      # The entry and every chunk it imports statically, which load before the first render.
      def chunks(manifest, key, seen = [])
        return seen if seen.include?(key) || !manifest.key?(key)

        seen << key
        manifest[key].fetch("imports", []).each { chunks(manifest, it, seen) }
        seen
      end

      def url(file) = "#{prefix}/#{file}"

      # Hashed files never change, so they cache for good; everything else revalidates.
      class Server
        IMMUTABLE = {"cache-control" => "public, max-age=31536000, immutable"}.freeze

        def call(env)
          Rack::Files.new(Assets.root.to_s, env["PATH_INFO"].start_with?("/assets/") ? IMMUTABLE : {}).call(env)
        end
      end
    end
  end
end
