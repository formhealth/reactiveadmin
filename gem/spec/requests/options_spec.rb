RSpec.describe "_options", type: :request do
  include_context "with a blog"

  let(:path) { "/api/admin/posts/_options" }
  def options = json["options"]

  def labels = options.pluck("label")

  def fetch(params, resource_path = path) = api_get(resource_path, params, schema: "OptionsResponse")

  context "when signed in as an admin" do
    before { sign_in admin }

    describe "filters" do
      it "lists a relation-backed source alphabetically" do
        fetch(field: "author_id_eq", context: "filter")

        expect(options).to eq([{"label" => "Alice Author", "value" => alice.id.to_s}, {"label" => "Bob Builder", "value" => bob.id.to_s}])
        expect(json["truncated"]).to be(false)
      end

      it "pages with limit and an opaque cursor" do
        fetch(field: "author_id_eq", context: "filter", limit: 1)
        expect(labels).to eq(["Alice Author"])
        expect(json).to include("truncated" => true)

        fetch(field: "author_id_eq", context: "filter", limit: 1, cursor: json["next_cursor"])
        expect(labels).to eq(["Bob Builder"])
        expect(json["truncated"]).to be(false)
      end

      it "rejects a cursor it cannot decode" do
        fetch(field: "author_id_eq", context: "filter", cursor: "!!!")

        expect(response).to have_http_status(:bad_request)
        expect(json).to include("code" => "invalid", "message" => "Invalid cursor")
      end

      it "caps limit at 100" do
        fetch(field: "author_id_eq", context: "filter", limit: 5000)

        expect(response).to have_http_status(:ok)
      end

      it "resolves selected values to labels instead of searching" do
        fetch(field: "author_id_eq", context: "filter", value: bob.id.to_s)

        expect(options).to eq([{"label" => "Bob Builder", "value" => bob.id.to_s}])
        expect(json["truncated"]).to be(false)
      end

      it "resolves several comma-separated values" do
        fetch(field: "author_id_eq", context: "filter", value: "#{alice.id},#{bob.id}")

        expect(labels).to match_array(["Alice Author", "Bob Builder"])
      end

      it "serves association filters" do
        fetch(field: "category", context: "filter")

        expect(labels).to eq(["News"])
      end

      it "serves has_many through filters" do
        fetch(field: "tags", context: "filter")

        expect(labels).to eq(["ruby"])
      end

      it "searches literal collections in memory" do
        fetch(field: "status", context: "filter", term: "pub")

        expect(options).to eq([{"label" => "published", "value" => "1"}])
      end

      it "is a 404 for a field that is not a declared filter" do
        fetch(field: "body", context: "filter")

        expect(response).to have_http_status(:not_found)
      end
    end

    describe "forms" do
      it "serves a form control's options" do
        fetch(field: "author", context: "form")

        expect(labels).to eq(["Alice Author", "Bob Builder"])
      end

      it "serves an edit form's control for the record in id" do
        fetch(field: "category", context: "form", id: first_post.id)

        expect(labels).to eq(["News"])
      end

      it "is a 404 for a field the form does not have" do
        fetch(field: "nope", context: "form")

        expect(response).to have_http_status(:not_found)
      end
    end

    it "is a 400 without a field or a valid context" do
      api_get(path, context: "filter")
      expect(response).to have_http_status(:bad_request)

      api_get(path, field: "author", context: "banana")
      expect(response).to have_http_status(:bad_request)
    end

    it "is served for nested resources at the top-level path too" do
      fetch({field: "post", context: "filter"}, "/api/admin/comments/_options")

      expect(labels).to match_array(["Hello world", "Bob's draft", "Old news"])
    end

    it "is served under the parent for a nested resource's form" do
      api_get("/api/admin/posts/#{first_post.id}/comments/_options", field: "body", context: "form")

      expect(response).to have_http_status(:not_found)
      expect(json).to include("code" => "not_found")
    end

    describe "typeahead search on any adapter" do
      it "matches word prefixes case-insensitively and ranks exact matches first" do
        create_author(name: "Zed Alice")
        fetch(field: "author_id_eq", context: "filter", term: "ALICE")

        expect(labels).to eq(["Alice Author", "Zed Alice"])
      end
    end

    describe "Postgres typeahead search", :postgres do
      it "matches every token against the start of a word" do
        fetch(field: "author_id_eq", context: "filter", term: "bu bo")

        expect(labels).to eq(["Bob Builder"])
      end

      it "matches the start of any word, ranking exact and prefix matches first" do
        create_author(name: "Zed Alice")
        fetch(field: "author_id_eq", context: "filter", term: "alice")

        expect(labels).to eq(["Alice Author", "Zed Alice"])
      end

      it "finds a record by pasted id" do
        fetch(field: "author_id_eq", context: "filter", term: bob.id.to_s)

        expect(labels).to include("Bob Builder")
      end

      it "searches the source's declared columns" do
        fetch(field: "author_id_eq", context: "filter", term: "bob@example")

        expect(labels).to eq(["Bob Builder"])
      end

      it "treats LIKE wildcards in the term as text" do
        fetch(field: "author_id_eq", context: "filter", term: "%")

        expect(options).to eq([])
      end
    end
  end

  context "when signed in as an editor" do
    before { sign_in editor }

    it "offers only the posts the adapter lets the editor read" do
      fetch({field: "post", context: "filter"}, "/api/admin/comments/_options")

      expected = [first_post, second_post, third_post].select { can_see_post?(editor, it) }.map(&:title)
      expect(labels).to match_array(expected)
    end

    it "refuses options of a resource the adapter denies" do
      api_get("/api/admin/categories/_options", field: "name", context: "filter")

      expect(response).to have_http_status(can_read_categories?(editor) ? :ok : :forbidden)
    end
  end

  context "when signed out" do
    it "is a 401" do
      api_get(path, field: "author_id_eq", context: "filter")

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
