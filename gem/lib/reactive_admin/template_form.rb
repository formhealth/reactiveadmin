module ReactiveAdmin
  # FormResponse for a custom ERB template whose forms are Formtastic-only. The template renders as
  # it does in the classic admin, except that its form builders record their inputs instead of
  # printing them. The first form is the response; html around it is kept in order as html fields,
  # unless the template has more to show (further forms, row actions, results after the form), in
  # which case everything outside the form becomes typed `layout` nodes with the form in place.
  class TemplateForm
    Unsupported = Class.new(StandardError)

    METHODS = %w[get post put patch delete].freeze

    # Mixed into the view that renders the template.
    module Recording
      def semantic_form_for(*args, &block)
        state = @_reactiveadmin_template
        return super unless state
        return state.extra_form(self) { semantic_form_for(*args, &block) } if state.extra_form?

        items = nil
        markup = super do |builder|
          state.objects << builder.object
          items = state.expand(state.capture(self, Recorder.new(builder, state, self), &block))
          "".html_safe
        end
        state.mark([:form, {items:, **Form.target(markup)}])
      end

      # AA's version builds an Arbre form around a real builder, which the recorder can't stand in for.
      def active_admin_form_for(resource, options = {}, &block)
        state = @_reactiveadmin_template
        return super unless state
        return state.extra_form(self) { active_admin_form_for(resource, options, &block) } if state.extra_form?

        state.arbre { semantic_form_for(resource, {builder: AA.form_builder}.merge(options), &block) }
      end
    end

    # Reads the form tag Rails built: its action and verb, whichever way `url:` and `method:` were given.
    module Form
      module_function

      def target(markup)
        form = HtmlPolicy.parse(markup.to_s)&.at_css("form")
        verb = form&.at_css("input[name=_method]")&.[]("value") || form&.[]("method")
        {path: form&.[]("action"), method: verb.to_s.downcase}
      end

      # A GET form is a client-side navigation: it must re-read the very view that served it, with its
      # fields as the query. Returns that view's classic path, or nil for a form that goes to another page.
      def own_view(url, request)
        uri = URI.parse(url.to_s)
        return if uri.host.present? && !uri.host.casecmp?(request.host)
        return view_path(request) if uri.path.blank?

        uri.path.chomp("/") if same_route?(uri.path, request)
      rescue URI::InvalidURIError
        nil
      end

      # By route rather than by path, so a request that reached the action by another URL (a trailing slash, the
      # API's page endpoint) still counts as the same view.
      def same_route?(path, request)
        current = identify(request.path_parameters)
        identify(Rails.application.routes.recognize_path(path, method: "GET")) == current
      rescue ActionController::RoutingError
        false
      end

      def identify(params)
        params.except(:format).transform_values(&:to_s).tap { it[:action] = "index" if it[:action] == "reactiveadmin_page" }
      end

      # The classic path of the request being served, which an API request reaches under the mount.
      def view_path(request) = request.path.delete_prefix(ReactiveAdmin.config.mount_path).sub("/_pages/", "/").chomp("/")
    end

    # The ordered record of what a template printed: each recording call leaves a marker in the output
    # that points at its entry, so inputs and plain html keep the order the template gave them.
    class State
      attr_reader :schema, :entries, :objects, :marker_pattern
      attr_accessor :submit_label, :submit_confirm

      # With a controller, forms after the first record as inline `form` nodes of the layout.
      def initialize(schema, controller: nil)
        @token = SecureRandom.hex(8)
        @marker_pattern = /<!--ra:#{@token}:(\d+)-->/
        @schema = schema
        @controller = controller
        @entries = []
        @buffers = []
        @objects = []
      end

      def extra_form? = @controller && entries.any? { it.first == :form }

      def extras? = @extras

      # A form the recorder can't describe is left to print as it does in the classic admin.
      def extra_form(view, &block)
        @extras = true
        forms.node(view, &block) || forms.suspended { printing(view, &block) }
      end

      def mark(entry)
        @entries << entry
        marker(@entries.size - 1).html_safe.tap { @buffers.last&.push(it) }
      end

      # AA's form components record by statement (`f.input` registers itself), where Formtastic
      # templates print with `<%= %>`. Within an arbre form every mark counts, not just the printed ones.
      def arbre
        previous = @arbre
        @arbre = true
        yield
      ensure
        @arbre = previous
      end

      def capture(view, *args, &block)
        return view.capture(*args, &block) unless @arbre

        buffer = []
        @buffers.push(buffer)
        printed = view.capture(*args, &block).to_s
        (buffer.size > printed.scan(marker_pattern).size) ? buffer.join.html_safe : printed
      ensure
        @buffers.pop if buffer
      end

      def expand(html)
        html.to_s.split(marker_pattern).each_slice(2).flat_map do |text, id|
          [(text unless text.strip.empty?), (@entries[id.to_i] if id)].compact
        end
      end

      # scan_html treats markup too deep to parse as unsupported raw input, so the form isn't submittable.
      def html_field(html)
        schema.scan_html(html)
        return if schema.controls_only?

        FormField.html(HtmlNodes.sanitize(html).strip, schema.next_html_name) if visible?(html)
      end

      # The fields among recorded items, in order; plain html between them becomes html fields.
      def fields(items)
        items.flat_map do |item|
          case item
          in String then [html_field(item)].compact
          in [:field, Hash => field] then [field]
          in [:section, Hash => section] then section[:fields]
          in [:group, Array => list] then fields(list)
          else []
          end
        end
      end

      # Plain html before, between and after the forms stays as html fields; the first heading is the title.
      def arrange(html) = arrange_items(expand(html).flat_map { |item| (item in [:form, Hash => inner]) ? inner[:items] : [item] })

      def arrange_items(items)
        title = nil
        sections = []
        loose = nil
        items.each do |item|
          case item
          in String
            title ||= extract_title!(item)
            field = html_field(item) or next
            (loose ||= new_section(sections)) && loose[:fields] << field
          in [:section, section]
            loose = nil
            sections << section
          in [:field | :group, _]
            fields([item]).each { (loose ||= new_section(sections))[:fields] << it }
          end
        end
        [sections.reject { it[:fields].empty? }, title]
      end

      # Whether the template shows more than its form: further forms, controls that act, or content after it.
      def layout?(html, index)
        return false unless html.to_s.include?(marker(index))
        return true if extras? || ActionLinks.controls(html).any? { ActionLinks.control?(it) }

        visible?(html.to_s.split(marker(index), 2).last)
      end

      # The token is random per render, so stored text can't forge a marker for an entry.
      def marker(index) = "<!--ra:#{@token}:#{index}-->"

      def new_section(sections) = {kind: "inputs", fields: []}.tap { sections << it }

      def extract_title!(chunk)
        fragment = HtmlPolicy.parse(chunk) or return
        heading = fragment.at_css("h1, h2, h3, h4") or return
        heading.text.strip.presence&.tap do
          heading.remove
          chunk.replace(fragment.to_html)
        end
      end

      private

      def forms = (@forms ||= PageForms.new(@controller, options: false))

      def printing(view)
        previous = view.instance_variable_get(:@_reactiveadmin_template)
        view.instance_variable_set(:@_reactiveadmin_template, nil)
        yield
      ensure
        view.instance_variable_set(:@_reactiveadmin_template, previous)
      end

      # Too deep to read is still shown, as the too-complex notice.
      def visible?(html)
        fragment = HtmlPolicy.parse(html) or return true

        fragment.text.strip.present? || fragment.at_css("img, table")
      end
    end

    # Stands in for the Formtastic builder inside the template's form block.
    class Recorder
      NOOPS = %i[semantic_errors cancel_link commit_action_with_cancel_link].freeze

      attr_reader :builder

      def initialize(builder, state, view, path: nil)
        @builder = builder
        @state = state
        @view = view
        @path = path
      end

      def object = builder.object

      def input(method, options = {}, &)
        field = field(method, options)
        field ? @state.mark([:field, field]) : "".html_safe
      end

      def inputs(*args, &block)
        options = args.extract_options!
        title = options[:name] || options[:title] || (args.shift if args.first.is_a?(String))
        yielded = block&.arity&.zero? ? [] : [self]
        items = block ? @state.expand(@state.capture(@view, *yielded, &block)) : listed(args, options)
        @state.mark([:section, {title: title&.to_s, kind: "inputs", fields: @state.fields(items)}.compact])
      end

      def semantic_fields_for(name, *args, &block)
        items = []
        builder.semantic_fields_for(name, *args) do |nested|
          items.concat(@state.expand(@state.capture(@view, self.class.new(nested, @state, @view, path: [@path, name].compact.join(".")), &block)))
          "".html_safe
        end
        @state.mark([:group, items])
      end

      def actions(*, &block)
        @state.capture(@view, self, &block) if block
        "".html_safe
      end

      def action(name, options = {})
        return "".html_safe unless name.to_s == "submit"

        @state.submit_label ||= options[:label].to_s if options[:label]
        confirming(options[:button_html])
      end

      def submit(label = nil, *args)
        @state.submit_label = label.to_s if label.is_a?(String)
        confirming(args.last || label)
      end

      NOOPS.each { |name| define_method(name) { |*, &| "".html_safe } }

      private

      # The `data-confirm` a classic browser asks about before posting.
      def confirming(options)
        data = options.is_a?(Hash) ? options.with_indifferent_access : {}
        @state.submit_confirm ||= (data.dig(:data, :confirm) || data["data-confirm"]).presence&.to_s
        "".html_safe
      end

      def field(method, options)
        field = FormField.new(builder, @state.schema, @path).call(method.to_sym, options)
        (field && @path) ? field.merge(name: "#{@path}.#{field[:name]}") : field
      end

      def listed(names, options)
        (names.presence || AA.default_form_columns(builder, except: options[:except])).filter_map { field(it, {}) }.map { [:field, it] }
      end

      ruby2_keywords def method_missing(name, *args, &block)
        return super unless builder.respond_to?(name)

        builder.public_send(name, *args, &block).to_s
      end

      def respond_to_missing?(name, include_all = false) = builder.respond_to?(name, include_all) || super
    end

    # Form fields need a schema for choices and html field names; a template has no record to build one from.
    class Schema < FormSchema
      def initialize(controller, view, only: nil, controls_only: false)
        @only = only
        @controls_only = controls_only
        @view = view
        @assigns = controller.view_assigns
        @config = AA.config_of(controller)
        @record = nil
        @choices = {}
        @html_fields = 0
        @parent_id = nil
        @params = controller.params
      end

      attr_writer :sections

      def sections = (@sections ||= [])

      def record_id = @params[:id].presence&.to_s

      def partial? = false
    end

    def initialize(controller, template, only: nil)
      @controller = controller
      @template = template
      @only = only
      @config = AA.config_of(controller)
    end

    # FormResponse.
    def as_json(*)
      NodeRegistry.with_scope do
        state, html = render
        index = state.entries.index { it.first == :form } or raise Unsupported, "#{@template} renders no Formtastic form"
        form = state.entries[index].last
        raise Unsupported, "#{@template} has a #{form[:method]} form" unless METHODS.include?(form[:method])
        own = Form.own_view(form[:path], @controller.request) if form[:method] == "get"
        raise Unsupported, "#{@template} has a GET form to another page" if form[:method] == "get" && !own

        RansackGuard.learn(state.entries.filter_map { it.last if it.first == :form })

        @objects = state.objects
        layout, heading = content_layout(state, html, index)
        sections, title = layout ? state.arrange_items(form[:items]) : state.arrange(html)
        state.schema.sections = sections
        sections.each { |section| section[:fields].each { it[:options_path] &&= options_path(it[:name]) } }
        Degradation.attach({
          resource: key, id: @controller.params[:id].presence&.to_s, title: title || heading || default_title,
          display_name: display_name, actions: [], action: {method: form[:method], path: Paths.api(own || form[:path].to_s)},
          form: {sections:}, layout:, submit_label: state.submit_label, submit_confirm: state.submit_confirm, permissions: permissions,
          submittable: state.schema.submittable?, unsupported_reason: state.schema.unsupported_reason, lock: lock
        }.compact)
      end
    end

    # What the template's forms were built on, once it has rendered: a write that renders it again
    # is rejected when one of them has errors.
    def objects = @objects || []

    # Choices of one field, for the _options endpoint.
    def choices(field)
      render.first.schema.choices.fetch(field) { raise ActiveRecord::RecordNotFound, "No options for #{field}" }
    end

    # Runs the block (a render) on a view whose Formtastic forms record; returns the state and the html.
    def self.recording(schema, view, controller: nil)
      state = State.new(schema, controller:)
      view.extend(Recording)
      view.instance_variable_set(:@_reactiveadmin_template, state)
      [state, yield]
    ensure
      view.instance_variable_set(:@_reactiveadmin_template, nil)
    end

    private

    def render
      @controller.lookup_context.formats = [:html]
      view = @controller.view_context
      self.class.recording(Schema.new(@controller, view, only: @only), view, controller: @controller) { view.render(template: @template, layout: false) }
    end

    # [nodes, title], or nil when the form and its html fields say it all. The nodes are the template's
    # content, with `{type: "form"}` standing for the response's own form; a heading above the form is
    # the title rather than content.
    def content_layout(state, html, index)
      return unless state.layout?(html, index)

      fragment = HtmlPolicy.parse(html.to_s.sub(state.marker(index)) { NodeRegistry.marker({type: "form"}) }) or return
      title = heading_above_form(fragment)
      host = @controller.request.host
      links = ActionLinks.new(host:, base_url: @controller.request.base_url, authorizer: Authorizer.for(@controller), subject: record || @config)
      nodes = HtmlNodes.nodes(fragment.to_html, host:, links:, frame_src: classic_url, resource: key)
      [nodes, title] if own_form?(nodes)
    end

    # A form that landed somewhere the walker drops (inside inline text, say) leaves nothing to show it by.
    def own_form?(tree)
      case tree
      when Array then tree.any? { own_form?(it) }
      when Hash then (tree[:type] == "form" && !tree.key?(:form)) || tree.values.any? { own_form?(it) }
      end
    end

    def heading_above_form(fragment)
      above = fragment.element_children.take_while { !(NodeRegistry.marker?(it) || it.at_css(".#{NodeRegistry::CLASS_NAME}")) }
      heading = above.find { it.name.match?(/\Ah[1-4]\z/) } or return
      heading.text.strip.presence&.tap { heading.remove }
    end

    def classic_url = @controller.request.path.delete_prefix(ReactiveAdmin.config.mount_path)

    # Options beyond the inline limit are searched by the action that renders the form, which has
    # set up what the template needs; the _options endpoint has not.
    def options_path(field)
      action = @controller.request.path.sub(%r{[^/]+\z}, File.basename(@template))
      "#{action}?#{OptionsPayload.page_query(@controller.request).merge(context: "template", field:).to_query}"
    end

    def key = AA.page?(@config) ? @config.underscored_resource_name : Registry.route_key(@config)

    def default_title = AA.t(@controller.action_name, default: @controller.action_name.to_s.titleize)

    def record = AA.resource_ivar(@controller)

    def lock = (FormLock.for(record)&.as_json if record&.persisted?)

    def display_name = (Values.display_name(record, @controller.view_context) if record&.persisted?)

    def permissions
      return {} unless AA.resource?(@config) && record&.persisted?

      Permissions.new(@config, Authorizer.for(@controller)).record(record)
    end
  end
end
