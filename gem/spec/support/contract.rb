require "json_schemer"
require "yaml"

# Validates payloads against the OpenAPI components in openapi/core.yaml.
module Contract
  PATH = File.expand_path("../../../openapi/core.yaml", __dir__)

  module_function

  def openapi = @openapi ||= JSONSchemer.openapi(YAML.safe_load_file(PATH, aliases: true))

  def errors(schema_name, data)
    openapi.ref("#/components/schemas/#{schema_name}").validate(JSON.parse(data.to_json)).map { it["error"] }
  end

  def valid?(schema_name, data) = errors(schema_name, data).empty?
end

RSpec::Matchers.define :match_contract do |schema_name|
  match { |data| Contract.valid?(schema_name, data) }

  failure_message { |data| "expected payload to match #{schema_name}:\n  #{Contract.errors(schema_name, data).first(8).join("\n  ")}" }
end
