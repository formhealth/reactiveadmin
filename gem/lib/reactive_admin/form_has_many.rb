module ReactiveAdmin
  # Records `f.has_many`, mirroring ActiveAdmin::HasManyBuilder: one set of fields per existing
  # child plus a template for new ones. Template params carry INDEX_PLACEHOLDER for the client
  # to replace with the new row's index.
  class FormHasMany
    INDEX_PLACEHOLDER = "__INDEX__".freeze
    LAYOUTS = %w[cards compact].freeze
    # Rows holding just one of these read as a list item; anything bigger needs room for its label.
    COMPACT_CONTROLS = %w[text email url phone number select typeahead].freeze
    NO_INPUT = %w[hidden html content].freeze

    def initialize(recorder, schema, assoc, options)
      @recorder = recorder
      @builder = recorder.builder
      @schema = schema
      @assoc = assoc.to_sym
      @options = options
      @klass = @builder.object.class.reflect_on_association(@assoc).klass
      @schema.nested!(@assoc)
    end

    def call(&block)
      sortable = @options[:sortable]
      template = (fields(@klass.new, INDEX_PLACEHOLDER, &block) if new_record_label || @schema.only)
      records = @schema.only ? [] : children(sortable).each_with_index.map { |child, index| record(child, index, &block) }
      layout = layout(template, records)
      {
        title: heading(layout, template),
        kind: "has_many",
        name: @assoc.to_s,
        param_key: "#{@assoc}_attributes",
        param: "#{@builder.object_name}[#{@assoc}_attributes]",
        allow_destroy: !!@options[:allow_destroy],
        sortable: sortable&.to_s,
        new_record_label: new_record_label,
        layout:,
        max_rows: @options[:max_rows],
        fields: [],
        template_fields: template,
        records:
      }.compact
    end

    private

    # `reactive { nested_layout :assoc, :cards }` wins; otherwise a list when every row is a single control.
    def layout(template, records)
      declared = @schema.config.try(:reactive_options)&.dig(:nested_layout, @assoc)
      return declared if declared

      rows = [template, *records.map { it[:fields] }].compact
      (rows.any? && !@options[:sortable] && rows.all? { compact_row?(it) }) ? "compact" : "cards"
    end

    def compact_row?(fields)
      visible = fields.reject { NO_INPUT.include?(it[:control]) }
      visible.one? && COMPACT_CONTROLS.include?(visible.first[:control]) && !visible.first[:multiple]
    end

    # Without a `heading:`, a list of one control is named for what it holds ("Admin policy" ->
    # "Admin policies"); anything else for the association's model.
    def heading(layout, template)
      return (@options[:heading] if @options[:heading].is_a?(String)) if @options.key?(:heading)

      label = template.reject { NO_INPUT.include?(it[:control]) }.then { it.first[:label] if it.one? } if layout == "compact" && template
      label.present? ? label.pluralize : @klass.model_name.human(count: AA.plural_many_count)
    end

    def new_record_label
      case (option = @options.fetch(:new_record, true))
      when String then option
      when true then AA.t("has_many_new", model: @klass.model_name.human)
      end
    end

    def children(sortable)
      records = @builder.object.public_send(@assoc).to_a
      return records unless sortable

      records.sort_by { [it.public_send(sortable) || Float::INFINITY, it.id || Float::INFINITY] }
    end

    def record(child, index, &block)
      nested = nested_builder(child, index)
      fields = fields_for(nested, index, &block)
      fields << FormField.hidden_id(nested, child) if child.persisted?
      {id: (child.to_param.to_s if child.persisted?), param: nested.object_name, fields:, destroy: destroyable?(child)}.compact
    end

    def fields(child, index, &block) = fields_for(nested_builder(child, index), index, &block)

    def fields_for(nested, index, &block)
      recorder = FormRecorder.build(nested, @schema, prefix: @assoc.to_s)
      sortable = @options[:sortable]
      recorder.record do
        block.call(recorder, index)
        recorder.input(sortable, as: :hidden) if sortable
      end
      recorder.fields
    end

    def nested_builder(child, index)
      nested = nil
      @builder.fields_for(@assoc, child, child_index: index) { nested = it }
      nested
    end

    def destroyable?(child)
      case (option = @options[:allow_destroy])
      when Symbol, String then child.public_send(option)
      when Proc then option.call(child)
      else !!option
      end
    end
  end
end
