module ReactiveAdmin
  # Stands in for AA's ActiveAdminForm while a `form do |f| ... end` block runs: inputs are
  # recorded instead of rendered, and any other Arbre content (panels, paragraphs) is captured
  # as typed `content` fields between them (see FormContent). An Element for the same reason as IndexRecorder.
  class FormRecorder < AA.arbre_element
    Holder = Class.new(AA.arbre_element)

    NOOPS = %i[semantic_errors commit_action_with_cancel_link cancel_link].freeze

    attr_reader :builder, :sections

    def self.build(builder, schema, prefix: nil)
      AA.arbre_context(schema.assigns, schema.view).insert_tag(self, builder, schema, prefix)
    end

    def build(builder, schema, prefix)
      @builder = builder
      @schema = schema
      @prefix = prefix
      @sections = []
      @cuts = {}
    end

    def record(&block)
      within(self) do
        instance_exec(self, &block)
        flush_html
      end
      settle
      self
    end

    def object = builder.object

    def form_builder = builder

    NOOPS.each { |name| define_method(name) { |*, &| nil } }

    # Only the submit button's confirm is kept; the block runs in a holder that is thrown away.
    def actions(*, &block)
      return unless block

      holder = insert_tag(Holder) do
        block.arity.zero? ? block.call : block.call(self)
        nil
      end
      holder.parent&.remove_child(holder)
    rescue => e
      Rails.logger.warn("[reactiveadmin] #{@schema.config.resource_name} actions block skipped: #{e.class} at #{e.backtrace&.first}")
    end

    def action(name, options = {})
      @schema.record_submit_confirm(FormSchema.confirm_of(options[:button_html])) if name.to_s == "submit"
      nil
    end

    def inputs(*args, &block)
      options = args.extract_options!
      return nested_inputs(args, options, &block) if options[:for]

      title = options[:name] || options[:title] || (args.shift if args.first.is_a?(String) || (block && args.first.is_a?(Symbol)))
      flush_html
      @section = new_section(title&.to_s)
      if block
        guard(title) { collect { block.arity.zero? ? block.call : block.call(self) } }
      else
        (args.presence || default_columns(options)).each { input(it) }
      end
      flush_html
      @section = nil
    end

    def input(method, options = {}, &)
      flush_html
      field = FormField.new(builder, @schema, @prefix).call(method.to_sym, options)
      section[:fields] << field if field
    end

    def has_many(assoc, options = {}, &block)
      return unless @schema.wants_nested?(assoc.to_s)

      flush_html
      guard((options[:heading] if options[:heading].is_a?(String)) || assoc.to_s.humanize) { @sections << FormHasMany.new(self, @schema, assoc, options).call(&block) }
      @section = nil
    end

    # has_one and other single nested records: the nested builder's own sections join this form's.
    def semantic_fields_for(*args, &block)
      name = args.first if args.first.is_a?(Symbol) || args.first.is_a?(String)
      path = [@prefix, name].compact.join(".")
      return unless @schema.wants_nested?(path)

      flush_html
      nested = nil
      builder.fields_for(*args) { nested = it }
      @sections.concat(nested_sections(nested, path.presence, &block)) if nested
      @section = nil
    end
    alias_method :fields_for, :semantic_fields_for

    def fields = @sections.flat_map { it[:fields] || [] }

    # Content so far belongs in this spot: a marker says where, and `settle` fills the field once the
    # whole block has run (an element open around an input can't be walked before then).
    def flush_html(element = current_arbre_element)
      return discard(element) unless @schema.content?

      id = (@cuts.size + 1).to_s
      field = FormField.content(@schema.next_content_name)
      section[:fields] << field
      @cuts[id] = [section, field]
      text_node(FormContent.marker(id))
    end

    private

    def nested_inputs(args, options, &block)
      for_args = [options[:for], options[:for_options] || {}].flatten(1)
      inner = options.except(:for, :for_options)
      semantic_fields_for(*for_args) { |nested| nested.inputs(*args, inner, &block) }
    end

    def nested_sections(nested, path, &block)
      recorder = FormRecorder.build(nested, @schema, prefix: path)
      recorder.record { block.arity.zero? ? block.call : block.call(recorder) }
      sections = recorder.sections.reject { it[:kind] == "inputs" && it[:fields].empty? }
      sections.last[:fields] << FormField.hidden_id(nested, nested.object) if sections.any? && nested.object.try(:persisted?) && !@schema.only && nested_attributes?(nested)
      sections
    end

    # Rails emits the id of a persisted record only for an association the model takes nested attributes for.
    def nested_attributes?(nested) = nested.object_name.to_s.match?(/_attributes\]/)

    # A block that can't run here (it may need a parent record or params) costs its own section, not the form.
    def guard(label)
      yield
    rescue => e
      Rails.logger.warn("[reactiveadmin] #{@schema.config.resource_name} #{label} section unavailable: #{e.class} at #{e.backtrace&.first}")
      @schema.unsupported!(:section_failed)
      section[:fields] << FormField.html("<p>This section is unavailable here.</p>", @schema.next_html_name, label: label.to_s)
      Degradation.record(kind: :form_section_failed, where: "form/section[#{@sections.index(section)}]", reason: "Section raised #{e.class}; shown as unavailable")
    end

    # A write or one field's options only needs to know whether the markup holds inputs.
    def discard(element)
      @schema.scan_html(element.children.to_s)
      element.children.clear
    end

    # Walks everything the block rendered once, then gives each marker's field the nodes before it. A field
    # left empty (a wrapper around inputs) is dropped.
    def settle
      return if @cuts.empty?

      raw = children.to_s
      @schema.scan_html(raw)
      parts = @schema.content.split(raw) || [[nil, raw]]
      parts.each do |id, html|
        section, field = @cuts.delete(id) || next
        nodes = @schema.content.nodes(html)
        nodes.empty? ? drop(section, field) : field[:layout] = nodes
      end
      @cuts.each_value { |section, field| drop(section, field) }
    end

    def drop(section, field) = section[:fields].delete_if { it.equal?(field) }

    def section = @section ||= new_section(nil)

    def new_section(title) = {title:, kind: "inputs", fields: []}.tap { @sections << it }

    # Arbre content built by the block lands in a throwaway holder so it can be flushed in order.
    def collect
      insert_tag(Holder) do
        yield
        flush_html
        nil
      end
    end

    def default_columns(options) = AA.default_form_columns(builder, except: options[:except])

    ruby2_keywords def method_missing(name, *args, &block)
      return super unless builder.respond_to?(name)

      builder.public_send(name, *args, &block)
      nil
    end

    def respond_to_missing?(name, include_all = false) = builder.respond_to?(name, include_all) || super
  end
end
