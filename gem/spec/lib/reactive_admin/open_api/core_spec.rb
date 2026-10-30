RSpec.describe ReactiveAdmin::OpenApi::Core do
  describe ".convert" do
    it "turns nullable types into type arrays" do
      converted = described_class.convert({"type" => "string", "nullable" => true, "description" => "x"})

      expect(converted).to eq("type" => %w[string null], "description" => "x")
    end

    it "adds null to an enum of a nullable type" do
      expect(described_class.convert({"type" => "string", "enum" => %w[a b], "nullable" => true}))
        .to eq("type" => %w[string null], "enum" => ["a", "b", nil])
    end

    it "leaves a bare nullable schema as any value" do
      expect(described_class.convert({"nullable" => true})).to eq({})
    end

    it "allows null beside a reference" do
      expect(described_class.convert({"$ref" => "#/components/schemas/Ref", "nullable" => true, "description" => "d"}))
        .to eq("anyOf" => [{"$ref" => "#/components/schemas/Ref"}, {"type" => "null"}], "description" => "d")
    end

    it "turns example into examples" do
      expect(described_class.convert({"type" => "string", "example" => "en"})).to eq("type" => "string", "examples" => ["en"])
    end

    it "does not read property names as keywords" do
      schema = {"type" => "object", "properties" => {"example" => {"type" => "string", "nullable" => true}, "nullable" => {"type" => "boolean"}}}

      expect(described_class.convert(schema)["properties"]).to eq("example" => {"type" => %w[string null]}, "nullable" => {"type" => "boolean"})
    end
  end

  describe "the contract" do
    it "holds no 3.0-only keywords once converted" do
      text = JSON.generate(described_class.document)

      expect(text).not_to match(/"nullable"|"example":/)
    end

    it "gives out its component groups and copies of its operations" do
      expect(described_class.components("schemas")).to include("Node", "IndexResponse")
      expect(described_class.operation("/admin/{resource}/_options", "get")["operationId"]).to eq("getOptions")
      expect(described_class.operation("/admin/_openapi", "get")["operationId"]).to eq("getOpenApi")
    end

    it "hands out operations the caller may change without touching the contract" do
      described_class.operation("/admin/{resource}/_options", "get")["operationId"] = "changed"

      expect(described_class.operation("/admin/{resource}/_options", "get")["operationId"]).to eq("getOptions")
    end
  end
end
