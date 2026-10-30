RSpec.describe "browser-navigating POSTs", type: :request do
  let(:admin) { create_admin }
  let(:page) { "/api/admin/_pages/connections" }

  before { sign_in admin }

  def actions = nodes_of(json["layout"], "action").pluck("action").index_by { it["label"] }

  def navigations = actions.select { |_, action| action["navigate"] }

  let(:offered) { ["Connect with Provider", "Connect on this host", "Connect by link", "Raw form connect"] }

  describe "a button_to or form_tag the DSL rendered, to a route of this host outside the admin" do
    before { api_get(page, schema: "PageResponse") }

    it "is a link action that navigates with the POST verb, and carries no API path" do
      expect(actions["Connect with Provider"]).to eq(
        "key" => "connect_with_provider", "label" => "Connect with Provider", "kind" => "link", "method" => "post", "navigate" => true, "placement" => "inline",
        "href" => "http://www.example.com/auth/provider", "params" => {"origin" => "/admin/connections"}, "enabled" => true
      )
    end

    it "takes a same-host absolute URL, with its confirm" do
      expect(actions["Connect on this host"]).to include("navigate" => true, "href" => "http://www.example.com/auth/absolute", "confirm" => "Link your account?")
    end

    it "takes a rails-ujs link with data-method post, keeping the query" do
      expect(actions["Connect by link"]).to include("navigate" => true, "method" => "post", "href" => "http://www.example.com/auth/link?x=1")
    end

    it "takes a form_tag that holds only hidden fields and a submit button, without the token the browser would carry" do
      expect(actions["Raw form connect"]).to include("navigate" => true, "method" => "post", "href" => "http://www.example.com/auth/raw", "params" => {"origin" => "/admin/connections"})
      expect(response.body).not_to include("authenticity_token")
    end

    it "stays external and GET-only for another host" do
      expect(actions["Connect elsewhere"]).to include("external" => true, "href" => "https://evil.example/auth/provider")
      expect(actions["Connect elsewhere"]).not_to have_key("navigate")
    end

    it "is unsupported for what a browser would resolve elsewhere or run" do
      ["Connect through a dot segment", "Connect to the API", "Connect by script"].each do |label|
        expect(actions[label]).to include("supported" => false, "enabled" => false)
        expect(actions[label]).not_to have_key("navigate")
      end
    end

    it "leaves a plain link and a GET form to the external GET handling" do
      expect(nodes_of(json["layout"], "link").pluck("label")).to include("Open provider page")
      expect(actions["Not a post"]).to include("external" => true, "method" => "get")
      expect(navigations.keys).to match_array(offered)
    end

    it "never turns markup that isn't the DSL's into an action: stored text and literal forms" do
      expect(actions.keys).not_to include("Stored connect", "Literal connect")
      expect(response.body).not_to include("/auth/stored", "/auth/literal")
    end

    it "matches the contract" do
      expect(json).to match_contract("PageResponse")
      expect(Contract.openapi.ref("#/components/schemas/Action").validate(actions["Connect with Provider"]).to_a).to be_empty
    end
  end

  describe "the same page for a bearer token" do
    let(:token) { token_for(admin) }

    it "offers no navigation at all: a token has no browser or cookie" do
      api_get(page, headers: bearer(token))

      expect(response).to have_http_status(:ok)
      expect(navigations).to be_empty
      expect(actions.keys & offered).to be_empty
      expect(response.body).not_to include("/auth/raw", "/auth/absolute", "/auth/link", "navigate")
    end
  end

  describe "through MCP" do
    let(:token) { token_for(admin) }

    it "doesn't expose it in a page, as an action or as text" do
      result = call_tool("get_page", {page: "connections"}, token:)

      text = JSON.generate(result)
      offered.each { expect(text).not_to include(it) }
      expect(text).not_to include("navigate", "/auth/raw", "/auth/absolute", "/auth/link")
    end

    it "has no tool that could run one" do
      names = rpc("tools/list", token:).dig("result", "tools").pluck("name")

      expect(names.grep(/navigate|connect/i)).to be_empty
    end
  end

  describe "with api guards" do
    it "keeps offering it to a session when the page's actions are read-only or session-only" do
      declare_guard("connections", :read_only)
      declare_guard("connections", :session_only, only: :index)

      api_get(page, schema: "PageResponse")

      expect(navigations.keys).to include("Connect with Provider")
      expect(actions["Connect with Provider"]).not_to include("api_denied")
    end

    it "is still refused with the page when the page is denied" do
      declare_guard("connections", :deny)

      api_get(page)

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "the classic page" do
    it "keeps every button as it was" do
      get "/admin/connections"

      expect(response.body).to include('action="/auth/provider"', 'action="/auth/stored"', 'action="/auth/literal"')
    end
  end
end
