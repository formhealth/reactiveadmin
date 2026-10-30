module ReactiveAdmin
  # Typed nodes for plain attribute values (index cells backed by a symbol).
  module Values
    PLAIN = [String, Symbol, Numeric, TrueClass, FalseClass, NilClass, Date, Time, ActiveSupport::TimeWithZone].freeze

    module_function

    def for(value, view, source: nil)
      case value
      when nil then {type: "empty"}
      when true, false then {type: "boolean", value:}
      when Time, DateTime, ActiveSupport::TimeWithZone then {type: "datetime", value: value.iso8601}
      when Date then {type: "date", value: value.iso8601}
      when Numeric then {type: "number", value: value.is_a?(BigDecimal) ? value.to_f : value}
      when String, Symbol then value.to_s.strip.empty? ? {type: "empty"} : {type: "text", text: value.to_s}
      when ActiveRecord::Base then record(value, view)
      when Hash, Array then plain?(value) ? ValuePayload.node(value, source) : formatted(value, view)
      else formatted(value, view)
      end
    end

    def record(record, view)
      label = display_label(record, view)
      ref = Registry.ref(record)
      ref ? {type: "ref", label:, ref:} : {type: "text", text: label}
    end

    def display_label(record, view) = CGI.unescapeHTML(AA.display_name(view, record).to_s)

    # AA's display_name, or nil where AA would only fall back to "Model #id".
    def display_name(record, view) = AA.explicit_display_name(view, record)

    def plain?(value)
      case value
      when Hash then value.all? { |k, v| plain?(k) && plain?(v) }
      when Array then value.all? { plain?(it) }
      else PLAIN.any? { value.is_a?(it) }
      end
    end

    def formatted(value, view) = HtmlNodes.convert(AA.pretty_format(view, value).to_s)
  end
end
