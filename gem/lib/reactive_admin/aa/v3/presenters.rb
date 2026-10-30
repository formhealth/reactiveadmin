module ReactiveAdmin
  module AA
    module V3
      # What a resource or page declares: presenters, filters, scopes, batch actions, action items
      # and sidebars.
      module Presenters
        BUILT_IN_INDEX = %w[Table Grid Blog Block].freeze

        # The presenter of a page type (`:index`, `:show`, `:form`); for `:index`, `as` picks one of
        # several index views.
        def page_presenter(config, type, as = nil) = as ? config.get_page_presenter(type, as) : config.get_page_presenter(type)

        # All index presenters: a Hash by `as` when the resource declared several.
        def index_presenters(config) = config.page_presenters[:index]

        # Built-in index renderers by name; anything else a host passes as `as:` is custom.
        def index_renderers = @index_renderers ||= BUILT_IN_INDEX.to_h { [it.downcase, ::ActiveAdmin::Views.const_get("IndexAs#{it}")] }

        def index_renderer(as)
          case as
          when Class then as
          when nil then ::ActiveAdmin::Views::IndexAsTable
          else ::ActiveAdmin::Views.const_get("IndexAs#{as.to_s.camelcase}")
          end
        end

        def index_name(renderer) = renderer.index_name

        def table_column_class = ::ActiveAdmin::Views::TableFor::Column

        # A copy of a table column that reads `data` instead (a masked export, say).
        def column_with_data(column, data) = column.dup.tap { it.instance_variable_set(:@data, data) }

        # AA's parse of an `order` param (`name_desc`), which rewrites keys it doesn't recognise.
        def order_clause(config, order) = config.order_clause.new(config, order)

        def filters(config) = config.filters

        def filters_enabled?(config) = config.filters_enabled?

        def scopes(config) = config.scopes

        def scope_visible?(view, scope) = view.call_method_or_exec_proc(scope.display_if_block)

        def scope_name(view, scope) = view.scope_name(scope)

        # The scope's row count, or nil when it doesn't show one. `chain` is the collection before scoping.
        def scope_count(controller, scope, chain)
          collection_size(scope_chain(controller, scope, chain)) if scope.show_count
        end

        def batch_actions(config) = config.batch_actions

        def batch_action_visible?(view, action) = view.call_method_or_proc_on(view, action.display_if_block)

        def batch_action_title(view, action) = view.render_or_call_method_or_proc_on(view, action.title)

        def batch_action_confirm(view, action) = view.render_or_call_method_or_proc_on(view, action.confirm)

        # The `form:` dialog's inputs: `{name => type}`, where a type is an input kind or a list of options.
        def batch_action_inputs(view, action) = view.render_in_context(view, action.inputs)

        # Items in the order AA lays them out.
        def action_items(config) = config.action_items.each_with_index.sort_by { |item, index| [item.priority, index] }.map(&:first)

        # The item rendered for a page, or nil when it isn't displayed there.
        def render_action_item(item, page, assigns, view)
          context = arbre_context(assigns, view)
          return unless item.display_on?(page, context)

          context.insert_tag(::ActiveAdmin::Views::ActionItems, [item])
          context.to_s
        end

        def sidebar_sections(config) = config.sidebar_sections? ? config.sidebar_sections : []

        # `{title:, html:}` of a section's contents for an action, or nil when it isn't displayed there.
        def render_sidebar(section, action, assigns, view)
          context = arbre_context(assigns, view)
          return unless section.display_on?(action, context)

          panel = context.insert_tag(::ActiveAdmin::Views::SidebarSection, section)
          fragment = HtmlPolicy.parse(panel.to_s)
          {title: section.title, html: fragment ? fragment.at_css(".panel_contents")&.inner_html : HtmlPolicy::TOO_COMPLEX}
        end

        # Row count the way AA's paginator and scope counts take it: ignores select and order, and
        # counts groups.
        def collection_size(relation) = (@collection_helper ||= Object.new.extend(::ActiveAdmin::Helpers::Collection)).collection_size(relation)
      end
    end
  end
end
