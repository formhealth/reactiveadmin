RSpec.describe "composite primary keys", type: :request do
  let!(:level) { StockLevel.create!(warehouse: "east", sku: "A/1", quantity: 4, details: {"bin" => "x"}) }
  let(:id) { level.to_param }

  before { sign_in create_admin }

  it "keys the record by its joined parameter" do
    expect(id).to eq "east_A/1"
  end

  describe "index" do
    before { api_get("/api/admin/stock_levels", schema: "IndexResponse") }

    let(:row) { json["rows"].first }

    it "lists the row with an escaped member path and no failing cells" do
      expect(row).to include("id" => id)
      expect(row["paths"]).to include("show" => "/admin/stock_levels/east_A%2F1", "api_show" => "/api/admin/stock_levels/east_A%2F1")
      expect(row["cells"].values.pluck("type")).not_to include("error")
      expect(json["degraded"].to_a).to be_empty
    end

    it "renders the key column as a ref to the record" do
      expect(row["cells"].values.first).to include("type" => "ref", "label" => id, "ref" => a_hash_including("resource" => "stock_levels", "id" => id))
    end

    it "points json values at the escaped member path" do
      expect(row["cells"]["details"]["expand_path"]).to start_with("/api/admin/stock_levels/east_A%2F1/_value?")
    end
  end

  describe "show" do
    it "finds the record by its joined parameter" do
      api_get("/api/admin/stock_levels/#{CGI.escape(id)}", schema: "ShowResponse")

      expect(json).to include("id" => id)
    end

    it "serves the audited json value" do
      api_get("/api/admin/stock_levels", schema: "IndexResponse")
      api_get(json["rows"].first["cells"]["details"]["expand_path"])

      expect(json).to eq("value" => {"bin" => "x"})
    end

    it "edits and updates through the joined parameter" do
      api_get("/api/admin/stock_levels/#{CGI.escape(id)}/edit", schema: "FormResponse")
      expect(json).to include("id" => id)

      api(:put, "/api/admin/stock_levels/#{CGI.escape(id)}", {stock_level: {quantity: 9}, lock: json["lock"]})

      expect(response).to have_http_status(:ok)
      expect(level.reload.quantity).to eq 9
    end

    it "is a 404 for an unknown key" do
      api_get("/api/admin/stock_levels/west_B")

      expect(response).to have_http_status(:not_found)
    end
  end
end
