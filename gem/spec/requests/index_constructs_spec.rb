RSpec.describe "index constructs", type: :request do
  include_context "with a blog"

  let!(:gold) { Plan.create!(name: "Gold", notes: "best") }
  let!(:basic) { Plan.create!(name: "Basic", notes: "") }
  let!(:platinum) { Plan.create!(name: "Platinum", notes: "better") }

  def meta(**params) = api_get("/api/admin/construct_plans/_meta", params, schema: "ResourceMeta")

  def list(params = nil) = api_get("/api/admin/construct_plans", params, schema: "IndexResponse")

  def names = json["rows"].map { it["cells"]["name"]["text"] }

  describe "sortable columns" do
    before { sign_in admin }

    it "sorts a block column by the database column in its symbol, both ways" do
      list(order: "notes_asc")
      expect(by_key(json["columns"])["notes"]).to include("sortable" => true, "sort_key" => "notes")
      expect(names).to eq(%w[Basic Gold Platinum])

      list(order: "notes_desc")
      expect(names).to eq(%w[Platinum Gold Basic])
    end

    it "sorts by a custom sort_key declared with order_by" do
      list(order: "name_length_asc")
      expect(by_key(json["columns"])["name_length"]).to include("sortable" => true, "sort_key" => "name_length")
      expect(names.first).to eq("Gold")

      list(order: "name_length_desc")
      expect(names.first).to eq("Platinum")
    end
  end

  describe "row items" do
    it "renders the `item`s of `actions do |r|` per record, honoring conditions in the block" do
      sign_in admin
      list
      rows = json["rows"].index_by { it["cells"]["name"]["text"] }

      expect(rows["Gold"]["actions"].pluck("label")).to eq(["Rename", "Gold only"])
      expect(rows["Basic"]["actions"].pluck("label")).to eq(["Rename"])
      expect(rows["Basic"]["actions"].first).to include("placement" => "row", "method" => "get")
    end
  end

  describe "scope if:" do
    it "offers the scope its `if:` allows" do
      sign_in admin

      expect(meta["scopes"].pluck("id")).to eq(%w[all with_notes])
      list(scope: "with_notes")
      expect(json["meta"]["scopes"].pluck("id")).to eq(%w[all with_notes])
      expect(names).to match_array(%w[Gold Platinum])
    end

    it "hides the scope from a user its `if:` refuses" do
      sign_in editor

      expect(meta["scopes"].pluck("id")).to eq(%w[all])
    end

    it "hides the posts' featured scope from editors" do
      sign_in editor

      expect(api_get("/api/admin/posts/_meta")["scopes"].pluck("id")).not_to include("featured")
    end
  end

  describe "filter if: and unless:" do
    it "offers each filter only when its condition holds for the request" do
      sign_in admin
      expect(meta["filters"].pluck("name")).to eq(%w[name notes updated_at])

      sign_in editor
      expect(meta["filters"].pluck("name")).to eq(%w[name notes id])
    end
  end

  describe "filter options that depend on other values" do
    before { sign_in admin }

    it "evaluates the collection with the request's view context" do
      expect(by_key(meta["filters"], "name")["name"]["options"].pluck("value")).to match_array(%w[Basic Gold Platinum])
      expect(by_key(meta(q: {notes_cont: "bett"})["filters"], "name")["name"]["options"].pluck("value")).to eq(%w[Platinum])
    end

    it "serves the same dependent options from _options" do
      api_get("/api/admin/construct_plans/_options", context: "filter", field: "name", q: {notes_cont: "bes"})

      expect(json["options"].pluck("value")).to eq(%w[Gold])
    end
  end
end
