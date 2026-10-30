RSpec.describe "native GET forms", type: :request do
  let!(:ticket) { Ticket.create!(title: "Alpha 0") }
  let(:path) { "/api/admin/tickets/#{ticket.id}/related" }

  before { sign_in create_admin }

  around do |example|
    ReactiveAdmin::Ladder.reset!
    example.run
  ensure
    ReactiveAdmin::Ladder.reset!
  end

  def related(query = {}, **) = api_get(path, query, schema: "FormResponse", **)

  describe "deciding from the source" do
    def decide(source) = ReactiveAdmin::Ladder.decide([source], "x")

    it "calls a template whose only form is a GET Formtastic form native, and a page" do
      ["method: :get", "method: \"get\"", "method => :get"].each do |option|
        decision = decide("<%= semantic_form_for @s, url: x, #{option} do |f| %><%= f.input :a %><% end %><p>results</p>")

        expect(decision).to have_attributes(mode: "native", get_form: true, wide: true, presentation: "page", reason: "Formtastic GET form (filters and results)")
      end
    end

    it "keeps a POST form a dialog, and a GET link without a form no GET form" do
      expect(decide("<%= semantic_form_for @s, url: x do |f| %><%= f.input :a %><% end %>")).to have_attributes(get_form: false, presentation: "dialog")
      expect(decide("<%= link_to 'x', y, method: :get %>")).to have_attributes(get_form: false)
    end

    it "still frames a raw GET form and one with other markup around it" do
      expect(decide("<%= form_tag x, method: :get %><%= semantic_form_for @s, method: :get do |f| %><% end %>")).to have_attributes(mode: "frame", get_form: false)
    end

    it "offers the view on the action: a page, fetched at the action's own path" do
      api_get("/api/admin/tickets/#{ticket.id}")

      expect(by_key(json["actions"])["related"]["view"]).to eq("mode" => "native", "path" => path, "presentation" => "page")
    end
  end

  describe "a member action template" do
    it "is decided native, as a page, with the GET form noted" do
      decision = ReactiveAdmin::Ladder.action(ReactiveAdmin::Registry.find("tickets"), "related")

      expect(decision).to have_attributes(mode: "native", presentation: "page", get_form: true, reason: a_string_including("GET form"))
      expect(ReactiveAdmin::Ladder.action(ReactiveAdmin::Registry.find("tickets"), "lookup").get_form).to be false
    end

    it "answers a FormResponse that reads the same view with its fields as the query" do
      related

      expect(response).to have_http_status(:ok)
      expect(json["action"]).to eq("method" => "get", "path" => path)
      expect(fields_of(json["form"])["term"]).to include("param" => "filter[term]", "control" => "text")
      expect(json).not_to have_key("layout")
    end

    it "shows the results below the form for a query, with the fields prefilled from it" do
      related({filter: {term: "Alpha"}})

      expect(fields_of(json["form"])["term"]).to include("value" => "Alpha")
      expect(json["layout"].first).to eq("type" => "form")
      expect(nodes_of(json["layout"], "table").first["rows"].flatten.pluck("text")).to eq ["Alpha 0"]
    end

    it "prefills a deep link's control from its param too" do
      related({filter: {term: "Alpha", pick: ticket.id.to_s}})

      expect(fields_of(json["form"])["pick"]).to include("param" => "filter[pick]", "value" => ticket.id.to_s)
    end

    it "is a read: no CSRF, no write audit, no write guards" do
      events = []
      callback = ->(name, *) { events << name }

      ActiveSupport::Notifications.subscribed(callback, /\.reactiveadmin\z/) { related({filter: {term: "Alpha"}}, headers: {"X-CSRF-Token" => "stale"}) }

      expect(response).to have_http_status(:ok)
      expect(events).to be_empty
    end

    it "answers 403 when an api guard refuses the action, as it would a GET without the query" do
      declare_guard("tickets", :deny, only: :related)

      related({filter: {term: "Alpha"}})

      expect(response).to have_http_status(:forbidden)
      expect(json).to include("code" => "api_denied", "guard" => "deny")
    end

    it "is rate limited like any read of the action" do
      allow(ReactiveAdmin::RateLimit).to receive(:retry_after).and_return(9)

      related({filter: {term: "Alpha"}})

      expect(response).to have_http_status(:too_many_requests)
    end

    it "needs the user to be signed in" do
      delete "/logout"

      related({filter: {term: "Alpha"}})

      expect(response).to have_http_status(:unauthorized)
    end

    it "keeps a GET form that goes to another page out of the native ladder" do
      api_get("/api/admin/tickets/#{ticket.id}/elsewhere")

      expect(response).to have_http_status(:not_implemented)
      expect(json["code"]).to eq "unsupported"
    end
  end

  # The options of `pick` are the tickets matching the term, so a search only finds them when it renders with the page's query.
  describe "option search" do
    before do
      now = Time.current
      rows = %w[Alpha Beta].flat_map { |word| Array.new(130) { |i| {title: "#{word} #{i + 1}", created_at: now, updated_at: now} } }
      Ticket.insert_all(rows)
    end

    def search(url, term: "1") = api_get("#{url}&term=#{term}", schema: "OptionsResponse")

    it "keeps the query of a template in the field's options_path" do
      related({filter: {term: "Alpha"}})
      field = fields_of(json["form"])["pick"]

      expect(field).to include("control" => "typeahead", "options_path" => "#{path}?context=template&field=pick&filter%5Bterm%5D=Alpha")

      search(field["options_path"])
      labels = json["options"].pluck("label")
      expect(labels).to include("Alpha 1", "Alpha 10")
      expect(labels.grep(/Beta/)).to be_empty
    end

    it "finds nothing of the scope without the query, which is what dropping it did" do
      search("#{path}?context=template&field=pick", term: "Beta 1")

      expect(json["options"].pluck("label")).to include("Beta 1")
    end

    it "keeps the query of a page in the field's options_path, without the endpoint's own params" do
      api_get("/api/admin/_pages/ticket_report", {report: {term: "Alpha"}, term: "ignored", limit: 5})
      field = nodes_of(json["layout"], "form").sole["form"].then { fields_of(it["form"])["pick"] }

      expect(field["options_path"]).to eq "/api/admin/_pages/ticket_report?context=page_form&field=pick&form=0&report%5Bterm%5D=Alpha"

      search(field["options_path"])
      labels = json["options"].pluck("label")
      expect(labels).to include("Alpha 1", "Alpha 10")
      expect(labels.grep(/Beta/)).to be_empty
    end

    it "authorizes and throttles a page's search like the page's read" do
      allow(ReactiveAdmin::RateLimit).to receive(:retry_after).with(:options, anything).and_return(3)

      api_get("/api/admin/_pages/ticket_report", {report: {term: "Alpha"}, context: "page_form", form: 0, field: "pick"})

      expect(response).to have_http_status(:too_many_requests)
    end
  end

  describe "a register_page" do
    let(:page) { "/api/admin/_pages/ticket_report" }

    def report(query = {}, **) = api_get(page, query, schema: "PageResponse", **)

    def form = nodes_of(json["layout"], "form").sole["form"]

    it "is a native page whose form node is a GET form on the page itself" do
      report

      expect(json["view"]).to include("mode" => "native")
      expect(form["action"]).to eq("method" => "get", "path" => page)
      expect(form["submit_label"]).to eq "Run report"
      expect(fields_of(form["form"])["term"]).to include("param" => "report[term]")
      expect(nodes_of(json["layout"], "frame")).to be_empty
    end

    it "renders the results below the form for a deep link, with the form prefilled" do
      Ticket.create!(title: "Alpha 1")
      report({report: {term: "Alpha"}})

      expect(fields_of(form["form"])["term"]).to include("value" => "Alpha")
      panel = json["layout"].find { it["type"] == "panel" }
      expect(panel["title"]).to eq "Matches"
      expect(nodes_of(panel["children"], "table").first["rows"].flatten.pluck("text")).to eq ["Alpha 0", "Alpha 1"]
    end

    it "shows no results without a query" do
      report

      expect(json["layout"].pluck("type")).to eq ["form"]
    end

    it "is decided native with the GET form noted, from the content's source" do
      decision = ReactiveAdmin::Ladder.page(ReactiveAdmin::Registry.find_page("ticket_report"))

      expect(decision).to have_attributes(mode: "native", get_form: true)
    end

    it "answers 403 when an api guard refuses the page" do
      declare_guard("ticket_report", :deny)

      report({report: {term: "Alpha"}})

      expect(response).to have_http_status(:forbidden)
    end

    it "serves a session and refuses a token when the page is session-only, with or without the query" do
      declare_guard("ticket_report", :session_only)

      report({report: {term: "Alpha"}}, schema: "PageResponse")
      expect(response).to have_http_status(:ok)

      api_get(page, {report: {term: "Alpha"}}, headers: bearer(token_for(create_admin(email: "token@example.com"))))
      expect(response).to have_http_status(:forbidden)
      expect(json).to include("code" => "api_denied", "guard" => "session_only")
    end

    it "keeps the classic page unchanged" do
      get "/admin/ticket_report", params: {report: {term: "Alpha"}}

      expect(response.body).to include('method="get"', 'name="report[term]"', "Alpha 0")
    end

    it "keeps a GET form to another page a frame" do
      api_get("/api/admin/_pages/legacy_forms")

      expect(nodes_of(json["layout"], "frame").size).to eq 3
      expect(nodes_of(json["layout"], "form")).to be_empty
    end
  end
end
