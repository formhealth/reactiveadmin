module ReactiveAdmin
  # The columns a resource shows when it declares no `index`/`show` block. AA would render every
  # content column; under `config.implicit_defaults = :secure` credentials and binary data stay out,
  # and json and free text, which may hold sensitive data, are shown the way explicit json is: summarized or
  # truncated, with the full value one audited `_value` call away. An explicit block is the host's
  # deliberate choice and is never filtered.
  module ImplicitDefaults
    HIDDEN_TYPES = %i[binary].freeze
    TEXT_PREVIEW = 120
    REASON = "column hidden by secure defaults".freeze

    # Extended onto the show view: rows of default text columns become truncated text nodes.
    module Display
      attr_writer :reactiveadmin_implicit_text

      def format_attribute(resource, attr)
        config = @reactiveadmin_value_config
        return super unless @reactiveadmin_implicit_text&.include?(attr.to_s) && resource.instance_of?(config.resource_class)

        value = AA.find_value(self, resource, attr)
        return super unless value.is_a?(String)

        reactiveadmin_attributes << attr.to_s
        source = ValuePayload::Source.new(config:, record: resource, field: attr.to_s, controller:, via: "show")
        NodeRegistry.marker(ImplicitDefaults.text_node(value, source, inline: true))
      end
    end

    class << self
      def secure? = ReactiveAdmin.config.implicit_defaults == :secure

      def strict? = ReactiveAdmin.config.strict_defaults

      # [visible columns, [[name, kind]] hidden], as AA's `resource_columns` would list them.
      def split(config)
        columns = config.resource_columns
        return [columns, []] unless secure?

        hidden = columns.filter_map { |key| (kind = kind(config, key)) && [key.to_s, kind] }
        [columns.reject { |key| hidden.assoc(key.to_s) }, hidden]
      end

      # The visible default columns; every hidden one is recorded as degraded for `where` (index or
      # show), except those the host masked on purpose: that is a decision, not a gap.
      def columns(config, where:)
        columns, hidden = split(config)
        hidden.reject { |name, _| Masking.explicit?(name, config) }.each { |name, kind| record(where, "#{kind} #{REASON}: #{name}") }
        columns
      end

      # Names of the visible text columns that secure defaults show truncated.
      def text_columns(config)
        return [] unless secure?

        split(config).first.map(&:to_s).select { text_column?(config, it) }
      end

      # A plain text column: the only kind `_value` returns as a string.
      def text_column?(config, field) = config.resource_class.columns_hash[field.to_s]&.type == :text && kind(config, field).nil?

      # The text a default column shows: all of it when short enough (on show, up to
      # `inline_text_limit`; anywhere, up to the preview), else the start and a way to the rest.
      def text_node(value, source, inline:)
        text = value.to_s
        return {type: "empty"} if text.strip.empty?
        return {type: "text", text:} if text.length <= TEXT_PREVIEW || (inline && text.bytesize <= ReactiveAdmin.config.inline_text_limit)

        {type: "text", text: text.first(TEXT_PREVIEW), truncated: true, expand_path: ValuePayload.expand_path(source)}.compact
      end

      def blocked(where) = record(where, "no #{where} block declared and strict_defaults is on", kind: "implicit_view_blocked")

      # Hidden column names per section that falls back to defaults, for `doctor`.
      def audit(config)
        {index: !IndexViews.new(config).presenter&.block, show: !AA.page_presenter(config, :show)&.block}
          .select { |_, implicit| implicit }
          .transform_values { split(config).last.map(&:first) }
      end

      private

      def kind(config, key)
        name = key.to_s
        klass = config.resource_class
        type = klass.columns_hash[name]&.type
        if Array(klass.try(:encrypted_attributes)).map(&:to_s).include?(name) then "encrypted"
        elsif AA.filter_attributes.map(&:to_s).include?(name) then "filtered"
        elsif Masking.attribute?(name, config) then "masked"
        elsif HIDDEN_TYPES.include?(type) then type.to_s
        end
      end

      def record(where, reason, kind: "implicit_column_hidden")
        Degradation.record(kind:, where:, reason:)
      end
    end
  end
end
