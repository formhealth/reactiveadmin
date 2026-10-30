RSpec.describe "_options/lookup", type: :request do
  include_context "with a blog"

  let(:path) { "/api/admin/posts/_options/lookup" }

  def lookups = json["lookups"]

  def labels(field) = lookups[field].pluck("label")

  def lookup(fields, params = {}) = api_get(path, {fields:, context: "filter"}.merge(params), schema: "LookupResponse")

  context "when signed in as an admin" do
    before { sign_in admin }

    it "resolves several fields in one request" do
      lookup({author_id_eq: "#{alice.id},#{bob.id}", category: news.id.to_s, tags: ruby.id.to_s})

      expect(labels("author_id_eq")).to match_array(["Alice Author", "Bob Builder"])
      expect(labels("category")).to eq(["News"])
      expect(labels("tags")).to eq(["ruby"])
    end

    it "serves form controls, for the record in id" do
      lookup({author: alice.id.to_s, category: news.id.to_s}, context: "form", id: first_post.id)

      expect(lookups).to eq("author" => [{"label" => "Alice Author", "value" => alice.id.to_s}], "category" => [{"label" => "News", "value" => news.id.to_s}])
    end

    it "matches what _options answers for the same values" do
      lookup({author_id_eq: bob.id.to_s})
      batched = lookups["author_id_eq"]
      api_get("/api/admin/posts/_options", field: "author_id_eq", context: "filter", value: bob.id.to_s)

      expect(batched).to eq(json["options"])
    end

    it "leaves out values that match nothing" do
      lookup({author_id_eq: "#{alice.id},0"})

      expect(labels("author_id_eq")).to eq(["Alice Author"])
    end

    it "accepts a list of values per field" do
      lookup({author_id_eq: [alice.id.to_s, bob.id.to_s]})

      expect(labels("author_id_eq")).to match_array(["Alice Author", "Bob Builder"])
    end

    it "ignores fields without values" do
      lookup({author_id_eq: alice.id.to_s, category: ""})

      expect(lookups.keys).to eq(["author_id_eq"])
    end

    it "caps values per field" do
      lookup({author_id_eq: (1..26).to_a.join(",")})
      expect(response).to have_http_status(:bad_request)
      expect(json["message"]).to include("max 25")

      lookup({author_id_eq: (1..25).to_a.join(",")})
      expect(response).to have_http_status(:ok)
    end

    it "caps values in total" do
      many = (1..25).to_a.join(",")
      lookup({author_id_eq: many, category: many, tags: many, status: many, other: "1"})

      expect(response).to have_http_status(:bad_request)
      expect(json["message"]).to include("max 100")
    end

    it "caps the value list of _options too" do
      api_get("/api/admin/posts/_options", field: "author_id_eq", context: "filter", value: (1..26).to_a.join(","))

      expect(response).to have_http_status(:bad_request)
    end

    it "is a 400 without usable fields or a valid context" do
      api_get(path, context: "filter")
      expect(response).to have_http_status(:bad_request)

      api_get(path, fields: "x", context: "filter")
      expect(response).to have_http_status(:bad_request)

      api_get(path, fields: {author_id_eq: {a: "1"}}, context: "filter")
      expect(response).to have_http_status(:bad_request)

      api_get(path, fields: {author_id_eq: "1"}, context: "banana")
      expect(response).to have_http_status(:bad_request)
    end

    it "is a 404 when any field is not a declared filter or form field" do
      lookup({author_id_eq: alice.id.to_s, body: "1"})
      expect(response).to have_http_status(:not_found)

      lookup({nope: "1"}, context: "form")
      expect(response).to have_http_status(:not_found)
    end

    it "is served for nested resources at the top-level path" do
      api_get("/api/admin/comments/_options/lookup", fields: {post: first_post.id.to_s}, context: "filter")

      expect(labels("post")).to eq(["Hello world"])
    end

    it "builds a form once for all its fields" do
      builds = 0
      allow(ReactiveAdmin::FormSchema).to receive(:new).and_wrap_original do |original, *args, **kwargs|
        builds += 1
        original.call(*args, **kwargs)
      end
      lookup({author: alice.id.to_s, category: news.id.to_s}, context: "form")

      expect(builds).to eq(1)
    end
  end

  context "when signed in as an editor" do
    before { sign_in editor }

    it "only labels the posts the adapter lets the editor read" do
      ids = [first_post, second_post, third_post].map(&:id).join(",")
      api_get("/api/admin/comments/_options/lookup", fields: {post: ids}, context: "filter")

      expected = [first_post, second_post, third_post].select { can_see_post?(editor, it) }.map(&:title)
      expect(labels("post")).to match_array(expected)
    end

    it "refuses a resource the adapter denies" do
      api_get("/api/admin/categories/_options/lookup", fields: {name: "News"}, context: "filter")

      expect(response).to have_http_status(can_read_categories?(editor) ? :ok : :forbidden)
    end
  end

  context "when signed out" do
    it "is a 401" do
      lookup({author_id_eq: "1"})

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
