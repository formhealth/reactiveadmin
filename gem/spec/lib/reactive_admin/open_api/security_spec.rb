RSpec.describe ReactiveAdmin::OpenApi::Security do
  let(:settings) { ReactiveAdmin.config.openapi }

  after { settings.security_schemes = nil }

  describe ".schemes" do
    it "defaults to the session cookie, the CSRF header and, for a bearer adapter, a bearer token" do
      expect(described_class.schemes.keys).to eq(%w[sessionCookie csrfToken bearerAuth])
      expect(described_class.schemes["csrfToken"]).to include("in" => "header", "name" => "X-CSRF-Token")
      expect(described_class.schemes["bearerAuth"]).to include("type" => "http", "scheme" => "bearer")
    end

    it "declares no bearer token without a bearer adapter" do
      allow(ReactiveAdmin.config).to receive(:auth).and_return(nil)

      expect(described_class.schemes.keys).to eq(%w[sessionCookie csrfToken])
    end

    it "declares only the bearer token when sessions aren't accepted" do
      allow(ReactiveAdmin.config).to receive(:auth).and_return(ReactiveAdmin::Auth::Bearer.new { nil })

      expect(described_class.schemes.keys).to eq(%w[bearerAuth])
    end

    it "leaves a bearer scheme to the host when it configures schemes" do
      settings.security_schemes = {sessionCookie: {type: "apiKey", in: "cookie", name: "s"}}

      expect(described_class.schemes.keys).to eq(%w[sessionCookie])
    end

    it "names the cookie after the host's session key" do
      allow(Rails.application.config).to receive(:session_options).and_return({key: "_acme_session"})

      expect(described_class.schemes["sessionCookie"]).to include("in" => "cookie", "name" => "_acme_session")
    end

    it "falls back to a generic cookie name" do
      allow(Rails.application.config).to receive(:session_options).and_return({})

      expect(described_class.schemes["sessionCookie"]["name"]).to eq("_session_id")
    end

    it "prefers configured schemes, then an authorization adapter's own" do
      adapter = Class.new { def self.openapi_security_scheme = {adapterToken: {type: "http", scheme: "bearer"}} }
      allow(ReactiveAdmin::AA).to receive(:authorization_adapter).and_return(adapter)
      expect(described_class.schemes.keys).to eq(%w[adapterToken])

      settings.security_schemes = {bearer: {type: "http", scheme: "bearer", bearerFormat: "JWT"}}
      expect(described_class.schemes).to eq("bearer" => {"type" => "http", "scheme" => "bearer", "bearerFormat" => "JWT"})
    end
  end

  describe ".requirement" do
    it "asks the CSRF token of writes only, and offers the bearer token instead of the session" do
      expect(described_class.requirement(write: false)).to eq([{"sessionCookie" => []}, {"bearerAuth" => []}])
      expect(described_class.requirement(write: true)).to eq([{"sessionCookie" => [], "csrfToken" => []}, {"bearerAuth" => []}])
    end

    it "asks the session alone without a bearer adapter" do
      allow(ReactiveAdmin.config).to receive(:auth).and_return(nil)

      expect(described_class.requirement(write: true)).to eq([{"sessionCookie" => [], "csrfToken" => []}])
    end

    it "lists the token schemes for token-only endpoints" do
      expect(described_class.token_requirement).to eq([{"bearerAuth" => []}])
    end

    it "asks whatever is configured of both" do
      settings.security_schemes = {bearer: {type: "http", scheme: "bearer"}}

      expect(described_class.requirement(write: false)).to eq([{"bearer" => []}])
      expect(described_class.requirement(write: true)).to eq([{"bearer" => []}])
    end
  end
end
