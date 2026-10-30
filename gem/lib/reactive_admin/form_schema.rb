module ReactiveAdmin
  # The resource's `form do |f| ... end` block run the way ActiveAdmin::Views::Pages::Form
  # does, but against a FormRecorder so the result is data instead of html.
  class FormSchema
    DEFAULT_BLOCK = proc do |f|
      f.semantic_errors
      f.inputs
      f.actions
    end

    UNSUPPORTED_REASON = "This form can't be edited here yet — open it in the classic admin".freeze
    # Inputs that html fields can't carry: the sanitizer drops them, so the API would post without them.
    RAW_INPUTS = "input, select, textarea, button[type=submit]".freeze

    attr_reader :config, :view, :assigns, :record, :choices, :parent_id, :only, :content

    # The `data-confirm` a classic submit button asks about before posting.
    def self.confirm_of(button_html)
      data = button_html.respond_to?(:with_indifferent_access) ? button_html.with_indifferent_access : {}
      (data.dig(:data, :confirm) || data["data-confirm"]).presence&.to_s
    end

    # `only` is a field key (`name`, or `assoc.name` inside has_many), or a list of them: just those are built.
    # `controls_only` records what write guards and param normalization read (params, controls, disabled,
    # summarized, nesting, unsupported kinds) and skips what only a client shows: options, labels, hints,
    # values, sanitized html.
    def initialize(controller, record, only: nil, controls_only: false)
      @only = only
      @controls_only = controls_only
      @controller = controller
      @view = Masking.install(controller.view_context, AA.config_of(controller))
      @assigns = controller.view_assigns
      @config = AA.config_of(controller)
      @record = record
      @parent_id = Paths.parent_id(@config, controller.params)
      @choices = {}
      @html_fields = 0
      @content_fields = 0
      @content = FormContent.new(controller, record)
      note_prepare_failure(controller.reactiveadmin_prepare_failure)
    end

    def as_json(*) = {sections:}

    def submit_confirm = sections && @submit_confirm

    def record_submit_confirm(text) = (@submit_confirm ||= text)

    def controls_only? = !!@controls_only

    def record_id = (record.to_param.to_s if record.persisted?)

    def next_html_name = "html_#{@html_fields += 1}"

    def next_content_name = "content_#{@content_fields += 1}"

    # Whether the content around inputs is carried: a client shows it, a write or one field's options doesn't need it.
    def content? = !controls_only? && only.nil?

    # False when posting this form through the API would leave out inputs the classic form sends.
    def submittable?
      return @submittable if defined?(@submittable)

      sections
      @submittable = unsupported.empty?
      report_unsupported unless @submittable
      @submittable
    end

    def unsupported_reason = (UNSUPPORTED_REASON unless submittable?)

    def unsupported!(kind) = unsupported << kind

    def unsupported_kinds = unsupported.to_a

    # Associations the form edits in has_many sections: the lock has to cover their rows too.
    def nested_associations = sections && nested.to_a

    def nested!(assoc) = nested << assoc

    # A partial leans on ivars its controller's `new` set up, so only that action can render it.
    def partial? = AA.page_presenter(@config, :form)&.options&.dig(:partial).present?

    # Raw html from a form block, before sanitizing removes the inputs it holds. Markup too deep to scan may hold
    # inputs, so it makes the form unsupported rather than input-free.
    def scan_html(raw)
      fragment = HtmlPolicy.parse(raw.to_s)
      unsupported! :raw_inputs if fragment.nil? || fragment.at_css(RAW_INPUTS)
    end

    def wants?(key) = only.nil? || Array(only).include?(key)

    def wants_nested?(path) = only.nil? || (path.present? && Array(only).any? { it.start_with?("#{path}.") })

    def sections
      @sections ||= begin
        presenter = AA.page_presenter(@config, :form)
        options = presenter&.options || {}
        options[:partial] ? partial_sections(options[:partial]) : record_sections(builder_for(options), presenter&.block)
      rescue => e
        Rails.logger.warn("[reactiveadmin] #{@config.resource_name} form block fell back to defaults: #{e.class} at #{e.backtrace&.first}")
        Degradation.record(kind: :form_block_failed, where: "form", reason: "Form block raised #{e.class}; showing default fields")
        unsupported! :block_failed
        record_sections(builder_for({}), nil)
      end
    end

    private

    def unsupported = (@unsupported ||= Set.new)

    # The host's `new`/`edit` block raised before the form was built; the collector wasn't open yet.
    def note_prepare_failure(error_class)
      return unless error_class

      unsupported! :prepare_failed
      Degradation.record(kind: :prepare_block_failed, where: "form", reason: "The action's block raised #{error_class}; showing the record as built")
    end

    def nested = (@nested ||= Set.new)

    def report_unsupported
      resource = @config.resource_name.to_s
      ReactiveAdmin.diagnostics.record(:form_unsupported, resource:, reason: unsupported.to_a.join(","))
      Degradation.record(kind: partial? ? :form_partial : :form_unsupported, where: "form", reason: UNSUPPORTED_REASON)
    end

    def builder_for(options)
      options = {url: "#", as: @config.param_key, builder: AA.form_builder}.merge(options.except(:partial, :title))
      builder = nil
      @view.semantic_form_for(@record, options) { builder = it }
      builder
    end

    def record_sections(builder, block)
      @choices.clear
      @submit_confirm = nil
      nested.clear
      @html_fields = @content_fields = 0
      NodeRegistry.with_scope do
        FormRecorder.build(builder, self).record(&block || DEFAULT_BLOCK).sections.reject do |section|
          section[:kind] == "inputs" && section[:fields].empty?
        end
      end
    end

    # The partial renders as a custom template does: its Formtastic inputs are recorded, the rest is html.
    def partial_sections(partial)
      @choices.clear
      @html_fields = 0
      state, html = TemplateForm.recording(self, @view) { @view.render(partial:) }
      state.arrange(html).first
    rescue => e
      Rails.logger.warn("[reactiveadmin] #{@config.resource_name} form partial #{partial} unavailable: #{e.class} at #{e.backtrace&.first}")
      Degradation.record(kind: :form_partial_failed, where: "form", reason: "Form partial raised #{e.class}; shown empty")
      unsupported! :partial_failed
      [{kind: "inputs", fields: [FormField.html("", next_html_name)]}]
    end
  end
end
