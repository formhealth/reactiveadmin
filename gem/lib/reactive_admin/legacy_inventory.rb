require "yaml"
require "json"

module ReactiveAdmin
  # Everything the new admin still leans on classic ActiveAdmin for, as a checklist that can shrink:
  # custom views behind the ladder, classic-only actions and forms, degradations, html-heavy views,
  # skipped filters and classic menu links. Items name resources, actions and structural paths,
  # never record values. `api` guard declarations and menu overlay links are decisions, so they are not listed.
  # `rake reactiveadmin:legacy` prints it and holds it to a baseline.
  class LegacyInventory
    VERSION = 1
    IMPACTS = %w[high med low].freeze
    HTML_THRESHOLD = 0.10
    MIN_HTML_LEAVES = 2

    # category => [label, suggested WP]
    CATEGORIES = {
      "view_unsupported" => ["Views answering 501 (classic only)", nil],
      "view_iframe" => ["Views in an iframe", nil],
      "view_frame" => ["Views in a frame", nil],
      "view_custom" => ["Views rendered by a host component", nil],
      "action_unsupported" => ["Classic-only actions and links", "S7"],
      "form_not_submittable" => ["Forms that cannot be submitted", "S7"],
      "degradation" => ["Degradations", nil],
      "html_heavy" => ["Html-heavy views", "L1"],
      "filter_skipped" => ["Filters with no inferable control", "S5"],
      "typeahead_scan_capped" => ["Scan-capped typeaheads", nil],
      "menu_link" => ["Menu items linking to classic", "MENU"],
      "not_exposed" => ["Permitted but not exposed", nil],
      "nested_no_entry" => ["Nested resources without an entry point", nil]
    }.freeze

    DEGRADATION_WP = {"sidebar_dropped" => "S5", "sidebar_failed" => "S5"}.freeze
    IGNORED_DIAGNOSTICS = %w[implicit_view form_unsupported form_partial html_unmapped_tag unknown_layout_class inline_style_ignored].freeze
    DEGRADATION_IMPACT = {"page_iframe_fallback" => "low", "form_field_html" => "high"}.freeze
    # Already reported as a view or a form that cannot be submitted.
    COVERED_KINDS = %w[page_frame form_partial form_unsupported].freeze
    FORM_REASON = /several forms|raw form controls|form builder call|markup beyond simple wrappers|forms render as frame nodes/
    RECORD_ID = %r{/(?:\d+|\h{8}-\h{4}-\h{4}-\h{4}-\h{12})(?=/|\z)}

    Item = Data.define(:category, :key, :item, :mode, :reason, :impact, :fix, :wp) do
      def id = [category, key, item].join("|")

      def to_h = super.merge(id:)
    end

    def self.run(**) = new(**).run

    # user: who to sample as (defaults to config.doctor_user); without one only declarations are read.
    def initialize(user: nil, sample: true, html_threshold: HTML_THRESHOLD)
      @user = user || ReactiveAdmin.config.doctor_user&.call
      @sample = sample && !@user.nil?
      @html_threshold = html_threshold
    end

    attr_reader :sampled

    # What changed against a baseline written by `.baseline`: new items and the cleared ones.
    def self.compare(items, baseline)
      before = baseline.fetch("items", {})
      current = items.to_h { [it.id, it.impact] }
      {new: items.reject { before.key?(it.id) }, cleared: (before.keys - current.keys).sort.map { |id| cleared(id, before[id]) }}
    end

    def self.cleared(id, impact)
      category, key, item = id.split("|", 3)
      {id:, category:, key:, item:, impact:}
    end

    def self.baseline(items)
      {"version" => VERSION, "summary" => items.group_by(&:category).transform_values(&:size).sort.to_h,
       "items" => items.sort_by(&:id).to_h { [it.id, it.impact] }}
    end

    def self.category_counts(baseline) = baseline.fetch("items", {}).keys.map { it.split("|", 2).first }.tally

    def run
      Rails.application.reload_routes_unless_loaded
      @items = []
      @degradation_kinds = Set.new
      @sampled = @sample
      ActiveRecord::Base.while_preventing_writes { silence { StyleSources.trace { collect } } }
      merged.sort_by { [IMPACTS.index(it.impact), it.key, it.category, it.item] }
    end

    private

    # Repeats of one finding (a kind at many paths) collapse into the first, with a count.
    def merged
      @items.group_by(&:id).values.map do |list|
        (list.size > 1) ? list.first.with(reason: "#{list.first.reason} (+#{list.size - 1} more)") : list.first
      end
    end

    def collect
      report = Doctor.run(user: @user, sample: false)
      report[:resources].each { resource(it) }
      report[:pages].each { page(it) }
      partials
      menu if @sample
      diagnostics
      nested
    end

    def add(category, key, item, impact:, fix:, mode: nil, reason: nil, wp: CATEGORIES.fetch(category).last)
      @items << Item.new(category:, key: key.to_s, item:, mode:, reason: reason&.to_s&.tr("`", "'")&.truncate(160), impact:, fix:, wp:)
    end

    def silence
      stdout = $stdout
      $stdout = StringIO.new
      yield
    ensure
      $stdout = stdout
    end

    def sampler(config) = Doctor::Sample.new(config, @user)

    # A section that raises is the doctor's finding, not this inventory's.
    def fetch(config, action, path_params: {}, query: {})
      sampler(config).call(action, path_params:, query:)
    rescue
      [nil, {}]
    end

    def exposed_resources = Registry.resources.select { Exposure.allowed?(it) && !ApiGuards.fully_denied?(it) }

    def first_record(config) = (config.resource_class.first unless Paths.nested?(config))

    # -- resources ------------------------------------------------------------------------------

    def resource(row)
      config = Registry.find(row[:key]) or return
      key = row[:key]
      row[:actions].each { action(config, key, it) }
      row[:filters][:skipped].each do |name|
        add("filter_skipped", key, "filter #{name}", impact: "med", fix: "declare the filter with `as:` or a collection so a control can be built")
      end
      sample_resource(config, key) if @sample && !Paths.nested?(config)
    end

    def action(config, key, row)
      return unless row[:mode].in?(%w[frame iframe custom])

      decision = Ladder.action(config, row[:name])
      verbs = declared_verbs(config, row[:name])
      view(key, "action #{row[:name]}", decision.mode, decision.reason, write: write?(verbs, decision, texts(config, decision)))
    end

    def declared_verbs(config, name)
      declared = AA.custom_actions(config)
      declaration = declared.find { it.name.to_s == name.to_s }
      Array.wrap(declaration&.http_verb).map(&:to_s)
    end

    def texts(config, decision)
      decision.template ? Ladder.sources_for(config, decision.template).map(&:last) : []
    rescue
      []
    end

    def write?(verbs, decision, texts)
      verbs.any? { it != "get" } || decision.reason.match?(FORM_REASON) ||
        texts.join.then { it.match?(Ladder::FORM_FOR) || it.match?(Ladder::RAW_CONTROLS) }
    end

    VIEW_FIXES = {
      /own JS/ => "port to a custom view (`reactive { render_as :custom, custom_key: }`) or drop the script",
      /several forms/ => "split into one `semantic_form_for` per action",
      /raw form controls/ => "convert the template to `semantic_form_for` (`method: :get` to its own path for a filter form)",
      /markup beyond simple wrappers/ => "keep only simple wrappers around the Formtastic form",
      /form builder call/ => "limit the form block to Formtastic calls (input, inputs, actions)",
      /forms render as frame nodes/ => "move the form to a member or collection action rendered with `semantic_form_for`, or make a filter form `method: :get` to the page's own path",
      /no Formtastic form/ => "raw controls or actions in the template: accept the frame, or rebuild with `semantic_form_for` or action items",
      /template not found/ => "add the template or fix its name",
      /render_as/ => "remove the `render_as` override once the view converts",
      /rendered content is/ => "load the page as the sample user: its content raised or needs a frame"
    }.freeze

    def view(key, item, mode, reason, write:)
      category = (mode == "custom") ? "view_custom" : "view_#{mode}"
      impact = if mode == "custom" then "low"
      elsif write then "high"
      else
        (mode == "iframe") ? "med" : "low"
      end
      fix = view_fix(mode, reason, write)
      add(category, key, item, mode:, reason:, impact:, fix:)
    end

    def view_fix(mode, reason, write)
      return "keep the host component, or convert to typed nodes" if mode == "custom"
      return "convert the template to `semantic_form_for` so it renders natively" if write && reason.to_s.include?("no Formtastic form")

      VIEW_FIXES.find { |pattern, _| reason.to_s.match?(pattern) }&.last || "add `reactive { render_as :native }` once the view is Formtastic-only"
    end

    def sample_resource(config, key)
      record = first_record(config)
      index(config, key)
      show(config, key, record) if record
      form(config, key, record)
      member_native_actions(config, key, record)
    end

    def index(config, key)
      return unless Registry.actions(config).include?(:index)

      status, payload = fetch(config, :index, query: {per_page: 5})
      return unless status == 200

      scan(key, "index", payload)
      html_heavy(key, "index", Doctor::Tally.nodes(payload["rows"].flat_map { [*it["cells"].values, *it["layout"]] }))
    end

    def show(config, key, record)
      return unless Registry.actions(config).include?(:show)

      status, payload = fetch(config, :show, path_params: {id: record.to_param})
      return unless status == 200

      scan(key, "show", payload)
      html_heavy(key, "show", Doctor::Tally.nodes(payload["layout"]))
    end

    def fetch_form(config, record)
      if Registry.actions(config).include?(:new)
        fetch(config, :new, path_params: Paths.parent_params(config, record))
      elsif record && Registry.actions(config).include?(:edit)
        fetch(config, :edit, path_params: {id: record.to_param})
      end
    end

    def form(config, key, record)
      status, payload = fetch_form(config, record)
      return unless status == 200

      scan(key, "form", payload)
      sections = payload.dig("form", "sections") || []
      html_heavy(key, "form", Doctor::Tally.fields(sections))
      not_submittable(key, "form", payload) if payload["submittable"] == false
    end

    def not_submittable(key, item, payload)
      kinds = Array(payload["degraded"]).pluck("kind")
      partial = kinds.include?("form_partial")
      add("form_not_submittable", key, item, mode: partial ? "form partial" : "raw inputs", reason: payload["unsupported_reason"].presence || "the form cannot be submitted faithfully",
        impact: "high", fix: partial ? "replace `form partial:` with a `form do |f|` block of Formtastic inputs" : "replace raw html inputs with Formtastic `f.input` calls")
    end

    # GET template actions the ladder calls native, answered for real: a 501 means classic only.
    def member_native_actions(config, key, record)
      [*config.member_actions.map { [it, true] }, *config.collection_actions.map { [it, false] }].each do |declaration, member|
        name = declaration.name.to_s
        next unless Array.wrap(declaration.http_verb).first.to_s == "get" && Ladder.action(config, name)&.native?
        next if member && record.nil?

        status, payload = fetch(config, name, path_params: (member ? {id: record.to_param} : {}))
        case status
        when 501 then add("view_unsupported", key, "action #{name}", mode: "unsupported", reason: "answers 501: renders no usable Formtastic form",
          impact: "high", fix: "convert the template to `semantic_form_for` (a GET form must target this same action), or `render_as :frame`")
        when 200
          scan(key, "action #{name}", payload)
          not_submittable(key, "action #{name}", payload) if payload["submittable"] == false
        end
      end
    end

    # -- payloads -------------------------------------------------------------------------------

    def scan(key, section, payload)
      Array(payload["degraded"]).each do |entry|
        kind = entry["kind"].to_s
        next if kind.in?(COVERED_KINDS)

        @degradation_kinds << kind
        reason = [entry["where"], entry["reason"]].compact.join(": ")
        add("degradation", key, "#{section}: #{kind}", mode: kind, reason:,
          impact: degradation_impact(kind, "med"), fix: "see the reason; rework the view so the server can represent it", wp: DEGRADATION_WP[kind])
      end
      each_hash(payload) { |hash| unsupported_action(key, section, hash) if hash["supported"] == false && hash.key?("label") && !hash["api_denied"] }
    end

    def degradation_impact(kind, default)
      DEGRADATION_IMPACT.fetch(kind) { kind.start_with?("implicit_") ? "low" : default }
    end

    def each_hash(value, &block)
      case value
      when Array then value.each { each_hash(it, &block) }
      when Hash
        yield value
        value.each_value { each_hash(it, &block) }
      end
    end

    def unsupported_action(key, section, hash)
      verb = hash["method"].to_s.presence || "get"
      path = hash["href"].to_s.split("?").first.to_s.gsub(RECORD_ID, "/:id")
      write = verb != "get"
      add("action_unsupported", key, "#{section}: #{hash["placement"] || "action"} #{verb.upcase} #{path.presence || "(no href)"}", mode: "classic", reason: hash["disabled_reason"],
        impact: write ? "high" : "med",
        fix: write ? "register the target as a member or collection action, or port it to a page action" : "link to a registered resource or page")
    end

    def html_heavy(key, section, tally)
      html = tally[:html].to_i
      total = tally[:typed].to_i + html
      return if html < MIN_HTML_LEAVES || html.fdiv(total) <= @html_threshold

      add("html_heavy", key, section, mode: "html", reason: "#{html} of #{total} leaves are html (#{(html * 100.0 / total).round}%)", impact: "low",
        fix: "replace raw markup with typed nodes (status_tag, attributes_table, panel, toolbar)")
    end

    # -- pages ----------------------------------------------------------------------------------

    def page(row)
      config = Registry.find_page(row[:key]) or return
      mode = row[:mode]
      reason = row[:reason]
      payload = {}
      if @sample && !Paths.nested?(config)
        status, payload = fetch(config, :reactiveadmin_page, query: Doctor.page_query(config))
        payload = {} unless status == 200
        mode = payload.dig("view", "mode") || mode
        reason = "the rendered content is #{mode} (the source reads as #{row[:mode]})" if mode != row[:mode]
      end
      scan("page #{row[:key]}", "page", payload)
      html_heavy("page #{row[:key]}", "page", Doctor::Tally.nodes(payload["layout"])) if payload.key?("layout")
      row[:actions].each { page_action(config, row[:key], it) }
      return if mode.in?(%w[native api])

      view("page #{row[:key]}", "content", mode, reason, write: reason.to_s.match?(FORM_REASON) || page_form?(config) || row[:actions].any? { it[:verb] != "get" })
    end

    def page_form?(config)
      content = Ladder.block_source(AA.page_presenter(config, :index)&.block).to_s
      [content, *Ladder.partial_texts(config, content)].join.then { it.match?(Ladder::FORM_FOR) || it.match?(Ladder::RAW_CONTROLS) }
    rescue
      false
    end

    def page_action(config, key, row)
      return unless row[:mode].in?(%w[frame iframe custom])

      decision = Ladder.action(config, row[:name])
      view("page #{key}", "action #{row[:name]}", decision.mode, decision.reason, write: write?(declared_verbs(config, row[:name]), decision, texts(config, decision)))
    end

    # -- menu, diagnostics, exposure ------------------------------------------------------------

    def menu
      controller = Struct.new(:controller).new(ReactiveAdmin::ManifestController)
      status, payload = fetch(controller, :show)
      return unless status == 200

      links = []
      walk_menu(payload["menu"], [], links, MenuOverlay.links.pluck(:id))
      links.each do |path|
        add("menu_link", "menu", path.join(" > "), mode: "classic", reason: "links to a classic URL", impact: "med",
          fix: "map the URL to a resource or page, or add an overlay entry for it")
      end
    end

    # Overlay links are the host's explicit decision; only links inherited from AA's menu are legacy.
    def walk_menu(nodes, path, links, explicit)
      Array(nodes).each do |node|
        here = [*path, node["label"].to_s]
        links << here if node["kind"] == "link" && node["url"].to_s.start_with?("/") && !node["api_denied"] && explicit.exclude?(node["id"])
        walk_menu(node["children"], here, links, explicit)
      end
    end

    def diagnostics
      entries = ReactiveAdmin.diagnostics.entries
      entries.select { it[:kind] == :exposure_permitted_not_exposed }.flat_map { it[:keys].to_s.split(", ") }.each do |key|
        add("not_exposed", key, "resource or page", mode: "classic", reason: "permitted by the policy but not exposed to the API", impact: "med",
          fix: "place it in the menu overlay or `config.exposed_resources` once its views are ready")
      end
      names = Registry.resources.to_h { [it.resource_name.to_s, Registry.route_key(it)] }
      entries.reject { it[:kind] == :exposure_permitted_not_exposed || it[:kind].to_s.in?(IGNORED_DIAGNOSTICS) || it[:kind].to_s.in?(@degradation_kinds) }
        .group_by { [it[:kind].to_s, (it[:resource] || it[:source] || it[:key] || "menu").to_s] }.each do |(kind, name), entries|
        key = names.fetch(name, name)
        details = entries.map { |entry| entry.except(:kind, :resource).map { |k, v| "#{k}=#{v}" }.join(" ") }.first(3).join("; ")
        if kind == "scan_capped"
          add("typeahead_scan_capped", key, "typeahead scan cap", mode: kind, reason: details, impact: "low",
            fix: "add `reactive { search :column }` on the target resource, or an option source")
        else
          add("degradation", key, "diagnostic: #{kind}", mode: kind, reason: "#{entries.size} occurrence(s): #{details}",
            impact: degradation_impact(kind, "low"), fix: "see the reason in `rake reactiveadmin:doctor FORMAT=json`", wp: DEGRADATION_WP[kind])
        end
      end
    end

    # A `form partial:` is recorded into fields like any form, so only one the form's own
    # `submittable` rejects is listed. Resources sampled in full are covered by their form check.
    def partials
      exposed_resources.each do |config|
        next unless AA.page_presenter(config, :form)&.options&.[](:partial)
        next if @sample && !Paths.nested?(config)

        status, payload = fetch_form(config, first_record(config))
        not_submittable(Registry.route_key(config), "form", payload) if status == 200 && payload["submittable"] == false
      end
    end

    # Resources whose parent has no show page to reach them from.
    def nested
      exposed_resources.each do |config|
        next unless Paths.nested?(config)

        parent = config.belongs_to_config.target
        next if AA.resource?(parent) && Registry.actions(parent).include?(:show)

        add("nested_no_entry", Registry.route_key(config), "nested under #{parent.try(:resource_name) || parent}", impact: "med",
          mode: "nested", reason: "the parent has no show page to link from", fix: "give the parent a show page with a link to the children")
      end
    end

    # Markdown and JSON renderings of an inventory, with trends against a baseline.
    class Report
      def initialize(items, sampled:, baseline: nil, generated_at: nil)
        @items = items
        @sampled = sampled
        @baseline = baseline
        @diff = LegacyInventory.compare(items, baseline) if baseline
        @generated_at = generated_at
      end

      attr_reader :items

      def new_items = @diff ? @diff[:new] : []

      def cleared = @diff ? @diff[:cleared] : []

      def summary
        before = @baseline && LegacyInventory.category_counts(@baseline)
        categories = CATEGORIES.keys.filter_map do |category|
          mine = items.select { it.category == category }
          next if mine.empty? && !before&.key?(category)

          [category, IMPACTS.to_h { |impact| [impact, mine.count { it.impact == impact }] }.merge("total" => mine.size, "trend" => trend(mine.size, before&.fetch(category, 0)))]
        end
        {total: items.size, impact: IMPACTS.to_h { |impact| [impact, items.count { it.impact == impact }] }, categories: categories.to_h,
         new: new_items.size, cleared: cleared.size}
      end

      def to_h
        {version: VERSION, generated_at: @generated_at || Time.current.iso8601, sampled: @sampled, summary:, items: items.map(&:to_h),
         new: new_items.map(&:id), cleared: cleared.pluck(:id)}
      end

      def to_json(*) = JSON.pretty_generate(to_h)

      def to_markdown
        [header, table, *IMPACTS.filter_map { checklist(it) }, cleared_section].compact.join("\n\n") + "\n"
      end

      private

      def trend(now, before)
        return "n/a" if before.nil?

        case now <=> before
        when 1 then "▲ +#{now - before}"
        when -1 then "▼ -#{before - now}"
        else "="
        end
      end

      def header
        s = summary
        counts = IMPACTS.map { "#{s[:impact][it]} #{it}" }.join(", ")
        ["# Legacy inventory",
          "Everything the new admin still relies on classic ActiveAdmin for#{" (static: no sample user)" unless @sampled}. " \
          "Regenerate with `rake reactiveadmin:legacy`; tick items off by fixing them, not by editing this file.",
          "**#{s[:total]} open** (#{counts})#{", #{s[:new]} new, #{s[:cleared]} cleared since the baseline" if @baseline}."].join("\n\n")
      end

      def table
        rows = summary[:categories].map do |category, c|
          "| #{CATEGORIES.fetch(category).first} (`#{category}`) | #{c["total"]} | #{c["high"]} | #{c["med"]} | #{c["low"]} | #{c["trend"]} |"
        end
        ["## Summary", "| Category | Open | High | Med | Low | Trend |", "| --- | ---: | ---: | ---: | ---: | --- |", *rows].join("\n")
      end

      def checklist(impact)
        mine = items.select { it.impact == impact }
        return if mine.empty?

        title = {"high" => "High impact", "med" => "Medium impact", "low" => "Low impact"}.fetch(impact)
        groups = mine.group_by(&:key).sort.map do |key, list|
          ["### #{key}", *list.sort_by { [it.category, it.item] }.map { bullet(it) }].join("\n")
        end
        ["## #{title} (#{mine.size})", *groups].join("\n\n")
      end

      def bullet(item)
        detail = [item.reason&.then { "`#{it}`." }, ("Fix: #{item.fix}." if item.fix), ("[#{item.wp}]" if item.wp)].compact.join(" ")
        "- [ ] `#{item.category}` #{item.item}#{" (#{item.mode})" if item.mode}: #{detail}"
      end

      def cleared_section
        return unless @baseline

        lines = cleared.map { "- [x] `#{it[:category]}` #{it[:key]}: #{it[:item]} (#{it[:impact]})" }
        ["## Recently cleared", lines.presence&.join("\n") || "Nothing cleared since the baseline."].join("\n\n")
      end
    end

    # The rake task's driver; options come from the environment so they pass through `rake`.
    module CLI
      HEADER = "# Legacy inventory baseline: every item is already known; new ones fail the ratchet.\n" \
        "# Regenerate on purpose with WRITE_BASELINE=path bundle exec rake reactiveadmin:legacy\n".freeze

      module_function

      # Number of new legacy items against BASELINE; 0 without one.
      def run(env = ENV, out: $stdout)
        inventory = LegacyInventory.new(sample: env["SAMPLE"] != "0", html_threshold: Float(env.fetch("HTML_THRESHOLD", HTML_THRESHOLD)))
        items = inventory.run
        baseline = YAML.safe_load_file(env["BASELINE"]) if env["BASELINE"].present?
        report = Report.new(items, sampled: inventory.sampled, baseline:)
        text = (env["FORMAT"] == "json") ? report.to_json : report.to_markdown
        emit(text, env["OUT"], report, out)
        write_baseline(items, env["WRITE_BASELINE"], out)
        report.new_items.each { out.puts("new legacy item: #{it.id}") }
        report.new_items.size
      end

      def emit(text, path, report, out)
        return out.puts(text) unless path.present?

        File.write(path, text)
        s = report.summary
        out.puts("legacy inventory written to #{path}: #{s[:total]} open (#{IMPACTS.map { "#{s[:impact][it]} #{it}" }.join(", ")})")
      end

      def write_baseline(items, path, out)
        return unless path.present?

        File.write(path, HEADER + LegacyInventory.baseline(items).to_yaml)
        out.puts("baseline written to #{path}")
      end
    end
  end
end
