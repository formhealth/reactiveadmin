module ReactiveAdmin
  module AA
    module V3
      # What AA's controllers hold: inherited_resources' record, the filtered collection and scope
      # chain, and the names of the hooks our prepended modules override.
      module Controller
        def base_controller = ::ActiveAdmin::BaseController

        def config_of(controller) = controller.send(:active_admin_config)

        def resource(controller) = controller.send(:resource)

        def build_resource(controller) = controller.send(:build_resource)

        # The record inherited_resources memoized, which a custom action may have set itself.
        def resource_ivar(controller) = (controller.send(:get_resource_ivar) if controller.respond_to?(:get_resource_ivar, true))

        # inherited_resources also memoizes the params it built the record from.
        def reset_resource_ivar(controller)
          controller.send(:set_resource_ivar, nil)
          controller.instance_variable_set(:@resource_params, nil)
        end

        # Applies AA's filtering, scoping, sorting and pagination; must run before `current_scope`
        # and `collection_before_scope` have anything to report.
        def collection(controller) = controller.send(:collection)

        def current_scope(controller) = controller.send(:current_scope)

        def collection_before_scope(controller) = controller.send(:collection_before_scope)

        def scope_chain(controller, scope, chain) = controller.send(:scope_chain, scope, chain)

        # A record found, decorated and authorized for reading the way AA's `resource` does.
        def find_authorized_resource(controller)
          record = controller.send(:apply_decorations, controller.send(:find_resource))
          controller.send(:authorize_resource!, record)
          record
        end

        # Looks a composite-key record up from its joined param: the last key part takes any remaining
        # delimiters, since it is the one most likely to hold them (a timestamp, a slug). Nil when the
        # key is a single column, which AA's own `find_resource` handles.
        def find_composite_resource(controller)
          klass = config_of(controller).resource_class
          key = klass.primary_key
          return unless key.is_a?(Array)

          controller.send(:scoped_collection).find(controller.params[:id].to_s.split(klass.param_delimiter, key.size))
        end

        # Formats the resource's controller answers, for resources that declare no download links.
        def default_download_formats(config) = config.controller.formats

        # Methods of AA's resource controller that refuse formats outside the download links.
        def format_guard_names = %i[restrict_format_access!]

        # The controller method AA asks which layout to render with.
        def layout_hook = :determine_active_admin_layout

        # Page and resource controllers are separate classes in AA, so each gets its own list.
        def prepend_controller_extensions(page:, resource:)
          {::ActiveAdmin::PageController => page, ::ActiveAdmin::ResourceController => resource}.each do |controller, mods|
            mods.each { |mod| controller.prepend(mod) unless controller.include?(mod) }
          end
        end
      end
    end
  end
end
