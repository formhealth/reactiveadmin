module ReactiveAdmin
  # Labels for the selected values of several fields at once (`_options/lookup`), so opening a form
  # with many typeaheads costs one request and one build of the form. Same sources, authorization
  # and policy scoping as `_options`.
  class LookupPayload
    MAX_VALUES = 100

    def initialize(controller)
      @controller = controller
      @params = controller.params
    end

    def as_json(*)
      requested = values_by_field
      sources = OptionsPayload.sources(@controller, @params[:context], requested.keys)
      {lookups: requested.to_h { |field, values| [field, lookup(sources.fetch(field), field, values)] }}
    end

    private

    def lookup(source, field, values)
      source.lookup(values).tap do
        LookupAudit.record(@controller, model: source.try(:model), kind: :lookup, field:, result_count: it.size)
      end
    end

    def values_by_field
      fields = @params.require(:fields)
      raise ApiErrors::BadRequest, "fields must map field names to values" unless fields.respond_to?(:to_unsafe_h)

      fields = fields.to_unsafe_h
      raise ApiErrors::BadRequest, "fields must map field names to values" unless fields.values.all? { it.is_a?(String) || it.is_a?(Array) }

      requested = fields.transform_values { OptionsPayload.split_values(it) }.reject { |_, values| values.empty? }
      raise ApiErrors::BadRequest, "Too many values (max #{MAX_VALUES})" if requested.values.sum(&:size) > MAX_VALUES
      raise ActionController::ParameterMissing, :fields if requested.empty?

      requested
    end
  end
end
