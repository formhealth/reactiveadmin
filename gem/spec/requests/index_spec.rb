RSpec.describe "index", type: :request do
  include_context "with a blog"

  let(:path) { "/api/admin/posts" }
  let(:rows) { json["rows"] }
  let(:titles) { rows.map { cell_text(it, "title") } }

  def cell_text(row, key) = row["cells"].fetch(key).values_at("text", "label", "value").compact.first

  def list(params = nil) = api_get(path, params, schema: "IndexResponse")

  context "when signed in as an admin" do
    before { sign_in admin }

    describe "payload" do
      before { list }

      it "describes the columns of the index block" do
        expect(json["resource"]).to eq("posts")
        expect(json["columns"].pluck("key")).to eq(%w[id title status author views link published_at])
        expect(by_key(json["columns"])["views"]).to include("label" => "Views", "sortable" => true, "sort_key" => "views_count")
        expect(by_key(json["columns"])["link"]).to include("sortable" => false, "sort_key" => nil)
      end

      it "lists records newest first by default" do
        expect(rows.pluck("id")).to eq([third_post, second_post, first_post].map { it.id.to_s })
        expect(json["meta"]).to include("order" => "id_desc", "page" => 1, "per_page" => 10)
      end

      it "types cells: refs, text, status, formatted blocks, links, datetimes and empties" do
        cells = row_for(rows, first_post)["cells"]

        expect(cells["id"]).to eq("type" => "ref", "label" => first_post.id.to_s, "ref" => {"resource" => "posts", "id" => first_post.id.to_s})
        expect(cells["title"]).to eq("type" => "text", "text" => "Hello world")
        expect(cells["status"]).to include("type" => "status", "label" => "Published")
        expect(cells["author"]).to include("type" => "ref", "label" => "Alice Author", "ref" => {"resource" => "authors", "id" => alice.id.to_s})
        expect(cells["views"]).to eq("type" => "text", "text" => "1,200")
        expect(cells["link"]).to include("type" => "link", "label" => "Open", "href" => "/admin/posts/#{first_post.id}", "external" => false)
        expect(cells["published_at"]).to eq("type" => "datetime", "value" => "2026-01-05T12:00:00Z")
        expect(row_for(rows, second_post)["cells"]["published_at"]).to eq("type" => "empty")
      end

      it "gives each row its display name and record paths" do
        row = row_for(rows, first_post)

        expect(row["display_name"]).to eq("Hello world")
        expect(row["paths"]).to eq("show" => "/admin/posts/#{first_post.id}", "edit" => "/admin/posts/#{first_post.id}/edit",
          "api_show" => "/api/admin/posts/#{first_post.id}", "api_edit" => "/api/admin/posts/#{first_post.id}/edit")
      end

      it "gives each row its own permissions" do
        expect(row_for(rows, first_post)["permissions"]).to eq("show" => true, "update" => true, "destroy" => can_destroy_post?(admin))
      end

      it "renders custom row items (`actions defaults: false do item ...`) as row actions" do
        actions = by_key(row_for(rows, first_post)["actions"])

        expect(actions["preview"]).to include("placement" => "row", "kind" => "member", "method" => "get", "label" => "Preview",
          "api_path" => "/api/admin/posts/#{first_post.id}/preview")
        expect(actions["publish"]).to include("placement" => "row", "method" => "put", "api_path" => "/api/admin/posts/#{first_post.id}/publish")
        expect(row_for(rows, first_post)["actions"].size).to eq(2)
      end

      it "does not add View, Edit and Delete as row actions" do
        expect(row_for(rows, first_post)["actions"].pluck("key")).not_to include("view", "edit", "destroy")
      end
    end

    describe "filters" do
      it "filters strings with a predicate" do
        list(q: {title_cont: "Hello"})

        expect(titles).to eq(["Hello world"])
      end

      it "filters numbers" do
        list(q: {views_count_gt: 1000})

        expect(titles).to eq(["Hello world"])
      end

      it "filters date ranges" do
        list(q: {published_at_gteq: "2026-01-01", published_at_lteq: "2026-12-31"})

        expect(titles).to eq(["Hello world"])
      end

      it "filters selects by enum value" do
        list(q: {status_eq: Post.statuses[:draft]})

        expect(titles).to eq(["Bob's draft"])
      end

      it "filters booleans" do
        list(q: {featured_eq: "true"})

        expect(titles).to eq(["Hello world"])
      end

      it "filters by association id" do
        list(q: {author_id_eq: bob.id})

        expect(titles).to eq(["Bob's draft"])
      end

      it "filters by check_boxes association" do
        list(q: {category_id_eq: news.id})

        expect(titles).to eq(["Hello world"])
      end

      it "filters through has_many :through" do
        list(q: {tags_id_eq: ruby.id})

        expect(titles).to eq(["Hello world"])
      end

      it "combines filters" do
        list(q: {author_id_eq: alice.id, status_eq: Post.statuses[:archived]})

        expect(titles).to eq(["Old news"])
      end

      it "returns an empty page when nothing matches" do
        list(q: {title_cont: "zzz"})

        expect(rows).to eq([])
        expect(json["meta"]).to include("total_count" => 0)
      end

      it "rejects predicates no declared filter explains rather than probing columns" do
        api_get(path, q: {body_cont: "secret"})

        expect(response).to have_http_status(:bad_request)
        expect(json).to include("code" => "invalid", "message" => "Unsupported filter: body_cont")
      end
    end

    describe "scopes" do
      it "reports the current scope with counts" do
        list

        expect(json["meta"]["current_scope"]).to eq("all")
        expect(by_key(json["meta"]["scopes"], "id").transform_values { it["count"] })
          .to eq("all" => 3, "draft" => 1, "published" => 1, "archived" => nil, "featured" => 1)
      end

      it "applies a scope" do
        list(scope: "draft")

        expect(titles).to eq(["Bob's draft"])
        expect(json["meta"]["current_scope"]).to eq("draft")
      end

      it "leaves counts null when the scope sets show_count: false" do
        list(scope: "archived")

        expect(titles).to eq(["Old news"])
        expect(by_key(json["meta"]["scopes"], "id")["archived"]["count"]).to be_nil
      end

      it "counts scopes within the active filters" do
        list(q: {author_id_eq: alice.id})

        expect(by_key(json["meta"]["scopes"], "id")["all"]["count"]).to eq(2)
      end
    end

    describe "sorting" do
      it "sorts by a sort_key" do
        list(order: "views_count_desc")

        expect(titles).to eq(["Hello world", "Bob's draft", "Old news"])
        expect(json["meta"]["order"]).to eq("views_count_desc")
      end

      it "sorts ascending" do
        list(order: "title_asc")

        expect(titles).to eq(["Bob's draft", "Hello world", "Old news"])
      end
    end

    describe "pagination with totals" do
      before { 10.times { |i| create_post(author: alice, title: "Filler #{i}") } }

      it "pages and counts" do
        list(page: 2)

        expect(rows.size).to eq(3)
        expect(json["meta"]).to include("page" => 2, "per_page" => 10, "total_count" => 13, "total_pages" => 2, "has_next_page" => false)
      end

      it "reports a next page on the first page" do
        list

        expect(rows.size).to eq(10)
        expect(json["meta"]).to include("has_next_page" => true, "total_pages" => 2)
      end

      it "honours per_page" do
        list(per_page: 5)

        expect(rows.size).to eq(5)
        expect(json["meta"]).to include("per_page" => 5, "total_pages" => 3)
      end
    end

    describe "pagination without totals (pagination_total: false)" do
      let(:path) { "/api/admin/tags" }

      before { 11.times { |i| Tag.create!(name: "tag #{i}") } }

      it "omits totals but still says whether another page exists" do
        list

        expect(json["rows"].size).to eq(10)
        expect(json["meta"]).to include("total_count" => nil, "total_pages" => nil, "has_next_page" => true)
      end

      it "reports the last page" do
        list(page: 2)

        expect(json["rows"].size).to eq(2)
        expect(json["meta"]).to include("has_next_page" => false, "page" => 2)
      end
    end

    describe "other registrations" do
      it "falls back to the resource's columns without an index block" do
        api_get("/api/admin/categories", nil, schema: "IndexResponse")

        expect(json["columns"].pluck("key")).to include("id", "name")
      end

      it "describes a block with `actions defaults: false` on authors" do
        api_get("/api/admin/authors", nil, schema: "IndexResponse")

        row = row_for(json["rows"], alice)
        expect(row["actions"].pluck("key", "method")).to eq([%w[ping post]])
        expect(json["columns"].pluck("key")).to eq(%w[id name email rating])
      end

      it "types `mail_to` cells as links or html without leaking raw markup" do
        api_get("/api/admin/authors", nil, schema: "IndexResponse")

        email = row_for(json["rows"], alice)["cells"]["email"]
        expect(email["type"]).to eq("link")
        expect(email["href"]).to eq("mailto:alice@example.com")
        expect(email["external"]).to be(true)
      end
    end
  end

  context "when signed in as an editor" do
    before do
      sign_in editor
      list
    end

    it "only lists the posts the adapter exposes" do
      expected = [first_post, second_post, third_post].select { can_see_post?(editor, it) }

      expect(rows.pluck("id")).to match_array(expected.map { it.id.to_s })
    end

    it "counts scopes within what the editor can see" do
      expect(json["meta"]["total_count"]).to eq([first_post, second_post, third_post].select { can_see_post?(editor, it) }.size)
      expect(by_key(json["meta"]["scopes"], "id")["all"]["count"]).to eq(json["meta"]["total_count"])
    end

    it "hides `if:`-gated scopes" do
      expect(json["meta"]["scopes"].pluck("id")).not_to include("featured")
    end

    it "gives rows the adapter's permissions" do
      expect(rows.map { it["permissions"]["destroy"] }.uniq).to eq([can_destroy_post?(editor)])
    end
  end

  context "when the adapter denies the resource" do
    before { sign_in editor }

    it "answers 403 for a resource the adapter hides from editors" do
      api_get("/api/admin/categories")

      expect(response).to have_http_status(can_read_categories?(editor) ? :ok : :forbidden)
    end
  end

  context "when signed out" do
    it "is a 401" do
      api_get(path)

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
