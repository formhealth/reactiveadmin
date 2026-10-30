module ReactiveAdmin
  # Display names for ids the user opened recently (command palette), so recents never fetch whole
  # records. Each record goes through the same finder and READ authorization as `show`; ids that
  # are missing or refused are left out, and nothing but resource, id and name is returned.
  class LabelsPayload
    MAX_IDS = 20

    def initialize(controller)
      @controller = controller
      @config = AA.config_of(controller)
    end

    def as_json(*)
      ids.filter_map { label(it) }.tap do
        LookupAudit.record(@controller, model: @config.resource_class, kind: :labels, result_count: it.size)
      end
    end

    private

    def ids
      raw = @controller.params.require(:ids)
      Array(raw).flat_map { it.to_s.split(",") }.map(&:strip).compact_blank.uniq.first(MAX_IDS)
    end

    def label(id)
      @controller.params[:id] = id
      record = AA.find_authorized_resource(@controller)
      {resource: Registry.route_key(@config), id: record.to_param.to_s, display_name: Values.display_label(record, @controller.view_context)}
    rescue ActiveRecord::RecordNotFound, AA::AccessDenied
      nil
    end
  end
end
