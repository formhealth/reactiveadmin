module ReactiveAdmin
  # Everything the shell needs on load. Per-resource details (filters, scopes, ...) come from
  # ResourceMeta, so this stays cheap however many resources are registered.
  class Manifest
    SCHEMA_VERSION = 2

    def initialize(controller, authorizer: Authorizer.for(controller))
      @controller = controller
      @authorizer = authorizer
    end

    def as_json(*)
      resources = self.resources
      menu = menu(resources)
      {schema_version: SCHEMA_VERSION, site: Site.new(@controller, menu), menu:, resources:}
    end

    # The summaries of the resources the user may open, in registration order.
    def resources = Registry.resources.filter_map { resource(it) }

    def menu(resources) = Menu.new(@controller.view_context, @authorizer, resources.pluck(:key), user: ReactiveAdmin.current_user(@controller))

    private

    def resource(config)
      return unless Exposure.allowed?(config) && Registry.actions(config).include?(:index) && !ApiGuards.denies?(config, "index")

      summary = ResourceSummary.new(config, @authorizer)
      summary.as_json if summary.permissions[:index]
    rescue => e
      Rails.logger.warn("[reactiveadmin] skipped #{config.resource_name} in manifest: #{e.class} at #{e.backtrace&.first}")
      Degradation.record(kind: :manifest_resource_dropped, where: "manifest/resource[#{config.resource_name}]", reason: "Resource raised #{e.class}; left out of the manifest")
      nil
    end
  end
end
