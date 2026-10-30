RSpec.describe "has_many layout", type: :request do
  include_context "with a blog"

  let(:comments) { json["form"]["sections"].find { it["kind"] == "has_many" } }
  let(:article_config) { ActiveAdmin.application.namespace(:admin).resource_for(Article) }

  before { sign_in admin }

  def article_form = api_get("/api/admin/articles/new", schema: "FormResponse")

  describe "layout" do
    it "is compact when each row is one control" do
      article_form

      expect(comments).to include("layout" => "compact", "max_rows" => 5)
    end

    it "is cards when a row has several controls" do
      api_get("/api/admin/posts/new", schema: "FormResponse")

      expect(comments).to include("layout" => "cards")
      expect(comments).not_to have_key("max_rows")
    end

    it "judges existing rows too" do
      article = Article.create!(title: "Row", author: alice)
      Comment.create!(post_id: article.id, body: "one")
      api_get("/api/admin/articles/#{article.id}/edit", schema: "FormResponse")

      expect(comments).to include("layout" => "compact")
      expect(comments["records"].size).to eq(1)
    end

    it "follows the host's nested_layout declaration" do
      article_config.reactive_options[:nested_layout] = {comments: "cards"}
      article_form

      expect(comments).to include("layout" => "cards")
    ensure
      article_config.reactive_options.delete(:nested_layout)
    end

    it "rejects a layout it doesn't know" do
      expect { ReactiveAdmin::ReactiveDSL.new(article_config).nested_layout(:comments, :grid) }.to raise_error(ArgumentError, /cards, compact/)
    end
  end

  describe "row errors" do
    let!(:saved) { Comment.create!(post: first_post, body: "kept") }
    let!(:other) { Comment.create!(post: first_post, body: "also kept") }

    def update(rows) = api(:patch, "/api/admin/posts/#{first_post.id}", {post: {comments_attributes: rows}, lock: lock_of(first_post)})

    it "names a failed saved row by its id and a failed new row by its place among the new ones" do
      update("0" => {id: saved.id, body: ""}, "1" => {id: other.id, body: "fine"}, "2" => {body: "ok"}, "3" => {body: ""})

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["errors"]).to include("comments.body" => ["can't be blank"])
      expect(json["row_errors"]).to eq("comments" => [
        {"id" => saved.id.to_s, "errors" => {"body" => ["can't be blank"]}},
        {"new" => 1, "errors" => {"body" => ["can't be blank"]}}
      ])
      expect(json).to match_contract("ValidationError")
    end

    it "leaves out rows that are being removed" do
      update("0" => {id: saved.id, body: "", _destroy: "1"}, "1" => {body: ""})

      expect(json["row_errors"]).to eq("comments" => [{"new" => 0, "errors" => {"body" => ["can't be blank"]}}])
    end

    it "is absent when only the record failed" do
      api(:patch, "/api/admin/posts/#{first_post.id}", {post: {title: ""}, lock: lock_of(first_post)})

      expect(json).not_to have_key("row_errors")
    end
  end
end
