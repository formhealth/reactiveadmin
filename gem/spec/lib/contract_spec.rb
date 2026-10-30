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
  end
end
