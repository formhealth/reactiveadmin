module ReactiveAdmin
  # Re-draws AA's routes under mount_path with the reactiveadmin format so AA's own
  # controllers serve the JSON API.
  def self.routes(router)
    ns = config.namespace
    router.scope(config.mount_path, as: :reactiveadmin, defaults: {format: :reactiveadmin}, constraints: method(:api_format?)) do
      router.get "#{ns}/_manifest", to: "reactive_admin/manifest#show"
      router.get "#{ns}/_session", to: "reactive_admin/session#show"
      router.get "#{ns}/_openapi", to: "reactive_admin/openapi#show"
      router.post "#{ns}/_mcp", to: "reactive_admin/mcp#create"
      router.match "#{ns}/_mcp", to: "reactive_admin/mcp#unsupported", via: %i[get delete]
      # Must precede AA's `/:id` routes, which would otherwise swallow `_options` and `_meta`.
      AA.load_registrations!
      Registry.resources.each do |config|
        controller = config.controller.controller_path
        router.get(Paths.meta(config), to: "#{controller}#reactiveadmin_meta")
        router.get(Paths.labels(config), to: "#{controller}#reactiveadmin_labels") unless Paths.nested?(config)
        to = "#{controller}#reactiveadmin_options"
        router.get(Paths.options(config), to:)
        lookup = "#{controller}#reactiveadmin_lookup"
        router.get(Paths.lookup(config), to: lookup)
        value = "#{controller}#reactiveadmin_value"
        router.get(Paths.value(config), to: value) unless Paths.nested?(config)
        router.get(Paths.value(config, parent_id: ":#{config.belongs_to_config.to_param}"), to: value) if config.belongs_to?
        # Form options of a nested resource are built from a record under its parent.
        if config.belongs_to?
          parent_id = ":#{config.belongs_to_config.to_param}"
          router.get(Paths.options(config, parent_id:), to:)
          router.get(Paths.lookup(config, parent_id:), to: lookup)
        end
      end
      Registry.pages.each do |page|
        # A page under a required parent is only routed under it, as its classic route is.
        parent = "#{Registry.route_key(page.belongs_to_config.target)}/:#{page.belongs_to_config.to_param}/" if Paths.nested?(page)
        router.get "#{ns}/#{parent}_pages/#{page.underscored_resource_name}", to: "#{page.controller.controller_path}#reactiveadmin_page"
      end
      AA.draw_routes(router)
      # Last: anything unrouted answers in JSON instead of the host's html 404 page.
      router.match "#{ns}/*path", to: NOT_FOUND, via: :all, format: false, as: :not_found
    end
    ui_routes(router)
  end

  # The built client's files, for hosts whose static file server doesn't serve them.
  def self.ui_routes(router)
    prefix = config.ui.asset_prefix.to_s
    router.mount Ui::Assets::Server.new, at: prefix, as: :reactiveadmin_assets if prefix.start_with?("/")
  end

  NOT_FOUND = ->(_env) { [404, {"Content-Type" => "application/json"}, ['{"code":"not_found","message":"Not found"}']] }

  # AA's responders would serialize whole records for .json and .xml, so the mount only answers
  # in its own format, plus CSV on index (AA's streamed export, which honours `csv do` blocks).
  def self.api_format?(request)
    params = request.path_parameters
    format = params[:format].to_s
    format == "reactiveadmin" || (format == "csv" && params[:action] == "index")
  end
end
