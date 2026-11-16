RSpec.describe "register_page content and actions", type: :request do
  include_context "with a blog"

  before { sign_in admin }

  it "serves a script in the content as an iframe of the chrome-free classic page" do
    api_get("/api/admin/_pages/chart_embed", schema: "PageResponse")

    expect(json["layout"].size).to eq 1
    expect(json["layout"].first).to include("type" => "iframe", "title" => "Chart Embed")
    expect(json["view"]).to include("mode" => "iframe")
  end

  describe "page actions" do
    before { api_get("/api/admin/_pages/export_hub", schema: "PageResponse") }

    it "lists a GET page_action with the view that renders it" do
      expect(by_key(json["actions"])["summary"]).to include(
        "label" => "Summary", "method" => "get", "kind" => "custom", "placement" => "header", "enabled" => true,
        "api_path" => "/api/admin/export_hub/summary", "view" => hash_including("mode" => "native")
      )
    end

    it "leaves a writing page_action to the form or button that posts to it" do
      expect(by_key(json["actions"])).not_to have_key("rebuild")
    end

    it "honors an action_item's if:" do
      expect(by_key(json["actions"])).to have_key("staff_only")
      expect(by_key(json["actions"])).not_to have_key("hidden")
    end
  end

  it "runs a writing page_action" do
    api(:post, "/api/admin/export_hub/rebuild", schema: "ActionResult")

    expect(json).to include("ok" => true, "message" => "Rebuilt")
  end

  it "renders a GET page_action's template" do
    api_get("/api/admin/export_hub/summary")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Export summary")
  end
end
