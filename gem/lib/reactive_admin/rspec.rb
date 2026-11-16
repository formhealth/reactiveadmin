require "erb"
require "json"
require "yaml"
require "json_schemer"
require "reactive_admin"

module ReactiveAdmin
  # Contract checks for request specs. Needs json_schemer in the host's test group.
  module RSpec
    # openapi/core.yaml with every object schema that lists properties closed, so an undeclared key
    # fails here instead of reaching the client untyped.
    module Contract
      PATH = OpenApi::Core::PATH

      module_function

      def document = @document ||= YAML.safe_load_file(PATH, aliases: true)

      def openapi = @openapi ||= JSONSchemer.openapi(closed(document.deep_dup))

      def closed(node)
        case node
        when Array then node.each { closed(it) }
        when Hash
          node["additionalProperties"] = false if node.key?("properties") && !node.key?("additionalProperties")
          node.each_value { closed(it) }
        end
        node
      end

      # `schema` is a component name (`IndexResponse`) or a JSON pointer into core.yaml.
      def errors(schema, data)
        pointer = schema.start_with?("#") ? schema : "#/components/schemas/#{schema}"
        openapi.ref(pointer).validate(JSON.parse(data.to_json)).map { it["error"] }
      end

      def valid?(schema, data) = errors(schema, data).empty?

      # What core.yaml declares for `status` on the operation that serves `path`; nil when it declares nothing.
      def response_schema(verb, path, status)
        keys = ["paths", template(path), verb.to_s.downcase, "responses", status.to_s]
        ref = document.dig(*keys, "$ref")
        keys = ref.delete_prefix("#/").split("/") if ref
        keys += ["content", "application/json", "schema"]
        schema = document.dig(*keys) or return
        schema["$ref"]&.delete_prefix("#/components/schemas/") || pointer(keys)
      end

      def pointer(keys) = "#/#{keys.map { ERB::Util.url_encode(it.gsub("~", "~0").gsub("/", "~1")) }.join("/")}"

      # Most literal first, so `/admin/{resource}/new` wins over `/admin/{resource}/{id}`.
      def template(path)
        route = canonical(path.split("?").first.delete_prefix(ReactiveAdmin.config.mount_path))
        templates.find { |_, pattern| pattern.match?(route) }&.first
      end

      # core.yaml says `/admin/{resource}/...`: map a custom namespace to it, and a route nested under
      # its parent (`/posts/42/comments/new`) to the resource's own.
      def canonical(route)
        _, namespace, *parts = route.split("/", -1)
        return route unless namespace == ReactiveAdmin.config.namespace.to_s

        parts.slice!(0, 2) if nested_under_parent?(parts)
        ["", "admin", *parts].join("/")
      end

      def nested_under_parent?(parts)
        child = Registry.find(parts[2])
        child&.belongs_to? && Registry.route_key(child.belongs_to_config.target) == parts[0]
      end

      def templates
        @templates ||= document["paths"].keys
          .sort_by { |path| -path.split("/").count { !it.include?("{") } }
          .map { |path| [path, /\A#{path.split(/\{\w+\}/, -1).map { Regexp.escape(it) }.join("[^/]+")}\z/] }
      end
    end

    HEADERS = {"ACCEPT" => "application/json"}.freeze

    module_function

    # Adds an example per registration to a request spec group: its meta, index and first listed
    # record answer as core.yaml says. Sign in, as a user who can read everything, in a `before`.
    # Resources that only exist under a parent are left out.
    def contract_examples(group)
      Rails.application.try(:reload_routes_unless_loaded)
      Registry.resources.reject { Paths.nested?(it) }.each do |config|
        key = Registry.route_key(config)
        group.it "serves #{key} as the contract describes" do
          check = lambda do |path|
            get(path, headers: HEADERS)
            expect(response.status).to be < 500, "GET #{path} answered #{response.status}"
            schema = (response.status >= 400) ? "Error" : Contract.response_schema("get", path, response.status)
            body = response.parsed_body if response.media_type == "application/json"
            expect(body).not_to be_nil, "GET #{path} answered #{response.status} #{response.media_type}"
            errors = schema ? Contract.errors(schema, body) : []
            expect(errors).to be_empty, "GET #{path} (#{response.status}) doesn't match #{schema}:\n  #{errors.first(8).join("\n  ")}"
            body
          end

          check.call(Paths.api(Paths.meta(config)))
          index = check.call(Paths.api(Paths.collection(config)))
          show = response.successful? && index["rows"].first&.dig("paths", "api_show")
          check.call(show) if show
        end
      end
    end
  end
end

RSpec::Matchers.define :match_contract do |schema|
  match { |data| ReactiveAdmin::RSpec::Contract.valid?(schema, data) }

  failure_message { |data| "expected payload to match #{schema}:\n  #{ReactiveAdmin::RSpec::Contract.errors(schema, data).first(8).join("\n  ")}" }
end
