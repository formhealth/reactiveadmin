RSpec.describe "resource _meta", type: :request do
  include_context "with a blog"

  let(:meta) { api_get("/api/admin/posts/_meta", schema: "ResourceMeta") }
  let(:filters) { by_key(meta["filters"], "name") }

  context "when signed in as an admin" do
    before { sign_in admin }

    it "is valid for every resource the manifest lists" do
      keys = api_get("/api/admin/_manifest")["resources"].pluck("key")

      keys.each do |key|
        api_get("/api/admin/#{key}/_meta", schema: "ResourceMeta")
        expect(response).to have_http_status(:ok), "#{key}: #{response.status}"
      end
    end

    it "carries the summary fields too" do
      expect(meta).to include("key" => "posts", "label" => "Post", "meta_path" => "/api/admin/posts/_meta",
        "default_per_page" => 10, "per_page_options" => [10], "default_order" => "id_desc", "pagination_total" => true)
    end

    describe "filters" do
      it "turns string filters into text with predicates" do
        expect(filters["title"]).to include("control" => "text")
        expect(filters["title"]["predicates"].pluck("param")).to eq(%w[title_cont title_eq title_start title_end])
      end

      it "turns numeric filters into number with predicates" do
        expect(filters["views_count"]).to include("control" => "number")
        expect(filters["views_count"]["predicates"].pluck("param")).to eq(%w[views_count_eq views_count_gt views_count_lt])
      end

      it "turns date_range filters into a from/to pair" do
        expect(filters["published_at"]).to include("control" => "date_range", "range" => {"from" => "published_at_gteq", "to" => "published_at_lteq"})
      end

      it "inlines small select collections" do
        expect(filters["status"]).to include("control" => "select", "param" => "status_eq")
        expect(filters["status"]["options"]).to eq([{"label" => "draft", "value" => "0"}, {"label" => "published", "value" => "1"}, {"label" => "archived", "value" => "2"}])
      end

      it "turns boolean filters into yes/no options" do
        expect(filters["featured"]).to include("control" => "boolean", "param" => "featured_eq")
        expect(filters["featured"]["options"].pluck("value")).to eq(%w[true false])
      end

      it "searches relation-backed filters (check_boxes, associations) through _options" do
        expect(filters["category"]).to include("control" => "typeahead", "multiple" => true, "param" => "category_id_in")
        expect(filters["category"]["options_path"]).to eq("/api/admin/posts/_options?context=filter&field=category")
        expect(filters["tags"]).to include("control" => "typeahead", "param" => "tags_id_eq")
      end

      it "turns `as: :typeahead, source:` into a typeahead without inlined options" do
        expect(filters["author_id_eq"]).to include("label" => "Author", "control" => "typeahead", "param" => "author_id_eq", "options" => [])
        expect(filters["author_id_eq"]["options_path"]).to include("field=author_id_eq", "context=filter")
      end

      it "keeps filters in their declared order" do
        expect(meta["filters"].pluck("name")).to eq(%w[title views_count published_at status featured category author_id_eq tags])
      end

      it "does not let one request's selected filter values leak into the cached payload" do
        api_get("/api/admin/posts/_meta", {q: {author_id_eq: bob.id}})

        expect(filters["author_id_eq"]["options"]).to eq([])
      end
    end

    describe "scopes" do
      it "lists the AA scopes with their defaults" do
        expect(meta["scopes"].pluck("id")).to eq(%w[all featured draft published archived])
        expect(meta["scopes"].pluck("name")).to eq(%w[All Featured Draft Published Archived])
        expect(meta["default_scope"]).to eq("all")
      end

      it "leaves counts to the index" do
        expect(meta["scopes"].pluck("count").uniq).to eq([nil])
      end
    end

    describe "batch actions" do
      let(:batch) { by_key(meta["batch_actions"]) }

      it "describes the form of a batch action" do
        expect(batch["set_status"]["inputs"].pluck("name", "control")).to eq([%w[status select], %w[note text]])
        expect(batch["set_status"]["inputs"].first["options"].pluck("value")).to eq(%w[draft published archived])
      end

      it "carries confirm messages" do
        expect(batch["feature"]).to include("label" => "Feature", "confirm" => "Feature these posts?")
      end

      it "includes `if:`-gated actions for those who pass it" do
        expect(batch).to have_key("admins_only")
      end

      it "offers AA's destroy only when the adapter allows it" do
        expect(batch.key?("destroy")).to eq(can_destroy_post?(admin))
      end
    end

    describe "action items and downloads" do
      let(:items) { by_key(meta["action_items"]) }

      it "renders index action items as header actions" do
        expect(items["import"]).to include("kind" => "collection", "method" => "post", "placement" => "header",
          "api_path" => "/api/admin/posts/import", "href" => "/admin/posts/import", "enabled" => true, "label" => "Import")
      end

      it "lists GET collection actions exposed with `reactive { expose }`" do
        expect(items["stats"]).to include("kind" => "collection", "method" => "get", "api_path" => "/api/admin/posts/stats")
      end

      it "does not duplicate New, which the client derives from permissions" do
        expect(items.keys).not_to include("new")
      end

      it "advertises csv downloads" do
        expect(meta["download_formats"]).to eq(["csv"])
      end
    end

    it "reports pagination_total from the index presenter" do
      expect(api_get("/api/admin/tags/_meta", schema: "ResourceMeta")["pagination_total"]).to be(false)
    end

    it "describes nested resources by their parent" do
      nested = api_get("/api/admin/comments/_meta", schema: "ResourceMeta")

      expect(nested["belongs_to"]).to include("parent" => "posts", "param" => "post_id", "optional" => false)
      expect(nested["index_path_template"]).to eq("/admin/posts/{parent_id}/comments")
    end

    it "is cached between requests" do
      api_get("/api/admin/posts/_meta")
      Category.create!(name: "Late")
      expect(api_get("/api/admin/posts/_meta")).to eq(meta)
    end

    it "is a 404 for an unknown resource" do
      api_get("/api/admin/nopes/_meta")

      expect(response).to have_http_status(:not_found)
    end
  end

  context "when signed in as an editor" do
    before { sign_in editor }

    it "omits `if:`-gated batch actions the user fails" do
      expect(by_key(meta["batch_actions"])).not_to have_key("admins_only")
    end

    it "omits `if:`-gated scopes the user fails" do
      expect(meta["scopes"].pluck("id")).not_to include("featured")
    end

    it "does not serve an admin's cached payload" do
      sign_in admin
      api_get("/api/admin/posts/_meta")
      sign_in editor

      expect(by_key(meta["batch_actions"])).not_to have_key("admins_only")
    end

    it "reflects the adapter in permissions and the destroy batch action" do
      expect(meta["permissions"]["destroy"]).to eq(can_destroy_post?(editor))
      expect(by_key(meta["batch_actions"]).key?("destroy")).to eq(can_destroy_post?(editor))
    end

    it "denies resources the adapter denies" do
      api_get("/api/admin/categories/_meta")

      expect(response).to have_http_status(can_read_categories?(editor) ? :ok : :forbidden)
    end
  end

  context "when signed out" do
    it "is a 401" do
      api_get("/api/admin/posts/_meta")

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
