RSpec.describe "form param normalization", type: :request do
  include_context "with a blog"

  before { sign_in admin }

  def create_memo(attrs) = api(:post, "/api/admin/memos", {memo: {title: "Standup", **attrs}})

  let(:memo) { Memo.find_by!(title: "Standup") }

  describe "blank values" do
    it "stores a null text field as an empty string, as classic's empty input posts" do
      create_memo(summary: nil)

      expect(memo.summary).to eq("")
    end

    it "leaves a missing field untouched" do
      create_memo({})

      expect(memo.summary).to be_nil
    end

    it "stores a null json field as an empty string, as classic's empty textarea posts" do
      create_memo(payload: nil)

      expect(memo.payload).to eq("")
    end
  end

  describe "json fields" do
    it "posts a structured value as JSON text where the host permits a scalar, like classic's textarea" do
      create_memo(payload: {"a" => {"b" => [1, 2]}})

      expect(response).to have_http_status(:created)
      expect(memo.payload).to eq('{"a":{"b":[1,2]}}')
    end

    it "takes JSON text as it is" do
      create_memo(payload: '{"a":1}')

      expect(memo.payload).to eq('{"a":1}')
    end

    it "keeps the structure where the host permits `attr: {}`" do
      api(:post, "/api/admin/posts", {post: {title: "Meta", author_id: alice.id, metadata: {"a" => {"b" => [1, 2]}}}})

      expect(Post.find_by!(title: "Meta").metadata).to eq("a" => {"b" => [1, 2]})
    end
  end

  describe "a record prepared by the host's `new` block" do
    let(:author) { Author.create!(name: "Alice") }

    it "reaches the form" do
      api_get("/api/admin/authors/#{author.id}/memos/new", schema: "FormResponse")

      expect(fields_of(json["form"])["summary"]).to include("value" => "Draft by Alice")
      expect(json).to include("submittable" => true)
    end

    it "degrades to an unsubmittable form, not a 500, when the block raises" do
      api_get("/api/admin/memos/new", schema: "FormResponse")

      expect(json).to include("submittable" => false)
      expect(json["degraded"]).to include(a_hash_including("kind" => "prepare_block_failed", "where" => "form", "reason" => a_string_including("NoMethodError")))
      expect(json["degraded"].pluck("kind")).to include("form_unsupported")
    end
  end

  describe "error keys" do
    it "names the field the client shows" do
      api(:post, "/api/admin/posts", {post: {title: "No author", author_id: ""}})

      expect(json["errors"]).to eq("author" => ["must exist"])
    end
  end
end
