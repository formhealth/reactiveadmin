RSpec.describe "action items and link/button verbs", type: :request do
  include_context "with a blog"

  let!(:badge) { Tag.create!(name: "gold") }
  let(:items) { by_key(api_get("/api/admin/badges/_meta", schema: "ResourceMeta")["action_items"]) }

  before { sign_in admin }

  describe "on the index" do
    it "honors only:, except: and if:" do
      expect(items.keys).to include("index_only", "purge")
      expect(items.keys).not_to include("except_index", "seed")
    end

    it "gates on if: once the condition holds" do
      Tag.destroy_all

      expect(items.keys).to include("seed")
      expect(items.keys).not_to include("purge")
    end

    it "keeps the verb and confirmation of a link_to with `method:` and `data: {confirm:}`" do
      expect(items["purge"]).to include("kind" => "collection", "method" => "delete", "placement" => "header",
        "confirm" => "Purge every badge?", "api_path" => "/api/admin/badges/purge")
    end

    it "runs the collection action" do
      api(:delete, "/api/admin/badges/purge", schema: "ActionResult")

      expect(json).to include("message" => "Purged")
    end
  end

  describe "on the show page" do
    let(:actions) { by_key(api_get("/api/admin/badges/#{badge.id}", schema: "ShowResponse")["actions"]) }

    it "honors except: and only:" do
      expect(actions.keys).to include("except_index", "retire")
      expect(actions.keys).not_to include("index_only", "purge")
    end

    it "reads the verb and confirmation from a link_to's `data-method` and `data-confirm`" do
      expect(actions["retire"]).to include("kind" => "member", "method" => "delete", "placement" => "header", "confirm" => "Retire this badge?",
        "api_path" => "/api/admin/badges/#{badge.id}/retire")
    end

    it "keeps the confirmation of a button_to in the layout" do
      api_get("/api/admin/badges/#{badge.id}", schema: "ShowResponse")

      expect(nodes_of(json["layout"], "action").first["action"]).to include("key" => "pin", "method" => "post", "placement" => "inline",
        "confirm" => "Pin this badge?")
    end

    it "runs the member action the link points at" do
      api(:delete, "/api/admin/badges/#{badge.id}/retire", schema: "ActionResult")

      expect(json).to include("message" => "Retired")
    end
  end
end
