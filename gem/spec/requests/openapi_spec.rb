RSpec.describe "GET /api/admin/_openapi", type: :request do
  include_context "with a blog"

  let(:path) { "/api/admin/_openapi" }
  let(:doc) { api_get(path) }
  let(:manifest) { api_get("/api/admin/_manifest") }

  def operations(document) = document["paths"].flat_map { |route, item| item.keys.map { |verb| [verb, route] } }

  context "when signed out" do
    it "answers 401 in JSON, like the manifest" do
      api_get(path)

      expect(response).to have_http_status(:unauthorized)
      expect(json).to include("code" => "unauthorized")
    end
  end

  context "when signed in" do
    before { sign_in admin }

    it "serves the user's document as plain JSON" do
      expect(doc).to include("openapi" => "3.1.0")
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/json")
      expect(JSON.parse(response.body)).to eq(JSON.parse(ReactiveAdmin::OpenApi.build(admin).to_json))
    end

    it "also answers the vnd format" do
      get path, headers: {"ACCEPT" => "application/vnd.reactiveadmin+json"}

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/json")
      expect(json["openapi"]).to eq("3.1.0")
    end

    it "answers a plain browser or viewer request without a special Accept" do
      get path

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/json")
    end

    it "validates against the OpenAPI 3.1 meta-schema" do
      errors = JSONSchemer.openapi(doc).validate.map { it["error"] }

      expect(errors).to eq([])
    end

    it "is cached, so the second request builds nothing" do
      allow(ReactiveAdmin::OpenApi).to receive(:build).and_call_original

      2.times { api_get(path) }

      expect(ReactiveAdmin::OpenApi).to have_received(:build).once
    end

    it "serves each user their own document" do
      sign_in editor
      scopes = doc["paths"]["/api/admin/posts"]["get"]["parameters"].find { it["name"] == "scope" }.dig("schema", "enum")

      expect(scopes).not_to include("featured")
    end

    it "counts against the default rate bucket" do
      old = ReactiveAdmin.config.rate_limits
      ReactiveAdmin.config.rate_limits = {default: [1, 1.minute]}

      api_get(path)
      expect(response).to have_http_status(:ok)
      api_get(path)

      expect(response).to have_http_status(:too_many_requests)
      expect(json).to include("code" => "rate_limited")
    ensure
      ReactiveAdmin.config.rate_limits = old
    end

    it "describes the same operations the manifest says the user can take, and none more" do
      crud = {
        index: ["get", ""], show: ["get", "/{id}"], new: ["get", "/new"], create: ["post", ""],
        edit: ["get", "/{id}/edit"], update: ["patch", "/{id}"], destroy: ["delete", "/{id}"]
      }
      permission = {index: "index", show: "show", new: "create", create: "create", edit: "update", update: "update", destroy: "destroy"}
      declared = ReactiveAdmin::Registry.resources.to_h do |config|
        [ReactiveAdmin::Registry.route_key(config), [*config.member_actions, *config.collection_actions].map { it.name.to_s }]
      end
      extras = %w[_meta _options lookup _labels _value batch_action]
      described = operations(doc)
      all_expected = []

      manifest["resources"].each do |resource|
        base = (resource["belongs_to"] && !resource["belongs_to"]["optional"]) ? "/api/admin/#{resource["belongs_to"]["parent"]}/{#{resource["belongs_to"]["param"]}}/#{resource["key"]}" : "/api/admin/#{resource["key"]}"
        expected = resource["actions"].filter_map do |action|
          verb, suffix = crud[action.to_sym]
          reserved = ReactiveAdmin::ApiGuards.denies?(ReactiveAdmin::Registry.find(resource["key"]), action, permission[action.to_sym])
          [verb, base + suffix] if verb && resource["permissions"][permission[action.to_sym]] && !reserved
        end
        all_expected += expected
        tagged = doc["paths"].flat_map { |route, item| item.filter_map { |verb, operation| [verb, route] if operation["tags"] == [resource["key"]] } }
        own = tagged.select { |_, route| route.start_with?(base) && route.delete_prefix(base).match?(%r{\A(|/new|/\{id\}(/edit)?)\z}) }

        expect(own).to match_array(expected), resource["key"]
        other = (tagged - own).reject { |_, route| route.end_with?(".csv") || (extras + declared[resource["key"]]).include?(route.split("/").last) }
        expect(other).to eq([]), "#{resource["key"]} documents operations the manifest doesn't list"
      end
      expect(described).to include(*all_expected)
    end

    it "lists no resource the manifest leaves out" do
      listed = manifest["resources"].pluck("key")
      tags = doc["tags"].pluck("name").reject { it.start_with?("page:") || it == "meta" }

      expect(tags).to match_array(listed)
    end
  end
end
