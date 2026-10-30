module ReactiveAdmin
  # Walks AA-rendered HTML into typed nodes; anything unrecognised becomes sanitized html.
  class HtmlNodes
    include HtmlRich

    VARIANTS = {
      success: %w[yes ok success completed],
      warning: %w[warning pending hold],
      danger: %w[error no failed danger],
      info: %w[info]
    }.freeze
    BOX_TAGS = %w[div span p section].freeze
    SAFE_SCHEMES = %w[http https mailto tel].freeze
    TOOLBAR_TAGS = %w[div section].freeze
    PASSTHROUGH_TAGS = %w[div span section].freeze
    STRUCTURAL_CLASSES = %w[panel attributes_table tabs columns status_tag empty].freeze

    # `frame_src` is the classic URL the html came from: forms that PageForms did not record
    # (see its marker nodes) are kept as interactive frame nodes that submit relative to it.
    # `resource` only labels diagnostics about layout classes the walker can't translate.
    def self.nodes(html, host: nil, links: nil, frame_src: nil, resource: nil) = new(host, links, frame_src:, resource:).nodes(html)

    def self.convert(html, host: nil, links: nil, frame_src: nil, resource: nil) = new(host, links, frame_src:, resource:).convert(html)

    # Content of a show or page view. A view that runs its own JS can't be walked, so it is embedded whole.
    def self.layout(html, src:, host: nil, links: nil, title: nil, resource: nil)
      if Ladder.script?(html)
        Degradation.record(kind: :layout_iframe, where: Degradation.where, reason: "Content runs its own JS; embedded as iframe")
        return [{type: "iframe", src: Ladder.embed_url(src), title:}.compact]
      end

      nodes(html, host:, links:, frame_src: src, resource:)
    end

    # Forms stay, scripts and handlers go, and nothing submits off-site.
    def self.interactive(html, host: nil, where: nil) = HtmlPolicy.interactive(html, host:, where:)

    def self.sanitize(html, host: nil, where: nil) = HtmlPolicy.display(html, host:, where:)

    # `links` maps controls that act (button_to, data-method) to Actions, given the record in view.
    def initialize(host = nil, links = nil, frame_src: nil, resource: nil)
      @host = host
      @links = links || ActionLinks.new(host:)
      @frame_src = frame_src
      @resource = resource&.to_s
      @path = []
    end

    def nodes(html)
      fragment = HtmlPolicy.parse(html, where: @path.join("/")) or return [{type: "text", text: HtmlPolicy::TOO_COMPLEX}]
      merge_toolbars(siblings(fragment.children))
    end

    def convert(html)
      list = nodes(html)
      if list.size == 1
        list.first
      else
        (list.empty? ? {type: "empty"} : {type: "group", children: list})
      end
    end

    private

    def node(el)
      return text(el.text) if el.text? || el.cdata?
      return unless el.element?

      if el.name == "br"
        nil
      elsif el.name == "span" && el["class"].to_s.split.include?("status_tag")
        status(el)
      elsif el.name == "span" && el.classes.include?("empty")
        {type: "empty"}
      elsif el.name == "span" && el.classes.include?(Masking::CLASS_NAME)
        Masking::NODE
      elsif NodeRegistry.marker?(el)
        NodeRegistry.from_html(el)
      elsif action?(el)
        action_node(el)
      elsif HtmlPolicy::MEDIA.key?(el.name)
        media(el)
      elsif el.name == "time" && (typed = time(el))
        typed
      elsif %w[pre code].include?(el.name) && (typed = code(el))
        typed
      elsif @frame_src && el.name == "form" && Provenance.trusted?(el)
        frame(el)
      elsif el.name == "a"
        link(el)
      elsif el.name == "div" && el.classes.include?("attributes_table")
        attributes_table(el)
      elsif el.name == "div" && el.classes.include?("panel")
        panel(el)
      elsif el.name == "div" && el.classes.include?("tabs")
        tabs(el)
      elsif el.name == "div" && el.classes.include?("columns")
        columns(el)
      elsif el.name == "table"
        table(el)
      elsif rich?(el)
        rich(el)
      elsif (bar = toolbar(el))
        bar
      elsif BOX_TAGS.include?(el.name) && (el.element_children.any? || layout_hints(el).any?)
        box(el)
      elsif BOX_TAGS.include?(el.name)
        text(el.text)&.merge(classes(el).text_style)
      else
        html(el)
      end
    end

    # Only controls the DSL's own helpers stamped act; the same markup in a stored value is a link or text.
    def action?(el) = ActionLinks.control?(el) && Provenance.trusted?(el)

    # No node when the control isn't offered to this channel (a browser-only POST, for a token).
    def action_node(el) = (action = @links.action(el, placement: "inline")) && {type: "action", action:}

    # The frame follows data-method links itself, so a form's stored text can't keep them.
    def frame(el)
      el.css("a[data-method], a[data-remote]").reject { Provenance.trusted?(it) }.each { |link| %w[data-method data-remote].each { link.remove_attribute(it) } }
      {type: "frame", html: self.class.interactive(el.to_html, host: @host, where: @path.join("/")), src: @frame_src}
    end

    # External images and documents never load on their own: they become links.
    def media(el)
      typed = MediaNodes.for(el, host: @host)
      return typed if typed

      src = el["src"].to_s.strip
      return {type: "iframe", src: Ladder.embed_url(src), title: el["title"].presence}.compact if el.name == "iframe" && embeddable?(src)

      decision = HtmlPolicy.media(el, host: @host)
      return html(el) if decision == :keep
      return if decision == :drop

      HtmlPolicy.degrade(:external_media_blocked, "Replaced an external image or document with a link", where: @path.join("/"))
      {type: "link", label: decision.first, href: decision.last, external: true}
    end

    def time(el)
      value = el["datetime"].to_s.strip
      value.match?(/\A\d{4}-\d{2}-\d{2}\z/) ? {type: "date", value: Date.iso8601(value).iso8601} : {type: "datetime", value: Time.iso8601(value).iso8601}
    rescue ArgumentError
      nil
    end

    # Code (typically a JSON dump) with nothing but text inside; anything marked up stays html.
    def code(el)
      only = el.element_children.one? && el.element_children.first.name == "code" && el.children.none? { it.text? && it.text.strip.present? }
      source = (el.name == "pre" && only) ? el.element_children.first : el
      return unless source.element_children.empty?

      text = source.text.delete_prefix("\n").rstrip
      return {type: "empty"} if text.blank?

      json = parse_json(text)
      return Values.for(json, nil, source: ValuePayload::Source.new(inline: @frame_src.present?)) if json

      language = [source, el].filter_map { it["class"].to_s[/\blang(?:uage)?-(\S+)/, 1] }.first
      {type: "code", text:, language:}.compact
    end

    def parse_json(text)
      JSON.parse(text) if text.lstrip.start_with?("{", "[")
    rescue JSON::ParserError
      nil
    end

    def text(string)
      string = string.strip
      {type: "text", text: string} unless string.empty?
    end

    def status(el)
      classes = el.classes
      variant = VARIANTS.find { |_, names| (names & classes).any? }&.first || :neutral
      {type: "status", label: el.text.strip, variant: variant.to_s}
    end

    def link(el)
      label = el.text.strip
      return text(label) if ActionLinks.verb(el["data-method"]) != "get"

      uri = begin
        URI.parse(el["href"].to_s)
      rescue
        nil
      end
      return text(label) if uri.nil? || (uri.scheme && !SAFE_SCHEMES.include?(uri.scheme))

      external = external?(uri)
      node = {type: "link", label:, href: external ? @links.absolute(uri) : uri.to_s, external:}
      ref = ref_for(uri)
      node = node.merge(ref:) if ref
      view = view_for(uri)
      view ? node.merge(view:) : node
    end

    # A link to a custom view (a custom GET action or a register_page) says how the client shows it.
    def view_for(uri)
      return if external?(uri) || uri.path.blank?

      route = Rails.application.routes.recognize_path(uri.path)
      href = [uri.path, uri.query].compact.join("?")
      action = route[:action].dup.force_encoding(Encoding::UTF_8)
      if (config = Registry.for_controller_path(route[:controller]))
        Ladder.view(config, action, href:) if Exposure.allowed?(config)
      elsif (page = Registry.page_for_controller_path(route[:controller]))
        return unless Exposure.allowed?(page)

        (action == "index") ? Ladder.page_view(page, href:) : Ladder.view(page, action, href:)
      end
    rescue ActionController::RoutingError
      nil
    end

    # An iframe in markup may only frame a page of a registered, exposed resource or page: a same-origin
    # path elsewhere (an upload, a blob) runs with the admin's session and the frame's `allow-same-origin`.
    def embeddable?(src)
      return false unless HtmlPolicy.same_origin?(src, @host) && !HtmlPolicy.trusted_url?(src)

      path = URI.parse(src).path.to_s
      return false unless path.start_with?("/admin/") && !path.match?(%r{/\.\.?(/|\z)|%2[ef]}i)

      route = Rails.application.routes.recognize_path(path)
      config = Registry.for_controller_path(route[:controller]) || Registry.page_for_controller_path(route[:controller])
      config.present? && Exposure.allowed?(config)
    rescue ActionController::RoutingError, URI::InvalidURIError
      false
    end

    def external?(uri) = @links.external?(uri)

    def ref_for(uri)
      return if external?(uri) || uri.path.blank?

      route = Rails.application.routes.recognize_path(uri.path)
      return unless route[:action] == "show" && route[:id]

      config = Registry.for_controller_path(route[:controller]) or return
      return unless Exposure.allowed?(config)

      ref = {resource: Registry.route_key(config), id: route[:id].to_s}
      Paths.nested?(config) ? ref.merge(path: uri.path, api_path: Paths.api(uri.path)) : ref
    rescue ActionController::RoutingError
      nil
    end

    def attributes_table(el)
      title = el.parent&.classes&.include?("panel_contents") ? panel_title(el.parent.parent) : nil
      rows = el.css("tr").map do |tr|
        {label: tr.at_css("th")&.text.to_s.strip, value: cell_nodes(tr.at_css("td"))}
      end
      {type: "attributes_table", title:, rows:}
    end

    def cell_nodes(td)
      list = td ? nodes(td.inner_html) : []
      list.empty? ? [{type: "empty"}] : list
    end

    def panel(el)
      contents = child(el, "panel_contents")
      {type: "panel", title: panel_title(el), children: nodes((contents || el).inner_html)}
    end

    def panel_title(panel) = panel&.element_children&.find { it.name == "h3" }&.text&.strip

    def child(el, class_name) = el.element_children.find { it.classes.include?(class_name) }

    def tabs(el)
      titles = child(el, "nav-tabs")&.element_children.to_a.map { it.text.strip }
      contents = child(el, "tab-content")&.element_children.to_a
      tabs = titles.zip(contents).map { |title, content| {type: "tab", title:, children: nodes(content&.inner_html)} }
      {type: "tabs", children: tabs}
    end

    def columns(el)
      columns = el.element_children.select { it.classes.include?("column") }
      {type: "columns", children: columns.map { {type: "column", children: nodes(it.inner_html)} }}
    end

    def table(el)
      headers = el.css("thead th").map { it.text.strip }
      cells = headers.empty? ? "th, td" : "td"
      rows = el.css("tbody tr").map { |tr| tr.css(cells).map { convert(it.inner_html) } }
      {type: "table", headers:, rows:}
    end

    def box(el)
      result = classes(el)
      {type: "box", tag: el.name, **result.hints, **result.text_style, children: nodes(el.inner_html)}
    end

    # A container holding only actions and links, however deeply wrapped. A width or a column
    # direction means it is laying out other content, so it stays a box.
    def toolbar(el)
      return unless TOOLBAR_TAGS.include?(el.name) && (STRUCTURAL_CLASSES & el.classes).empty?

      wrappers = [el]
      items = toolbar_items(el, wrappers)
      return if items.blank?

      results = wrappers.map { classes(it) }
      return if results.any? { it.width || it.span || it.max_width || it.grow || it.layout&.dig(:direction) == "column" }

      {type: "toolbar", align: results.filter_map(&:toolbar_align).first || "start", spacing: results.filter_map(&:spacing).first, children: items}.compact
    end

    def toolbar_items(el, wrappers)
      el.children.flat_map do |child|
        next [] if child.comment? || (child.text? && child.text.strip.empty?) || child.name == "br"

        toolbar_item(child, wrappers) || (return nil)
      end
    end

    def toolbar_item(el, wrappers)
      if NodeRegistry.marker?(el)
        nil
      elsif action?(el)
        [action_node(el)].compact
      elsif el.name == "a"
        node = link(el)
        [node] if node[:type] == "link"
      elsif PASSTHROUGH_TAGS.include?(el.name) && (STRUCTURAL_CLASSES & el.classes).empty?
        wrappers << el
        toolbar_items(el, wrappers)
      end
    end

    def merge_toolbars(list)
      list.each_with_object([]) do |node, merged|
        last = merged.last
        if node[:type] == "toolbar" && last&.dig(:type) == "toolbar" && last[:align] == node[:align]
          merged[-1] = last.merge(children: last[:children] + node[:children])
        else
          merged << node
        end
      end
    end

    def layout_hints(el) = classes(el).hints

    # Classes and styles are never passed on; the ones with no translation are reported for `doctor`,
    # not to the user: the content renders, only some spacing is lost.
    def classes(el)
      result = LayoutClasses.parse(el["class"], style: el["style"])
      result.unknown.each { diagnose(:unknown_layout_class, class: it) }
      diagnose(:inline_style_ignored, style: InlineStyle.redact(el["style"]), ignored: InlineStyle.redact(result.unknown_styles.join("; "))) if result.unknown_styles.any?
      result
    end

    def diagnose(kind, **details)
      source = StyleSources.locate(details[:class] || details[:style], resource: @resource)
      ReactiveAdmin.diagnostics.record(kind, resource: @resource, path: @path.join("/"), **details, **{source:}.compact)
    end

    def at(step)
      @path.push(step)
      yield
    ensure
      @path.pop
    end

    def html(el)
      diagnose(:html_unmapped_tag, tag: el.name)
      Degradation.tally(kind: :html_fallback, where: Degradation.where(*@path), reason: "%d elements shown as sanitized html")
      {type: "html", html: self.class.sanitize(el.to_html, host: @host, where: @path.join("/"))}
    end
  end
end
