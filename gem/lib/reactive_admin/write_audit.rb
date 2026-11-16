module ReactiveAdmin
  # A trail for API writes the model's own audit can't give: the ones that changed nothing, and which
  # ones came through the API. Events carry who, what and which record, never params or values.
  module WriteAudit
    ID_FORMAT = /\A[\w-]{1,64}\z/

    # A refused action is worth recording whatever its verb: GETs can act too.
    def self.rejected(controller, code, guard: nil) = emit("write_rejected", controller, always: code.to_s == "api_denied", code: code.to_s, **{guard:}.compact)

    # A dry run saves nothing, so it isn't a write.
    def self.written(controller) = (emit("write", controller) unless dry_run?(controller))

    # Never raises: the write has already been answered, and an audit hiccup must not turn it into a 500.
    def self.emit(event, controller, always: false, **extra)
      return if (!always && read?(controller)) || unaudited?(controller)

      user_id = ReactiveAdmin.current_user(controller)&.id
      return unless user_id

      payload = {resource: resource_key(controller), action: controller.action_name, id: record_id(controller), user_id:, **batch_ids(controller), **extra}
      payload[:dry_run] = true if dry_run?(controller)
      # After the write's own transaction, so a rolled-back write isn't reported as done.
      ActiveRecord.after_all_transactions_commit { Audit.instrument(event, controller, payload) }
    rescue => e
      Rails.logger.error("[reactiveadmin] write audit failed: #{e.class}")
    end

    def self.read?(controller) = ActionSafety.request_read?(controller)

    def self.dry_run?(controller) = controller.respond_to?(:reactiveadmin_dry_run?, true) && controller.send(:reactiveadmin_dry_run?)

    def self.unaudited?(controller) = controller.respond_to?(:audit_writes?, true) && !controller.send(:audit_writes?)

    def self.resource_key(controller) = AA.config_of(controller)&.resource_name&.route_key || controller.controller_path

    # The path segment is client input, so anything that isn't plainly an id is left out.
    def self.record_id(controller)
      record = AA.resource_ivar(controller)
      id = (record.try(:persisted?) || record.try(:destroyed?)) ? record.to_param : controller.params[:id]
      id.to_s if id.to_s.match?(ID_FORMAT)
    end

    def self.batch_ids(controller)
      ids = controller.params[:collection_selection] if controller.action_name == "batch_action"
      ids.is_a?(Array) ? {record_ids: ids.map(&:to_s).grep(ID_FORMAT)} : {}
    end

    private

    # False for endpoints that aren't writes themselves: MCP's POSTs carry tool calls, and each tool's
    # own request reports what it wrote.
    def audit_writes? = true

    def process_action(*)
      super.tap { WriteAudit.written(self) if reactiveadmin_request? && response.successful? }
    end
  end
end
