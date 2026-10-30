RSpec.describe ReactiveAdmin::Values do
  include_context "with a blog"

  let(:view) { ApplicationController.new.view_context.tap { it.extend(ActiveAdmin::ViewHelpers) } }

  def node(value) = described_class.for(value, view)

  it "types scalars" do
    expect(node(nil)).to eq(type: "empty")
    expect(node(true)).to eq(type: "boolean", value: true)
    expect(node(false)).to eq(type: "boolean", value: false)
    expect(node(3)).to eq(type: "number", value: 3)
    expect(node(BigDecimal("1.5"))).to eq(type: "number", value: 1.5)
    expect(node("hi")).to eq(type: "text", text: "hi")
    expect(node(:sym)).to eq(type: "text", text: "sym")
    expect(node("  ")).to eq(type: "empty")
  end

  it "types dates and times as ISO 8601" do
    expect(node(Date.new(2026, 1, 2))).to eq(type: "date", value: "2026-01-02")
    expect(node(Time.utc(2026, 1, 2, 3, 4, 5))).to eq(type: "datetime", value: "2026-01-02T03:04:05Z")
    expect(node(Time.zone.local(2026, 1, 2, 3))).to eq(type: "datetime", value: "2026-01-02T03:00:00Z")
  end

  it "summarizes plain hashes and arrays as json" do
    expect(node({"a" => [1, {"b" => nil}]})).to eq(type: "json", summary: {kind: "object", keys: ["a"], size: 20})
    expect(node([1, "x"])).to eq(type: "json", summary: {kind: "array", keys: [], size: 7})
  end

  it "sends a json value only when asked to inline it" do
    source = ReactiveAdmin::ValuePayload::Source.new(config: nil, inline: true)

    expect(described_class.for({"a" => 1}, view, source:)).to eq(type: "json", value: {"a" => 1})
  end

  it "formats other objects instead of dumping them" do
    expect(node([Object.new]).fetch(:type)).not_to eq("json")
  end

  it "refs registered records with their label" do
    expect(node(alice)).to eq(type: "ref", label: "Alice Author", ref: {resource: "authors", id: alice.id.to_s})
  end

  it "falls back to text for records no resource shows" do
    profile = Profile.create!(author: alice, bio: "x")

    expect(node(profile)[:type]).to eq("text")
  end

  describe ".display_name" do
    it "is the AA display name" do
      expect(described_class.display_name(alice, view)).to eq("Alice Author")
    end

    it "is nil where AA would only fall back to Model #id" do
      expect(described_class.display_name(Tagging.create!(post: first_post, tag: ruby), view)).to be_nil
    end
  end
end
