module ReactiveAdmin
  module AA
    module V3
      # Registrations, namespace settings and authorization.
      module Registry
        def namespace(name) = ::ActiveAdmin.application.namespaces[name]

        # Everything registered in the namespace, resources and pages, as AA's own collection.
        def registrations(namespace) = namespace.resources

        def resource?(config) = config.is_a?(::ActiveAdmin::Resource)

        def page?(config) = config.is_a?(::ActiveAdmin::Page)

        # The resource registered for a model, or nil (pages and unregistered models too).
        def resource_for(namespace, klass)
          config = namespace.resources[klass]
          config if resource?(config)
        end

        def defined_actions(config) = config.defined_actions

        # Member and collection actions of a resource, or the actions of a page.
        def custom_actions(config) = page?(config) ? config.page_actions : [*config.member_actions, *config.collection_actions]

        def root_page_key(namespace) = namespace.root_to.to_s.split("#").first

        def current_user_method(namespace) = namespace.current_user_method

        # The adapter class the namespace authorizes with (AA stores a class or its name).
        def authorization_adapter(namespace)
          adapter = namespace.authorization_adapter
          adapter.is_a?(String) ? adapter.constantize : adapter
        end

        def load_registrations! = ::ActiveAdmin.application.load!

        def draw_routes(router) = ::ActiveAdmin.routes(router)

        def on_before_load(&block) = ActiveSupport::Notifications.subscribe(::ActiveAdmin::Application::BeforeLoadEvent) { block.call }

        # Attributes AA keeps out of default views and forms.
        def filter_attributes = ::ActiveAdmin.application.filter_attributes

        def display_name_methods = ::ActiveAdmin.application.display_name_methods

        def default_per_page = ::ActiveAdmin.application.default_per_page

        def localize_format = ::ActiveAdmin.application.localize_format

        # The namespace's settings, as its site header evaluates them for a view.
        def site_settings(namespace, view)
          {
            name: namespace.name,
            title: namespace.site_title(view),
            title_link: namespace.site_title_link,
            title_image: namespace.site_title_image(view),
            favicon: namespace.favicon,
            footer: namespace.footer(view),
            comments: !!namespace.try(:comments),
            default_per_page: namespace.default_per_page,
            max_per_page: namespace.max_per_page,
            logout_path: namespace.logout_link_path,
            logout_method: namespace.logout_link_method
          }
        end

        def site_title(view) = ::ActiveAdmin.application.site_title(view)

        # A text of the resource's locale scope, such as `:details`.
        def resource_text(config, key) = ::ActiveAdmin::Localizers.resource(config).t(key)

        # AA's own translations (`active_admin.*`).
        def t(key, **) = I18n.t("active_admin.#{key}", **)
      end
    end
  end
end
