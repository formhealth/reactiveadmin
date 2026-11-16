RSpec.describe "decorate_with", type: :request do
  include_context "with a blog"

  let!(:label) { Tag.create!(name: "elixir") }

  before { sign_in admin }

  it "decorates index rows, so a column block can call decorator methods" do
    api_get("/api/admin/labels", schema: "IndexResponse")

    expect(row_for(json["rows"], label)["cells"]["shout"]).to eq("type" => "text", "text" => "ELIXIR!")
  end

  it "keeps filtering and paging working over the decorated collection" do
    Tag.create!(name: "go")
    api_get("/api/admin/labels", {q: {name_cont: "elix"}}, schema: "IndexResponse")
    expect(json["rows"].pluck("id")).to eq([label.id.to_s])

    11.times { Tag.create!(name: "tag#{it}") }
    api_get("/api/admin/labels", {page: 2}, schema: "IndexResponse")
    expect(json["meta"]).to include("page" => 2, "total_count" => Tag.count)
    expect(json["rows"].size).to eq(Tag.count - 10)
  end

  it "decorates the shown record" do
    api_get("/api/admin/labels/#{label.id}", schema: "ShowResponse")

    rows = nodes_of(json["layout"], "attributes_table").first["rows"].to_h { [it["label"], it["value"]] }
    expect(rows["Shout"]).to eq([{"type" => "text", "text" => "ELIXIR!"}])
  end

  it "edits and updates the record" do
    api_get("/api/admin/labels/#{label.id}/edit", schema: "FormResponse")
    expect(fields_of(json["form"])["name"]["value"]).to eq("elixir")

    api(:put, "/api/admin/labels/#{label.id}", {tag: {name: "rails"}, lock: lock_of(label)})
    expect(response).to have_http_status(:ok)
    expect(label.reload.name).to eq("rails")
  end

  it "exports to CSV" do
    get "/api/admin/labels.csv"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("elixir")
  end
end
