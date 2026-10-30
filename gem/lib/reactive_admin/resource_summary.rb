module ReactiveAdmin
  # What the shell needs of a resource: enough to build the menu and routes, cheap to compute
  # for every registered resource.
  class ResourceSummary
    def initialize(config, authorizer)
      @config = config
      @authorizer = authorizer
    end

    def permissions = @permissions ||= Permissions.new(@config, @authorizer).resource

    def as_json(*)
      placement = AA.menu_placement(@config)
      template = Paths.index_template(@config)

      {
        key: Registry.route_key(@config),
        label: @config.resource_label.to_s,
        plural_label: @config.plural_resource_label.to_s,
        menu_parent: placement&.[](:parent),
        menu_priority: placement&.[](:priority),
        meta_path: Paths.api(Paths.meta(@config)),
        belongs_to:,
        index_path_template: template,
        api_index_path_template: (Paths.api(template) if template),
        actions: Registry.top_level_actions(@config).map(&:to_s),
        permissions:,
        api_denied: ApiGuards.summary(@config)
      }.compact # a lean manifest: 100+ resources, so absent beats null
    end

    private

    def belongs_to
      return unless @config.belongs_to?

      parent = @config.belongs_to_config
      {parent: Registry.route_key(parent.target), param: parent.to_param.to_s, optional: !!parent.optional?}
    end
  end
end
