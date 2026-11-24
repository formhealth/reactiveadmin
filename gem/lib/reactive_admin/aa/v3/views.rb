module ReactiveAdmin
  module AA
    module V3
      # AA's view helpers, Arbre, and the markup of its classic pages.
      module Views
        # Host procs and method names AA evaluates against a subject: `call_on` calls them, `render_or_call`
        # also accepts a string to render, `exec_in` runs a proc in the view.
        def call_on(view, subject, value) = view.call_method_or_proc_on(subject, value)

        def render_or_call(view, subject, value) = view.render_or_call_method_or_proc_on(subject, value)

        def exec_in(view, value) = view.call_method_or_exec_proc(value)

        def render_in_context(view, context, value) = view.render_in_context(context, value)

        # The attribute's value as AA's tables read it (a method, or a record's association).
        def find_value(view, record, attr) = view.find_value(record, attr)

        def format_attribute(view, record, attr) = view.format_attribute(record, attr)

        def pretty_format(view, value) = view.pretty_format(value)

        def display_name(view, record) = view.display_name(record)

        # The display name when the resource has a method AA knows, nil where AA would fall back to "Model #id".
        def explicit_display_name(view, record)
          method = view.display_name_method_for(record)
          view.render_in_context(record, method).to_s.strip.presence unless fallback_method?(method)
        end

        def display_name_fallback?(view, record) = fallback_method?(view.display_name_method_for(record))

        def plural_many_count = ::ActiveAdmin::Helpers::I18n::PLURAL_MANY_COUNT

        # The elements the index block and a show or page block run in, to subclass.
        def index_recorder_base = Recorders::Index

        def page_element_base = Recorders::Page

        def arbre_context(assigns, view) = ::Arbre::Context.new(assigns, view)

        def arbre_element?(object) = object.is_a?(::Arbre::Element)

        # The view helpers an Arbre tag was built with.
        def arbre_helpers(tag) = tag.arbre_context.helpers

        # Has `tracer` see every tag's `build`, once.
        def trace_arbre_tags(tracer) = (::Arbre::HTML::Tag.prepend(tracer) unless ::Arbre::HTML::Tag.include?(tracer))

        # Class names of the classic pages' components that HtmlNodes walks into typed nodes.
        MARKUP = {
          status_tag: "status_tag", empty: "empty", attributes_table: "attributes_table", panel: "panel",
          panel_contents: "panel_contents", tabs: "tabs", nav_tabs: "nav-tabs", tab_content: "tab-content",
          columns: "columns", column: "column", header_action: "header_action"
        }.freeze
        STRUCTURAL = MARKUP.values_at(:panel, :attributes_table, :tabs, :columns, :status_tag, :empty).freeze

        def markup = MARKUP

        # The contract's `span` limit.
        MAX_COLUMN_SPAN = 12

        # AA 3 sizes `column span:, max_width:, min_width:` only as inline styles: `width: N%`, with a 2% margin between
        # columns, so each width plus 2 is the column's span times one shared unit (the widths and margins add up to 102).
        # Answers each column's span (the smallest whole numbers in that ratio) and its raw `max-width` and `min-width`.
        # AA prints the widths at full Float precision, so the ratio only has to absorb rounding.
        def column_sizes(styles)
          css = styles.map { |style| style.to_s.split(";").filter_map { it.split(":", 2).map(&:strip) if it.include?(":") }.to_h }
          shares = css.map { it["width"].to_f + 2 }
          count = (1..(MAX_COLUMN_SPAN * shares.size)).find do |n|
            shares.all? { (it * n / shares.sum).then { |span| span >= 1 - 1e-6 && (span - span.round).abs < 1e-6 } }
          end
          css.zip(shares).map do |props, share|
            {span: count && (share * count / shares.sum).round, max_width: props["max-width"], min_width: props["min-width"]}
          end
        end

        # Containers whose children HtmlNodes must not flatten into a toolbar or pass through.
        def structural_classes = STRUCTURAL

        # Where a classic page keeps its content, and the chrome the embed hides.
        def frame_content_selector = "#main_content"

        def chrome_selectors = "#header, #footer, #title_bar, .breadcrumb, #sidebar, .flashes"

        # Stylesheet and script tags of AA's layout, for the embed layout's head.
        def embed_head(view)
          app = ::ActiveAdmin.application
          styles = app.stylesheets.map { |style, options| app.use_webpacker ? view.stylesheet_pack_tag(style, **options) : view.stylesheet_link_tag(style, **options) }
          scripts = app.javascripts.map { |path, options| app.use_webpacker ? view.javascript_pack_tag(path, **options) : view.javascript_include_tag(path, **options) }
          view.safe_join([*styles, *scripts], "\n")
        end

        private

        def fallback_method?(method) = method == ::ActiveAdmin::ViewHelpers::DisplayHelper::DISPLAY_NAME_FALLBACK
      end
    end
  end
end
