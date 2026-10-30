RSpec.describe "nested resources", type: :request do
  include_context "with a blog"

  let!(:comment) { Comment.create!(post: first_post, body: "Nice post", approved: true) }
  let!(:other_comment) { Comment.create!(post: second_post, body: "Meh") }
  let(:parent_path) { "/api/admin/posts/#{first_post.id}/comments" }

  context "when signed in as an admin" do
    before { sign_in admin }

    describe "index" do
      it "lists only the parent's records" do
        api_get(parent_path, schema: "IndexResponse")

        expect(json["rows"].pluck("id")).to eq([comment.id.to_s])
      end

      it "gives rows paths under the parent" do
        api_get(parent_path)

        expect(json["rows"].first["paths"]).to eq(
          "show" => "/admin/posts/#{first_post.id}/comments/#{comment.id}",
          "edit" => "/admin/posts/#{first_post.id}/comments/#{comment.id}/edit",
          "api_show" => "/api/admin/posts/#{first_post.id}/comments/#{comment.id}",
          "api_edit" => "/api/admin/posts/#{first_post.id}/comments/#{comment.id}/edit"
        )
      end

      it "gives refs to nested-only records their own paths" do
        api_get(parent_path)

        ref = json["rows"].first["cells"]["id"]["ref"]
        expect(ref).to include("resource" => "comments", "id" => comment.id.to_s,
          "path" => "/admin/posts/#{first_post.id}/comments/#{comment.id}",
          "api_path" => "/api/admin/posts/#{first_post.id}/comments/#{comment.id}")
      end

      it "refs the parent with a plain resource reference" do
        api_get(parent_path)

        expect(json["rows"].first["cells"]["post"]["ref"]).to eq("resource" => "posts", "id" => first_post.id.to_s)
      end

      it "is a 404 under a missing parent" do
        api_get("/api/admin/posts/0/comments")

        expect(response).to have_http_status(:not_found)
      end

      it "has no top-level index" do
        api_get("/api/admin/comments")

        expect(response).to have_http_status(:not_found)
        expect(json).to include("code" => "not_found")
      end
    end

    describe "show and forms" do
      it "shows a record under its parent" do
        api_get("#{parent_path}/#{comment.id}", schema: "ShowResponse")

        expect(json).to include("resource" => "comments", "id" => comment.id.to_s)
      end

      it "is a 404 when the record belongs to another parent" do
        api_get("/api/admin/posts/#{second_post.id}/comments/#{comment.id}")

        expect(response).to have_http_status(:not_found)
      end

      it "builds the new form with the nested submit path" do
        api_get("#{parent_path}/new")

        expect(json["action"]).to eq("method" => "post", "path" => parent_path)
      end

      it "builds the edit form with the nested submit path" do
        api_get("#{parent_path}/#{comment.id}/edit")

        expect(json["action"]).to eq("method" => "patch", "path" => "#{parent_path}/#{comment.id}")
        expect(fields_of(json["form"])["body"]["value"]).to eq("Nice post")
      end
    end

    describe "writes" do
      it "creates under the parent and locates the new record nested" do
        api(:post, parent_path, {comment: {body: "Fresh"}}, schema: "WriteResult")

        created = Comment.find_by!(body: "Fresh")
        expect(response).to have_http_status(:created)
        expect(created.post).to eq(first_post)
        expect(json["location"]).to include("url" => "/admin/posts/#{first_post.id}/comments/#{created.id}")
      end

      it "reports validation errors" do
        api(:post, parent_path, {comment: {body: ""}})

        expect(response).to have_http_status(:unprocessable_content)
        expect(json["errors"]).to eq("body" => ["can't be blank"])
      end

      it "updates" do
        api(:patch, "#{parent_path}/#{comment.id}", {comment: {body: "Edited"}, lock: lock_of(comment)})

        expect(response).to have_http_status(:ok)
        expect(comment.reload.body).to eq("Edited")
      end

      it "destroys" do
        api(:delete, "#{parent_path}/#{comment.id}")

        expect(response).to have_http_status(:ok)
        expect(Comment.exists?(comment.id)).to be(false)
      end
    end

    describe "metadata" do
      it "describes the parent relationship" do
        api_get("/api/admin/comments/_meta", schema: "ResourceMeta")

        expect(json).to include("index_path_template" => "/admin/posts/{parent_id}/comments",
          "api_index_path_template" => "/api/admin/posts/{parent_id}/comments")
      end
    end

    it "builds forms of nested resources from a record under the parent" do
      api_get("#{parent_path}/_options", field: "body", context: "form")

      expect(response.media_type).to eq("application/json")
    end
  end

  context "when signed out" do
    it "is a 401" do
      api_get(parent_path)

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
