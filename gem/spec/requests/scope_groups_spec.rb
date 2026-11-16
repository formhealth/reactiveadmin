RSpec.describe "scope groups", type: :request do
  include_context "with a blog"

  let(:index_meta) { json["meta"] }

  before do
    ["Free Monthly", "Free Annual", "Pro Monthly", "Pro Annual", "Enterprise Annual", "Retired Monthly", "Internal Monthly"].each { Plan.create!(name: it) }
    ["Trial A", "Paid A", "Paid B"].each { Offer.create!(name: it) }
  end

  def list(resource, params = nil) = api_get("/api/admin/#{resource}", params, schema: "IndexResponse")

  def meta_of(resource) = api_get("/api/admin/#{resource}/_meta", schema: "ResourceMeta")

  def ids(scopes) = scopes.pluck("id")

  context "as an admin" do
    before { sign_in admin }

    it "keeps each group together, in order of first appearance, when groups interleave" do
      scopes = meta_of("plans")["scopes"]

      expect(ids(scopes)).to eq(%w[free pro enterprise retired monthly annual internal])
      expect(scopes.to_h { [it["id"], it["group"]] }).to include("free" => "tier", "enterprise" => "tier", "retired" => nil, "annual" => "billing")
      expect(scopes.find { it["id"] == "retired" }).not_to have_key("group")
    end

    it "makes the default scope inside a group the current one and filters by it" do
      expect(meta_of("plans")["default_scope"]).to eq("free")

      list("plans")

      expect(index_meta["current_scope"]).to eq("free")
      expect(json["rows"].size).to eq(2)
    end

    it "counts per scope, leaving out the count where show_count is false" do
      list("plans")

      counts = index_meta["scopes"].to_h { [it["id"], it["count"]] }
      expect(counts).to eq("free" => 2, "pro" => 2, "enterprise" => 1, "retired" => 1, "monthly" => 4, "annual" => nil, "internal" => 1)
      expect(ids(index_meta["scopes"])).to eq(%w[free pro enterprise retired monthly annual internal])
    end

    it "selects a scope from another group" do
      list("plans", scope: "monthly")

      expect(index_meta["current_scope"]).to eq("monthly")
      expect(json["rows"].size).to eq(4)
    end

    it "omits every count with scope_count: false, groups intact" do
      list("offers")

      expect(index_meta["scopes"]).to eq([
        {"id" => "all", "name" => "All", "count" => nil},
        {"id" => "trial", "name" => "Trial", "count" => nil, "group" => "kind"},
        {"id" => "paid", "name" => "Paid", "count" => nil, "group" => "kind"}
      ])
    end
  end

  context "as an editor" do
    before { sign_in editor }

    it "drops a grouped scope whose `if:` is false and keeps the rest in order" do
      expect(ids(meta_of("plans")["scopes"])).to eq(%w[free pro enterprise retired monthly annual])

      list("plans")

      expect(ids(index_meta["scopes"])).to eq(%w[free pro enterprise retired monthly annual])
    end
  end
end
