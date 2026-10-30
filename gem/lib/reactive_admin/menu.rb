module ReactiveAdmin
  # AA's navigation menus (default and utility), filtered and resolved for the current user.
  class Menu
    UNEXPOSED = :unexposed

    # AA's menu procs (`if:`, label, url) are instance_exec'd in a view that responds to these.
    def initialize(view, authorizer, resource_keys, user: authorizer.user)
      @view = view
      @resource_keys = resource_keys
      AA.prepare_menu_view(view, namespace: Registry.namespace, user:, authorizer:)
    end

    def as_json(*) = menu(AA.default_menu)

    def menu(name)
      nodes = AA.menu_entries(Registry.namespace, name, @view).filter_map { node(it) }
      if name == AA.default_menu
        MenuOverlay.record_audit
        nodes = MenuOverlay::Layout.new(nodes, evaluate: method(:evaluate), build: method(:overlay_node)).call
      end
      finish(nodes)
    end

    def self.page_key(config) = config.underscored_resource_name

    private

    def node(entry)
      return unless entry.display?

      url = entry.url.presence
      destination = destination(url)
      return if destination == UNEXPOSED

      url = nil if (destination&.key?(:resource) && !destination[:api_denied]) || url == "#"
      node = {id: entry.id, label: entry.label.to_s, kind: kind(destination, url), resource: nil, **destination.to_h, url:, priority: entry.priority,
              children: entry.children.filter_map { node(it) }}
      verb = entry.http_method
      verb ? node.merge(method: verb.to_s) : node
    rescue => e
      Rails.logger.warn("[reactiveadmin] skipped menu item #{entry.id}: #{e.class} at #{e.backtrace&.first}")
      Degradation.record(kind: :menu_item_dropped, where: "menu/item[#{entry.id}]", reason: "Menu item raised #{e.class}; left out")
      nil
    end

    def overlay_node(config) = node(AA.menu_entry_for(config, @view))

    def kind(destination, url)
      if destination&.key?(:api_denied) then "link"
      elsif destination&.key?(:resource) then "resource"
      elsif destination then "page"
      elsif url then "link"
      else
        "group"
      end
    end

    # Each level is ordered by priority, then overlay order, then label; emptied groups go.
    def finish(nodes, depth = 1)
      nodes.sort_by { [it[:priority], it[:seq] || MenuOverlay::UNSEQUENCED, it[:label]] }.filter_map do |node|
        MenuOverlay.check_depth!(depth, node[:label])
        children = finish(node[:children], depth + 1)
        node.except(:seq).merge(children:) unless node[:kind] == "group" && children.empty?
      end
    end

    def evaluate(value) = AA.render_in_context(@view, @view, value)

    def destination(url)
      return unless url&.start_with?("/")

      route = Rails.application.routes.recognize_path(url)
      return unless route[:action] == "index"

      if (config = Registry.for_controller_path(route[:controller]))
        key = Registry.route_key(config)
        return UNEXPOSED unless Exposure.allowed?(config)
        return {resource: key, api_denied: true} if ApiGuards.denies?(config, "index")

        {resource: key} if @resource_keys.include?(key)
      elsif (page = Registry.page_for_controller_path(route[:controller]))
        return UNEXPOSED unless Exposure.allowed?(page)

        {page: Menu.page_key(page), **({api_denied: true} if ApiGuards.denies?(page, "index")).to_h}
      end
    rescue ActionController::RoutingError
      nil
    end
  end
end
