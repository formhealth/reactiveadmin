module ReactiveAdmin
  # A resource's AA `action_item`s for one page, rendered in the page's view context and walked
  # into header Actions.
  class ActionItems
    def initialize(controller, page, subject: nil)
      @controller = controller
      @page = page
      @config = AA.config_of(controller)
      @view = controller.view_context
      @links = ActionLinks.new(host: controller.request.host, base_url: controller.request.base_url, authorizer: Authorizer.for(controller),
        subject: subject || @config.resource_class)
    end

    # `generated` are the buttons the client already derives (edit, destroy, ...); AA's default
    # items for them would duplicate those.
    def call(generated = [])
      known = generated.map { signature(it) }
      ordered.flat_map { render(it) }.reject { known.include?(signature(it)) }
    end

    private

    def ordered = AA.action_items(@config)

    def render(item)
      html = AA.render_action_item(item, @page, @controller.view_assigns, @view) or return []

      ActionLinks.controls(html).each_with_index.filter_map do |el, index|
        @links.action(el, placement: "header", key: index.zero? ? item.name : "#{item.name}_#{index + 1}")
      end
    rescue => e
      Rails.logger.warn("[reactiveadmin] #{@config.resource_name} action item #{item.name} skipped: #{e.class} at #{e.backtrace&.first}")
      Degradation.record(kind: :action_item_dropped, where: "#{@page}/action_item[#{item.name}]", reason: "Action item raised #{e.class}; left out")
      []
    end

    def signature(action) = [action[:method], action[:href].to_s.split("?").first]
  end
end
