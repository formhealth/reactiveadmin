module ReactiveAdmin
  # Batch actions offered on a resource's index, with the inputs of their `form:` dialog.
  class BatchActions
    CONTROLS = {text: "text", textarea: "textarea", number: "number", datepicker: "date", checkbox: "boolean"}.freeze

    def initialize(config, view)
      @config = config
      @view = view
    end

    def as_json(*)
      AA.batch_actions(@config).filter_map do |action|
        next unless safely(false, action) { AA.batch_action_visible?(@view, action) }

        key = action.sym.to_s
        {key:, label: label(action), confirm: confirm(action), inputs: inputs(action), **api_marks(key)}.compact
      end
    end

    private

    def api_marks(key)
      names = ["batch_action", key]
      declaration = ApiGuards.denial(@config, names, verb: "post")
      return ApiGuards.annotate({}, ApiGuards.custom_for(@config, names)) unless declaration

      {api_denied: true, classic_url: Paths.collection(@config, parent_id: Paths.parent_id(@config, @view.params)), disabled_reason: ApiGuards.message(declaration)}
    end

    def label(action)
      title = AA.batch_action_title(@view, action)
      AA.t("batch_actions.labels.#{action.sym}", default: title.to_s)
    end

    def confirm(action) = AA.batch_action_confirm(@view, action).presence

    def inputs(action)
      form = safely({}, action) { AA.batch_action_inputs(@view, action) }
      form.to_h.map { |name, type| input(name.to_s, type) }
    end

    def input(name, type)
      field = {name:, param: name, label: name.humanize, value: nil, required: false}
      return field.merge(control: CONTROLS.fetch(type.to_s.to_sym, "text")) unless type.is_a?(Array)

      options = type.map { |item| item.is_a?(Array) ? {label: item.first.to_s, value: item.last.to_s} : {label: item.to_s, value: item.to_s} }
      field.merge(control: "select", options:)
    end

    def safely(fallback, action)
      yield
    rescue => e
      Degradation.record(kind: :batch_action_block_failed, where: "index/batch_action[#{action.sym}]", reason: "Block raised #{e.class}; used a default")
      fallback
    end
  end
end
