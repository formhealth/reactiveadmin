RSpec.describe ReactiveAdmin::ValuePayload do
  let(:config) { ReactiveAdmin::Registry.find("categories") }
  let(:controller) { Object.new.tap { it.instance_variable_set(:@reactiveadmin_token_user, "1") } }
  let(:source) { described_class::Source.new(config:, record: Category.new(id: 7), field: "settings", inline: true, controller:, via: "index") }
  let(:value) { {"theme" => "dark", "list" => [1]} }

  before { Rails.application.reload_routes_unless_loaded }

  describe ".node" do
    it "inlines a small value for an inline source" do
      expect(described_class.node(value, source)).to eq(type: "json", value:)
    end

    it "summarizes unless the source is inline" do
      source.inline = false

      expect(described_class.node(value, source)).to match(
        type: "json", summary: {kind: "object", keys: %w[theme list], size: value.to_json.bytesize},
        expand_path: start_with("/api/admin/categories/7/_value?field=settings&token=")
      )
    end

    it "leaves the token out in legacy mode" do
      source.inline = false
      ReactiveAdmin.config.value_token = false

      expect(described_class.node(value, source)[:expand_path]).to eq("/api/admin/categories/7/_value?field=settings")
    ensure
      ReactiveAdmin.config.value_token = true
    end

    it "summarizes a value over the limit and one holding a masked key" do
      ReactiveAdmin.config.inline_json_limit = 5
      expect(described_class.node(value, source)).to include(:summary)
      ReactiveAdmin.config.inline_json_limit = 2048

      expect(described_class.node({"x" => {"api_token" => "t"}}, source)).to include(:summary)
    ensure
      ReactiveAdmin.config.inline_json_limit = 2048
    end

    it "types an empty hash or array as empty" do
      expect([{}, []].map { described_class.node(it, source) }).to all(eq(type: "empty"))
    end

    it "omits expand_path without a record" do
      expect(described_class.node(value, nil)).not_to include(:expand_path)
    end
  end

  describe ".mask" do
    it "replaces present values of masked keys at any depth, leaving blanks and arrays' other items" do
      masked = described_class.mask({"api_token" => "t", "empty" => 1, "a" => [{"api_token" => ""}, {"api_token" => "x", "ok" => 1}]}, config)

      expect(masked).to eq("api_token" => "[masked]", "empty" => 1, "a" => [{"api_token" => ""}, {"api_token" => "[masked]", "ok" => 1}])
    end
  end

  describe ".dig" do
    it "follows keys and array indexes and 404s on anything else" do
      value = {"a" => [{"b" => 1}]}

      expect(described_class.dig(value, "a.0.b")).to eq(1)
      expect(described_class.dig(value, "")).to eq(value)
      expect { described_class.dig(value, "a.-1") }.to raise_error(ActiveRecord::RecordNotFound)
      expect { described_class.dig(value, "a.0.b.c") }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end
end
