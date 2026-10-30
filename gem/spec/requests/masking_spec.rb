require "csv"

RSpec.describe "sensitive attribute masking", type: :request do
  include_context "with a blog"

  before do
    news.update!(api_token: "tok-secret-123")
    sign_in admin
  end

  def values = response.body

  it "masks attribute-keyed index cells and keeps the value out of the response", :all_defaults do
    api_get("/api/admin/categories", schema: "IndexResponse")

    row = row_for(json["rows"], news)
    expect(row["cells"]["api_token"]).to eq("type" => "masked")
    expect(row["cells"]["name"]).to include("type" => "text")
    expect(values).not_to include("tok-secret-123")
  end

  it "shows an unset secret as empty", :all_defaults do
    Category.create!(name: "plain")
    api_get("/api/admin/categories")

    row = json["rows"].find { it["cells"]["name"]["text"] == "plain" }
    expect(row["cells"]["api_token"]).to eq("type" => "empty")
  end

  it "masks attribute rows of the default show page", :all_defaults do
    api_get("/api/admin/categories/#{news.id}", schema: "ShowResponse")

    rows = nodes_of(json["layout"], "attributes_table").flat_map { it["rows"] }
    expect(rows.find { it["label"] == "Api Token" }["value"]).to eq([{"type" => "masked"}])
    expect(values).not_to include("tok-secret-123")
  end

  it "withholds the value of a masked form field and marks it" do
    api_get("/api/admin/categories/#{news.id}/edit", schema: "FormResponse")

    field = fields_of(json["form"])["api_token"]
    expect(field).to include("masked" => true, "param" => "category[api_token]")
    expect(field).not_to have_key("value")
    expect(values).not_to include("tok-secret-123")
  end

  it "keeps the stored secret when the field is submitted blank" do
    api(:patch, "/api/admin/categories/#{news.id}", {category: {name: "Headlines", api_token: ""}, lock: lock_of(news)}, headers: {"X-CSRF-Token" => csrf_token})

    expect(response).to have_http_status(:ok)
    expect(news.reload).to have_attributes(name: "Headlines", api_token: "tok-secret-123")
  end

  it "writes a blank over a blank, as the classic form does" do
    news.update!(api_token: nil)
    api(:patch, "/api/admin/categories/#{news.id}", {category: {api_token: ""}, lock: lock_of(news)}, headers: {"X-CSRF-Token" => csrf_token})

    expect(news.reload.api_token).to eq("")
  end

  it "replaces the secret when a value is submitted" do
    api(:patch, "/api/admin/categories/#{news.id}", {category: {api_token: "new-token"}, lock: lock_of(news)}, headers: {"X-CSRF-Token" => csrf_token})

    expect(news.reload.api_token).to eq("new-token")
  end

  context "on a new record" do
    it "treats a masked field as an ordinary input" do
      api_get("/api/admin/categories/new", schema: "FormResponse")

      expect(fields_of(json["form"])["api_token"]).to include("param" => "category[api_token]").and(satisfy { !it.key?("masked") })
    end

    it "writes the submitted value" do
      api(:post, "/api/admin/categories", {category: {name: "Fresh", api_token: "first-token"}}, headers: {"X-CSRF-Token" => csrf_token})

      expect(response).to have_http_status(:created)
      expect(Category.find_by!(name: "Fresh").api_token).to eq("first-token")
    end

    it "writes a blank one as blank, as the classic form does" do
      api(:post, "/api/admin/categories", {category: {name: "Blank", api_token: ""}}, headers: {"X-CSRF-Token" => csrf_token})

      expect(Category.find_by!(name: "Blank").api_token).to eq("")
    end
  end

  describe "CSV" do
    it "masks the same attributes by default" do
      api_get("/api/admin/categories.csv")

      expect(response.body).not_to include("tok-secret-123")
      expect(CSV.parse(response.body.delete_prefix("﻿"), headers: true)["Api token"]).to include("[MASKED]")
    end

    it "exports the raw values when mask_csv is turned off" do
      old = ReactiveAdmin.config.mask_csv
      ReactiveAdmin.config.mask_csv = false
      api_get("/api/admin/categories.csv")

      expect(response.body).to include("tok-secret-123")
    ensure
      ReactiveAdmin.config.mask_csv = old
    end
  end

  it "leaves the classic admin alone" do
    get "/admin/categories/#{news.id}", headers: {"ACCEPT" => "text/html"}

    expect(response.body).to include("tok-secret-123")
  end
end
