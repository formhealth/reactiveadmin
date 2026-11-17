require "open3"
require "rails/generators"

module ReactiveAdmin
  module Generators
    class InstallGenerator < Rails::Generators::Base
      DOCS = "https://github.com/formhealth/reactiveadmin/blob/main/docs/guide"
      INITIALIZERS = %w[config/initializers/reactive_admin.rb config/initializers/reactiveadmin.rb]
      MENU = "app/admin/menu.rb"
      DASHBOARD = "app/admin/dashboard.rb"
      ADAPTERS = {"pundit" => "ActiveAdmin::PunditAdapter", "cancancan" => "ActiveAdmin::CanCanAdapter"}
      AA_ROUTES = /^[ \t]*ActiveAdmin\.routes(?:\(self\)| self)[ \t]*(?:#[^\r\n]*)?\r?\n/
      RA_ROUTES = /^[ \t]*ReactiveAdmin\.routes\b/
      PRESETS = %w[quick guided strict]
      MCP_MODES = %w[off read_only full]
      UI_MODES = %w[nobody admins everyone]

      # Columns worth masking, by name. Secrets and identity numbers are proposed; contact details are only
      # named, since operators usually need to see them.
      SECRET = /password|passcode|secret|token|api_key|private_key|otp|_digest\z|crypt|\A(?:ssn|social_security\w*|tax_id|ein|passport\w*|drivers?_license\w*|mrn|medical_record\w*|dob|date_of_birth|birth_?date|birthday)\z/
      CONTACT = /email|phone|mobile|\Afax\z|address|street|\Acity\z|zip|postal|postcode|first_name|last_name|middle_name|full_name|maiden_name/
      NOT_A_VALUE = /_(?:at|on|count|type)\z/
      FOREIGN_KEY = /_id\z/

      namespace "reactiveadmin:install"
      source_root File.expand_path("templates", __dir__)
      desc "Sets ReactiveAdmin up: an initializer (and for guided and strict, a menu that decides what the API serves), " \
        "the API routes, and optionally the new-admin switch. Prompts in a terminal; every answer is also a flag."

      class_option :preset, type: :string, enum: PRESETS,
        desc: "quick: serve everything ActiveAdmin registers. guided (default): serve what app/admin/menu.rb lists, generated with every registration to prune. strict: serve only what you list, plus the dashboard and anything marked `reactive { expose true }`"
      class_option :namespace, type: :string, desc: "The ActiveAdmin namespace to serve. Defaults to the one config/initializers/active_admin.rb sets, else admin."
      class_option :mask, type: :string, banner: "a,b",
        desc: "Attributes to mask everywhere in the API, or --no-mask for none. Defaults to the secrets found in db/schema.rb"
      class_option :mcp, type: :string, enum: MCP_MODES, desc: "The MCP endpoint for AI agents (default off)"
      class_option :ui, type: :string, enum: UI_MODES, desc: "Who may switch to the new admin (default nobody)"
      class_option :yes, type: :boolean, default: false, desc: "Take the default for every question instead of prompting"
      class_option :skip_check, type: :boolean, default: false, desc: "Don't boot the app at the end to check the setup"

      # Runs first, so nothing is written for a namespace the API can't serve.
      def resolve_namespace
        given = options[:namespace]
        # Written into the initializer as a bare symbol, so anything but a plain name would break the app's boot.
        raise Thor::Error, "--namespace must be a plain name (letters, digits, underscores), not #{given.inspect}." if given.present? && !given.match?(/\A[a-z_]\w*\z/i)
        return if namespace_name

        raise Thor::Error, "ActiveAdmin's default_namespace in config/initializers/active_admin.rb is #{aa_namespace[:raw]}, " \
          "which ReactiveAdmin can't serve under a name. Rerun with --namespace NAME."
      end

      def choose
        @preset = pick(:preset, "How should ReactiveAdmin start?", PRESETS, "guided", <<~HELP)
          quick   serve everything ActiveAdmin registers, with the secure defaults
          guided  serve what app/admin/menu.rb lists; it's generated with every registration, to prune
          strict  serve only what you list (plus the dashboard), and no columns that a block doesn't name
        HELP
        @masked = masked_attributes_choice
        @mcp = pick(:mcp, "Turn on the MCP endpoint for AI agents?", MCP_MODES, "off", <<~HELP)
          off        no agent access
          read_only  agents read and run GET actions, as the signed-in admin
          full       agents also create, update and delete, where your policy allows
        HELP
        @ui = pick(:ui, "Who may switch to the new admin?", UI_MODES, "nobody", <<~HELP)
          nobody    keep the classic admin for now
          admins    users whose admin? is true (adjust in the initializer)
          everyone  every signed-in admin user
        HELP
      end

      def create_initializer
        if (existing = INITIALIZERS.find { exist?(it) })
          @kept_initializer = existing
          say_status :skip, existing, :yellow
        else
          template (@preset == "quick") ? "reactive_admin.rb.tt" : "reactive_admin_annotated.rb.tt", INITIALIZERS.first
        end
      end

      def create_menu
        return if @preset == "quick" || @kept_initializer
        return say_status(:skip, MENU, :yellow) if exist?(MENU)

        template "menu.rb.tt", MENU
      end

      def mount_routes
        routes = read("config/routes.rb")
        if routes.match?(RA_ROUTES)
          say_status :identical, "ReactiveAdmin.routes(self)", :blue
        elsif (line = routes[AA_ROUTES])
          # Same indent and line ending as ActiveAdmin's line, so a CRLF file stays CRLF.
          inject_into_file "config/routes.rb", "#{line[/\A[ \t]*/]}ReactiveAdmin.routes(self)#{line[/\r?\n\z/]}", after: AA_ROUTES
        else
          say_status :error, "ActiveAdmin.routes(self) not found in config/routes.rb. Install ActiveAdmin, then add ReactiveAdmin.routes(self) after it", :red
        end
      end

      # The switch lives on a classic page: the dashboard is where people land.
      def add_ui_toggle
        return if @ui == "nobody"

        dashboard = read(DASHBOARD)
        return say_status(:identical, "reactiveadmin_ui_toggle in #{DASHBOARD}", :blue) if uncommented(dashboard).include?("reactiveadmin_ui_toggle")

        if (line = dashboard[DASHBOARD_CONTENT])
          inject_into_file DASHBOARD, "#{line[/\A[ \t]*/]}  text_node reactiveadmin_ui_toggle#{line[/\r?\n\z/]}", after: DASHBOARD_CONTENT
        else
          say_status :warning, "No `content do` block opening on its own line in #{DASHBOARD}. Add `text_node reactiveadmin_ui_toggle` to the page people land on; see #{DOCS}/rollout.md", :yellow
        end
      end

      def check_authorization_adapter
        return unless adapter
        # ActiveAdmin also takes the adapter's class name as a string.
        return if active_admin_config.match?(/^\s*config\.authorization_adapter\s*=\s*(["']?)(?:::)?#{adapter}\1/)

        say_status :warning, "#{authorization_gem} is bundled, but ActiveAdmin doesn't use it. ReactiveAdmin authorizes through ActiveAdmin's adapter; " \
          "if your classic admin should too, set `config.authorization_adapter = #{adapter}` in config/initializers/active_admin.rb", :yellow
      end

      def warn_about_mcp_writes
        say_status :warning, "MCP agents can create, update and delete wherever your policy allows. Set `reactive { mcp :read_only }` on resources they shouldn't change", :yellow if @mcp == "full"
      end

      def check_boot
        return if options[:skip_check] || !exist?("bin/rails")

        output, ok = boot_report
        if ok
          say_status :ok, output.lines.last.to_s.strip, :green
        else
          say_status :warning, "The app didn't boot with this setup. Run `bin/rails runner 'ReactiveAdmin.config'` to see why. " \
            "#{output.lines.grep(/Error/).first.to_s.strip}", :yellow
        end
      end

      def show_next_steps
        say <<~TEXT

          ReactiveAdmin is installed. Next:

          #{exposure_step}
             #{DOCS}/security.md#exposure
          2. Start Rails, sign in to the classic admin, and open /api/#{namespace_name}/_manifest.
          3. Set `config.doctor_user`, then measure coverage: bin/rails reactiveadmin:doctor
             #{DOCS}/doctor.md
          #{client_step}
             #{ui_step}
             #{DOCS}/rollout.md
        TEXT
      end

      private

      # A line that opens the block, ending in `do` (with block args or a comment): a one-line block is left alone.
      DASHBOARD_CONTENT = /^[ \t]*content\b[^\r\n]*\bdo[ \t]*(?:\|[^|\r\n]*\|)?[ \t]*(?:#[^\r\n]*)?\r?\n/
      BOOT_CHECK = <<~RUBY.freeze
        Rails.application.reload_routes_unless_loaded
        configs = ReactiveAdmin::Registry.resources + ReactiveAdmin::Registry.pages
        exposed = configs.count { ReactiveAdmin::Exposure.allowed?(it) }
        puts "ReactiveAdmin serves \#{ReactiveAdmin.config.mount_path}/\#{ReactiveAdmin.config.namespace}: \#{exposed} of \#{configs.size} resources and pages exposed"
      RUBY

      def boot_report
        output, status = Open3.capture2e("bin/rails", "runner", BOOT_CHECK, chdir: destination_root)
        [output, status.success?]
      end

      def interactive? = !options[:yes] && $stdin.tty?

      def pick(name, question, choices, default, help)
        return options[name] if options[name]
        return default unless interactive?

        say "\n#{help}"
        ask(question, limited_to: choices, default:)
      end

      def masked_attributes_choice
        return [] if options.key?("mask") && options[:mask].nil?
        return split(options[:mask]) if options[:mask]
        return proposed_masks unless interactive?

        say "\nIn db/schema.rb: #{schema_summary}" if schema_columns.any?
        answer = ask("Attributes to mask everywhere in the API (comma-separated, or none):", default: proposed_masks.join(", ").presence || "none")
        (answer.strip == "none") ? [] : split(answer)
      end

      def split(list) = list.split(/[\s,]+/).map { it.delete_prefix(":") }.reject(&:empty?).uniq

      def schema_columns
        # An `_id` column is a foreign key unless its name says it's an identity number (tax_id).
        @schema_columns ||= read("db/schema.rb").scan(/^\s*t\.\w+\s+["'](\w+)["']/).flatten.uniq
          .reject { it.match?(NOT_A_VALUE) || (it.match?(FOREIGN_KEY) && !it.match?(SECRET)) }
      end

      # Rails' filter_parameters are masked already (mask_filter_parameters), so only what they miss is proposed.
      def proposed_masks = schema_columns.select { it.match?(SECRET) && !filtered?(it) }

      # Only literal entries prove coverage, the way Rails matches them (anywhere in the name). A regexp, a
      # constant or a method call proves nothing, so the column stays proposed.
      def filtered?(column) = filter_parameters.any? { column.downcase.include?(it.downcase) }

      def filter_parameters
        @filter_parameters ||= begin
          code = read("config/initializers/filter_parameter_logging.rb").gsub(/(^|[ \t])#[^\r\n]*/, "\\1")
          lists = code.scan(/filter_parameters\s*(?:\+=|=|\.concat\(|\.push\(|<<)\s*(%[iw]\[[^\]]*\]|\[[^\]]*\]|:\w+|"[^"]*"|'[^']*')/m).flatten
          lists.flat_map { |list| list.start_with?("%") ? list[3..-2].split : list.scan(/:(\w+)|"([^"]*)"|'([^']*)'/).flatten.compact }.reject(&:empty?)
        end
      end

      def schema_summary
        filtered = schema_columns.select { it.match?(SECRET) && filtered?(it) }
        contact = schema_columns.select { it.match?(CONTACT) && !filtered?(it) }
        [
          ("already masked by filter_parameters: #{filtered.join(", ")}" if filtered.any?),
          ("personal details operators usually need (add any they shouldn't see): #{contact.join(", ")}" if contact.any?)
        ].compact.join("\n  ").presence || "no secrets found"
      end

      # What app/admin registers, read statically so the generator runs before the app boots.
      def registrations
        @registrations ||= Dir[File.join(destination_root, "app/admin/**/*.rb")].sort.flat_map do |path|
          next [] if path.end_with?("/#{MENU.split("/").last}")

          # Each registration runs from its own `ActiveAdmin.register` to the next, so a file can hold several.
          File.read(path).split(/(?=^[ \t]*ActiveAdmin\.register)/).filter_map { registration(it) }
        end.uniq
      end

      REGISTRATION = /\A\s*ActiveAdmin\.register(_page)?\s*\(?\s*(?:["']([^"']+)["']|([A-Z][\w:]*))/
      REQUIRED_PARENT = /^\s*belongs_to\s+:\w+(?![^\r\n]*optional:\s*true)/

      def registration(chunk)
        match = chunk.match(REGISTRATION) or return
        page, title, model = match.captures
        call = chunk[/\A.*?(?:\bdo\b|\{)/m] || chunk
        name = call[/\bas:\s*["']([^"']+)["']/, 1] || title || model
        key = name.gsub("::", "/").tr(" ", "_").underscore.tr("/", "_")
        {kind: page ? :page : :resource, key: page ? key : key.pluralize, nested: !page && chunk.match?(REQUIRED_PARENT)}
      end

      def menu_resources = registrations.select { it[:kind] == :resource && !it[:nested] }.map { it[:key] }

      def menu_pages = registrations.select { it[:kind] == :page }.map { it[:key] }

      def nested_resources = registrations.select { it[:nested] }.map { it[:key] }

      def authorization_gem
        @authorization_gem ||= ADAPTERS.keys.find do |name|
          read("Gemfile.lock").match?(/^ {4}#{name} \(/) || read("Gemfile").match?(/^\s*gem ["']#{name}["']/)
        end
      end

      def adapter = ADAPTERS[authorization_gem]

      def docs = DOCS

      def exist?(path) = File.exist?(File.join(destination_root, path))

      def read(path) = exist?(path) ? File.read(File.join(destination_root, path)) : ""

      def active_admin_config = read("config/initializers/active_admin.rb")

      # `--namespace`, else the name ActiveAdmin's initializer assigns, else ActiveAdmin's default. Nil when that
      # assignment is the root namespace (false or nil) or isn't a plain name, so nothing guesses one.
      def namespace_name
        return options[:namespace] if options[:namespace].present?

        aa_namespace[:name]
      end

      NAME = /\A(?::(?:"(\w+)"|'(\w+)'|(\w+))|"(\w+)"|'(\w+)')\z/

      def aa_namespace = @aa_namespace ||= read_aa_namespace

      # More than one assignment (say, per environment) means the right one can't be told statically.
      def read_aa_namespace
        found = active_admin_config.scan(/^[ \t]*config\.default_namespace[ \t]*=[ \t]*([^#\r\n]+?)[ \t]*(?:#[^\r\n]*)?\r?$/).flatten.uniq
        return {raw: found.join(" and "), name: nil} if found.size > 1

        raw = found.first
        {raw:, name: raw ? raw.match(NAME)&.captures&.compact&.first : "admin"}
      end

      def uncommented(code) = code.gsub(/(^|[ \t])#[^\r\n]*/, "\\1")

      def masked_line
        return "# config.masked_attributes = [:api_key, /token/]" if @masked.empty?

        "config.masked_attributes = %i[#{@masked.join(" ")}]"
      end

      def ui_line
        case @ui
        when "admins" then "config.ui.available = ->(user) { user.try(:admin?) } # TODO(setup): who may switch to the new admin"
        when "everyone" then "config.ui.available = ->(_user) { true }"
        else "# config.ui.available = ->(user) { user.admin? }"
        end
      end

      # A released gem carries the client (vendor/client); a git checkout has the source to build it from instead.
      def client_step
        return "4. The gem ships a prebuilt client, so there's nothing to build." if packaged_client?

        "4. Build the client (Node.js 24 and pnpm): bin/rails reactiveadmin:client:build"
      end

      def ui_step
        return "Then set `config.ui.available` and add `reactiveadmin_ui_toggle` to your dashboard." if @ui == "nobody" || @kept_initializer

        "People switch from the dashboard's panel; `config.ui.available` decides who sees it."
      end

      def packaged_client? = File.exist?(File.expand_path("../../../../vendor/client/manifest.json", __dir__))

      def exposure_step
        return <<~TEXT.chomp if @kept_initializer
          1. Check exposure: #{@kept_initializer} was kept as it is. Set `config.expose = :listed` there unless you mean
             to serve every registration (`:all` is the default).
        TEXT

        case @preset
        when "quick" then <<~TEXT.chomp
          1. Exposure: everything ActiveAdmin registers is served (`config.expose = :all`). To choose instead, set
             `:listed` and place resources in `ReactiveAdmin.menu` (app/admin/menu.rb).
        TEXT
        when "strict" then <<~TEXT.chomp
          1. Expose resources: only the dashboard (the namespace's root page) and anything marked
             `reactive { expose true }` or placed by a menu hint is served yet. Uncomment what else the API should
             serve in #{MENU}, then work through the TODO(setup) notes in the initializer, yourself or with an agent.
        TEXT
        else <<~TEXT.chomp
          1. Prune #{MENU}: it lists every registration, and the API serves only what stays. Then work through
             the TODO(setup) notes in the initializer, yourself or with an agent.
        TEXT
        end
      end
    end
  end
end
