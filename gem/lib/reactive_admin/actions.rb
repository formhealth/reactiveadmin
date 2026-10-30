module ReactiveAdmin
  # Buttons derived from a resource's declarations: edit and destroy on a record. Member and
  # collection actions are never listed just for existing; classic only surfaces them through
  # action items, links in the content, or the host's own code. Here they appear through an
  # action item, an inline control, or `reactive { expose :name, if: ->(record) { ... } }`.
  # `href` is the classic admin URL, `api_path` the API one.
  class Actions
    def initialize(config, authorizer, record = nil, view: nil)
      @config = config
      @authorizer = authorizer
      @record = record
      @view = view
    end

    def as_json(*) = [edit, destroy].compact

    # Declared member (or, without a record, GET collection) actions the resource exposes
    # explicitly, except those an action item already produced. Collection actions that write are
    # the target of a form, which can't be run without its params.
    def exposed(linked = [])
      declared = @record ? @config.member_actions : @config.collection_actions
      declared.filter_map do |declaration|
        name = declaration.name.to_s
        condition = exposures[name.to_sym]
        next if condition.nil? || linked.any? { it[:key] == name } || !visible?(condition, name)
        next if !@record && Array.wrap(declaration.http_verb) != [:get]

        @record ? member(declaration) : collection(declaration)
      rescue NoMethodError, ActionController::UrlGenerationError => e
        Degradation.record(kind: :action_dropped, where: "#{scope}/action[#{name}]", reason: "Action has no route (#{e.class}); left out")
        nil # nested resources have no collection path without their parent; some actions lack a route
      end
    end

    private

    def edit
      return unless defines?(:edit)

      action("edit", "Edit", :edit, :get, @config.route_edit_instance_path(@record), authorized?(AA::Auth::EDIT))
    end

    def destroy
      return unless defines?(:destroy)

      action("destroy", "Delete", :destroy, :delete, @config.route_instance_path(@record),
        authorized?(AA::Auth::DESTROY), confirm: AA.t("delete_confirmation"))
    end

    def member(declaration)
      name = declaration.name.to_s
      action(name, name.titleize, :member, Array.wrap(declaration.http_verb).first,
        @config.route_member_action_path(declaration.name, @record), authorized?(declaration.name.to_sym))
    end

    def collection(declaration)
      name = declaration.name.to_s
      action(name, name.titleize, :collection, :get, File.join(@config.route_collection_path, name),
        authorized?(declaration.name.to_sym, @config.resource_class))
    end

    def exposures = @config.reactive_options.fetch(:exposed, {})

    # A guard that raises hides the action: showing a button the host meant to withhold is the worse error.
    def visible?(condition, name)
      return true if condition == true

      args = condition.arity.zero? ? [] : [@record].compact
      result = @view ? @view.instance_exec(*args, &condition) : condition.call(*args)
      !!result
    rescue => e
      Degradation.record(kind: :action_guard_failed, where: "#{scope}/action[#{name}]", reason: "Exposure guard raised #{e.class}; action hidden")
      false
    end

    def scope = @record ? "show" : "index"

    def action(key, label, kind, method, href, enabled, confirm: nil)
      reason = "You don't have permission to #{label.downcase}#{" this record" if @record}" unless enabled
      api_path = File.join(ReactiveAdmin.config.mount_path, href)
      view = Ladder.view(@config, key, href:) if %w[member collection].include?(kind.to_s) && method.to_s == "get"
      ApiGuards.mark({key:, label:, kind: kind.to_s, placement: "header", method: method.to_s, href:, api_path:, confirm:, enabled:,
                      disabled_reason: reason, view:}.compact, @config, key)
    end

    def authorized?(action, subject = @record)
      @authorizer.authorized?(action, subject, config: @config)
    rescue => e
      Degradation.record(kind: :authorization_check_failed, where: "#{scope}/action[#{action}]", reason: "Authorization check raised #{e.class}; treated as denied")
      false
    end

    def defines?(action) = Registry.actions(@config).include?(action)
  end
end
