module ReactiveAdmin
  module AA
    # ActiveAdmin 4 (tested against 4.0.0.beta23), not supported yet: the gemspec stays `< 4`. It
    # inherits V3 for what the AA 4 source shows to be unchanged, implements the small differences, and
    # raises NotImplementedError for the rest, each naming what to build (docs/internal/AA_SOURCE_NOTES.md, 3).
    # The `aa4` CI probe boots the dummy app against it and reports what still fails.
    #
    # Hook names our prepended modules override that differ in AA 4 are not renamed here but through the
    # `format_guard_names` and `layout_hook` methods; the others (`authenticate_active_admin_user`,
    # `dispatch_active_admin_access_denied`, `action_to_permission`, `find_resource`) exist unchanged.
    module V4
      include V3

      TODO = {
        index_renderers: "IndexAsGrid, IndexAsBlog and IndexAsBlock are gone; only table and custom classes remain",
        index_renderer: "no built-in grid, blog or block renderers; map `as:` to a table or a custom class",
        scope_count: "scopes take `show_count: :async` (Scope#async_count?, AsyncCount); honour it or count synchronously",
        batch_action_inputs: "no `form:` hash or `inputs`; batch actions take `partial:` and `link_html_options:`, so flag them degraded",
        render_action_item: "Views::ActionItems is gone; run the item's block with instance_exec against the context",
        render_sidebar: "Views::SidebarSection is gone; sections are blocks or partials, and `title` is an I18n lookup",
        menu_entries: "menu items evaluate `label(ctx)`, `url(ctx)`, `display?(ctx)` and `items(ctx)`; one nesting level",
        menu_entry_for: "build the item from the config's default menu options for resources registered with `menu false`",
        prepare_menu_view: "the menu API takes the context as an argument instead of reading helpers off the view",
        menu_placement: "`menu_item.parent` is a single level; read the parent through the new item API",
        site_settings: "namespace settings removed (logout link, footer, site_title_image, ...); read what remains, nil for the rest",
        default_download_formats: "`controller.formats` is gone; read the formats from the resource config",
        layout_hook: "the layout is static (`layout \"active_admin\"`); declare a `layout` lambda instead of overriding a method",
        embed_head: "assets come from importmap (`javascript_importmap_tags`, `stylesheet_link_tag \"active_admin\"`), not `application.stylesheets`",
        display_name_fallback?: "`DISPLAY_NAME_FALLBACK` moved with the display helper (ActiveAdmin::DisplayHelper)",
        explicit_display_name: "see display_name_fallback?"
      }.freeze

      TODO.each do |name, change|
        define_method(name) { |*, **, &| raise NotImplementedError, "ReactiveAdmin::AA::V4##{name}: #{change}" }
      end

      def format_guard_names = %i[restrict_download_format_access!]

      # Moved out of AA's Helpers::Collection into IndexHelper.
      def collection_size(relation)
        return relation.count if relation.is_a?(Array)
        return relation.length if relation.limit_value

        relation = relation.except(:select, :order)
        relation.group_values.present? ? relation.count.count : relation.count
      end

      # Inlined in AA 4 (no ActiveAdmin::Helpers::I18n::PLURAL_MANY_COUNT).
      def plural_many_count = 2.1

      # Private in AA 4.
      def find_value(view, record, attr) = view.send(:find_value, record, attr)

      def frame_content_selector = "[data-test-page-content]"

      def chrome_selectors = "[data-test-page-header], #main-menu, header"
    end
  end
end
