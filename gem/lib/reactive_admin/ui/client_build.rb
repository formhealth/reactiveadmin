module ReactiveAdmin
  module Ui
    # Builds the React client from this repository's checkout (Vite, at deploy time; nothing runs node in
    # production) into the directory the gem serves it from. `rake reactiveadmin:client:build`.
    class ClientBuild
      Error = Class.new(StandardError)

      SCRIPT = "build:host".freeze

      def self.source = Pathname(ENV["REACTIVEADMIN_CLIENT_SRC"] || File.expand_path("../../../../apps/standalone", __dir__))

      def initialize(out: Assets.root, prefix: Assets.prefix, source: self.class.source, root: Rails.root, runner: method(:run))
        @out = Pathname(out).expand_path
        @prefix = prefix
        @source = Pathname(source).expand_path
        @root = Pathname(root).expand_path
        @runner = runner
      end

      attr_reader :out, :source

      def call
        check!
        workspace = source.parent.parent
        @runner.call({}, %w[pnpm install --frozen-lockfile], workspace)
        @runner.call(env, %W[pnpm --filter standalone #{SCRIPT}], workspace)
        raise Error, "The build wrote no manifest.json to #{out}" unless out.join("manifest.json").exist?

        out
      end

      def env = {"RA_OUT_DIR" => out.to_s, "RA_ASSET_PREFIX" => "#{@prefix}/"}

      private

      # The build empties its output directory, so it only ever writes inside the app.
      def check!
        raise Error, "No client source at #{source}. It ships with the reactiveadmin repository; set REACTIVEADMIN_CLIENT_SRC." unless source.join("package.json").exist?
        raise Error, "Refusing to build into #{out}: it must be a directory inside #{@root}." unless out.to_s.start_with?("#{@root}/")
      end

      def run(env, command, chdir)
        ok = Bundler.with_unbundled_env { system(env, *command, chdir: chdir.to_s) }
        raise Error, "#{command.join(" ")} failed (is node >= 24 with pnpm installed?)" unless ok
      end
    end
  end
end
