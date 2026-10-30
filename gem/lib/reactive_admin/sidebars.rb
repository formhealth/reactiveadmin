module ReactiveAdmin
  # A resource's AA sidebar sections for one page, rendered in the page's view context and walked
  # into nodes. AA's own filters and search-status sections are left out: the client has its own.
  class Sidebars
    BUILT_IN = %w[filters search_status].freeze

    def initialize(controller, action, src:, subject: nil)
      @controller = controller
      @action = action
      @src = src
      @config = AA.config_of(controller)
      @view = controller.view_context
      @links = ActionLinks.new(host: controller.request.host, base_url: controller.request.base_url, authorizer: Authorizer.for(controller), subject: subject || @config.resource_class)
    end

    def as_json(*)
      sections = AA.sidebar_sections(@config).reject { BUILT_IN.include?(it.name) }.sort_by(&:priority)
      sections.filter_map { render(it) }
    end

    private

    def render(section)
      rendered = AA.render_sidebar(section, @action, @controller.view_assigns, @view) or return

      {title: rendered[:title], layout: HtmlNodes.layout(rendered[:html], src: @src, host: @controller.request.host, links: @links, title: rendered[:title], resource: @config.resource_name)}
    rescue => e
      Rails.logger.warn("[reactiveadmin] #{@config.resource_name} sidebar #{section.name} skipped: #{e.class} at #{e.backtrace&.first}")
      ReactiveAdmin.diagnostics.record(:sidebar_failed, resource: @config.resource_name, section: section.name)
      Degradation.record(kind: :sidebar_dropped, where: "#{@action}/sidebar[#{section.name}]", reason: "Sidebar raised #{e.class}; left out")
      nil
    end
  end
end
