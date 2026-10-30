module ReactiveAdmin
  # Lookups (typeahead search, option resolution, `_labels`) are background requests, not page views,
  # yet an author's name is sensitive wherever it appears. When the records returned belong to a sensitive resource
  # (`config.sensitive_resources` or `reactive { sensitive true }`), each request emits one `lookup.reactiveadmin`
  # event: who, where, how many. Never the search term and never a returned name.
  module LookupAudit
    module_function

    def sensitive?(model)
      config = model && AA.resource_for(Registry.namespace, model)
      return false unless config

      config.reactive_options.fetch(:sensitive) { ReactiveAdmin.config.sensitive_resources.map(&:to_s).include?(Registry.route_key(config)) }
    end

    # Never raises: the lookup has been answered, and an audit hiccup must not turn it into a 500.
    def record(controller, model:, kind:, result_count:, field: nil)
      return unless sensitive?(model)

      ActiveSupport::Notifications.instrument("lookup.reactiveadmin", resource: WriteAudit.resource_key(controller), field:, kind:,
        target: Registry.route_key(AA.resource_for(Registry.namespace, model)), result_count:, user_id: ReactiveAdmin.current_user(controller)&.id)
    rescue => e
      Rails.logger.error("[reactiveadmin] lookup audit failed: #{e.class}")
    end
  end
end
