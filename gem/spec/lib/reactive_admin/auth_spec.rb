RSpec.describe ReactiveAdmin::Auth do
  let(:user) { Struct.new(:id).new(7) }
  let(:bearer) { ReactiveAdmin::Auth::Bearer.new { |token, _request| user if token == "good" } }
  let(:session) { ReactiveAdmin::Auth::Session.new }

  def request_with(authorization: nil, cookie: nil, path: "/api/admin/posts")
    env = Rack::MockRequest.env_for(path, "HTTP_AUTHORIZATION" => authorization, "HTTP_COOKIE" => cookie)
    ActionDispatch::Request.new(env.compact)
  end

  describe ReactiveAdmin::Auth::Bearer do
    it "claims requests with the Bearer scheme, any case" do
      expect(bearer.claims?(request_with(authorization: "Bearer good"))).to be(true)
      expect(bearer.claims?(request_with(authorization: "bearer good"))).to be(true)
      expect(bearer.claims?(request_with(authorization: "Bearer"))).to be(true)
      expect(bearer.claims?(request_with(authorization: "Basic abc"))).to be(false)
      expect(bearer.claims?(request_with)).to be(false)
    end

    it "wraps a bare user as an unrestricted identity" do
      identity = bearer.authenticate(request_with(authorization: "Bearer good"))

      expect(identity).to have_attributes(user:, scopes: nil, client_id: nil)
      expect(identity.allows?("admin:write")).to be(true)
    end

    it "reads user, scopes and client_id from a hash, scopes as a list or a string" do
      resolver = ->(scopes) { described_class.new { |*| {user:, scopes:, client_id: 42} } }
      listed = resolver.call(%w[admin:read]).authenticate(request_with(authorization: "Bearer x"))
      spaced = resolver.call("admin:read admin:write").authenticate(request_with(authorization: "Bearer x"))

      expect(listed).to have_attributes(scopes: %w[admin:read], client_id: "42")
      expect(listed.allows?("admin:write")).to be(false)
      expect(spaced.scopes).to eq(%w[admin:read admin:write])
    end

    it "returns nil for a rejected token, a missing token, and a raising resolver" do
      raising = described_class.new { |*| raise "boom" }

      expect(bearer.authenticate(request_with(authorization: "Bearer bad"))).to be_nil
      expect(bearer.authenticate(request_with(authorization: "Bearer"))).to be_nil
      expect(raising.authenticate(request_with(authorization: "Bearer good"))).to be_nil
    end

    it "needs a block" do
      expect { described_class.new }.to raise_error(ArgumentError)
    end
  end

  describe ".any" do
    let(:auth) { described_class.any(session, bearer) }

    it "gives a Bearer request to the bearer adapter whatever the order" do
      request = request_with(authorization: "Bearer good", cookie: "_session=abc")

      expect(auth.adapter_for(request)).to be(bearer)
      expect(described_class.any(bearer, session).adapter_for(request)).to be(bearer)
    end

    it "gives everything else to the session adapter" do
      expect(auth.adapter_for(request_with(cookie: "_session=abc"))).to be(session)
      expect(auth.adapter_for(request_with(authorization: "Basic abc"))).to be(session)
    end

    it "needs an adapter" do
      expect { described_class.any }.to raise_error(ArgumentError)
    end
  end

  describe ".identity" do
    around do |example|
      original = ReactiveAdmin.config.auth
      ReactiveAdmin.config.auth = described_class.any(session, bearer)
      example.run
    ensure
      ReactiveAdmin.config.auth = original
    end

    it "resolves once per request" do
      calls = 0
      counting = ReactiveAdmin::Auth::Bearer.new { |*| (calls += 1) && user }
      ReactiveAdmin.config.auth = counting
      request = request_with(authorization: "Bearer good")

      2.times { described_class.identity(request) }

      expect(calls).to eq(1)
    end

    it "is nil for a session request" do
      expect(described_class.identity(request_with)).to be_nil
    end

    it "treats a host with no auth configured as the session" do
      ReactiveAdmin.config.auth = nil

      expect(described_class.token_based?(request_with(authorization: "Bearer good"))).to be(false)
    end
  end

  describe ".challenge" do
    it "adds the error, scope and resource metadata that apply" do
      original = ReactiveAdmin.config.mcp.resource_metadata_url
      ReactiveAdmin.config.mcp.resource_metadata_url = "https://x.test/meta"

      expect(described_class.challenge).to eq('Bearer resource_metadata="https://x.test/meta"')
      expect(described_class.challenge(error: "insufficient_scope", scope: "admin:write")).to eq('Bearer error="insufficient_scope", scope="admin:write", resource_metadata="https://x.test/meta"')
    ensure
      ReactiveAdmin.config.mcp.resource_metadata_url = original
    end

    it "is the bare scheme when there is nothing to add" do
      expect(described_class.challenge).to eq("Bearer")
    end
  end

  describe ReactiveAdmin::Auth::TokenRequests do
    let(:seen) { [] }
    let(:app) { ->(env) { seen << env["HTTP_COOKIE"] && [200, {}, []] } }
    let(:middleware) { described_class.new(app) }

    around do |example|
      original = ReactiveAdmin.config.auth
      ReactiveAdmin.config.auth = ReactiveAdmin::Auth.any(session, bearer)
      example.run
    ensure
      ReactiveAdmin.config.auth = original
    end

    def call(path: "/api/admin/posts", **headers)
      middleware.call(Rack::MockRequest.env_for(path, headers))
      seen.last
    end

    it "drops cookies from a bearer request to the API" do
      expect(call("HTTP_AUTHORIZATION" => "Bearer good", "HTTP_COOKIE" => "_session=abc")).to be_nil
    end

    it "leaves a session request alone" do
      expect(call("HTTP_COOKIE" => "_session=abc")).to eq("_session=abc")
    end

    it "leaves requests outside the API alone, such as classic admin pages" do
      expect(call(:path => "/admin/posts", "HTTP_AUTHORIZATION" => "Bearer good", "HTTP_COOKIE" => "_session=abc")).to eq("_session=abc")
    end
  end
end
