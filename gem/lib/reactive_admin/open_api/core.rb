require "yaml"

module ReactiveAdmin
  module OpenApi
    # openapi/core.yaml (OpenAPI 3.0) as a source of 3.1 components and operation templates.
    module Core
      PATH = File.expand_path("../../../../openapi/core.yaml", __dir__)
      KINDS = %w[parameters headers requestBodies responses schemas].freeze

      module_function

      def document = @document ||= begin
        raise "reactiveadmin: #{PATH} is missing; the OpenAPI document embeds its schemas" unless File.exist?(PATH)

        convert(YAML.safe_load_file(PATH, aliases: true)).freeze
      end

      def components(kind) = document.dig("components", kind) || {}

      # A copy of one of core's operations, for the caller to specialize.
      def operation(path, verb) = document.dig("paths", path, verb).deep_dup

      # `nullable` and `example` became type arrays and `examples` in JSON Schema 2020-12.
      def convert(node, names: false)
        case node
        when Array then node.map { convert(it) }
        when Hash then names ? node.transform_values { convert(it) } : schema(node)
        else node
        end
      end

      def schema(node)
        node = node.dup
        nullable = node.delete("nullable")
        node["examples"] = [node.delete("example")] if node.key?("example")
        converted = node.to_h { |key, value| [key, convert(value, names: key == "properties")] }
        nullable ? allow_null(converted) : converted
      end

      def allow_null(node)
        node["enum"] = [*node["enum"], nil].uniq if node["enum"]
        case (type = node["type"])
        when String then node.merge("type" => [type, "null"])
        when Array then node.merge("type" => [*type, "null"].uniq)
        when nil then (node.key?("$ref") || node.key?("oneOf") || node.key?("allOf")) ? {"anyOf" => [node.except("description"), {"type" => "null"}], **node.slice("description")} : node
        else node
        end
      end
    end
  end
end
