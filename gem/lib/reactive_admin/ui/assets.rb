module ReactiveAdmin
  module Ui
    # The built client: a Vite production build whose `manifest.json` names the hashed files the shell loads.
    # It comes from `config.ui.client_assets` if set, else the host's own build (`rake reactiveadmin:client:build`)
    # when it has one, so a host that builds a fork keeps it, else the build packaged in the gem. Served by the
    # host's static files or, when it has none, by `Server`.
    module Assets
      ENTRY = "index.html".freeze
      TOGGLE = "src/classic/uiToggle.ts".freeze
      Tags = Data.define(:script, :styles, :preloads)

      module_function

      def root = configured || host_build || packaged || build_dir

      # Where `client:build` writes: the configured directory, or public/reactiveadmin.
      def build_dir = configured || Rails.root.join("public/reactiveadmin")

      def configured
        dir = Ui.settings.client_assets
        dir = dir.call if dir.respond_to?(:call)
        Pathname(dir) if dir
      end

      def host_build = (build_dir if build_dir.join("manifest.json").exist?)

      def packaged = (PackagedClient.dir if PackagedClient.usable?)

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

        # The packaged build's stamp names the exact gem version, which is nobody's business. Judged on the path as
        # Rack::Files will read it, decoded and cleaned, so an encoded name can't slip past.
        def call(env)
          path = Rack::Utils.unescape_path(env["PATH_INFO"].to_s)
          return not_found unless Rack::Utils.valid_path?(path)
          return not_found if File.basename(Rack::Utils.clean_path_info(path)) == PackagedClient::INFO

          Rack::Files.new(Assets.root.to_s, env["PATH_INFO"].start_with?("/assets/") ? IMMUTABLE : {}).call(env)
        end

        private

        def not_found = [404, {"content-type" => "text/plain"}, ["Not Found"]]
      end
    end
  end
end
