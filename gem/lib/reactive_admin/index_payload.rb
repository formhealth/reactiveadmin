module ReactiveAdmin
  class IndexPayload
    NUMERIC_TYPES = %i[integer float decimal].freeze
    ALIGNMENTS = {"right" => /(\A|[-_])(right|number|numeric|amount|money|currency)\z/, "center" => /(\A|[-_])center\z/, "left" => /(\A|[-_])left\z/}.freeze
    TONES = {"danger" => %w[danger error alert], "warning" => %w[warning warn], "success" => %w[success ok], "info" => %w[info]}.freeze

    def initialize(controller)
      @controller = controller
      @config = AA.config_of(controller)
      @view = Masking.install(controller.view_context, @config)
      @authorizer = Authorizer.for(controller)
      @permissions = Permissions.new(@config, @authorizer)
      @views = IndexViews.new(@config, as: @controller.params[:as])
    end

    def as_json(*)
      # Must run first: it applies filtering/scoping/sorting and memoizes the pre-scope chain.
      records = AA.collection(@controller)
      recorder = columns_recorder
      if (sort = unsupported_sort(recorder))
        raise ApiErrors::BadRequest, "Unsupported sort: #{sort}"
      end
      keys = column_keys(recorder, recorder.columns)

      Degradation.attach({
        resource: Registry.route_key(@config),
        columns: recorder.columns.zip(keys).map { |col, key| column_json(col, key, recorder) },
        rows: records.each_with_index.map { |record, index| row(record, recorder, keys, records.try(:offset_value).to_i + index) },
        meta: meta(records, recorder)
      })
    end

    # [column json, attribute name or nil] for each column, without reading any rows.
    def declared_columns
      recorder = columns_recorder
      recorder.columns.zip(column_keys(recorder, recorder.columns)).map do |col, key|
        [column_json(col, key, recorder), (col.data.to_s if col.data.is_a?(Symbol))]
      end
    end

    # Attributes shown as symbol columns: the allowlist for `_value`.
    def symbol_columns = columns_recorder.columns.filter_map { it.data if it.data.is_a?(Symbol) }

    # The requested `order`'s sort key when the index doesn't offer it. Ordering by a column the
    # page hides would leak how its values compare.
    def unsupported_sort(recorder = columns_recorder)
      QueryGuard.order_violation(@config, @controller.params[:order], recorder.columns.select { orderable?(it) }.map(&:sort_key))
    end

    private

    def columns_recorder = @views.table? ? record_columns : new_recorder

    def record_columns
      block = @views.presenter&.block
      return new_recorder.tap { default_columns(it) } unless block

      new_recorder.tap { it.instance_exec(it, &block) }
    rescue => e
      Rails.logger.warn("[reactiveadmin] #{@config.resource_name} index block fell back to defaults: #{e.class} at #{e.backtrace&.first}")
      Degradation.record(kind: :index_block_failed, where: "index", reason: "Index block raised #{e.class}; showing default columns")
      new_recorder.tap { default_columns(it) }
    end

    def new_recorder = IndexRecorder.build(@config.resource_class, @controller.view_assigns, @view)

    def default_columns(recorder)
      return ImplicitDefaults.blocked("index") if ImplicitDefaults.strict?

      recorder.id_column if @config.resource_class.primary_key
      @implicit_text = ImplicitDefaults.text_columns(@config)
      ImplicitDefaults.columns(@config, where: "index").each { recorder.column(it) }
      recorder.actions
    end

    def column_keys(recorder, columns)
      seen = Hash.new(0)
      columns.map do |col|
        base = key_base(recorder, col)
        ((seen[base] += 1) == 1) ? base : "#{base}_#{seen[base]}"
      end
    end

    def key_base(recorder, col)
      return "index" if recorder.index_column?(col)

      (col.data.is_a?(Symbol) ? col.data : col.title).to_s.parameterize(separator: "_").presence || "column"
    end

    # pretty_title overwrites the column's symbol title with its label, which sort_key then reads.
    def column_json(col, key, recorder)
      sortable = orderable?(col)
      class_name = recorder.column_class(col).to_s.presence
      {key:, label: col.dup.pretty_title.to_s, sortable:, sort_key: (col.sort_key if sortable)}.merge(
        {kind: ("index" if recorder.index_column?(col)), class_name:, align: align(col, class_name, sortable, recorder)}.compact
      )
    end

    # A sort key the controller can't parse back, or that AA's order clause would rewrite, would
    # order by something else (or nothing) when the client sent it.
    def orderable?(col)
      return false unless col.sortable?

      key = col.sort_key
      clause = AA.order_clause(@config, "#{key}_asc")
      clause.valid? && clause.field == key
    end

    def align(col, class_name, sortable, recorder)
      words = class_name.to_s.split
      ALIGNMENTS.each { |side, pattern| return side if words.any? { pattern.match?(it) } }
      "right" if recorder.index_column?(col) || numeric?(col.data.is_a?(Symbol) ? col.data.to_s : (col.sort_key if sortable))
    end

    # Ids and enums are labels, not quantities.
    def numeric?(name)
      klass = @config.resource_class
      column = klass.columns_hash[name.to_s] if name
      !!column && NUMERIC_TYPES.include?(column.type) && name != klass.primary_key &&
        !name.end_with?("_id") && !klass.defined_enums.key?(name)
    end

    def row(record, recorder, keys, position)
      links = ActionLinks.new(host: @controller.request.host, base_url: @controller.request.base_url, authorizer: @authorizer, subject: record)
      row = {id: record.to_param.to_s, display_name: Values.display_name(record, @view), paths: Paths.record(@config, record),
             permissions: @permissions.record(record)}
      return row.merge(cells: {}, layout: item_layout(record, recorder, links, row[:display_name])) unless @views.table?

      cells = recorder.columns.zip(keys).to_h { |col, key| [key, cell(record, col, recorder, links, position)] }
      actions = row_actions(record, recorder, links)
      row = row.merge(cells:, **row_style(record))
      actions.any? ? row.merge(actions:) : row
    end

    def item_layout(record, recorder, links, fallback)
      HtmlNodes.nodes(recorder.render_item(record, @views), host: @controller.request.host, links:, resource: @config.resource_name)
    rescue => e
      Rails.logger.warn("[reactiveadmin] #{@config.resource_name} #{@views.name} view failed: #{e.class} at #{e.backtrace&.first}")
      Degradation.record(kind: :item_view_failed, where: "index/view[#{@views.name}]", reason: "Item view raised #{e.class}; showing the display name")
      [{type: "text", text: fallback.to_s}]
    end

    def row_style(record)
      block = @views.presenter&.[](:row_class)
      class_name = Array(block.call(record)).flatten.compact_blank.join(" ").presence if block
      words = class_name.to_s.downcase.split(/[^a-z0-9]+/)
      tone = TONES.find { |_, names| (names & words).any? }&.first
      {class_name:, tone:}.compact
    rescue => e
      Rails.logger.warn("[reactiveadmin] #{@config.resource_name} row_class failed: #{e.class} at #{e.backtrace&.first}")
      Degradation.record(kind: :row_class_failed, where: "index/row_class", reason: "row_class raised #{e.class}; rows left unstyled")
      {}
    end

    def row_actions(record, recorder, links)
      return [] unless recorder.row_items?

      ActionLinks.controls(recorder.render_row_items(record)).filter_map { links.action(it, placement: "row") }
    rescue => e
      Rails.logger.warn("[reactiveadmin] #{@config.resource_name} row items failed: #{e.class} at #{e.backtrace&.first}")
      Degradation.record(kind: :row_actions_failed, where: "index/row_actions", reason: "Row actions raised #{e.class}; rows have no actions")
      []
    end

    def cell(record, col, recorder, links, position)
      if recorder.index_column?(col)
        {type: "number", value: position + recorder.index_start(col)}
      elsif recorder.id_column?(col) || (col.data.is_a?(Symbol) && col.data.to_s == @config.resource_class.primary_key)
        {type: "ref", label: (col.data.is_a?(Symbol) ? record.public_send(col.data) : record.to_param).to_s, ref: Registry.ref(record)}.compact
      elsif col.data.is_a?(Symbol)
        value = AA.find_value(@view, record, col.data)
        source = ValuePayload::Source.new(config: @config, record:, field: col.data.to_s, controller: @controller, via: "index")
        if value.is_a?(String) && @implicit_text&.include?(col.data.to_s) then ImplicitDefaults.text_node(value, source, inline: false)
        else Masking.node(@config, col.data, value) || Values.for(value, @view, source:)
        end
      else
        HtmlNodes.convert(recorder.render_cell(record, col), host: @controller.request.host, links:, resource: @config.resource_name)
      end
    rescue => e
      Rails.logger.warn("[reactiveadmin] #{@config.resource_name} cell #{col.title} failed: #{e.class} at #{e.backtrace&.first}")
      Degradation.record(kind: :cell_failed, where: "index/column[#{key_base(recorder, col)}]", reason: "Cell raised #{e.class}")
      {type: "error", label: "Couldn't display this value"}
    end

    def meta(records, recorder)
      counted = ResourceMeta.pagination_total?(@config, @views.presenter)
      {
        page: records.try(:current_page) || 1,
        per_page: records.try(:limit_value) || records.size,
        total_count: (records.try(:total_count) || records.size if counted),
        total_pages: (records.try(:total_pages) || 1 if counted),
        has_next_page: next_page?(records, counted),
        scopes: scopes,
        current_scope: AA.current_scope(@controller)&.id,
        order: @controller.params[:order]
      }.merge(view_meta(recorder))
    end

    def view_meta(recorder)
      table = @views.table?
      {
        as: @views.name,
        view: @views.kind,
        grid_columns: (@views.grid_columns if @views.kind == "grid"),
        title: @views.title(@controller),
        blank_slate: @views.blank_slate(@view),
        default_row_actions: table && recorder.default_row_actions?,
        row_actions_label: (recorder.row_actions_label if table),
        row_actions_dropdown: (true if table && recorder.dropdown?),
        paginator: (false unless @views.paginator?),
        per_page_options: @views.per_page_options,
        sidebars: Sidebars.new(@controller, "index", src: Paths.collection(@config, parent_id: Paths.parent_id(@config, @controller.params))).as_json.presence
      }.compact
    end

    # Without totals the answer costs one indexed probe past the page, as in AA's countless paginator.
    def next_page?(records, counted)
      return records.current_page < records.total_pages if counted && records.respond_to?(:total_pages)
      return false unless records.respond_to?(:offset)

      records.offset(records.current_page * records.limit_value).exists?
    end

    def scopes
      before_scope = AA.collection_before_scope(@controller)
      counts = @views.presenter&.fetch(:scope_count, true) != false
      visible = AA.scopes(@config).select { AA.scope_visible?(@view, it) }
      IndexViews.scopes_in_render_order(visible).map do |scope|
        count = AA.scope_count(@controller, scope, before_scope) if counts
        {id: scope.id, name: AA.scope_name(@view, scope), count:}.merge(scope.group ? {group: scope.group.to_s} : {})
      end
    end
  end
end
