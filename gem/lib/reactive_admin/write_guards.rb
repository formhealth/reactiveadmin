module ReactiveAdmin
  # What create and update must pass before AA's own write runs: the form has to be one the API
  # can submit completely, and the record must be unchanged since the client loaded it.
  module WriteGuards
    GUARDED = %w[create update].freeze
    MAX_UNKNOWN_LISTED = 20

    private

    # Runs after every before_action, immediately before the action itself.
    def send_action(*)
      return super unless reactiveadmin_request? && GUARDED.include?(action_name)

      record, schema = guard_write
      return if performed?

      within_lock_transaction(record) do
        guard_lock(record, schema) if action_name == "update"
        super unless performed?
      end
    end

    # Timestamp-locked updates hold a row lock from the check until the write commits, so a
    # concurrent update can't slip between them. Opened here rather than around the whole request so
    # host before_actions and the schema build don't hold a connection and a row lock.
    def within_lock_transaction(record, &)
      return yield unless action_name == "update" && FormLock.field_for(record.class) == "updated_at"

      record.class.transaction(&)
    end

    # Taken out of params so AA's permitted_params never sees it.
    def take_lock_param = (@reactiveadmin_lock = params.delete(:lock) if GUARDED.include?(action_name))

    def guard_write
      prepared = AA.resource_ivar(self)
      record = write_record
      schema = FormSchema.new(self, record, controls_only: true)
      return render_api_error(:unsupported, schema.unsupported_reason, 422) unless writable?(schema)

      unknown = FormKeys.new(schema.sections, active_admin_config.param_key).filter!(params)
      return reject_unknown_params(unknown) if unknown.any? && reject_unknown_params?(schema)

      keep_masked_values(record)
      ParamNormalizer.call(params, schema.sections, permitted: -> { permitted_params })
      MaskedJson.restore(params, schema.sections.flat_map { it[:fields] || [] }, (record if action_name == "update"), active_admin_config)
      # The record was built from params that may have held withheld values; the action builds its own.
      reset_prepared_record if action_name == "create" && prepared.nil?
      [record, schema]
    end

    # A create has no stored value for a blank to mean "keep".
    def keep_masked_values(record)
      attrs = params[active_admin_config.param_key]
      Masking.keep_unchanged(attrs, active_admin_config, record) if action_name == "update" && attrs.respond_to?(:keys)
    end

    def reset_prepared_record = AA.reset_resource_ivar(self)

    # A partial renders only where its controller's `new` set up the ivars it needs, and a record built
    # as the plain resource class lacks what a custom `new` gave it. Failures there say nothing about
    # the form, so only raw inputs, which show regardless, refuse the write.
    def writable?(schema)
      return true if schema.submittable?
      return false unless schema.partial? || @reactiveadmin_stand_in_record

      (schema.unsupported_kinds - [:partial_failed, :block_failed, :section_failed, :input_degraded]).empty?
    end

    # A form that didn't record completely doesn't know all its fields, so what it misses isn't refused.
    def reject_unknown_params?(schema) = ReactiveAdmin.config.reject_unknown_params && schema.submittable?

    # Names only, never values, and a bounded list of them: both are the client's input.
    def reject_unknown_params(paths)
      listed = paths.first(MAX_UNKNOWN_LISTED).map { it.truncate(100) }
      render_api_error(:invalid, "Not fields of this form: #{listed.join(", ")}", 422, errors: {}, base: ["These aren't fields of this form: #{listed.join(", ")}"])
    end

    # A custom create may build a different class than the resource's (AdhocPlan for AppointmentPlan),
    # so assigning the submitted params to a plain one can fail.
    def write_record
      FormPayload.record_for(self)
    rescue ActiveModel::UnknownAttributeError
      @reactiveadmin_stand_in_record = true
      active_admin_config.resource_class.new
    end

    # `lock!` reloads the row, so it runs before the action assigns the submitted attributes.
    def guard_lock(record, schema)
      lock_row(record)
      return if performed?

      lock = FormLock.for(record, nested: schema.nested_associations) or return
      if @reactiveadmin_lock.nil?
        render_api_error(:invalid, "Missing lock: reload the form and try again", 400) if ReactiveAdmin.config.require_lock
      elsif !lock.matches?(@reactiveadmin_lock)
        render_api_error(:stale, FormLock::STALE_MESSAGE, 409)
      end
    end

    # A record deleted since it was loaded, or one a host before_action left with unsaved changes (which
    # `lock!` refuses to discard), can't be compared against the client's token.
    def lock_row(record)
      record.lock! if FormLock.field_for(record.class) == "updated_at"
    rescue ActiveRecord::RecordNotFound
      render_api_error(:not_found, "Record not found", 404)
    rescue RuntimeError
      raise unless record.changed?

      render_api_error(:stale, FormLock::STALE_MESSAGE, 409)
    end
  end
end
