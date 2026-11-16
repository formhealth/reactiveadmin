RSpec.describe "openapi/core.yaml" do
  let(:document) { YAML.safe_load_file(Contract::PATH, aliases: true) }

  it "is a valid OpenAPI document" do
    expect(JSONSchemer.openapi(document).validate.map { it["data_pointer"] }).to eq([])
  end

  it "has unique operation ids" do
    ids = document["paths"].values.flat_map { |item| item.values.filter_map { it["operationId"] if it.is_a?(Hash) } }

    expect(ids.tally.select { |_, count| count > 1 }).to eq({})
  end

  it "resolves every $ref" do
    refs = document.to_s.scan(%r{#/components/(\w+)/(\w+)}).uniq

    refs.each do |section, name|
      expect(document.dig("components", section, name)).to be_present, "#/components/#{section}/#{name}"
    end
  end

  it "keeps property names snake_case" do
    names = document["components"]["schemas"].values.flat_map { |schema| (schema["properties"] || {}).keys }

    expect(names.grep(/[A-Z]/)).to eq([])
  end

  describe "Contract helper" do
    it "accepts nullable values the OpenAPI 3.0 way" do
      expect(Contract.valid?("Scope", {"id" => "a", "name" => "A", "count" => nil})).to be(true)
    end

    it "rejects values outside enums" do
      expect(Contract.valid?("Error", {"code" => "teapot", "message" => "x"})).to be(false)
    end

    it "requires required properties" do
      expect(Contract.errors("Error", {"code" => "forbidden"})).not_to be_empty
    end

    it "validates nodes recursively" do
      node = {"type" => "panel", "title" => "P", "children" => [{"type" => "text", "text" => "x"}, {"type" => "bogus"}]}

      expect(Contract.valid?("Node", node)).to be(false)
    end

    it "rejects keys the contract doesn't declare" do
      expect(Contract.errors("Option", {"label" => "A", "value" => "a", "extra" => 1})).to include(/extra/)
    end
  end

  describe "the schema a response is checked against" do
    it "follows the most literal path" do
      expect(Contract.response_schema("GET", "/api/admin/posts/new", 200)).to eq("FormResponse")
      expect(Contract.response_schema("GET", "/api/admin/posts/1?x=1", 200)).to eq("ShowResponse")
      expect(Contract.response_schema("POST", "/api/admin/posts", 201)).to eq("WriteResult")
    end

    it "points into an inline union" do
      schema = Contract.response_schema("GET", "/api/admin/_pages/reports", 200)

      expect(Contract.valid?(schema, {"options" => [], "truncated" => false})).to be(true)
    end

    it "matches routes nested under a parent to the resource's own" do
      expect(Contract.response_schema("GET", "/api/admin/posts/42/comments/new", 200)).to eq("FormResponse")
      expect(Contract.response_schema("GET", "/api/admin/posts/42/comments/7", 200)).to eq("ShowResponse")
    end

    it "matches pages nested under a parent to the page's own" do
      expect(Contract.response_schema("GET", "/api/admin/posts/42/_pages/post_digests", 200)).to eq(Contract.response_schema("GET", "/api/admin/_pages/post_digests", 200))
      expect(Contract.response_schema("GET", "/api/admin/posts/42/_pages/post_digests", 200)).not_to be_nil
    end

    it "matches a custom namespace to the canonical paths" do
      allow(ReactiveAdmin.config).to receive(:namespace).and_return(:backoffice)
      allow(ReactiveAdmin::Registry).to receive(:find)

      expect(Contract.response_schema("GET", "/api/backoffice/posts/_meta", 200)).to eq(Contract.response_schema("GET", "/api/admin/posts/_meta", 200))
      expect(Contract.response_schema("GET", "/api/backoffice/posts/_meta", 200)).not_to be_nil
    end

    it "is nil where the contract declares nothing" do
      expect(Contract.response_schema("PUT", "/api/admin/posts/new", 200)).to be_nil
    end

    it "finds an operation by id" do
      expect(Contract.operation_schema("runMemberActionGet", 200)).to eq("ActionGetResponse")
      expect(Contract.operation_schema("runMemberActionPost", 501)).to eq("Error")
      expect(Contract.operation_schema("noSuchOperation", 200)).to be_nil
    end
  end
end
