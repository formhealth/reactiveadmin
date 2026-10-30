module ReactiveAdmin
  # Decides how a custom view reaches the client, best first: native (a typed FormResponse) >
  # frame (layout-less html over the wire) > iframe (the page needs its own JS) > custom (a host
  # React component). Decisions come from the view source, so they are cheap and need no request;
  # `reactive { render_as ... }` overrides them.
  module Ladder
    MODES = %w[native frame iframe custom].freeze
    RANK = {"native" => 0, "custom" => 0, "frame" => 1, "iframe" => 2}.freeze
    DIALOG_FIELDS = 6

    SCRIPT = /<script\b|<iframe\b|\bjavascript_(?:tag|include_tag|pack_tag)\b|data-controller|data:\s*\{[^}]*\bcontroller:|\sremote:\s*true|href=["']javascript:|[\s,{(]on(?:click|change|submit|input|focus|blur|load|key\w+|mouse\w+)\s*(?:=|:|=>)/i
    RAW_CONTROLS = /<(?:form|input|select|textarea|button|fieldset)\b|\b(?:form_tag|form_with|submit_tag|select_tag|label_tag|\w+_field_tag|\w+_box_tag|collection_select|radio_button_tag)\b|(?<!\w)form_for\b/
    # Controls that act (a single-button form, a rails-ujs link) become typed action nodes, which map to the API
    # per route at render time and are listed as unavailable when they don't.
    ACTION_CONTROLS = /\bbutton_to\b|link_to[^\n]*(?:method:|confirm)/
    FORM_FOR = /\b(?:semantic_form_for|active_admin_form_for)\b/
    GET_FORM = /\bmethod(?::|\s*=>)\s*(?::get\b|["']get["'])/
    SIMPLE_TAGS = %w[h1 h2 h3 h4 h5 h6 p div span br hr a strong em b i small ul ol li section table thead tbody tfoot tr th td caption].freeze
    BUILDER_METHODS = %w[input inputs semantic_fields_for actions action submit commit_action_with_cancel_link cancel_link semantic_errors object].freeze
    RENDER = /\brender\s*\(?\s*(?<kind>partial:\s*|template:\s*|action:\s*)?(?::(?<sym>\w+)|["'](?<name>[\w\/-]+)["'])/

    # `wide`: the template shows more than a form (further forms, actions, tables), which needs a page.
    # `read_only`: native without a form; the content is answered as a PageResponse of typed nodes.
    # `get_form`: a GET form among them (filters over results), read from the query string of the same view.
    Decision = Data.define(:mode, :reason, :template, :custom_key, :fields, :wide, :read_only, :get_form) do
      def initialize(mode:, reason:, template:, custom_key:, fields:, wide: false, read_only: false, get_form: false) = super

      def native? = mode == "native"

      def presentation = (native? && fields <= DIALOG_FIELDS && !wide && !read_only) ? "dialog" : "page"
    end

    module_function

    # An action's decision, or nil when it renders no page (it redirects, sends data or renders json).
    def action(config, name)
      return unless declared?(config, name)

      remember([config, name.to_s]) do
        override = override_for(config, name)
        next custom(override) if override&.fetch(:mode) == "custom"

        template = template_for(config, name)
        overridden(template(config, template), override) if template
      end
    end

    # Member and collection actions of a resource, page actions of a page; AA's own are not views.
    def declared?(config, name)
      AA.custom_actions(config).any? { it.name.to_s == name.to_s }
    end

    def reset!
      @decisions = nil
      @downgraded = nil
    end

    # Templates that failed to record are decided as frames until the next reset.
    def downgrade!(path)
      (@downgraded ||= Set.new) << path.to_s
      @decisions = nil
    end

    # Reading view source is cheap but not free; code only changes with a reload.
    def remember(key)
      return yield if Rails.application.config.enable_reloading

      cache = (@decisions ||= {})
      cache.key?(key) ? cache[key] : (cache[key] = yield)
    end

    # The same for a template named by a render call, e.g. the re-render after a failed write.
    def for_template(config, path)
      override = override_for(config, File.basename(path))
      return custom(override) if override&.fetch(:mode) == "custom"

      overridden(template(config, path), override)
    end

    # Decision for a template (and the partials it renders) given by name, e.g. "approve".
    def template(config, name)
      return Decision.new("frame", "recording failed", name, nil, 0) if @downgraded&.include?(name.to_s)

      sources = sources_for(config, name)
      return Decision.new("frame", "template not found", name, nil, 0) if sources.empty?

      decide(sources.map(&:last), name)
    end

    # The page's `content` block, plus the partials it renders.
    def page(config)
      override = override(config, "*")
      return custom(override) if override&.fetch(:mode) == "custom"

      content = block_source(AA.page_presenter(config, :index)&.block).to_s
      overridden(decide_page([content, *partial_texts(config, content)]), override)
    end

    def script?(text) = SCRIPT.match?(text.to_s)

    # Where a client (or the frame) loads the classic page; iframes get the chrome-free layout.
    def view(config, name, href:)
      decision = action(config, name) or return
      path = case decision.mode
      when "native" then Paths.api(href)
      when "frame" then href
      when "iframe" then embed_url(href)
      end
      {mode: decision.mode, path:, custom_key: decision.custom_key, presentation: decision.presentation}.compact
    end

    # A page's index is always fetched as a PageResponse, whose nodes carry any frames and iframes.
    def page_view(config, href:)
      decision = page(config)
      return {mode: "custom", custom_key: decision.custom_key, presentation: "page"}.compact if decision.mode == "custom"

      {mode: "native", path: Paths.api(page_path(config, href)), presentation: "page"}
    end

    # `/admin/key?x=1` is served as a PageResponse at `/admin/_pages/key?x=1`, under its parent when nested.
    # The key comes from the config because the root page (dashboard) is also reachable at `/admin`.
    def page_path(config, href)
      path, query = href.split("?", 2)
      key = config.underscored_resource_name
      base = path.chomp("/").delete_suffix("/#{key}")
      ["#{base}/_pages/#{key}", query].compact.join("?")
    end

    def embed_url(href) = href + (href.include?("?") ? "&" : "?") + "embed=1"

    def page_key_for(url)
      return unless url&.start_with?("/")

      route = Rails.application.routes.recognize_path(url)
      page_config = Registry.page_for_controller_path(route[:controller])
      page_config&.underscored_resource_name if route[:action] == "index"
    rescue ActionController::RoutingError
      nil
    end

    def override(config, name) = config.try(:reactive_options)&.dig(:render_as)&.[](name.to_s)

    def override_for(config, name) = override(config, name) || (override(config, "*") if AA.resource?(config))

    def custom(override) = Decision.new("custom", "render_as custom", nil, override[:custom_key], 0)

    def overridden(decision, override)
      override ? decision.with(mode: override[:mode], reason: "render_as #{override[:mode]}") : decision
    end

    def template_for(config, name)
      controller_path = config.controller.controller_path
      return "#{controller_path}/#{name}" if lookup.exists?(name.to_s, [controller_path], false, [], formats: [:html])

      explicit_template(config, name)
    end

    # An action that renders another template by name: `render :approve`, `render "admin/x/y", layout: ...`.
    def explicit_template(config, name)
      return unless config.controller.method_defined?(name.to_sym)

      location = config.controller.instance_method(name.to_sym).source_location or return
      match = renders(block_at(*location)).find { it[:kind].nil? || it[:kind].start_with?("template", "action") } or return
      target = (match[:sym] || match[:name]).to_s
      target.include?("/") ? target : "#{config.controller.controller_path}/#{target}"
    end

    def renders(text) = text.to_enum(:scan, RENDER).map { Regexp.last_match }

    def decide(texts, name)
      all = texts.join("\n")
      markup = strip_erb(all)
      forms = all.scan(FORM_FOR).size
      read_only = forms.zero? && !all.match?(RAW_CONTROLS) && !all.match?(ACTION_CONTROLS)
      get = forms.positive? && all.match?(GET_FORM)
      reason = if (match = all[SCRIPT]) then ["iframe", "needs the page's own JS (#{match.strip})"]
      elsif read_only then ["native", "read-only markup"]
      elsif forms.zero? then ["frame", "no Formtastic form"]
      elsif (match = markup[RAW_CONTROLS] || all[RAW_CONTROLS]) then ["frame", "raw form controls (#{match.strip.first(30)})"]
      elsif (tag = other_tags(markup).first) then ["frame", "markup beyond simple wrappers (<#{tag}>)"]
      elsif (call = builder_misuse(all).first) then ["frame", "form builder call #{call}"]
      else
        ["native", get ? "Formtastic GET form (filters and results)" : "Formtastic-only form"]
      end
      get_form = get && reason[0] == "native"
      wide = get_form || forms > 1 || all.match?(ACTION_CONTROLS) || markup.match?(/<table\b/) || all.match?(/\btable_for\b/)
      Decision.new(mode: reason[0], reason: reason[1], template: name, custom_key: nil, fields: all.scan(/\.input\s*[(:]/).size, wide:, read_only: read_only && reason[0] == "native", get_form:)
    end

    def decide_page(texts)
      all = texts.join("\n")
      if (match = all[SCRIPT])
        Decision.new("iframe", "needs the page's own JS (#{match.strip})", nil, nil, 0)
      elsif all.match?(RAW_CONTROLS) || all.match?(ACTION_CONTROLS)
        Decision.new("frame", "forms render as frame nodes", nil, nil, 0)
      elsif all.match?(FORM_FOR)
        Decision.new(mode: "native", reason: "Formtastic forms render as form nodes", template: nil, custom_key: nil, fields: 0, get_form: all.match?(GET_FORM))
      else
        Decision.new("native", "content walks into typed nodes", nil, nil, 0)
      end
    end

    def strip_erb(text) = text.gsub(/<%#.*?%>/m, "").gsub(/<!--.*?-->/m, "").gsub(/<%.*?%>/m, "")

    def other_tags(markup) = markup.scan(/<\/?([a-z][a-z0-9]*)/i).flatten.map(&:downcase).uniq - SIMPLE_TAGS

    # Anything beyond Formtastic's own methods on the form block's variable renders something we can't record.
    def builder_misuse(text)
      vars = text.scan(/(?:semantic_form_for|active_admin_form_for|semantic_fields_for|fields_for)\b[^\n]*?do\s*\|\s*(\w+)/).flatten.uniq
      vars.flat_map { |var| text.scan(/\b#{var}\.(\w+)/).flatten }.uniq - BUILDER_METHODS
    end

    # [[name, text]] of the template and every partial it renders, depth first.
    def sources_for(config, name, seen = {})
      controller_path = config.controller.controller_path
      found = lookup.find_all(name.to_s, name.to_s.include?("/") ? [] : [controller_path], false, [], formats: [:html]).first
      return [] if found.nil? || seen[found.identifier]

      seen[found.identifier] = true
      text = found.source.to_s
      [[name, text]] + partial_refs(text).flat_map { |partial| partial_sources(config, partial, File.dirname(name.to_s), seen) }
    end

    def partial_sources(config, partial, dir, seen)
      prefixes = [dir, config.controller.controller_path]
      found = lookup.find_all(partial, partial.include?("/") ? [] : prefixes, true, [], formats: [:html]).first
      return [] if found.nil? || seen[found.identifier]

      seen[found.identifier] = true
      text = found.source.to_s
      [[partial, text]] + partial_refs(text).flat_map { partial_sources(config, it, File.dirname(partial), seen) }
    end

    # Partials a view renders: `render "form"` and `render partial: "x"`, not `render template:`.
    def partial_refs(text)
      renders(text).filter_map { it[:name] unless it[:kind]&.start_with?("template", "action") }.uniq
    end

    def partial_texts(config, text, seen = {})
      partial_refs(text.to_s).flat_map { partial_sources(config, it, config.controller.controller_path, seen).map(&:last) }
    end

    def lines_of(file)
      return File.readlines(file) if Rails.application.config.enable_reloading

      (@files ||= {})[file] ||= File.readlines(file)
    end

    def lookup = @lookup ||= ActionView::LookupContext.new(ActionController::Base.view_paths)

    # Source of the block that starts at file:line, up to the line that closes it.
    def block_source(block) = (block_at(*block.source_location) if block)

    def block_at(file, line)
      lines = lines_of(file)
      first = lines[line - 1].to_s
      return first unless first.match?(/\b(?:do|\{)\s*(?:\|[^|]*\|)?\s*\z/)

      indent = first[/\A\s*/]
      body = [first]
      lines.drop(line).each do |text|
        body << text
        break if text.match?(/\A#{indent}(?:end|\})\b/)
      end
      body.join
    end
  end
end
