module ReactiveAdmin
  # FormResponse for the new and edit actions.
  class FormPayload
    # A custom `new`/`edit` may have already prepared its own record.
    def self.record_for(controller)
      AA.resource_ivar(controller) ||
        (controller.params[:id].present? ? AA.resource(controller) : AA.build_resource(controller))
    end

    def initialize(controller, only: nil)
      @controller = controller
      @only = only
      @config = AA.config_of(controller)
      @authorizer = Authorizer.for(controller)
      @record = self.class.record_for(controller)
    end

    def schema = @schema ||= FormSchema.new(@controller, @record, only: @only)

    def as_json(*)
      Degradation.attach({
        resource: Registry.route_key(@config),
        id: schema.record_id,
        title: title,
        display_name: (Values.display_name(@record, @controller.view_context) if @record.persisted?),
        actions: ActionItems.new(@controller, @record.persisted? ? "edit" : "new", subject: @record).call,
        action: action,
        form: schema.as_json,
        submit_confirm: schema.submit_confirm,
        submittable: schema.submittable?,
        unsupported_reason: schema.unsupported_reason,
        lock: FormLock.for(@record, nested: schema.nested_associations)&.as_json,
        permissions: permissions
      }.compact)
    end

    private

    def title
      custom = AA.page_presenter(@config, :form)&.[](:title)
      text = custom ? AA.render_or_call(@controller.view_context, @record, custom) : default_title
      CGI.unescapeHTML(text.to_s)
    end

    def default_title = AA.resource_text(@config, "#{@record.persisted? ? "edit" : "new"}_model")

    def action
      path = @record.persisted? ? @config.route_instance_path(@record) : @config.route_collection_path(@controller.params)
      {method: @record.persisted? ? "patch" : "post", path: Paths.api(path)}
    end

    def permissions
      perms = Permissions.new(@config, @authorizer)
      @record.persisted? ? perms.record(@record) : perms.resource
    end
  end
end
