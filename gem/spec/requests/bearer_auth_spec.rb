RSpec.describe "bearer authentication", type: :request do
  include_context "with a blog"

  let(:token) { token_for(admin) }
  let(:attrs) { {post: {title: "By token", author_id: alice.id}} }

  def with_metadata_url(url)
    original = ReactiveAdmin.config.mcp.resource_metadata_url
    ReactiveAdmin.config.mcp.resource_metadata_url = url
    yield
  ensure
    ReactiveAdmin.config.mcp.resource_metadata_url = original
  end

  describe "alongside the session" do
    it "serves a token with no cookie" do
      api_get("/api/admin/_session", headers: bearer(token))

      expect(response).to have_http_status(:ok)
      expect(json["user"]).to include("id" => admin.id.to_s)
    end

    it "still serves the session" do
      sign_in editor
      api_get("/api/admin/_session")

      expect(json["user"]).to include("id" => editor.id.to_s)
    end

    it "answers a signed-out request as the session adapter does" do
      api_get("/api/admin/_session")

      expect(response).to have_http_status(:unauthorized)
      expect(response.headers["WWW-Authenticate"]).to be_nil
      expect(json).to include("location" => "/login")
    end

    it "sets no cookie on a token request" do
      api_get("/api/admin/posts", headers: bearer(token))

      expect(response.headers["Set-Cookie"]).to be_nil
    end
  end

  describe "never falling back to cookies" do
    before { sign_in admin }

    it "refuses a bad token even with a valid session" do
      api_get("/api/admin/posts", headers: bearer("nope"))

      expect(response).to have_http_status(:unauthorized)
      expect(response.headers["WWW-Authenticate"]).to eq('Bearer error="invalid_token"')
    end

    it "acts as the token's user, not the session's" do
      api_get("/api/admin/_session", headers: bearer(token_for(editor)))

      expect(json["user"]).to include("id" => editor.id.to_s)
    end

    it "keeps the session user out of what host code reads" do
      api_get("/api/admin/_manifest", headers: bearer(token_for(editor)))

      expect(json.dig("site", "current_user", "id")).to eq(editor.id.to_s)
    end
  end

  describe "the user the authorization adapter sees" do
    it "scopes the policy to the token's user" do
      api_get("/api/admin/posts", headers: bearer(token_for(editor)))

      visible = json["rows"].pluck("id")
      expect(visible).to eq([first_post, second_post, third_post].select { can_see_post?(editor, it) }.map { it.id.to_s }.sort.reverse)
    end

    it "evaluates host conditions with the token's user" do
      scope_ids = ->(user) { api_get("/api/admin/posts/_meta", headers: bearer(token_for(user)))["scopes"].pluck("id") }

      expect(scope_ids.call(admin)).to include("featured")
      expect(scope_ids.call(editor)).not_to include("featured")
    end

    it "attributes writes in the audit trail to the token's user" do
      events = capture_events("write.reactiveadmin") { api(:post, "/api/admin/posts", attrs, headers: bearer(token)) }

      expect(response).to have_http_status(:created)
      expect(events).to contain_exactly(include(resource: "posts", action: "create", user_id: admin.id))
    end
  end

  describe "CSRF", :csrf do
    around do |example|
      original = ActionController::Base.allow_forgery_protection
      ActionController::Base.allow_forgery_protection = true
      example.run
    ensure
      ActionController::Base.allow_forgery_protection = original
    end

    it "is skipped for a token" do
      expect { api(:post, "/api/admin/posts", attrs, headers: bearer(token)) }.to change(Post, :count).by(1)
    end

    it "still applies to the session" do
      sign_in admin

      expect { api(:post, "/api/admin/posts", attrs) }.not_to change(Post, :count)
      expect(json).to include("code" => "invalid_csrf")
    end

    it "is not skipped by a bearer header that fails" do
      sign_in admin

      expect { api(:post, "/api/admin/posts", attrs, headers: bearer("nope")) }.not_to change(Post, :count)
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "scopes" do
    it "lets a token without scopes do anything its user can" do
      expect { api(:post, "/api/admin/posts", attrs, headers: bearer(token)) }.to change(Post, :count).by(1)
    end

    it "lets a read-only token read" do
      api_get("/api/admin/posts", headers: bearer(token_for(admin, scopes: ["admin:read"])))

      expect(response).to have_http_status(:ok)
    end

    it "refuses a write without the write scope, naming the scope" do
      token = token_for(admin, scopes: "admin:read")

      expect { api(:post, "/api/admin/posts", attrs, headers: bearer(token)) }.not_to change(Post, :count)
      expect(response).to have_http_status(:forbidden)
      expect(json).to include("code" => "insufficient_scope")
      expect(response.headers["WWW-Authenticate"]).to eq('Bearer error="insufficient_scope", scope="admin:write"')
    end

    it "refuses a read without the read scope" do
      api_get("/api/admin/posts", headers: bearer(token_for(admin, scopes: ["admin:write"])))

      expect(response).to have_http_status(:forbidden)
    end

    it "accepts scopes as a space-separated string" do
      expect { api(:post, "/api/admin/posts", attrs, headers: bearer(token_for(admin, scopes: "admin:read admin:write"))) }.to change(Post, :count).by(1)
    end

    it "stops requiring a scope that is configured off" do
      original = ReactiveAdmin.config.mcp.write_scope
      ReactiveAdmin.config.mcp.write_scope = nil

      expect { api(:post, "/api/admin/posts", attrs, headers: bearer(token_for(admin, scopes: ["admin:read"]))) }.to change(Post, :count).by(1)
    ensure
      ReactiveAdmin.config.mcp.write_scope = original
    end
  end

  describe "the WWW-Authenticate challenge" do
    it "points at the protected resource metadata when configured" do
      with_metadata_url("https://admin.example.com/.well-known/oauth-protected-resource") do
        api_get("/api/admin/_session", headers: bearer("nope"))
      end

      expect(response.headers["WWW-Authenticate"]).to eq('Bearer error="invalid_token", resource_metadata="https://admin.example.com/.well-known/oauth-protected-resource"')
    end

    it "is left off a session 401" do
      with_metadata_url("https://admin.example.com/meta") { api_get("/api/admin/_session") }

      expect(response.headers["WWW-Authenticate"]).to be_nil
    end
  end

  describe "a bearer resolver" do
    it "fails closed when it raises" do
      allow(DummyTokens).to receive(:resolve).and_raise("db down")
      api_get("/api/admin/posts", headers: bearer(token))

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
