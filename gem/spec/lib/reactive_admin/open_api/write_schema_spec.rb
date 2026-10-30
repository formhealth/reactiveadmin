RSpec.describe ReactiveAdmin::OpenApi::WriteSchema do
  let(:config) { ReactiveAdmin::Registry.find("categories") }

  def field(name, param, control, **extra) = {name:, param:, control:, **extra}

  def build(*sections, reserved: []) = described_class.new(config, sections, options_path: "/api/admin/categories/_options", reserved:)

  def inputs(*fields) = {kind: "inputs", fields:}

  def properties_of(schema, key = "c") = schema.dig(:properties, key, :properties)

  it "nests each control under the path its param names" do
    schema = build(inputs(field("name", "category[name]", "text"), field("sort", "category[meta][sort]", "number"))).schema

    expect(schema).to eq(
      type: "object", additionalProperties: false,
      properties: {"category" => {type: "object", additionalProperties: false, properties: {
        "name" => {type: "string"},
        "meta" => {type: "object", additionalProperties: false, properties: {"sort" => {type: "number"}}}
      }}}
    )
  end

  it "types controls by what they send" do
    fields = [
      field("on", "c[on]", "boolean"), field("day", "c[day]", "date"), field("at", "c[at]", "datetime"), field("mail", "c[mail]", "email"),
      field("tags", "c[tags][]", "checkboxes"), field("kind", "c[kind]", "select"), field("doc", "c[doc]", "json"), field("pdf", "c[pdf]", "file")
    ]
    props = properties_of(build(inputs(*fields)).schema)

    expect(props["on"]).to eq(type: "boolean")
    expect(props["day"]).to eq(type: "string", format: "date")
    expect(props["at"]).to eq(type: "string", format: "date-time")
    expect(props["mail"]).to include(format: "email")
    expect(props["tags"]).to include(type: "array", items: {type: "string"})
    expect(props["kind"]).to include(type: "string", description: a_string_including("/api/admin/categories/_options?context=form&field=kind"))
    expect(props["doc"]).not_to have_key(:type)
    expect(props["pdf"]).to include(format: "binary")
  end

  it "makes a multiple typeahead an array" do
    props = properties_of(build(inputs(field("ids", "c[ids][]", "typeahead"))).schema)

    expect(props["ids"]).to include(type: "array", items: a_hash_including(type: "string"))
  end

  it "leaves out disabled, masked, html and param-less controls" do
    fields = [
      field("locked", "category[locked]", "text", disabled: true), field("api_token", "category[api_token]", "text"),
      field("note", nil, "html"), field("name", "category[name]", "text")
    ]

    expect(properties_of(build(inputs(*fields)).schema, "category").keys).to eq(%w[name])
  end

  it "describes has_many rows by index, with their id and _destroy" do
    rows = {kind: "has_many", param: "category[items_attributes]", allow_destroy: true,
            template_fields: [field("title", "category[items_attributes][__INDEX__][title]", "text")]}
    items = properties_of(build(rows).schema, "category")["items_attributes"]

    expect(items[:type]).to eq("object")
    expect(items[:additionalProperties][:properties].keys).to eq(%w[title id _destroy])
  end

  context "with attributes the API refuses" do
    let(:reserved) { %w[role items items_attributes] }

    it "leaves them out at any depth" do
      fields = [field("role", "category[role]", "text"), field("deep", "category[meta][role]", "text"), field("name", "category[name]", "text")]

      expect(properties_of(build(inputs(*fields), reserved:).schema, "category").keys).to eq(%w[name])
    end

    it "leaves out a reserved has_many, rows and all" do
      rows = {kind: "has_many", param: "category[items_attributes]", allow_destroy: true,
              template_fields: [field("title", "category[items_attributes][__INDEX__][title]", "text")]}
      schema = build(rows, inputs(field("name", "category[name]", "text")), reserved:).schema

      expect(properties_of(schema, "category").keys).to eq(%w[name])
    end
  end

  it "has no schema without a writable control, and names its top-level keys" do
    expect(build(inputs).schema).to be_nil
    expect(build(inputs(field("name", "category[name]", "text"))).keys).to eq(%w[category])
  end
end
