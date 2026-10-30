module ReactiveAdmin
  # Prepended to ActiveAdmin::ResourceController: AA keeps doing authentication, authorization,
  # filtering, scoping, sorting, pagination and writes; we only change how requests are
  # parsed and how results are rendered.
  module ControllerExtension
    PAYLOADS = {"index" => IndexPayload, "show" => ShowPayload, "new" => FormPayload, "edit" => FormPayload}.freeze

    include Frame
    include Embed
    include TemplateActions
    include WriteGuards

    # CSV exports are AA's own streaming, so `csv do` blocks, filters, scopes and order all apply.
    def index(*)
      return super unless reactiveadmin_request? && !reactiveadmin_export?

      render_payload IndexPayload
    end

    def show(*)
      return super unless reactiveadmin_request?

      render_payload ShowPayload
    end

    def new(*, &block)
      return super unless reactiveadmin_request?

      AA.build_resource(self)
      prepare_record(&block)
      render_payload FormPayload
    end

    def edit(*, &block)
      return super unless reactiveadmin_request?

      AA.resource(self)
      prepare_record(&block)
      render_payload FormPayload
    end

    # Custom actions that only set up instance variables and leave the rendering implicit.
    def default_render(*)
      payload = PAYLOADS[action_name] if reactiveadmin_request?
      return render_payload(payload) if payload
      return render_native_template(action_name) if reactiveadmin_request? && request.get? && native_template?(action_name)

      super
    end

    attr_reader :reactiveadmin_prepare_failure

    def reactiveadmin_options
      authorize_options
      render json: OptionsPayload.new(self).as_json, content_type: "application/json"
    end

    def reactiveadmin_lookup
      authorize_options
      render json: LookupPayload.new(self).as_json, content_type: "application/json"
    end

    def reactiveadmin_labels
      authorize! AA::Auth::READ, active_admin_config.resource_class
      lookup_context.formats = [:html]
      response.cache_control[:no_store] = true
      render json: {labels: LabelsPayload.new(self).as_json}, content_type: "application/json"
    end

    def reactiveadmin_value
      record = AA.resource(self)
      field = params[:field].to_s
      value = ValuePayload.fetch(self, record, field, params[:path], token: params[:token])
      ActiveSupport::Notifications.instrument("value_viewed.reactiveadmin",
        resource: Registry.route_key(active_admin_config), id: record.to_param.to_s, field:, user_id: ReactiveAdmin.current_user(self)&.id)
      response.cache_control[:no_store] = true
      render json: {value:}, content_type: "application/json"
    rescue ValuePayload::Forbidden
      render_api_error(:forbidden, "Not authorized", 403)
    end

    def reactiveadmin_meta
      authorize! AA::Auth::READ, active_admin_config.resource_class
      raise ActiveRecord::RecordNotFound unless Registry.actions(active_admin_config).include?(:index)

      lookup_context.formats = [:html]
      meta = Degradation.with_collection(resource: active_admin_config.resource_name, action: "meta") { ResourceMeta.fetch(self) }
      render json: meta, content_type: "application/json"
    end

    def render(*args, &)
      return super unless reactiveadmin_request? && template_render?(args)

      template = rendered_template(args)
      if %w[new edit].include?(template)
        render_invalid
      elsif template.blank? && %w[create update destroy].include?(action_name)
        super # implicit render: responders rescue the missing template and redirect instead
      elsif native_template?(rendered_template_path(args))
        render_native_page_or_rejection(rendered_template_path(args))
      else
        render_api_error(:unsupported, "This action renders an HTML page; use the classic admin", 501)
      end
    end

    private

    # Choices for a form's controls expose what the form's own action would: someone who can't open
    # `new` or `edit` doesn't get them. Filter choices only need READ.
    def authorize_options
      resource_class = active_admin_config.resource_class
      authorize! AA::Auth::READ, resource_class
      return unless params[:context] == "form"

      params[:id].present? ? authorize!(AA::Auth::EDIT, AA.resource(self)) : authorize!(AA::Auth::NEW, resource_class)
    end

    # AA blocks render partials and templates by name; those only exist as html.
    def render_payload(payload_class)
      lookup_context.formats = [:html]
      render_collected((payload_class == FormPayload) ? "form" : action_name) { payload_class.new(self).as_json }
    end

    # Writes run as html so AA's responders, flashes and `controller do` overrides behave as in
    # the classic admin; the outcome is translated back to JSON by redirect_to and render.
    def process_action(*)
      if reactiveadmin_request? && !request.get?
        request.format = :html
        inputs = params[:batch_action_inputs]
        params[:batch_action_inputs] = inputs.to_unsafe_h.to_json if inputs.respond_to?(:to_unsafe_h)
        record_params = params[active_admin_config.param_key]
        Masking.keep_unchanged(record_params, active_admin_config) if record_params.respond_to?(:keys) && WriteGuards::GUARDED.exclude?(action_name)
        take_lock_param
      end
      super
    end

    # AA authorizes custom actions only through the host's own code; the API enforces the same
    # permission the show page's action buttons are gated on.
    def authenticate_active_admin_user
      super
      return if performed?

      authorize_declared_action if reactiveadmin_request? && ReactiveAdmin.config.authorize_custom_actions?
    end

    # AA hands the joined param to `find`, which wants one value per key part. The last part takes
    # any remaining delimiters, since it is the one most likely to hold them (a timestamp, a slug).
    def find_resource = AA.find_composite_resource(self) || super

    def authorize_declared_action
      if active_admin_config.member_actions.any? { it.name.to_s == action_name }
        AA.resource(self)
      elsif active_admin_config.collection_actions.any? { it.name.to_s == action_name }
        authorize! action_to_permission(action_name), active_admin_config.resource_class
      elsif action_name == "batch_action"
        authorize! AA::Auth::READ, active_admin_config.resource_class
      end
    end

    def action_to_permission(action)
      %w[reactiveadmin_options reactiveadmin_lookup reactiveadmin_labels reactiveadmin_value].include?(action.to_s) ? AA::Auth::READ : super
    end

    def render_redirect_result(location, response_options)
      notes = flash.to_hash.merge(response_options.fetch(:flash, {}).to_h.stringify_keys, response_options.slice(:notice, :alert, :error).stringify_keys)
      failure = notes.values_at("alert", "error").compact_blank.first
      flash.clear
      return render_invalid(failure, base: [failure], location: Location.for(location, host: request.host)) if failure

      render json: written(notes["notice"].presence, Location.for(location, host: request.host)),
        status: (action_name == "create") ? :created : :ok, content_type: "application/json"
    end

    def written(message, location)
      record = AA.resource_ivar(self) if %w[create update destroy].include?(action_name)
      {ok: true, id: record&.to_param&.to_s, message:, location:}.compact
    end

    def render_invalid(message = "Validation failed", base: [], location: nil, form: nil)
      record = rejected_record
      base = [*base, *flash.to_hash.values_at("alert", "error")].compact_blank
      flash.clear
      errors = record.respond_to?(:errors) ? record.errors : ActiveModel::Errors.new(nil)
      messages, row_errors = field_errors(record, errors.to_hash.except(:base))
      render_api_error(:invalid, message, 422, errors: messages, row_errors:, base: [*errors[:base], *base].uniq, location:, form:)
    end

    # A custom create that saves its own record and renders `new` hands it to the view as @resource,
    # which is where classic's form reads the errors from.
    def rejected_record
      candidates = [AA.resource_ivar(self), view_assigns["resource"]]
      candidates.find { it.respond_to?(:errors) && it.errors.any? } || candidates.first
    end

    # Errors keyed by the field a client shows (the raw attribute keys if the form can't be described),
    # and which of a has_many's rows they belong to.
    def field_errors(record, errors)
      return [errors, nil] if errors.empty?

      schema = FormSchema.new(self, record, controls_only: true)
      [ErrorKeys.call(errors, schema.sections), RowErrors.call(record, schema.nested_associations)]
    rescue
      [errors, nil]
    end

    # Host overrides such as `def new; super { resource.config = default }; end` prepare the record
    # classic's form shows; the responder runs that block, so the API must too. A block that takes
    # the responder's format can't run without one. One that raises (typically dereferencing a
    # parent the unnested route lacks, which classic's `new` can't survive either) leaves the
    # record as built and the form unsubmittable.
    def prepare_record(&block)
      block.call if block && block.arity <= 0
    rescue AA::AccessDenied, ActiveRecord::RecordNotFound
      raise
    rescue => e
      Rails.logger.warn("[reactiveadmin] #{controller_path}##{action_name} prepare block failed: #{e.class} at #{e.backtrace&.first}")
      @reactiveadmin_prepare_failure = e.class
    end
  end
end
