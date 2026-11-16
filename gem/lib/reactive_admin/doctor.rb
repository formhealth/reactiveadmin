require "action_controller/test_case"
require "yaml"
require "json"

module ReactiveAdmin
  # Coverage report behind `rake reactiveadmin:doctor`: how much of the admin the typed API covers
  # and where it degrades, per resource, action and page. Samples one page of rows and one record
  # per resource, read-only. Output names resources, sources and counts, never record data.
  class Doctor
    MODES = %w[native frame iframe custom api].freeze
    SECTIONS = %i[index show form].freeze
    BASELINE_VERSION = 1
    DEFAULT_THRESHOLD = 0.5

    # Runs an API action of a controller for real, as the given user: callbacks, `controller do`
    # overrides and authorization all apply. Marked internal, so hosts keep it out of
    # their view audits; the run as a whole is wrapped in while_preventing_writes.
    class Sample
      HOST = "doctor.invalid".freeze

      def initialize(config, user)
        @config = config
        @user = user
      end

      # [status, parsed json]; failures are the API's own JSON errors.
      def call(action, path_params: {}, query: {})
        controller = @config.controller.new
        bind_user(controller)
        response = ActionDispatch::TestResponse.new
        controller.dispatch(action, request(action, path_params, query), response)
        [response.status, JSON.parse(response.body)]
      rescue JSON::ParserError
        [response.status, {}]
      ensure
        ActiveSupport::CurrentAttributes.clear_all
      end

      # Only the parts a view needs, for payloads built outside a request (filters). It belongs to
      # the controller, as the user does, so AA's procs reach the helpers they would in a request.
      def view
        @view ||= begin
          controller = @config.controller.new
          bind_user(controller)
          controller.request = request("index", {}, {})
          controller.response = ActionDispatch::TestResponse.new
          controller.view_context
        end
      end

      def controller = view.controller

      private

      def bind_user(controller)
        method = AA.current_user_method(Registry.namespace)
        user = @user
        controller.define_singleton_method(method) { user } if method
      end

      def request(action, path_params, query)
        env = {"HTTP_HOST" => HOST, "PATH_INFO" => "/", "QUERY_STRING" => query.to_query,
               BackgroundRequests::INTERNAL_ENV => true, "rack.input" => StringIO.new}
        ActionDispatch::TestRequest.create(env).tap do |request|
          request.session = ActionController::TestSession.new
          request.path_parameters = {controller: @config.controller.controller_path, action: action.to_s, format: "reactiveadmin", **path_params}
        end
      end
    end

    # Typed versus html leaves of a payload's nodes or fields.
    module Tally
      CONTAINERS = %w[group box panel attributes_table table tabs tab columns column].freeze

      module_function

      def nodes(value, tally = {typed: 0, html: 0})
        case value
        when Array then value.each { nodes(it, tally) }
        when Hash
          type = value["type"] || value[:type]
          if type
            leaf(type, tally) unless CONTAINERS.include?(type)
            nodes(value.reject { |key, _| %w[type action ref].include?(key.to_s) }.values, tally)
          else
            nodes(value.values, tally)
          end
        end
        tally
      end

      def fields(sections, tally = {typed: 0, html: 0})
        sections.each do |section|
          [*section["fields"], *section["template_fields"], *Array(section["records"]).flat_map { it["fields"] }].each do |field|
            case field["control"]
            when "html" then tally[:html] += 1
            when "content" then nodes(field["layout"], tally)
            else tally[:typed] += 1
            end
          end
        end
        tally
      end

      def leaf(type, tally)
        return if %w[empty].include?(type)

        %w[html frame iframe].include?(type) ? tally[:html] += 1 : tally[:typed] += 1
      end
    end

    SampleFailed = Class.new(StandardError)

    def self.run(**) = new(**).run

    # What `doctor_page_params` gives the page to render with; pages that read required params need it.
    def self.page_query(config) = ReactiveAdmin.config.doctor_page_params&.call(config.underscored_resource_name) || {}

    # Options: user: (who to sample as; without one only the static parts run), sample: false for static only.
    def initialize(user: nil, sample: true)
      @user = user || ReactiveAdmin.config.doctor_user&.call
      @sample = sample && !@user.nil?
    end

    def run
      Rails.application.reload_routes_unless_loaded
      ReactiveAdmin.diagnostics.clear
      report = ApiGuards.with_channel(:session) { ActiveRecord::Base.while_preventing_writes { silence { StyleSources.trace { build } } } }
      [*Exposure.audit(user: @user), *ApiGuards.audit, *self.class.config_warnings].each { ReactiveAdmin.diagnostics.record(it[:kind], **it.except(:kind)) }
      report.merge(api_guards: ApiGuards.accepted, menu_links: MenuOverlay.links, diagnostics: ReactiveAdmin.diagnostics.entries.map { it.transform_values(&:to_s) })
    end

    # Baseline: what a later run must not do worse than.
    def self.baseline(report)
      {
        "version" => BASELINE_VERSION,
        "summary" => report[:summary].slice(:ladder_fallback_pct, :html_node_pct, :failures).transform_keys(&:to_s),
        "actions" => report[:resources].flat_map { |r| r[:actions].map { |a| ["#{r[:key]}##{a[:name]}", a[:mode]] } }.to_h,
        "pages" => report[:pages].to_h { [it[:key], it[:mode]] },
        "failures" => failures(report)
      }
    end

    def self.failures(report)
      [*report[:resources].flat_map { |r| r[:failures].map { |section| "#{r[:key]}: #{section}" } },
        *report[:pages].filter_map { "page #{it[:key]}: render" if it[:failure] }].sort
    end

    # Regressions against a baseline: a mode downgrade, a new failure, or a fallback share that grew.
    def self.compare(report, baseline, threshold: DEFAULT_THRESHOLD)
      issues = []
      current = baseline(report)
      %w[actions pages].each do |kind|
        baseline.fetch(kind, {}).each do |name, before|
          now = current[kind][name] or next
          issues << "#{kind.chomp("s")} #{name}: #{before} -> #{now}" if rank(now) > rank(before)
        end
      end
      (current["failures"] - baseline.fetch("failures", [])).each { issues << "new failure #{it}" }
      %w[ladder_fallback_pct html_node_pct].each do |key|
        before = baseline.dig("summary", key)
        now = current["summary"][key]
        issues << "#{key} #{before} -> #{now}" if before && now && now - before > threshold
      end
      issues
    end

    def self.rank(mode) = Ladder::RANK.fetch(mode.to_s, 0)

    CONFIG_KINDS = %w[expose_all null_cache_store].freeze

    # Gem defaults that are permissive, or protections that silently do nothing in this environment.
    def self.config_warnings
      [
        ({kind: :expose_all, reason: "expose = :all serves every resource and page the policy permits; set :listed and name what is served"} if ReactiveAdmin.config.expose == :all && !Rails.env.local?),
        ({kind: :null_cache_store, reason: "Rails.cache is a null store: rate limits and the meta cache are disabled"} if Rails.cache.is_a?(ActiveSupport::Cache::NullStore))
      ].compact
    end

    # Where an error came from in the host's own code; its message may carry record data.
    def self.location(error)
      trace = error.backtrace.to_a
      (trace.find { it.start_with?(Rails.root.to_s) } || trace.first).to_s.delete_prefix("#{Rails.root}/")
    end

    private

    def build
      resources = Registry.resources.select { Exposure.allowed?(it) && !ApiGuards.fully_denied?(it) }.map { resource(it) }
      pages = Registry.pages.select { Exposure.allowed?(it) && !ApiGuards.fully_denied?(it) }.map { page(it) }
      {generated_at: Time.current.iso8601, sampled: @sample, summary: summary(resources, pages), resources:, pages:}
    end

    def silence
      stdout = $stdout
      $stdout = StringIO.new
      yield
    ensure
      $stdout = stdout
    end

    def resource(config)
      row = {key: Registry.route_key(config), actions: actions(config), failures: []}
      meta = guard(row, "filters") { filters(config) }
      row[:filters] = meta || {total: 0, built: 0, by_control: {}, skipped: []}
      row[:sources] = sources(config)
      row[:implicit_view] = implicit_view(config, row[:key])
      SECTIONS.each { |section| row[section] = sample(config, section, row) } if @sample
      row[:index_options] = IndexOptions.declared(config).merge(row.dig(:index, :options) || {})
      row
    end

    # Sections that fall back to default columns, with what secure defaults leave out of them.
    def implicit_view(config, key)
      ImplicitDefaults.audit(config).tap do |sections|
        sections.each { |view, hidden| ReactiveAdmin.diagnostics.record(:implicit_view, resource: key, view:, hidden: hidden.join(", ")) if hidden.any? }
      end
    end

    def sources(config)
      SECTIONS.to_h do |section|
        block = AA.page_presenter(config, (section == :form) ? :form : section)&.block
        [section, block&.source_location&.then { "#{it[0].delete_prefix("#{Rails.root}/")}:#{it[1]}" }]
      end.compact
    end

    def filters(config)
      return {total: 0, built: 0, by_control: {}, skipped: []} unless AA.filters_enabled?(config)

      built = Filters.new(config, Sample.new(config, @user).view).call
      {total: AA.filters(config).size, built: built.size, by_control: built.pluck(:control).tally,
       skipped: AA.filters(config).keys.map(&:to_s) - built.pluck(:name)}
    end

    def actions(config)
      declared = [*config.member_actions.map { [it, :member] }, *config.collection_actions.map { [it, :collection] }]
      declared.reject { |declaration, _| ApiGuards.denies?(config, declaration.name, verb: Array.wrap(declaration.http_verb).first) }.map do |declaration, kind|
        name = declaration.name.to_s
        verb = Array.wrap(declaration.http_verb).first.to_s
        decision = Ladder.action(config, name) if verb == "get"
        {name:, kind: kind.to_s, verb:, mode: decision&.mode || "api", reason: decision&.reason || "runs through the API"}
      end
    end

    def page(config)
      decision = Ladder.page(config)
      key = config.underscored_resource_name
      row = {key:, mode: decision.mode, reason: decision.reason, actions: page_actions(config)}
      return row unless @sample && !Paths.nested?(config)

      rendered = render_page(config)
      return row.merge(failure: rendered[:failure]) if rendered[:failure]

      reason = (rendered[:mode] == decision.mode) ? decision.reason : "the rendered content is #{rendered[:mode]} (the source reads as #{decision.mode})"
      row.merge(mode: rendered[:mode], reason:, nodes: rendered[:nodes])
    end

    def page_actions(config)
      config.page_actions.reject { ApiGuards.denies?(config, it.name, verb: Array.wrap(it.http_verb).first) }.map do |declaration|
        name = declaration.name.to_s
        verb = Array.wrap(declaration.http_verb).first.to_s
        decision = Ladder.action(config, name) if verb == "get"
        {name:, verb:, mode: decision&.mode || "api", reason: decision&.reason || "runs through the API"}
      end
    end

    def render_page(config)
      status, payload = Sample.new(config, @user).call(:reactiveadmin_page, query: self.class.page_query(config))
      return {failure: failure(status, payload)} unless status == 200

      {mode: payload.dig("view", "mode"), nodes: Tally.nodes(payload["layout"])}
    end

    def failure(status, payload) = "#{status} #{payload["code"]}: #{payload["message"]}"

    # One page of rows, one record's show page, the new form (and edit when there is a record).
    def sample(config, section, row)
      action = (section == :form) ? :new : section
      return unless Registry.actions(config).include?(action)
      return {skipped: "nested under a parent"} if Paths.nested?(config) || !Registry.top_level_actions(config).include?(action)
      return {skipped: "api guard"} if ApiGuards.denies?(config, action)

      guard(row, section.to_s) { send(:"sample_#{section}", config) }
    end

    def sample_index(config)
      payload = fetch(config, :index, query: {per_page: 5})
      Tally.nodes(payload["rows"].flat_map { [*it["cells"].values, *it["layout"]] })
        .merge(rows: payload["rows"].size, columns: payload["columns"].size, options: IndexOptions.sampled(payload))
    end

    def sample_show(config)
      record = config.resource_class.first or return {typed: 0, html: 0, rows: 0}
      Tally.nodes(fetch(config, :show, path_params: {id: record.to_param})["layout"]).merge(rows: 1)
    end

    def sample_form(config)
      Tally.fields(fetch(config, :new, path_params: Paths.parent_params(config, config.resource_class.first))["form"]["sections"])
    end

    def fetch(config, action, path_params: {}, query: {})
      status, payload = Sample.new(config, @user).call(action, path_params:, query:)
      raise SampleFailed, failure(status, payload) unless status == 200

      payload
    end

    # A section that raises is a finding, not the end of the run.
    def guard(row, section)
      yield
    rescue => e
      row[:failures] << (e.is_a?(SampleFailed) ? "#{section} #{e.message}" : "#{section} #{e.class} at #{self.class.location(e)}")
      nil
    end

    def summary(resources, pages)
      actions = resources.flat_map { it[:actions] }
      views = [*actions.map { it[:mode] }.reject { it == "api" }, *pages.map { it[:mode] }]
      counts = views.tally
      typed = SECTIONS.to_h { |section| [section, aggregate(resources.filter_map { it[section] })] }
      all = aggregate(typed.values)
      filters = resources.map { it[:filters] }
      {
        resources: resources.size, pages: pages.size,
        actions: MODES.to_h { |mode| [mode.to_sym, actions.count { |action| action[:mode] == mode }] },
        views: MODES.first(4).to_h { |mode| [mode.to_sym, counts.fetch(mode, 0)] },
        pages_by_mode: pages.map { it[:mode] }.tally,
        ladder_fallback_pct: percent(counts.fetch("frame", 0) + counts.fetch("iframe", 0), views.size),
        typed:, html_node_pct: percent(all[:html], all[:typed] + all[:html]),
        filters: {total: filters.sum { it[:total] }, built: filters.sum { it[:built] }, skipped: filters.sum { it[:skipped].size },
                  by_control: filters.flat_map { it[:by_control].to_a }.each_with_object(Hash.new(0)) { |(k, v), h| h[k] += v }},
        index_options: resources.flat_map { it[:index_options].to_a }.each_with_object(Hash.new(0)) { |(k, _), h| h[k] += 1 },
        failures: self.class.failures({resources:, pages:}).size
      }
    end

    def aggregate(tallies) = {typed: tallies.sum { it[:typed].to_i }, html: tallies.sum { it[:html].to_i }}

    def percent(part, whole) = whole.zero? ? 0.0 : (part * 100.0 / whole).round(1)

    # Text rendering of a report.
    class Table
      def initialize(report)
        @report = report
      end

      def to_s
        [summary, ladder, resources, api_guards, menu_links, failures, warnings].compact.join("\n\n")
      end

      private

      attr_reader :report

      def summary
        s = report[:summary]
        lines = ["reactiveadmin doctor#{" (static: no sample user)" unless report[:sampled]}",
          "  resources #{s[:resources]}, pages #{s[:pages]}, filters #{s[:filters][:built]}/#{s[:filters][:total]} built (#{s[:filters][:skipped]} skipped)",
          "  actions: #{s[:actions].map { |k, v| "#{k} #{v}" }.join(", ")}",
          "  views (actions with a view + pages): #{s[:views].map { |k, v| "#{k} #{v}" }.join(", ")}; fallback #{s[:ladder_fallback_pct]}%",
          "  typed vs html leaves: #{s[:typed].map { |k, v| "#{k} #{v[:typed]}/#{v[:typed] + v[:html]}" }.join(", ")}; html #{s[:html_node_pct]}%",
          ("  index options (resources using each): #{s[:index_options].map { |k, v| "#{k} #{v}" }.join(", ")}" if s[:index_options].any?),
          "  failures #{s[:failures]}, diagnostics #{report[:diagnostics].size}"].compact
        lines.join("\n")
      end

      def ladder
        rows = report[:resources].flat_map { |r| r[:actions].reject { it[:mode].in?(%w[api native]) }.map { |a| ["#{r[:key]}##{a[:name]}", a[:mode], a[:reason]] } }
        rows += report[:pages].reject { it[:mode] == "native" }.map { |p| ["page #{p[:key]}", p[:mode], p[:reason]] }
        return if rows.empty?

        width = rows.map { it[0].size }.max
        "Fallback views\n" + rows.sort.map { |name, mode, reason| "  #{name.ljust(width)}  #{mode.ljust(6)}  #{reason}" }.join("\n")
      end

      def resources
        rows = report[:resources].filter_map do |r|
          html = SECTIONS.filter_map { |section| (r[section] || {}).then { |t| "#{section} #{t[:html]}" if t[:html].to_i.positive? } }
          skipped = r[:filters][:skipped]
          next if html.empty? && skipped.empty?

          "  #{r[:key]}: #{[*html.map { "#{it} html" }, ("filters skipped #{skipped.join(", ")}" if skipped.any?)].compact.join("; ")}"
        end
        ("Html leaves and skipped filters\n#{rows.join("\n")}" if rows.any?)
      end

      # Decisions, not findings: nothing here counts against coverage.
      def api_guards
        rows = report[:api_guards].to_a.map do |d|
          scope = [("only #{d[:only].join(", ")}" if d[:only]), ("except #{d[:except].join(", ")}" if d[:except]), ("attributes #{d[:attributes].join(", ")}" if d[:attributes])].compact
          "  #{d[:kind]} #{d[:key]}: #{d[:guard]} #{scope.join("; ").presence || "all"}#{" (#{d[:reason]})" if d[:reason]}"
        end
        ("API guards (accepted)\n#{rows.join("\n")}" if rows.any?)
      end

      def menu_links
        rows = report[:menu_links].to_a.map { "  #{it[:path].join(" > ")}: #{it[:url] || "computed"}" }
        ("Menu links (accepted)\n#{rows.join("\n")}" if rows.any?)
      end

      def warnings
        list = report[:diagnostics].select { it[:kind].in?(CONFIG_KINDS) }
        ("Configuration warnings\n#{list.map { "  #{it[:reason]}" }.join("\n")}" if list.any?)
      end

      def failures
        list = Doctor.failures(report)
        ("Failures\n#{list.map { "  #{it}" }.join("\n")}" if list.any?)
      end
    end

    # The rake task's driver: options come from the environment so they pass through `rake`.
    module CLI
      module_function

      def run(env = ENV, out: $stdout)
        report = Doctor.run(sample: env["SAMPLE"] != "0")
        out.puts((env["FORMAT"] == "json") ? JSON.pretty_generate(report) : Table.new(report))
        write_baseline(report, env["WRITE_BASELINE"], out)
        regressions(report, env, out)
      end

      def write_baseline(report, path, out)
        return unless path.present?

        File.write(path, Doctor.baseline(report).to_yaml)
        out.puts("baseline written to #{path}")
      end

      # Number of problems: regressions against the baseline, plus a fallback share above MAX_FALLBACK.
      def regressions(report, env, out)
        issues = []
        if env["BASELINE"].present?
          baseline = YAML.safe_load_file(env["BASELINE"])
          issues += Doctor.compare(report, baseline, threshold: Float(env.fetch("THRESHOLD", DEFAULT_THRESHOLD)))
        end
        max = env["MAX_FALLBACK"]
        issues << "fallback #{report[:summary][:ladder_fallback_pct]}% exceeds #{max}%" if max.present? && report[:summary][:ladder_fallback_pct] > Float(max)
        issues.each { out.puts("regression: #{it}") }
        issues.size
      end
    end
  end
end
