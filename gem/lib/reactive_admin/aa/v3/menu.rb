module ReactiveAdmin
  module AA
    module V3
      # AA's navigation menus: items carry procs that are evaluated in a view.
      module Menu
        # One menu item with its procs evaluated lazily in the view, in the order the caller asks.
        Entry = Struct.new(:item, :view) do
          def id = item.id

          def priority = item.priority

          def display? = evaluate(item.should_display)

          def url = evaluate(item.url)

          def label = evaluate(item.label)

          # The HTTP verb of a link such as logout.
          def http_method = item.html_options[:method]

          def children = item.items.map { Entry.new(it, view) }

          private

          def evaluate(value) = view.render_in_context(view, value)
        end

        def default_menu = ::ActiveAdmin::DEFAULT_MENU

        def utility_menu = :utility_navigation

        # The menu's top-level entries.
        def menu_entries(namespace, name, view) = namespace.fetch_menu(name).items.map { Entry.new(it, view) }

        # What AA would have listed for a config registered with `menu false`.
        def menu_entry_for(config, view) = Entry.new(::ActiveAdmin::MenuItem.new(config.default_menu_options), view)

        # AA's menu procs are instance_exec'd in a view that answers these.
        def prepare_menu_view(view, namespace:, user:, authorizer:)
          view.define_singleton_method(:authorized?) { |action, subject = nil| authorizer.authorized?(action, subject) }
          view.define_singleton_method(:current_active_admin_user) { user }
          view.define_singleton_method(:current_active_admin_user?) { !!user }
          view.define_singleton_method(:active_admin_namespace) { namespace }
        end

        # `belongs_to` moves an entry into the parent's own navigation menu (shown only when nested
        # under it) while leaving `include_in_menu?` true. A Proc names its menu per request, so it counts
        # as the default menu.
        def in_menu?(config)
          name = config.instance_variable_get(:@navigation_menu_name)
          config.include_in_menu? && (name.nil? || name.is_a?(Proc) || name == ::ActiveAdmin::DEFAULT_MENU)
        end

        # Where a resource sits in the default menu: `{priority:, parent:}` (the immediate parent group's
        # label), or nil when it isn't listed. The parent is read from the built item because AA
        # consumes the option's parent chain while adding it.
        def menu_placement(config)
          return unless in_menu?(config)

          parent = config.menu_item&.parent
          {priority: config.menu_item_options[:priority],
           parent: (parent.label.to_s if parent.is_a?(::ActiveAdmin::MenuItem) && !parent.label.respond_to?(:call))}
        end
      end
    end
  end
end
