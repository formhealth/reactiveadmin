module ReactiveAdmin
  # Shared by resource and page controllers: GET actions that render a template answer natively
  # (a FormResponse) when the ladder says so, and so does the re-render after a failed write.
  module TemplateActions
    EXPLICIT_OUTPUT = %i[json plain body text html xml js inline file nothing].freeze

    private

    # A read-only template is only answered natively for a GET: a write that renders it again stays classic.
    def native_template?(template)
      decision = Ladder.for_template(active_admin_config, template_path(template))
      decision.native? && (!decision.read_only || request.get?)
    end

    def template_path(template) = template.to_s.include?("/") ? template.to_s : "#{controller_path}/#{template}"

    def template_render?(args) = args.none? { it.is_a?(Hash) && it.keys.intersect?(EXPLICIT_OUTPUT) }

    def rendered_template(args) = rendered_target(args).split("/").last.to_s

    def rendered_template_path(args) = template_path(rendered_target(args))

    def rendered_target(args)
      target = args.first
      target = target[:action] || target[:template] if target.is_a?(Hash)
      target.to_s
    end

    # `context=template&field=` asks the same action for one field's options, as `_options` does for forms.
    def render_native_template(template)
      return render_read_only_template(template_path(template)) if Ladder.for_template(active_admin_config, template_path(template)).read_only

      searching = params[:context] == "template" && params[:field].present?
      form = TemplateForm.new(self, template_path(template), only: (params[:field] if searching))
      if searching
        render json: TemplateOptions.new(self, form.choices(params[:field])).as_json, content_type: "application/json"
      else
        render_collected("form") { recorded(form, template_path(template)) }
      end
    rescue TemplateForm::Unsupported
      render_api_error(:unsupported, "This action renders an HTML page; use the classic admin", 501)
    end

    # What the static ladder took for read-only markup may render controls: it is a frame from now on.
    def render_read_only_template(path)
      render_collected("template") { recorded(TemplateContent.new(self, path), path) }
    rescue TemplateForm::Unsupported
      Ladder.downgrade!(path)
      render_api_error(:unsupported, "This action renders an HTML page; use the classic admin", 501)
    end

    # A template that can't be recorded is shown as a frame from now on: this answer is the same
    # "use the classic admin" as for an unsupported one, never a 500.
    def recorded(form, path)
      form.as_json
    rescue ActionView::Template::Error => e
      raise if [AA::AccessDenied, ActiveRecord::RecordNotFound].any? { e.cause.is_a?(it) }

      Rails.logger.warn("[reactiveadmin] #{controller_path} #{path} not recordable: #{e.cause.class} at #{e.backtrace&.first}")
      Degradation.record(kind: :template_form_failed, where: "form", reason: "Template raised #{e.cause.class} while recording; shown as a frame")
      Ladder.downgrade!(path)
      raise TemplateForm::Unsupported, "#{path} could not be recorded"
    end

    # Renders a payload built in the block, with whatever it fell back to listed as `degraded`.
    def render_collected(action, &)
      render_body(collected(action, &))
    end

    def collected(action, &)
      Provenance.with_scope { Degradation.with_collection(resource: active_admin_config.resource_name, action:, &) }
    end

    def render_body(body)
      response.set_header(Degradation::HEADER, Array(body[:degraded]).size.to_s)
      render json: body, content_type: "application/json"
    end

    # A template rendered by name: the form itself on a GET. After a write it is the same page again,
    # as classic shows it (a search's results), unless the write was rejected.
    def render_native_page_or_rejection(path)
      return render_native_template(path) if request.get?

      form = TemplateForm.new(self, path)
      body = collected("form") { template_form_json(form) }
      return render_body(body) if body && !rejected?(form)

      render_invalid(form: body, base: form_messages(form))
    end

    # What the form's own objects say (a search object that failed validation); the record's errors are
    # reported by render_invalid itself.
    def form_messages(form)
      record = AA.resource_ivar(self)
      form.objects.reject { it.equal?(record) }.flat_map { it.try(:errors)&.full_messages.to_a }
    end

    # An alert flash or an object with errors says the write didn't take; a page with neither is an answer.
    def rejected?(form)
      return true if flash.to_hash.values_at("alert", "error").any?(&:present?)

      [*form.objects, (rejected_record if respond_to?(:rejected_record, true))].any? { it.respond_to?(:errors) && it.errors.any? }
    end

    # The options endpoint's paging and lookup over choices a template form produced.
    class TemplateOptions < OptionsPayload
      def initialize(controller, source)
        super(controller)
        @source = source
      end

      private

      def choices = @source
    end

    # The form a write rendered its template with; the response is still valid without it.
    def template_form_json(form)
      form.as_json
    rescue => e
      Rails.logger.warn("[reactiveadmin] #{controller_path} #{action_name} form unavailable: #{e.class} at #{e.backtrace&.first}")
      Degradation.record(kind: :template_form_failed, where: "form", reason: "Form for the write unavailable (#{e.class})")
      nil
    end
  end
end
