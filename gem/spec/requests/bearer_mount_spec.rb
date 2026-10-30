RSpec.describe "bearer tokens and the classic admin", type: :request do
  include_context "with a blog"

  let!(:other) { AdminUser.create!(name: "Olive Other", email: "olive@example.com", role: "editor", author: alice) }
  let(:token) { token_for(admin) }
  let(:headers) { bearer(token) }

  describe "off the mount" do
    let(:classic) do
      # The reserved actions, and routes the api guards leave alone.
      [
        [:post, "/admin/admin_users/#{other.id}/impersonate"],
        [:get, "/admin/admin_users/#{other.id}/impersonate"],
        [:post, "/admin/admin_users/sweep"],
        [:post, "/admin/admin_users/batch_action"],
        [:delete, "/admin/admin_users/#{other.id}"],
        [:post, "/admin/danger_zone/wipe"],
        [:post, "/admin/admin_users/#{other.id}/greet"],
        [:get, "/admin/posts"]
      ]
    end

    def unauthenticated?
      response.status == 401 || response.redirect?
    end

    it "does not authenticate classic routes, in any format" do
      classic.product(["", ".json", ".xml", ".reactiveadmin"]).each do |(verb, path), format|
        public_send(verb, path.sub(/(?=\?|\z)/, format), params: {batch_action: "promote", collection_selection: [other.id]}, headers:)

        expect(unauthenticated?).to be(true), "#{verb.upcase} #{path}#{format} answered #{response.status}"
        expect(flash[:notice]).to be_nil
      end
      expect(AdminUser.exists?(other.id)).to be(true)
    end

    it "does not authenticate a classic request that asks for the API's media type" do
      classic.each do |verb, path|
        public_send(verb, path, headers: headers.merge("ACCEPT" => "application/vnd.reactiveadmin+json", "CONTENT_TYPE" => "application/json"))

        expect(unauthenticated?).to be(true), "#{verb.upcase} #{path} answered #{response.status}"
      end
    end

    it "never reaches the action" do
      expect_any_instance_of(Admin::AdminUsersController).not_to receive(:impersonate)
      expect_any_instance_of(Admin::AdminUsersController).not_to receive(:sweep)

      post("/admin/admin_users/#{other.id}/impersonate", headers:)
      post("/admin/admin_users/#{other.id}/impersonate.json", headers:)
      post("/admin/admin_users/sweep.json", headers:)
    end

    it "leaves a signed-in session on a classic route to the session" do
      sign_in editor
      get("/admin/posts", headers: bearer(token_for(admin)))

      expect(response).to have_http_status(:ok)
    end

    it "keeps cookies on a classic request that carries a token" do
      sign_in admin
      post("/admin/admin_users/#{other.id}/impersonate", headers: bearer("not-a-token"))

      expect(response).to redirect_to("/admin/admin_users/#{other.id}")
    end

    it "serves the same token under the mount" do
      api_get("/api/admin/_session", headers:)

      expect(response).to have_http_status(:ok)
      expect(json["user"]).to include("id" => admin.id.to_s)
    end

    it "treats a classic path as the session's whatever the configured adapters" do
      bearer_only = ReactiveAdmin::Auth::Bearer.new { |t, _| DummyTokens.resolve(t) }
      allow(ReactiveAdmin.config).to receive(:auth).and_return(bearer_only)
      classic = ActionDispatch::Request.new(Rack::MockRequest.env_for("/admin/posts", "HTTP_AUTHORIZATION" => "Bearer #{token}"))
      api = ActionDispatch::Request.new(Rack::MockRequest.env_for("/api/admin/posts", "HTTP_AUTHORIZATION" => "Bearer #{token}"))

      expect(ReactiveAdmin::Auth.adapter_for(classic)).to be(ReactiveAdmin::Auth::SESSION)
      expect(ReactiveAdmin::Auth.identity(classic)).to be_nil
      expect(ReactiveAdmin::Auth.adapter_for(api)).to be(bearer_only)
      expect(ReactiveAdmin::Auth.identity(api).user).to eq(admin)
    end
  end

  describe "order of refusals on a reserved action" do
    let(:path) { "/api/admin/admin_users/#{other.id}/impersonate" }

    def code = json["code"]

    it "answers a request with no credentials 401, before api_denied" do
      api(:post, path)

      expect(response).to have_http_status(:unauthorized)
      expect(code).to eq("unauthorized")
    end

    it "answers an invalid token 401, before api_denied" do
      api(:post, path, headers: bearer("nope"))

      expect(response).to have_http_status(:unauthorized)
      expect(code).to eq("unauthorized")
      expect(response.headers["WWW-Authenticate"]).to eq('Bearer error="invalid_token"')
    end

    it "answers a token without the scope 403 insufficient_scope, before api_denied" do
      api(:post, path, headers: bearer(token_for(admin, scopes: ["admin:read"])))

      expect(response).to have_http_status(:forbidden)
      expect(code).to eq("insufficient_scope")
    end

    it "answers a token with the scope 403 api_denied" do
      api(:post, path, headers: bearer(token_for(admin, scopes: %w[admin:read admin:write])))

      expect(response).to have_http_status(:forbidden)
      expect(code).to eq("api_denied")
      expect(json["classic_url"]).to eq("/admin/admin_users/#{other.id}")
    end

    it "answers a token with no scope claim 403 api_denied" do
      api(:post, path, headers:)

      expect(code).to eq("api_denied")
    end

    it "checks a GET against the read scope" do
      api_get(path, headers: bearer(token_for(admin, scopes: ["admin:write"])))
      expect(code).to eq("insufficient_scope")

      api_get(path, headers: bearer(token_for(admin, scopes: ["admin:read"])))
      expect(code).to eq("api_denied")
    end

    it "refuses a reserved attribute only once the write is allowed" do
      attrs = {admin_user: {role: "admin"}}
      api(:patch, "/api/admin/admin_users/#{other.id}", attrs, headers: bearer(token_for(admin, scopes: ["admin:read"])))
      expect(code).to eq("insufficient_scope")

      api(:patch, "/api/admin/admin_users/#{other.id}", attrs, headers:)
      expect(code).to eq("api_denied")
      expect(other.reload.role).to eq("editor")
    end

    it "never runs the action for any token" do
      expect_any_instance_of(Admin::AdminUsersController).not_to receive(:impersonate)

      [headers, bearer(token_for(admin, scopes: ["admin:read"])), bearer("nope"), {}].each { api(:post, path, headers: it) }
    end
  end
end
