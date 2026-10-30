module ReactiveAdmin
  # One recorded `f.input`, described the way Formtastic would have rendered it: its input
  # class supplies the label, requiredness, hint, collection and param name.
  class FormField
    CONTROLS = {
      "string" => "text", "search" => "text", "color" => "text", "country" => "text",
      "text" => "textarea", "number" => "number", "range" => "number", "email" => "email",
      "url" => "url", "phone" => "phone", "password" => "password", "select" => "select",
      "time_zone" => "select", "radio" => "radio", "check_boxes" => "checkboxes",
      "boolean" => "boolean", "datepicker" => "date", "date_picker" => "date", "date_select" => "date",
      "datetime_picker" => "datetime", "datetime_select" => "datetime", "time_picker" => "time",
      "time_select" => "time", "file" => "file", "hidden" => "hidden", "datalist" => "typeahead",
      "typeahead" => "typeahead"
    }.freeze
    CHOICE_CONTROLS = %w[select radio checkboxes typeahead].freeze
    DAY_CONTROLS = %w[date datetime].freeze
    JSON_TYPES = %i[json jsonb hstore].freeze
    DERIVED_HTML = {
      "number" => %i[min max step], "date" => %i[min max], "datetime" => %i[min max],
      "text" => %i[maxlength], "textarea" => %i[maxlength],
      "email" => %i[maxlength], "url" => %i[maxlength], "phone" => %i[maxlength]
    }.freeze

    # Anything the API can't express is carried as sanitized html instead of being dropped.
    def self.html(html, name, label: "") = {name:, param: nil, label:, control: "html", value: html, required: false}

    # What the form block rendered around its inputs, read-only; the recorder fills `layout` once it can walk it.
    def self.content(name) = {name:, param: nil, label: "", control: "content", required: false}

    def self.hidden_id(nested, record)
      {name: "id", param: nested.field_name(:id), label: "Id", control: "hidden", value: record.to_param.to_s, required: false}
    end

    def initialize(builder, schema, prefix = nil)
      @builder = builder
      @schema = schema
      @view = schema.view
      @prefix = prefix
    end

    # Nil when the schema is built for one other field only.
    def call(method, options)
      return unless @schema.wants?([@prefix, method].compact.join("."))

      options = options.dup
      input = AA.build_input(@builder, @view, method, options)
      control = control_for(input)
      control ? build(input, control) : degraded(input)
    rescue => e
      Rails.logger.warn("[reactiveadmin] #{@schema.config.resource_name} field #{method} degraded: #{e.class} at #{e.backtrace&.first}")
      Degradation.record(kind: :form_field_failed, where: "form/field[#{[@prefix, method].compact.join(".")}]", reason: "Input raised #{e.class}; field left empty")
      @schema.unsupported!(:input_degraded)
      self.class.html("", @schema.next_html_name, label: method.to_s.humanize)
    end

    private

    def control_for(input)
      control = CONTROLS[input.as] or return
      return "date" if input.as == "string" && datepicker?(input)

      (json?(input) && %w[text textarea].include?(control)) ? "json" : control
    end

    # AA's JS datepicker is attached by class; the client has a native date control instead.
    def datepicker?(input) = input.options.dig(:input_html, :class).to_s.split.include?("datepicker")

    def build(input, control)
      multiple = control == "checkboxes" || (control == "select" && input.multiple?)
      control = "multiselect" if multiple && control == "select"
      return signals(input, control, multiple) if @schema.controls_only?

      value = value_for(input, control)
      field = {name: input.method.to_s, param: param(input, multiple), label: label(input), control:,
               value:, required: !!input.required?}
      field = summarized(field, input) if control == "json"
      field.merge!(choices(input, field, multiple)) if choice?(control)
      field = field.merge(extras(input, control).compact)
      field = api_marks(field, input)
      masked?(input, control) ? field.except(:value).merge(masked: true) : field
    end

    # What a write is judged by. A single select and a typeahead are normalized alike, so their options
    # are skipped. The other choice controls turn into a typeahead when truncated, which changes how a
    # blank is normalized, so for those the options are only counted.
    def signals(input, control, multiple)
      field = {name: input.method.to_s, param: param(input, multiple), control:}
      field[:value] = value_for(input, control) if control == "json"
      field = summarized(field, input) if control == "json"
      field.merge!(truncation(input, field)) if resolves_options?(control)
      field = field.merge(disabled: (true if input.options.dig(:input_html, :disabled) || input.readonly? || api_denied?(input))).compact.except(:value)
      masked?(input, control) ? field.merge(masked: true) : field
    end

    def api_denied?(input) = reserved_keys.intersect?(keys_of(input))

    def api_marks(field, input)
      return field.merge(disabled: true, api_denied: true, classic_url: ApiGuards.classic_url(@view.controller)) if api_denied?(input)

      ApiGuards.annotate(field, ApiGuards.attribute_guard(@schema.config, action_names, keys_of(input)))
    end

    def keys_of(input) = [input.method.to_s, input.input_name.to_s]

    def action_names = @action_names ||= ApiGuards.names_for(@view.controller)

    def reserved_keys = @reserved_keys ||= ApiGuards.reserved_keys(@schema.config, action_names)

    def resolves_options?(control) = choice?(control) && !%w[select typeahead].include?(control)

    # Same rule as a show row: a large value, or one with a masked key at any depth, is not sent. The
    # editor loads it through the audited `_value`, so a value never reaches the page unrecorded.
    def summarized(field, input)
      value = field[:value]
      return field unless ValuePayload.json?(value) && value.present?
      return field.merge(value: ValuePayload.mask(value, @schema.config)) unless @builder.object.persisted? && !ValuePayload.inline?(value, @schema.config)

      source = ValuePayload::Source.new(config: @schema.config, record: @builder.object, field: field[:name], controller: @view.controller, via: "form") unless @prefix || @schema.controls_only?
      field.merge(value: nil, summary: ValuePayload.summary(value), **{expand_path: ValuePayload.expand_path(source)}.compact)
    end

    # A new record has no stored value to protect, so its masked fields are ordinary inputs.
    def masked?(input, control) = control != "hidden" && @builder.object.try(:persisted?) && Masking.attribute?(input.method, @schema.config)

    def degraded(input)
      Degradation.record(kind: :form_field_html, where: "form/field[#{[@prefix, input.method].compact.join(".")}]", reason: "Input type #{input.as} has no typed control; shown as html")
      if @schema.controls_only?
        @schema.unsupported!(:input_degraded)
        return
      end

      collection = input.options[:collection]
      input.options[:collection] = @view.instance_exec(&collection) if collection.is_a?(Proc)
      html = HtmlNodes.sanitize(input.to_html)
      @schema.unsupported!(:input_degraded)
      self.class.html(html, input.method.to_s, label: label(input))
    rescue
      @schema.unsupported!(:input_degraded)
      self.class.html("", input.method.to_s, label: label(input))
    end

    # The builder names it as Rails does, `index:` of a repeated `fields_for` included. Formtastic's
    # check_boxes input_name is already the whole param, brackets included, and its hidden input posts
    # under the method name even for an association (`category`, not `category_id`).
    def param(input, multiple)
      kind = AA.input_kind(input)
      return plain(input.input_name) if kind == :check_boxes

      name = (kind == :hidden) ? input.method : input.input_name
      @builder.field_name(name, multiple:)
    end

    # An object-less form (`semantic_form_for ""`) posts top-level params, but Formtastic still wraps the name in brackets.
    def plain(param) = @builder.object_name.blank? ? param.to_s.sub(/\A\[([^\]]+)\]/, '\1') : param

    def label(input)
      return "" if input.options[:label] == false

      (input.localized_label || input.humanized_method_name).to_s
    end

    def extras(input, control)
      {
        hint: (CGI.unescapeHTML(@view.strip_tags(input.hint_text.to_s)) if input.hint?),
        placeholder: input.options[:placeholder] || input.options.dig(:input_html, :placeholder),
        errors: input.errors.presence,
        disabled: (true if input.options.dig(:input_html, :disabled) || input.readonly?),
        free_text: (true if %w[datalist typeahead].include?(input.as)),
        input_html: input_html(input, control)
      }
    end

    # Limits Formtastic derives from validations/columns, plus whatever the form block set explicitly.
    def input_html(input, control)
      derived = input.input_html_options.slice(*DERIVED_HTML.fetch(control, []))
      html = derived.merge(input.options[:input_html].to_h.slice(*DERIVED_HTML.values.flatten, :rows))
      html = html.merge(day_limits(input, html, control)) if DAY_CONTROLS.include?(control)
      html.compact_blank.presence
    end

    # `input_html:` wins over the classic datepicker's `datepicker_options: {min_date:, max_date:}`.
    def day_limits(input, html, control)
      picker = input.options[:datepicker_options].to_h.transform_keys { it.to_s.underscore.to_sym }
      %i[min max].to_h { |limit| [limit, DateBound.call(html[limit] || picker[:"#{limit}_date"], control)] }
    end

    def choices(input, field, multiple)
      key = [@prefix, field[:name]].compact.join(".")
      source = collection_choices(input, key)
      @schema.choices[key] ||= source
      return {} if @schema.only

      listing = source.list(Array(field[:value]).map(&:to_s), ReactiveAdmin.config.inline_options_limit)
      attrs = {options: listing[:options], multiple: (true if multiple)}.compact
      return attrs unless listing[:truncated]

      attrs.merge(control: "typeahead", options_path: Choices.path(@schema.config, key, "form", id: @schema.record_id, parent_id: @schema.parent_id))
    end

    def truncation(input, field)
      source = collection_choices(input, [@prefix, field[:name]].compact.join("."))
      source.truncated?(ReactiveAdmin.config.inline_options_limit) ? {control: "typeahead"} : {}
    end

    def collection_choices(input, key)
      return Choices.for(ActiveSupport::TimeZone.all.map { [it.to_s, it.name] }, @view) if input.as == "time_zone"

      cache = Choices.cache_key(@schema.config, "form", key, @view, id: @schema.record_id, parent_id: @schema.parent_id)
      return Choices.source(input.options[:source], @view, scope: input.options[:scope], object: scope_object, policy: true, cache:) if input.options[:source]

      collection = input.options[:collection]
      return Choices.for(collection, @view, cache:, policy: true) if collection.is_a?(Proc)

      raw = input.raw_collection
      if raw.is_a?(ActiveRecord::Relation)
        Choices.for(raw, @view, label: input.label_method, value: input.value_method, policy: true)
      else
        Choices.for(input.collection, @view, cache:)
      end
    end

    # Inside has_many the parent's form object, matching what the classic input hands to `scope:`.
    def scope_object = (@builder.options[:parent_builder] || @builder).object

    def json?(input)
      type = @builder.object.class.type_for_attribute(input.method.to_s).type
      JSON_TYPES.include?(type) || current(input).is_a?(Hash) || current(input).is_a?(Array)
    rescue
      false
    end

    def current(input)
      object = @builder.object
      names = [(input.association_primary_key if input.respond_to?(:association_primary_key)), input.input_name, input.method]
      name = names.find { (it.is_a?(Symbol) || it.is_a?(String)) && object.respond_to?(it) }
      object.public_send(name) if name
    end

    def value_for(input, control)
      return if control == "password"

      value = current(input)
      html = input.options[:input_html].to_h
      return serialize(html[:value], control) if value.nil? && html.key?(:value)

      (control == "boolean" && value.nil? && html.key?(:checked)) ? !!html[:checked] : serialize(value, control)
    end

    def serialize(value, control)
      case value
      when Time, DateTime, ActiveSupport::TimeWithZone then temporal(value, control)
      when Date then value.iso8601
      when BigDecimal then value.to_s("F")
      when Symbol then value.to_s
      when Hash then value
      when Array then (control == "json") ? value : value.map { serialize(it, control) }
      else attachment_or_choice(value, control)
      end
    end

    def attachment_or_choice(value, control)
      if value.respond_to?(:attached?)
        {filename: value.filename.to_s} if value.attached?
      else
        (choice?(control) && !value.nil?) ? value.to_s : value
      end
    end

    def temporal(value, control)
      case control
      when "time" then value.strftime("%H:%M:%S")
      when "date" then value.to_date.iso8601
      else value.iso8601
      end
    end

    def choice?(control) = CHOICE_CONTROLS.include?(control) || control == "multiselect"
  end
end
