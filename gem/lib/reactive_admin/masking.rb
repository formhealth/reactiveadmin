module ReactiveAdmin
  # Credentials and secrets never go over the API: their values in index cells, show rows and form
  # fields are replaced by a `masked` node. Which attributes count is decided by name, from
  # `config.masked_attributes`, a resource's `reactive { mask :token }` and, unless turned off with
  # `config.mask_filter_parameters = false`, Rails' `filter_parameters`. Only attribute-keyed values
  # are masked: a column or row computed by a block is the host's to handle.
  module Masking
    NODE = {type: "masked"}.freeze
    CLASS_NAME = "reactiveadmin-masked".freeze
    CSV_PLACEHOLDER = "[MASKED]".freeze

    # Rendered where AA's helpers would print the value; HtmlNodes turns it into NODE.
    def self.html = %(<span class="#{CLASS_NAME}"></span>).html_safe

    class << self
      def attribute?(name, config = nil)
        name = name.to_s
        return false if name.empty?

        explicit?(name, config) || (ReactiveAdmin.config.mask_filter_parameters && filtered?(name))
      end

      # Masked by the host's own declaration, as opposed to inferred from `filter_parameters`.
      def explicit?(name, config = nil) = match?([*ReactiveAdmin.config.masked_attributes, *config&.reactive_options&.[](:mask)], name.to_s)

      # An empty value shows as empty: masking it would only claim a secret is set.
      def node(config, name, value) = (NODE if value.present? && attribute?(name, config))

      # Makes AA's `format_attribute` (index cells, attributes_table rows) mask for this view only,
      # so the classic admin is untouched.
      def install(view, config)
        view.instance_variable_set(:@reactiveadmin_mask_config, config)
        view.extend(Display)
      end

      # A blank value for a masked attribute means "unchanged": the form never receives the current
      # value, so submitting it back blank must not wipe the secret. With a `record`, only its present
      # values are protected; a blank one has nothing to keep, and the blank is written as classic does.
      def keep_unchanged(params, config, record = nil)
        params.keys.each do |key|
          value = params[key]
          if value.respond_to?(:keys) then keep_unchanged(value, config)
          elsif value.is_a?(Array) then value.each { keep_unchanged(it, config) if it.respond_to?(:keys) }
          elsif (value.nil? || value == "") && attribute?(key, config) && !(record && record.try(key).blank?) then params.delete(key)
          end
        end
      end

      private

      def match?(list, name) = list.any? { it.is_a?(Regexp) ? it.match?(name) : it.to_s == name }

      def filtered?(name)
        filters = Rails.application.config.filter_parameters
        (@filters, @parameter_filter = filters.hash, ActiveSupport::ParameterFilter.new(filters)) unless @filters == filters.hash
        @parameter_filter.filter(name => +"x")[name] != "x"
      end
    end

    module Display
      def format_attribute(resource, attr)
        config = @reactiveadmin_mask_config
        masks = (attr.is_a?(Symbol) || attr.is_a?(String)) && Masking.attribute?(attr, config)
        (masks && AA.find_value(self, resource, attr).present?) ? Masking.html : super
      end
    end

    # Behind `config.mask_csv` (on by default): AA's own export, classic and API alike.
    module Csv
      def build(controller, csv)
        @reactiveadmin_config = AA.config_of(controller)
        super
      end

      def build_row(resource, columns, options)
        return super unless ReactiveAdmin.config.mask_csv

        columns = columns.map do |column|
          next column unless column.data.is_a?(Symbol) && Masking.attribute?(column.data, @reactiveadmin_config)

          data = column.data
          AA.column_with_data(column, ->(record) { CSV_PLACEHOLDER if record.public_send(data).present? })
        end
        super
      end
    end
  end
end
