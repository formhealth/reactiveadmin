RSpec.describe "session and CSRF", type: :request do
  include_context "with a blog"

  describe "GET _session" do
    it "reports the current user and a CSRF token" do
      sign_in editor
      api_get("/api/admin/_session", schema: "Session")

      expect(json["user"]).to eq("id" => editor.id.to_s, "display_name" => "Ed Editor")
      expect(json["csrf_token"]).to be_present
    end

    it "reports that nobody may switch UIs until the host says so" do
      sign_in editor
      api_get("/api/admin/_session", schema: "Session")

      expect(json["ui"]).to eq("available" => false, "default" => "classic")
    end

    it "reports who may switch UIs, and which one the host starts them in" do
      with_ui(available: ->(user) { user.role == "admin" }, default: :new) do
        sign_in admin
        api_get("/api/admin/_session", schema: "Session")
        expect(json["ui"]).to eq("available" => true, "default" => "new")

        sign_in editor
        api_get("/api/admin/_session", schema: "Session")
        expect(json["ui"]).to eq("available" => false, "default" => "new")
      end
    end

    it "is a 401 when signed out" do
      api_get("/api/admin/_session")

      expect(response).to have_http_status(:unauthorized)
      expect(json).to include("code" => "unauthorized")
    end
  end

  describe "with forgery protection on", :csrf do
    around do |example|
      original = ActionController::Base.allow_forgery_protection
      ActionController::Base.allow_forgery_protection = true
      example.run
    ensure
      ActionController::Base.allow_forgery_protection = original
    end

    let(:attrs) { {post: {title: "Guarded", author_id: alice.id}} }

    before { sign_in admin }

    it "does not ask reads for a token" do
      api_get("/api/admin/posts")

      expect(response).to have_http_status(:ok)
    end

    it "rejects a write without a token as invalid_csrf and writes nothing" do
      expect { api(:post, "/api/admin/posts", attrs) }.not_to change(Post, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(json).to eq("code" => "invalid_csrf", "message" => "Invalid CSRF token")
    end

    it "rejects a forged token" do
      api(:post, "/api/admin/posts", attrs, headers: {"X-CSRF-Token" => "forged"})

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["code"]).to eq("invalid_csrf")
    end

    it "accepts the token from _session as X-CSRF-Token" do
      token = csrf_token

      api(:post, "/api/admin/posts", attrs, headers: {"X-CSRF-Token" => token}, schema: "WriteResult")

      expect(response).to have_http_status(:created)
      expect(Post.where(title: "Guarded")).to exist
    end

    it "enforces the token on every verb" do
      token = csrf_token
      headers = {"X-CSRF-Token" => token}

      api(:patch, "/api/admin/posts/#{first_post.id}", {post: {title: "x"}})
      expect(json["code"]).to eq("invalid_csrf")
      api(:patch, "/api/admin/posts/#{first_post.id}", {post: {title: "x"}, lock: lock_of(first_post)}, headers:)
      expect(response).to have_http_status(:ok)

      api(:put, "/api/admin/posts/#{second_post.id}/publish")
      expect(json["code"]).to eq("invalid_csrf")
      api(:put, "/api/admin/posts/#{second_post.id}/publish", headers:)
      expect(response).to have_http_status(:ok)

      api(:delete, "/api/admin/tags/#{ruby.id}")
      expect(json["code"]).to eq("invalid_csrf")
      expect(Tag.exists?(ruby.id)).to be(true)
      api(:delete, "/api/admin/tags/#{ruby.id}", headers:)
      expect(response).to have_http_status(:ok)
    end

    it "enforces the token on batch actions" do
      api(:post, "/api/admin/posts/batch_action", {batch_action: "feature", collection_selection: [first_post.id.to_s]})

      expect(json["code"]).to eq("invalid_csrf")
      expect(second_post.reload.featured).to be(false)
    end

    it "does not accept another session's token" do
      stale = csrf_token
      reset!
      sign_in admin

      api(:post, "/api/admin/posts", attrs, headers: {"X-CSRF-Token" => stale})

      expect(json["code"]).to eq("invalid_csrf")
    end

    it "answers a signed-out write with a JSON auth or CSRF error, never a redirect" do
      reset!
      api(:post, "/api/admin/posts", attrs)

      expect(json).to include("code" => be_in(%w[unauthorized invalid_csrf]))
      expect(Post.where(title: "Guarded")).to be_empty
    end
  end
end
