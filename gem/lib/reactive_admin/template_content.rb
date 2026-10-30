module ReactiveAdmin
  # A read-only template of a custom GET action, answered natively as a PageResponse: its html walked
  # into the same typed nodes as a show page. A template that turns out to hold anything to intercept
  # (a form, a button, a link that acts) is Unsupported and stays a frame.
  class TemplateContent
    INTERACTIVE = "form, input, select, textarea, button, fieldset, a[data-method], a[data-remote], a[data-confirm]".freeze

    def initialize(controller, template)
      @controller = controller
      @template = template
      @config = AA.config_of(controller)
    end

    def as_json(*)
      NodeRegistry.with_scope do
        fragment = HtmlPolicy.parse(render) or raise TemplateForm::Unsupported, "#{@template} is too complex to display"
        raise TemplateForm::Unsupported, "#{@template} has controls to intercept" if fragment.at_css(INTERACTIVE) || Ladder.script?(fragment.to_html)

        title = leading_heading(fragment)
        Degradation.attach({key:, title: title || default_title, layout: nodes(fragment), actions: []})
      end
    end

    private

    def render
      @controller.lookup_context.formats = [:html]
      @controller.view_context.render(template: @template, layout: false)
    end

    def nodes(fragment)
      request = @controller.request
      links = ActionLinks.new(host: request.host, base_url: request.base_url, authorizer: Authorizer.for(@controller), subject: AA.resource_ivar(@controller) || @config)
      HtmlNodes.nodes(fragment.to_html, host: request.host, links:, frame_src: request.path.delete_prefix(ReactiveAdmin.config.mount_path), resource: key)
    end

    # The page's title, as a form's first heading is: taken out of the content.
    def leading_heading(fragment)
      heading = fragment.element_children.first
      return unless heading&.name&.match?(/\Ah[1-4]\z/)

      heading.text.strip.presence&.tap { heading.remove }
    end

    def key = AA.page?(@config) ? @config.underscored_resource_name : Registry.route_key(@config)

    def default_title = AA.t(@controller.action_name, default: @controller.action_name.to_s.titleize)
  end
end
