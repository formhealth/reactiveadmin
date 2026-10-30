module ReactiveAdmin
  # Single access point to ActiveAdmin's registrations.
  module Registry
    module_function

    def namespace = AA.namespace(ReactiveAdmin.config.namespace)

    def resources = index[:resources]

    def route_key(config) = config.resource_name.route_key

    def find(key) = index[:by_key][key]

    def for_class(klass)
      return unless klass.is_a?(Class)

      by_class = index[:by_class]
      config = by_class[klass.to_s] || (by_class[klass.base_class.to_s] if klass.respond_to?(:base_class))
      config if config && actions(config).include?(:show) && Exposure.allowed?(config) && !ApiGuards.denies?(config, "show")
    end

    # AA's own `defined_actions` lists the controller's instance methods on every call.
    def actions(config) = (index[:actions][config] ||= AA.defined_actions(config))

    # What the client may offer at the resource's top level, where a `new_needs_parent` resource can't build.
    def top_level_actions(config)
      config.reactive_options[:new_needs_parent] ? actions(config) - %i[new create] : actions(config)
    end

    def for_controller_path(path) = index[:by_controller_path][path]

    def pages = index[:pages]

    def find_page(key) = index[:pages_by_key][key]

    def page_for_controller_path(path) = index[:pages_by_controller_path][path]

    # Records of nested-only resources also carry their paths: `resource` + `id` don't locate them.
    def ref(record)
      config = for_class(record.class) or return
      ref = {resource: route_key(config), id: record.to_param.to_s}
      return ref unless Paths.nested?(config)

      paths = Paths.record(config, record)
      ref.merge(path: paths[:show], api_path: paths[:api_show]).compact
    end

    # Lookups run per menu item and per cell, and AA's own are linear scans that constantize
    # controllers. Registrations only change on (re)load, which swaps or grows the collection.
    def index
      collection = AA.registrations(namespace)
      stamp = [collection.object_id, collection.size]
      return @index if @index && @index_stamp == stamp

      resources = collection.select { AA.resource?(it) }
      pages = collection.select { AA.page?(it) }
      @index = {
        resources:,
        by_key: resources.index_by { route_key(it) },
        by_class: resources.index_by { it.resource_class.to_s },
        by_controller_path: resources.index_by { it.controller.controller_path },
        pages:,
        pages_by_key: pages.index_by(&:underscored_resource_name),
        pages_by_controller_path: pages.index_by { it.controller.controller_path },
        actions: {}
      }.tap { @index_stamp = stamp }
    end
  end
end
