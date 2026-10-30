module ReactiveAdmin
  # Stands in for AA's IndexAsTable while the `index do ... end` block runs, capturing columns
  # and rendering cells the way TableFor#build_table_cell does. An Element (not a Context):
  # Contexts forward unknown methods to their html string, which would swallow helpers like
  # `truncate` that column blocks call.
  class IndexRecorder < AA.arbre_element
    Column = AA.table_column_class

    attr_reader :columns, :row_options

    def self.build(resource_class, assigns, helpers)
      AA.arbre_context(assigns, helpers).insert_tag(self, resource_class)
    end

    def build(resource_class)
      @resource_class = resource_class
      @columns = []
      @column_classes = {}.compare_by_identity
      @index_starts = {}.compare_by_identity
      @id_columns = {}.compare_by_identity
    end

    def column(*args, &block)
      options = {i18n: @resource_class}.merge(args.extract_options!)
      title = args[0]
      explicit_class = options[:class]
      Column.new(title, args[1] || title, @resource_class, options, &block).tap do |col|
        @column_classes[col] = explicit_class
        @columns << col
      end
    end

    # The `class:` as written; Column keeps only the joined html class.
    def column_class(col) = @column_classes[col]

    def index_column?(col) = @index_starts.key?(col)

    def index_start(col) = @index_starts[col]

    def id_column?(col) = @id_columns.key?(col)

    # A composite key has no single attribute to read or sort by, so its column shows the joined param.
    def id_column(*args)
      options = args.extract_options!
      pk = @resource_class.primary_key
      return column(args[0].presence || "Id", **options.reverse_merge(sortable: false), &:to_param).tap { @id_columns[it] = true } if pk.is_a?(Array)

      title = args[0].presence || @resource_class.human_attribute_name(pk)
      column(title, pk.to_sym, options.reverse_merge(sortable: pk))
    end

    def selectable_column(*) = nil

    def index_column(start = 1)
      col = column("#", sortable: false)
      @index_starts[col] = start
    end

    # Only the block's custom items matter: View/Edit/Delete are derived from permissions and paths.
    def actions(*args, &block)
      @row_options = args.extract_options!
      @row_items = block
      nil
    end

    # Without an `actions` call the classic table has no View, Edit or Delete links either.
    def default_row_actions? = !@row_options.nil? && @row_options[:defaults] != false

    def dropdown? = !!@row_options&.[](:dropdown)

    def row_actions_label
      return unless @row_options

      label = dropdown? ? @row_options[:dropdown_name] || AA.t("dropdown_actions.button_label", default: "Actions") : @row_options[:name]
      label.to_s.presence
    end

    def row_items? = !@row_items.nil?

    # Renders a row's custom `item`s the way IndexTableFor#actions does.
    def render_row_items(record)
      items = table_actions do
        result = instance_exec(record, &@row_items)
        text_node result unless AA.arbre_element?(result)
      end
      items.to_s.tap { items.parent&.remove_child(items) }
    end

    # A grid or block view's item, or a blog or custom view's whole output for one record.
    def render_item(record, views)
      item = if views.custom? || views.kind == "blog"
        insert_tag(views.renderer, views.presenter, [record])
      else
        div { instance_exec(record, &views.presenter.block) }
      end
      html = item.to_s.tap { item.parent&.remove_child(item) }
      strip_selection(html)
    end

    def strip_selection(html)
      fragment = HtmlPolicy.parse(html) or return HtmlPolicy::TOO_COMPLEX

      fragment.css(".resource_selection_toggle_panel, .collection_selection").each(&:remove)
      fragment.to_html
    end

    def render_cell(record, col)
      cell = td do
        html = AA.format_attribute(helpers, record, col.data)
        current_arbre_element << html unless current_arbre_element.children.include?(html)
      end
      cell.children.to_s.tap { cell.parent&.remove_child(cell) }
    end
  end
end
