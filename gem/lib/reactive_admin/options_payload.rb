module ReactiveAdmin
  # Typeahead backend for the _options endpoint: filter and form controls whose collections
  # are too large to inline.
  class OptionsPayload
    MAX_LIMIT = 100
    MAX_VALUES = 25
    # The endpoint's own params; the rest of a page's query is what its content reads.
    RESERVED = %w[context form field term value limit cursor].freeze

    # What a page or template was loaded with, for a search that renders it again to find the field.
    def self.page_query(request) = request.query_parameters.except(*RESERVED)

    # Comma-separated values, as a string or a list of them; more than `max` is a 400.
    def self.split_values(raw, max = MAX_VALUES)
      values = Array.wrap(raw).flat_map { it.to_s.split(",") }
      raise ApiErrors::BadRequest, "Too many values (max #{max})" if values.size > max

      values
    end

    # The source of each field in a context. A form is built for just those fields: their options
    # may depend on the record, not on their siblings.
    def self.sources(controller, context, fields)
      case context
      when "filter"
        filters = Filters.new(AA.config_of(controller), controller.view_context)
        fields.index_with { filters.choices(it) }
      when "form"
        schema = FormPayload.new(controller, only: fields).schema
        schema.sections
        fields.index_with { |field| schema.choices.fetch(field) { raise ActiveRecord::RecordNotFound, "No options for #{field}" } }
      else raise ActionController::ParameterMissing, :context
      end
    end

    def initialize(controller)
      @controller = controller
      @params = controller.params
    end

    def as_json(*)
      source = choices
      values = self.class.split_values(@params[:value])
      result = if values.any?
        {options: source.lookup(values), truncated: false}
      else
        limit = @params.fetch(:limit, ReactiveAdmin.config.inline_options_limit).to_i.clamp(1, MAX_LIMIT)
        source.search(@params[:term].to_s, limit, @params[:cursor])
      end
      LookupAudit.record(@controller, model: source.try(:model), kind: values.any? ? :lookup : :search, field: @params[:field], result_count: result[:options].size)
      result
    end

    private

    def choices
      field = @params.require(:field)
      self.class.sources(@controller, @params[:context], [field]).fetch(field)
    end
  end
end
