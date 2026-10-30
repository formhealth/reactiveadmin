require "csv"

RSpec.describe "CSV export", type: :request do
  include_context "with a blog"

  def export(path = "/api/admin/posts.csv", params = nil) = api_get(path, params)

  def table = CSV.parse(response.body.delete_prefix("﻿"), headers: true)

  context "when signed in as an admin" do
    before { sign_in admin }

    it "streams AA's export using the csv block" do
      export

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/csv")
      expect(response.headers["Content-Disposition"]).to match(/attachment; filename="posts-\d{4}-\d{2}-\d{2}\.csv"/)
      expect(table.headers).to eq(%w[Id Title Author])
      expect(table.map(&:to_h)).to include("Id" => first_post.id.to_s, "Title" => "Hello world", "Author" => "Alice Author")
    end

    it "keeps the current filters, scope and order" do
      export("/api/admin/posts.csv", q: {author_id_eq: alice.id}, scope: "published", order: "title_asc")

      expect(table["Title"]).to eq(["Hello world"])
    end

    it "neutralizes formula-like cells whatever the mask settings" do
      create_post(author: alice, title: "=HYPERLINK(\"http://x\")")
      create_post(author: alice, title: "+1")
      create_post(author: alice, title: "@SUM(A1)")
      create_post(author: alice, title: "-2")
      create_post(author: alice, title: "\tcmd")
      export

      expect(table["Title"]).to include("'=HYPERLINK(\"http://x\")", "'+1", "'@SUM(A1)", "'-2", "'\tcmd")
      expect(table["Title"]).to include("Hello world")
    end

    it "exports every page, not just the first" do
      12.times { |i| create_post(author: alice, title: "Filler #{i}") }
      export

      expect(table.size).to eq(15)
    end

    it "falls back to the columns of a resource without a csv block" do
      export("/api/admin/authors.csv")

      expect(table.headers).to include("Id", "Name", "Email")
    end

    it "refuses a resource that turned downloads off" do
      export("/api/admin/tags.csv")

      expect(response).to have_http_status(:forbidden)
      expect(response.media_type).to eq("application/json")
      expect(json).to include("code" => "forbidden")
    end

    it "rejects undeclared ransack predicates like the index does" do
      export("/api/admin/posts.csv", q: {body_cont: "x"})

      expect(response).to have_http_status(:bad_request)
      expect(response.media_type).to eq("application/json")
    end

    it "leaves the classic admin export alone" do
      get "/admin/posts.csv"

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/csv")
    end
  end

  context "when signed in as an editor" do
    before { sign_in editor }

    it "exports only what the adapter exposes" do
      export

      expect(table["Id"]).to match_array([first_post, second_post, third_post].select { can_see_post?(editor, it) }.map { it.id.to_s })
    end
  end

  context "when signed out" do
    it "is a JSON 401, not a csv or a redirect" do
      export

      expect(response).to have_http_status(:unauthorized)
      expect(response.media_type).to eq("application/json")
      expect(json).to include("code" => "unauthorized")
    end
  end
end
