RSpec.describe "register_page", type: :request do
  include_context "with a blog"

  context "when signed in" do
    before { sign_in admin }

    it "walks the page's content into nodes" do
      api_get("/api/admin/_pages/dashboard", schema: "PageResponse")

      expect(json).to include("key" => "dashboard", "title" => "Dashboard")
      panel = json["layout"].first
      expect(panel).to include("type" => "panel", "title" => "Stats")
      expect(panel["children"]).to eq([{"type" => "text", "text" => "Posts: 3"}])
    end

    it "lists the page's action items as header actions" do
      api_get("/api/admin/_pages/dashboard", schema: "PageResponse")

      recalc = by_key(json["actions"])["recalc"]
      expect(recalc).to include("label" => "Recalculate", "method" => "post", "placement" => "header")
      expect(recalc).to include("kind" => "custom", "enabled" => true, "api_path" => "/api/admin/dashboard/recalc")
    end

    it "marks links to this host's non-admin paths external, with absolute hrefs" do
      api_get("/api/admin/_pages/ops_links", schema: "PageResponse")

      links = json["layout"].flat_map { it["children"] }
      expect(links.pluck("href", "external")).to eq([["http://www.example.com/sidekiq/retries?substr=Foo", true], ["/admin/posts", false]])
      expect(by_key(json["actions"])["sidekiq"]).to include("href" => "http://www.example.com/sidekiq", "external" => true, "kind" => "link")
    end

    it "serves the page at AA's own path under the mount too" do
      api_get("/api/admin/dashboard", schema: "PageResponse")

      expect(json["key"]).to eq("dashboard")
    end

    it "runs a page_action and reports its flash and redirect" do
      api(:post, "/api/admin/dashboard/recalc", schema: "ActionResult")

      expect(response).to have_http_status(:ok)
      expect(json).to include("ok" => true, "message" => "Recalculated")
      expect(json["location"]).to include("url" => "/admin/dashboard")
    end
  end

  context "when signed out" do
    it "is a 401 for the page and its actions" do
      api_get("/api/admin/_pages/dashboard")
      expect(response).to have_http_status(:unauthorized)

      api(:post, "/api/admin/dashboard/recalc")
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
