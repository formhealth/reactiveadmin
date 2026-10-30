module ReactiveAdmin
  module OpenApi
    # The JSON body create and update accept, from the same controls-only form schema the runtime
    # judges writes by: each control's `param` is a path into the body (`post[comments_attributes][__INDEX__][body]`).
    # Disabled inputs are dropped by the runtime, and masked ones are left out here, so no credential's name is published.
    class WriteSchema
      # One level of the body: named children, an indexed row template (has_many), or a leaf schema.
      class Node
        attr_accessor :props, :rows, :leaf

        def initialize(leaf = nil)
          @props = {}
          @leaf = leaf
        end
      end

      SCALARS = {
        "text" => {type: "string"}, "textarea" => {type: "string"}, "hidden" => {type: "string"}, "select" => {type: "string"},
        "radio" => {type: "string"}, "typeahead" => {type: "string"}, "phone" => {type: "string"},
        "email" => {type: "string", format: "email"}, "url" => {type: "string", format: "uri"},
        "password" => {type: "string", writeOnly: true}, "number" => {type: "number"}, "boolean" => {type: "boolean"},
        "date" => {type: "string", format: "date"}, "datetime" => {type: "string", format: "date-time"},
        "time" => {type: "string", format: "time"},
        "file" => {type: "string", format: "binary", description: "Send the request as multipart/form-data to upload a file."},
        "json" => {description: "Structured JSON (object, array or scalar), sent as JSON."}
      }.freeze
      CHOICES = %w[select radio typeahead multiselect checkboxes].freeze
      INDEX = "__INDEX__".freeze

      def initialize(config, sections, options_path:, reserved: [])
        @config = config
        @options_path = options_path
        @reserved = reserved
        @root = Node.new
        sections.each { add_section(it) }
      end

      # The object schema, or nil when the form has no writable control.
      def schema = (render(@root) if @root.props.any?)

      # Top-level body keys, e.g. the resource's param key.
      def keys = @root.props.keys

      private

      def add_section(section)
        if section[:kind] == "has_many"
          add_has_many(section)
        else
          Array(section[:fields]).each { add_field(it) }
        end
      end

      def add_has_many(section)
        Array(section[:template_fields]).each { add_field(it) }
        return if section[:param].blank? || reserved?(section[:param])

        row = descend(path_of(section[:param]) + [INDEX])
        row.props["id"] ||= Node.new({type: "string"})
        row.props["_destroy"] ||= Node.new({type: "boolean"}) if section[:allow_destroy]
      end

      def add_field(field)
        param = field[:param]
        return if param.blank? || field[:disabled] || reserved?(param) || masked?(field[:name])

        schema = leaf(field, param)
        descend(path_of(param)).leaf = schema if schema
      end

      # The runtime refuses a write naming a guarded attribute at any depth, so none is published.
      def reserved?(param) = path_of(param).intersect?(@reserved)

      def masked?(name) = Masking.attribute?(name.to_s.split(".").last, @config)

      def leaf(field, param)
        control = field[:control]
        base = SCALARS[control]
        base = {type: "array", items: {type: "string"}} if %w[multiselect checkboxes].include?(control)
        return unless base

        base = {type: "array", items: base} if param.end_with?("[]") && control != "checkboxes" && control != "multiselect"
        hint = "Options are served by `GET #{@options_path}?context=form&field=#{field[:name]}`." if CHOICES.include?(control)
        hint ? {description: hint, **base} : base
      end

      def path_of(param) = param.scan(/[^\[\]]+/)

      def descend(path)
        path.inject(@root) do |node, key|
          (key == INDEX) ? (node.rows ||= Node.new) : (node.props[key] ||= Node.new)
        end
      end

      def render(node)
        return node.leaf if node.leaf
        return {type: "object", additionalProperties: render(node.rows)} if node.rows && node.props.empty?

        props = node.props.transform_values { render(it) }
        {type: "object", properties: props, additionalProperties: false}
      end
    end
  end
end
