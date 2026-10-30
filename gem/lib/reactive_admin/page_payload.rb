module ReactiveAdmin
  # PageResponse for a register_page: its `content` block walked into nodes, plus its action items
  # and the GET page actions that render something. Sidebars are not carried.
  class PagePayload
    # Arbre context that runs the content block the way ActiveAdmin::Views::Pages::Page does.
    class Content < AA.arbre_element
      include PageForms::ArbreForms
    end

    def initialize(controller)
      @controller = controller
      @config = AA.config_of(controller)
      @view = Masking.install(controller.view_context, @config)
      @authorizer = Authorizer.for(controller)
    end

    def as_json(*)
      decision = Ladder.page(@config)
      layout = NodeRegistry.with_scope { layout(decision) }
      mode = rendered_mode(decision, layout)
      items = ActionItems.new(@controller, "index", subject: @config).call
      Degradation.record(kind: :page_frame, where: "page", reason: "Page content has forms; shown in a classic frame") if mode == "frame" && !forced?("frame")
      Degradation.attach({
        key:, title:, layout:, actions: items + page_actions(items),
        view: {mode:, path: path(mode), custom_key: decision.custom_key, presentation: "page"}.compact
      })
    end

    # What the content's forms recorded, to know how a write to one of them is shaped.
    def forms(controls_only: false)
      Degradation.with_collection(resource: @config.resource_name, action: "page") { render_content(controls_only:) }
      Array(@forms&.recorded)
    end

    private

    def key = @config.underscored_resource_name

    # The page's own URL, which carries its parent's id when it is nested.
    def classic_url = @classic_url ||= @controller.request.path.delete_prefix(ReactiveAdmin.config.mount_path).sub("/_pages/", "/")

    # What the content turned out to be: a page that walks into typed nodes is native even if its
    # source looked scripted, and one with a frame node needs the frame.
    def rendered_mode(decision, layout)
      if decision.mode == "custom" then "custom"
      elsif layout.size == 1 && layout.first[:type] == "iframe" then "iframe"
      elsif framed?(layout) then "frame"
      else
        "native"
      end
    end

    def framed?(nodes) = nodes.any? { it[:type] == "frame" || framed?(Array(it[:children])) }

    def path(mode)
      case mode
      when "native" then Paths.api(Ladder.page_path(@config, classic_url))
      when "frame" then classic_url
      when "iframe" then Ladder.embed_url(classic_url)
      end
    end

    def presenter = AA.page_presenter(@config, :index)

    def title
      custom = presenter && presenter[:title]
      text = custom ? AA.render_or_call(@view, @view, custom) : @config.name
      CGI.unescapeHTML(text.to_s)
    end

    def layout(decision)
      return [] if decision.mode == "custom"
      return [iframe] if decision.mode == "iframe" && forced?("iframe")

      html = render_content(forms: !forced?("frame"))
      return [{type: "frame", html: HtmlNodes.interactive(html, host: @controller.request.host), src: classic_url, title:}] if forced?("frame")

      HtmlNodes.layout(html, src: classic_url, host: @controller.request.host, links:, title:, resource: @config.resource_name)
    rescue => e
      Rails.logger.warn("[reactiveadmin] #{@config.resource_name} page content embedded as iframe: #{e.class} at #{e.backtrace&.first}")
      Degradation.record(kind: :page_iframe_fallback, where: "page", reason: "Page content raised #{e.class}; embedded as iframe")
      [iframe]
    end

    def forced?(mode) = Ladder.override(@config, "*")&.fetch(:mode) == mode

    def iframe = {type: "iframe", src: Ladder.embed_url(classic_url), title:}

    def links = ActionLinks.new(host: @controller.request.host, base_url: @controller.request.base_url, authorizer: @authorizer, subject: @config)

    # Formtastic forms are recorded into the nodes they stand for; the html left over keeps any other.
    def render_content(forms: true, controls_only: false)
      return "" unless presenter&.block

      context = AA.arbre_context(@controller.view_assigns, @view)
      render = -> { context.insert_tag(Content).instance_exec(&presenter.block) }
      if forms
        @forms = PageForms.recording(@view, @controller, controls_only:, &render)
      else
        render.call
      end
      context.to_s
    end

    # Only GETs: a page action that writes is the target of a form in the content.
    def page_actions(linked)
      @config.page_actions.filter_map do |declaration|
        name = declaration.name.to_s
        next if Array.wrap(declaration.http_verb) != [:get] || linked.any? { it[:key] == name }

        href = File.join(classic_url, name)
        action = {key: name, label: name.titleize, kind: "custom", placement: "header", method: "get", href:, api_path: Paths.api(href), enabled: true}
        next ApiGuards.mark(action, @config, name) if ApiGuards.denies?(@config, name, verb: "get")

        view = Ladder.view(@config, name, href:) or next
        action.merge(view:)
      end
    end
  end
end
