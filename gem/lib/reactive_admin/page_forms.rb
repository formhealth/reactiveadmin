module ReactiveAdmin
  # Formtastic forms in a page's or show's content become `form` nodes instead of frames. Each form's
  # block runs against the TemplateForm recorder, and a form it recorded faithfully travels as a
  # FormResponse the client renders inline; one it can't record keeps rendering as html, which the
  # walker frames. Forms leave a marker in the html, like show-row JSON values do.
  class PageForms
    Recorded = Struct.new(:response, :choices)

    # Mixed into the view that renders the content, ahead of TemplateForm::Recording.
    module Recording
      def semantic_form_for(*args, &block)
        forms = reactiveadmin_page_forms or return super
        forms.node(self) { super(*args, &block) } || forms.suspended { super(*args, &block) }
      end

      def active_admin_form_for(*args, &block)
        forms = reactiveadmin_page_forms or return super
        forms.node(self) { super(*args, &block) } || forms.suspended { super(*args, &block) }
      end

      def reactiveadmin_page_forms = @_reactiveadmin_page_forms
    end

    # For Arbre content: `active_admin_form_for` there is an Arbre component, not the view helper.
    module ArbreForms
      def active_admin_form_for(*args, &block)
        forms = helpers.try(:reactiveadmin_page_forms) or return super
        marker = forms.node(helpers) { helpers.active_admin_form_for(*args, &block) }
        marker ? text_node(marker) : forms.suspended { super(*args, &block) }
      end
    end

    # Runs the block with the view's forms recording, and returns what was recorded.
    def self.recording(view, controller, controls_only: false)
      forms = new(controller, controls_only:)
      view.extend(TemplateForm::Recording)
      view.extend(Recording)
      view.instance_variable_set(:@_reactiveadmin_page_forms, forms)
      yield
      forms
    ensure
      view.instance_variable_set(:@_reactiveadmin_page_forms, nil)
    end

    # Gives a write's params the shape a browser's post of the form it came from would have, as a
    # native form's does. Page content is rendered again to find that form.
    def self.normalize(controller, forms)
      path = controller.request.path
      sections = forms.select { it.response.dig(:action, :path) == path && it.response.dig(:action, :method) != "get" }.flat_map { it.response.dig(:form, :sections) }
      return if sections.empty?

      fields = sections.flat_map { it[:fields] }
      fields.select { it[:disabled] && it[:param] }.each { drop(controller.params, it[:param]) }
      ParamNormalizer.call(controller.params, sections)
    end

    # Browsers don't post disabled inputs, so a client that does is submitting what the form withheld.
    def self.drop(params, param)
      *path, leaf = param.delete_suffix("[]").scan(/[^\[\]]+/)
      path.inject(params) { |memo, key| memo.try(:[], key) }.try(:delete, leaf)
    end

    attr_reader :recorded

    # `options: false` for content that has no page to search a long list of choices (a template's forms).
    def initialize(controller, controls_only: false, options: nil)
      @controller = controller
      @controls_only = controls_only
      @options = options
      @config = AA.config_of(controller)
      @recorded = []
      @recording = false
    end

    # Renders a form as plain markup: the forms inside it (an Arbre form builds its own) are not recorded.
    def suspended
      previous = @recording
      @recording = true
      yield
    ensure
      @recording = previous
    end

    # Html with a marker for the form the block renders, or nil when it has to render as a plain form.
    def node(view, &)
      return if @recording

      @recording = true
      begin
        response = record(view, &)
        return unless response

        @recorded << Recorded.new(response, @last_choices)
        NodeRegistry.marker({type: "form", form: response})
      rescue => e
        Rails.logger.warn("[reactiveadmin] #{@config.resource_name} form not recordable: #{e.class} at #{e.backtrace&.first}")
        Degradation.record(kind: :page_form_failed, where: Degradation.where, reason: "A form raised #{e.class} while recording; shown in a classic frame")
        nil
      ensure
        @recording = false
      end
    end

    private

    def record(view)
      state = TemplateForm::State.new(TemplateForm::Schema.new(@controller, view, controls_only: @controls_only))
      markup = recording_in(view, state) { yield.to_s }
      form = state.entries.reverse_each.find { it.first == :form }&.last or return
      path = local_path(form[:path], form[:method])
      return unless TemplateForm::METHODS.include?(form[:method]) && path

      sections, title = state.arrange(markup)
      state.schema.sections = sections
      return unless state.schema.unsupported_kinds.empty?

      fields = sections.flat_map { it[:fields] }
      return if fields.any? { it[:options_path] } && !options?

      @last_choices = state.schema.choices
      fields.each { it[:options_path] &&= options_path(it[:name]) }
      {
        resource: key, title: title.to_s, actions: [], action: {method: form[:method], path: Paths.api(path)}, form: {sections:},
        submit_label: state.submit_label, submit_confirm: state.submit_confirm, permissions: {}, submittable: true
      }.compact
    end

    def recording_in(view, state)
      previous = view.instance_variable_get(:@_reactiveadmin_template)
      view.instance_variable_set(:@_reactiveadmin_template, state)
      yield
    ensure
      view.instance_variable_set(:@_reactiveadmin_template, previous)
    end

    # Where the form posts, when that is a route of the admin the API serves too. A GET form only
    # re-reads the view that holds it, so it is the one place that form is for.
    def local_path(url, verb)
      return own_view(url) if verb == "get"

      uri = URI.parse(url.to_s)
      return if uri.host.present? && uri.host != @controller.request.host

      path = [uri.path, uri.query].compact.join("?")
      path if path.start_with?("/#{ReactiveAdmin.config.namespace}/") && admin_route?(uri.path, verb)
    rescue URI::InvalidURIError
      nil
    end

    def admin_route?(path, verb)
      controller = Rails.application.routes.recognize_path(path, method: verb)[:controller]
      Registry.for_controller_path(controller) || Registry.page_for_controller_path(controller)
    rescue ActionController::RoutingError
      nil
    end

    # A page's content, or a template's further forms. A show page has no view of its own to re-read with a query.
    def get_forms? = page? || @options == false

    def own_view(url)
      path = TemplateForm::Form.own_view(url, @controller.request) if get_forms?
      path && ((@options == false) ? path : Ladder.page_path(@config, path))
    end

    # Options beyond the inline limit are searched by the page that holds the form: only it has
    # set up what the content needs, including what the page's own query says. A show page has no
    # such endpoint, so its forms stay frames.
    def options_path(field)
      query = OptionsPayload.page_query(@controller.request).merge(context: "page_form", form: @recorded.size, field:)
      "#{Paths.api(Ladder.page_path(@config, classic_url))}?#{query.to_query}"
    end

    def classic_url = @controller.request.path.delete_prefix(ReactiveAdmin.config.mount_path).sub("/_pages/", "/")

    def page? = AA.page?(@config)

    def options? = @options.nil? ? page? : @options

    def key = page? ? @config.underscored_resource_name : Registry.route_key(@config)
  end
end
