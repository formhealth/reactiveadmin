module ReactiveAdmin
  # Prepended to ActiveAdmin::PageController: a register_page's own controller (authentication,
  # authorization, `controller do` overrides, page actions) serves its API too.
  module PageControllerExtension
    include Frame
    include Embed
    include TemplateActions

    def index(*)
      return super unless reactiveadmin_request?

      (params[:context] == "page_form") ? render_form_options : render_page
    end

    # Through `index`, where hosts set up what the page's content needs.
    def reactiveadmin_page = index

    def default_render(*)
      return render_native_template(action_name) if reactiveadmin_request? && request.get? && native_template?(action_name)

      super
    end

    def render(*args, &)
      return super unless reactiveadmin_request? && template_render?(args)

      path = rendered_template_path(args)
      if native_template?(path)
        render_native_page_or_rejection(path)
      else
        render_api_error(:unsupported, "This action renders an HTML page; use the classic admin", 501)
      end
    end

    private

    def render_page
      lookup_context.formats = [:html]
      render_collected("page") { PagePayload.new(self).as_json }
    end

    # Choices of a form in the content too long to inline, searched like any form's options.
    def render_form_options
      lookup_context.formats = [:html]
      index = params.require(:form).to_i
      form = PagePayload.new(self).forms[index] if index >= 0
      source = form&.choices&.[](params.require(:field)) or raise ActiveRecord::RecordNotFound, "No options for that field"
      authorize_form_action(form)
      return if performed?

      render json: TemplateOptions.new(self, source).as_json, content_type: "application/json"
    end

    # The choices belong to a form that posts to a page or resource action; they need that action's permission.
    def authorize_form_action(form)
      action = form.response[:action]
      return if action[:method] == "get" # a read of this very page, which this request already is

      path = URI.parse(action[:path]).path.delete_prefix(ReactiveAdmin.config.mount_path)
      route = Rails.application.routes.recognize_path(path, method: action[:method])
      config = Registry.for_controller_path(route[:controller]) || Registry.page_for_controller_path(route[:controller])
      if (refusal = ApiGuards.refusal(self, config, [route[:action]], verb: action[:method]))
        return render_api_denied(refusal)
      end
      authorize! action_to_permission(route[:action]), AA.page?(config) ? config : config.resource_class
    end

    # Writes run as html so the page action and its flashes behave as in the classic admin.
    def process_action(*)
      request.format = :html if reactiveadmin_request? && !request.get?
      super
    end

    # Runs after the before_actions, so the content renders for a user who passed them.
    def send_action(*)
      normalize_form_params if reactiveadmin_request? && !request.get?
      super
    end

    # A write to a form of the page's content is shaped as a browser's post of that form would be. The
    # action still runs if the content can't be rendered for this write.
    def normalize_form_params
      lookup_context.formats = [:html]
      PageForms.normalize(self, PagePayload.new(self).forms(controls_only: true))
    rescue => e
      Rails.logger.warn("[reactiveadmin] #{controller_path} write not shaped like the form's post: #{e.class} at #{e.backtrace&.first}")
    end

    def action_to_permission(action)
      (action.to_s == "reactiveadmin_page") ? AA::Auth::READ : super
    end

    def render_redirect_result(location, response_options)
      notes = flash.to_hash.merge(response_options.fetch(:flash, {}).to_h.stringify_keys, response_options.slice(:notice, :alert, :error).stringify_keys)
      failure = notes.values_at("alert", "error").compact_blank.first
      flash.clear
      location = Location.for(location, host: request.host)
      return render_invalid(failure, base: [failure], location:) if failure

      render json: {ok: true, message: notes["notice"].presence, location:}.compact, content_type: "application/json"
    end

    def render_invalid(message = "Validation failed", base: [], location: nil, form: nil)
      base = [*base, *flash.to_hash.values_at("alert", "error")].compact_blank.uniq
      flash.clear
      render_api_error(:invalid, message, 422, errors: {}, base:, location:, form:)
    end
  end
end
