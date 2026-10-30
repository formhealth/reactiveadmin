RSpec.describe "show", type: :request do
  include_context "with a blog"

  let(:layout) { json["layout"] }
  let(:actions) { by_key(json["actions"]) }

  def show(record, resource: "posts") = api_get("/api/admin/#{resource}/#{record.id}", schema: "ShowResponse")

  context "when signed in as an admin" do
    before { sign_in admin }

    describe "header" do
      before { show(first_post) }

      it "identifies the record" do
        expect(json).to include("resource" => "posts", "id" => first_post.id.to_s, "title" => "Hello world", "display_name" => "Hello world")
        expect(json["paths"]).to include("show" => "/admin/posts/#{first_post.id}", "api_show" => "/api/admin/posts/#{first_post.id}")
      end

      it "reports record permissions" do
        expect(json["permissions"]).to eq("show" => true, "update" => true, "destroy" => can_destroy_post?(admin))
      end

      it "derives edit and destroy actions from the resource" do
        expect(actions["edit"]).to include("kind" => "edit", "method" => "get", "placement" => "header", "enabled" => true,
          "api_path" => "/api/admin/posts/#{first_post.id}/edit")
        expect(actions["destroy"]).to include("kind" => "destroy", "method" => "delete", "enabled" => can_destroy_post?(admin),
          "api_path" => "/api/admin/posts/#{first_post.id}", "confirm" => a_string_including("delete"))
      end

      it "explains a destroy the adapter disallows" do
        skip "adapter allows destroy" if can_destroy_post?(admin)

        expect(actions["destroy"]["disabled_reason"]).to include("permission")
      end

      it "renders action items as header actions, with confirm and verb" do
        expect(actions["archive"]).to include("kind" => "member", "method" => "post", "placement" => "header", "confirm" => "Archive this post?",
          "api_path" => "/api/admin/posts/#{first_post.id}/archive", "enabled" => true)
      end

      it "omits action items whose `if:` is false" do
        expect(actions).not_to have_key("publish")
      end
    end

    it "shows an `if:` action item once its condition holds" do
      show(second_post)

      expect(actions["publish"]).to include("method" => "put", "kind" => "member", "label" => "Publish")
    end

    describe "layout" do
      before { show(first_post) }

      it "walks tabs into typed nodes" do
        tabs = layout.first

        expect(tabs["type"]).to eq("tabs")
        expect(tabs["children"].pluck("type", "title")).to eq([%w[tab Details], %w[tab Comments]])
      end

      it "walks attributes tables into labelled rows of nodes" do
        table = nodes_of(layout, "attributes_table").first
        rows = table["rows"].to_h { [it["label"], it["value"]] }

        expect(rows["Title"]).to eq([{"type" => "text", "text" => "Hello world"}])
        expect(rows["Status"].first).to include("type" => "status", "label" => "Published")
        expect(rows["Author"].first).to include("type" => "link", "label" => "Alice Author", "ref" => {"resource" => "authors", "id" => alice.id.to_s})
        expect(rows["Featured"].first).to include("type" => "status", "variant" => "success")
      end

      it "walks table_for into headers and rows" do
        table = nodes_of(layout, "table").first

        expect(table).to include("headers" => %w[Body Approved], "rows" => [])
      end

      it "fills table_for rows with typed cells" do
        Comment.create!(post: first_post, body: "Nice", approved: true)
        show(first_post)

        table = nodes_of(layout, "table").first
        expect(table["rows"].size).to eq(1)
        expect(table["rows"].first.first).to include("type" => "text", "text" => "Nice")
      end

      it "walks columns and panels" do
        columns = layout.find { it["type"] == "columns" }

        expect(columns["children"].pluck("type")).to eq(%w[column column])
        panels = nodes_of(columns, "panel")
        expect(panels.pluck("title")).to eq(%w[Info Tags])
        expect(panels.first["children"]).to eq([{"type" => "text", "text" => "Views: 1200"}])
      end

      it "turns ul/li markup into list nodes" do
        list = nodes_of(layout, "list").first

        expect(list).to include("ordered" => false)
        expect(list["children"].first).to eq("type" => "list_item", "children" => [{"type" => "text", "text" => "ruby"}])
      end

      it "turns button_to forms into inline action nodes" do
        action = nodes_of(layout, "action").first["action"]

        expect(action).to include("key" => "flag", "kind" => "member", "method" => "post", "placement" => "inline", "label" => "Flag",
          "api_path" => "/api/admin/posts/#{first_post.id}/flag", "enabled" => true)
      end
    end

    it "falls back to the resource's columns without a show block" do
      show(news, resource: "categories")

      table = nodes_of(layout, "attributes_table").first
      expect(table["rows"].pluck("label")).to include("Name")
    end

    it "shows a block that renders no panel" do
      show(alice, resource: "authors")

      expect(nodes_of(layout, "attributes_table").first["rows"].pluck("label")).to eq(["Name", "Email", "Rating", "Born On"])
    end

    it "gives ref values a path when the target is nested-only" do
      comment = Comment.create!(post: first_post, body: "Hi")
      api_get("/api/admin/posts/#{first_post.id}/comments/#{comment.id}", schema: "ShowResponse")

      expect(json).to include("resource" => "comments", "id" => comment.id.to_s)
      expect(json["paths"]).to include("show" => "/admin/posts/#{first_post.id}/comments/#{comment.id}")
    end

    it "is a 404 for a missing record" do
      api_get("/api/admin/posts/0")

      expect(response).to have_http_status(:not_found)
      expect(json).to include("code" => "not_found")
    end
  end

  context "when signed in as an editor" do
    before { sign_in editor }

    it "applies the adapter's record permissions" do
      show(first_post)

      expect(json["permissions"]["destroy"]).to eq(can_destroy_post?(editor))
    end

    it "refuses another author's post under adapters that scope" do
      api_get("/api/admin/posts/#{second_post.id}")

      expect(response).to have_http_status(can_see_post?(editor, second_post) ? :ok : :forbidden)
      expect(json).to include("code" => "forbidden") unless can_see_post?(editor, second_post)
    end
  end

  context "when signed out" do
    it "is a 401" do
      api_get("/api/admin/posts/#{first_post.id}")

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
