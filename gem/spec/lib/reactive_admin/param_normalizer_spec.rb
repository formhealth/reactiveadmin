RSpec.describe ReactiveAdmin::ParamNormalizer do
  def field(name, control, param = "memo[#{name}]") = {name:, param:, control:}

  let(:sections) do
    [
      {kind: "inputs", fields: [field("title", "text"), field("summary", "textarea"), field("payload", "json"), field("pinned", "boolean"),
        field("kind", "radio"), field("tag_ids", "multiselect", "memo[tag_ids][]"), field("priority", "select"), field("weight", "number")]},
      {kind: "has_many", name: "notes", param: "memo[notes_attributes]", fields: [],
       records: [{id: "4", param: "memo[notes_attributes][0]", fields: [field("body", "textarea", "memo[notes_attributes][0][body]"), field("meta", "json", "memo[notes_attributes][0][meta]")]}],
       template_fields: [field("body", "textarea", "memo[notes_attributes][__INDEX__][body]")]}
    ]
  end
  let(:permit) { nil }

  def normalize(attrs)
    params = ActionController::Parameters.new(memo: attrs)
    described_class.call(params, sections, permitted: permit && -> { params.permit(*permit) })
    params[:memo].to_unsafe_h
  end

  it "matches a field in any row by its shape, and lists every field of a has_many" do
    expect(described_class.shape("memo[notes_attributes][12][body]")).to eq(described_class.shape("memo[notes_attributes][__INDEX__][body]"))
    expect(described_class.fields_in(sections.last).pluck(:param)).to eq(%w[memo[notes_attributes][0][body] memo[notes_attributes][0][meta] memo[notes_attributes][__INDEX__][body]])
  end

  describe ReactiveAdmin::FormKeys do
    def unknown(attrs, list = sections)
      params = ActionController::Parameters.new(memo: attrs)
      [described_class.new(list, "memo").filter!(params), params[:memo].to_unsafe_h]
    end

    it "lists params no field accounts for, at any depth, keeping the rest" do
      found, kept = unknown(title: "T", secret: "x", notes_attributes: {"3" => {body: "b", author_id: "1"}})

      expect(found).to eq(%w[memo[secret] memo[notes_attributes][3][author_id]])
      expect(kept).to include("title" => "T")
    end

    it "takes a json field's structure, a multiselect's list and a nested row's id as one value" do
      expect(unknown(payload: {a: {b: 1}}, tag_ids: %w[1 2], notes_attributes: [{id: "4", body: "b"}]).first).to be_empty
    end

    it "drops disabled fields, of nested rows too" do
      disabled = [{kind: "has_many", name: "notes", param: "memo[notes_attributes]", fields: [], records: [],
                   template_fields: [field("body", "textarea", "memo[notes_attributes][__INDEX__][body]").merge(disabled: true)]}]

      expect(unknown({notes_attributes: {"0" => {body: "b"}}}, disabled)).to eq([[], {"notes_attributes" => {"0" => {}}}])
    end
  end

  it "posts null text-like fields as empty strings" do
    expect(normalize(title: nil, summary: nil, priority: nil, weight: nil)).to eq("title" => "", "summary" => "", "priority" => "", "weight" => "")
  end

  it "leaves present values, absent fields and unknown params alone" do
    expect(normalize(title: "A", extra: nil)).to eq("title" => "A", "extra" => nil)
  end

  it "keeps the types of booleans and lists" do
    expect(normalize(pinned: nil, tag_ids: [])).to eq("pinned" => nil, "tag_ids" => [])
  end

  it "leaves a false radio value alone" do
    expect(normalize(kind: false)).to eq("kind" => false)
  end

  it "omits an unselected radio, which a browser does not post" do
    expect(normalize(kind: "")).to eq({})
    expect(normalize(kind: nil)).to eq({})
    expect(normalize(kind: "a")).to eq("kind" => "a")
  end

  describe "json fields" do
    it "turns structured values into json text" do
      expect(normalize(payload: {a: [1, {b: nil}]})).to eq("payload" => '{"a":[1,{"b":null}]}')
      expect(normalize(payload: [1, "x"])).to eq("payload" => '[1,"x"]')
      expect(normalize(payload: 5)).to eq("payload" => "5")
      expect(normalize(payload: false)).to eq("payload" => "false")
    end

    it "posts null as an empty string and keeps text as it is" do
      expect(normalize(payload: nil)).to eq("payload" => "")
      expect(normalize(payload: "")).to eq("payload" => "")
      expect(normalize(payload: '{"a": 1}')).to eq("payload" => '{"a": 1}')
    end

    context "when the host permits the attribute as a structure" do
      let(:permit) { [memo: [payload: {}]] }

      it "keeps the structure" do
        expect(normalize(payload: {a: "1"})).to eq("payload" => {"a" => "1"})
      end
    end

    context "when the host permits a scalar" do
      let(:permit) { [memo: [:payload]] }

      it "turns the structure into json text" do
        expect(normalize(payload: {a: "1"})).to eq("payload" => '{"a":"1"}')
      end
    end

    it "falls back to json text when the host's strong parameters raise" do
      params = ActionController::Parameters.new(memo: {payload: [1]})
      described_class.call(params, sections, permitted: -> { raise "boom" })

      expect(params[:memo][:payload]).to eq("[1]")
    end
  end

  describe "has_many rows" do
    it "matches rows of existing records and new rows by shape" do
      result = normalize(notes_attributes: {"0" => {body: nil, meta: {a: 1}}, "7" => {body: nil}})

      expect(result["notes_attributes"]).to eq("0" => {"body" => "", "meta" => '{"a":1}'}, "7" => {"body" => ""})
    end
  end
end
