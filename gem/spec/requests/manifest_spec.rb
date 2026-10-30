RSpec.describe "manifest", type: :request do
  include_context "with a blog"

  let(:manifest) { api_get("/api/admin/_manifest", schema: "Manifest") }
  let(:resources) { by_key(manifest["resources"]) }

  def menu_ids(items) = items.flat_map { [it["id"], *menu_ids(it["children"])] }

  def menu_item(items, id) = items.lazy.filter_map { |item| (item["id"] == id) ? item : menu_item(item["children"], id) }.first

  context "when signed in as an admin" do
    before { sign_in admin }

    it "lists the hosts image and document nodes may load from" do
      ReactiveAdmin.config.html_trusted_hosts = -> { ["cdn.test"] }

      expect(manifest["site"]["trusted_media_hosts"]).to eq(["cdn.test"])
    ensure
      ReactiveAdmin.config.html_trusted_hosts = []
    end

    it "reports the namespace settings and the current user" do
      expect(manifest["schema_version"]).to be_a(Integer)
      expect(manifest["site"]).to include(
        "title" => "Dummy Admin", "comments" => false, "default_per_page" => 10, "locale" => "en",
        "current_user" => {"id" => admin.id.to_s, "display_name" => "Ada Admin"},
        "logout" => {"url" => "/logout", "method" => "delete"}
      )
      expect(manifest["site"]["home"]).to include("url" => "/admin")
    end

    it "evaluates AA's date formats for the locale" do
      expect(manifest["site"]).to include("date_format" => "%B %d, %Y", "datetime_format" => "%B %d, %Y %H:%M")
    end

    it "includes the utility menu with the logout item" do
      logout = menu_item(manifest["site"]["utility_menu"], "logout")

      expect(logout).to include("label" => "Logout", "url" => "/logout", "method" => "delete")
    end

    it "builds the menu tree from AA's parents and priorities" do
      menu = manifest["menu"]
      content = menu_item(menu, "content")

      expect(menu_ids(menu)).to include("dashboard", "categories", "content", "posts", "tags", "people", "authors", "docs")
      expect(content["children"].pluck("id")).to eq(%w[posts tags people])
      expect(menu_item(content["children"], "people")["children"].pluck("id")).to eq(%w[authors])
      expect(menu.pluck("priority")).to eq(menu.pluck("priority").sort)
    end

    it "marks menu items as resources, pages and plain links" do
      menu = manifest["menu"]

      expect(menu_item(menu, "posts")).to include("resource" => "posts")
      expect(menu_item(menu, "docs")).to include("url" => "https://example.com/docs")
      expect(menu_item(menu, "dashboard")).to include("page" => "dashboard")
    end

    it "summarises resources with their actions and permissions" do
      posts = resources.fetch("posts")

      expect(posts).to include("label" => "Post", "plural_label" => "Posts", "menu_parent" => "Content", "meta_path" => "/api/admin/posts/_meta")
      expect(posts["actions"]).to include("index", "show", "new", "create", "edit", "update", "destroy")
      expect(posts["permissions"]).to include("index" => true, "show" => true, "create" => true, "update" => true,
        "destroy" => can_destroy_post?(admin))
    end

    it "describes a nested resource by its parent" do
      comments = resources.fetch("comments")

      expect(comments["belongs_to"]).to eq("parent" => "posts", "param" => "post_id", "optional" => false)
      expect(comments["api_index_path_template"]).to eq("/api/admin/posts/{parent_id}/comments")
    end

    it "offers new and create at the top level unless the resource's new needs its parent" do
      memos = ReactiveAdmin::Registry.find("memos")
      expect(resources.fetch("memos")).to include("actions" => include("new", "create"), "permissions" => include("create" => true))

      memos.reactive_options[:new_needs_parent] = true
      hidden = by_key(api_get("/api/admin/_manifest", schema: "Manifest")["resources"]).fetch("memos")

      expect(hidden["actions"]).to include("index", "show", "edit", "update")
      expect(hidden["actions"] & %w[new create]).to be_empty
      expect(hidden["permissions"]).to include("update" => true)
      expect(hidden["permissions"]).not_to have_key("create")
    ensure
      ReactiveAdmin::Registry.find("memos").reactive_options.delete(:new_needs_parent)
    end

    it "keeps nested-only resources out of the menu" do
      expect(menu_ids(manifest["menu"])).not_to include("comments")
    end

    it "leaves the per-resource details to _meta" do
      expect(resources.fetch("posts")).not_to include("filters", "scopes", "batch_actions")
    end

    it "keeps AA's disabled comment registration out of the menu" do
      expect(menu_ids(manifest["menu"])).not_to include("admin_comments")
    end

    it "gives a parent-array menu item a sensible menu_parent" do
      expect(resources.fetch("authors")["menu_parent"]).to eq("People")
    end
  end

  context "when signed in as an editor" do
    before { sign_in editor }

    it "reports who is signed in" do
      expect(manifest["site"]["current_user"]).to include("id" => editor.id.to_s, "display_name" => "Ed Editor")
    end

    it "applies the adapter to resource permissions" do
      expect(resources.fetch("posts")["permissions"]).to include("destroy" => can_destroy_post?(editor))
    end

    it "omits resources the adapter denies from resources and menu" do
      expect(resources.key?("categories")).to eq(can_read_categories?(editor))
      expect(menu_ids(manifest["menu"]).include?("categories")).to eq(can_read_categories?(editor))
    end
  end

  context "when signed out" do
    it "is a 401" do
      api_get("/api/admin/_manifest")

      expect(response).to have_http_status(:unauthorized)
      expect(json).to include("code" => "unauthorized", "message" => "Authentication required")
    end
  end
end
