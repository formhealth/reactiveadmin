RSpec.describe "template layout", type: :request do
  let!(:ticket) { Ticket.create!(title: "Printer jam") }
  let(:path) { "/api/admin/tickets/#{ticket.id}/lookup" }

  before do
    sign_in create_admin
    api_get(path) # rendering the form is how the search's `q` is known to be its own
  end

  around do |example|
    ReactiveAdmin::Ladder.reset!
    example.run
  ensure
    ReactiveAdmin::Ladder.reset!
  end

  def search(term) = api(:post, path, {q: {term:}}, schema: "FormResponse")

  def actions = nodes_of(json["layout"], "action").pluck("action").index_by { it["label"] }

  describe "deciding" do
    it "is native with several forms and row actions, and shown as a page" do
      decision = ReactiveAdmin::Ladder.action(ReactiveAdmin::Registry.find("tickets"), "lookup")

      expect(decision).to have_attributes(mode: "native", presentation: "page")
    end

    it "still frames raw form controls" do
      decision = ReactiveAdmin::Ladder.decide(["<%= semantic_form_for x do |f| %><% end %><%= form_tag y %>"], "x")

      expect(decision).to have_attributes(mode: "frame", reason: a_string_starting_with("raw form controls"))
    end
  end

  describe "the form before any search" do
    it "has no layout when nothing follows it" do
      api_get(path, schema: "FormResponse")

      expect(json).not_to have_key("layout")
      expect(json["action"]).to eq("method" => "post", "path" => path)
    end
  end

  describe "a search with results" do
    before { search("Printer") }

    it "answers 200 with the form again and the results as layout nodes" do
      expect(response).to have_http_status(:ok)
      expect(fields_of(json["form"])["term"]).to include("param" => "q[term]", "value" => "Printer")
      expect(json["title"]).to eq "Find tickets"
    end

    it "marks the response's own form in place with a form node that has no payload" do
      own = nodes_of(json["layout"], "form").reject { it["form"] }

      expect(own).to eq [{"type" => "form"}]
      expect(json["layout"].first).to eq("type" => "form")
    end

    it "keeps the results as a table and turns row controls into typed actions" do
      expect(nodes_of(json["layout"], "table").first["headers"]).to eq %w[Title Actions]
      expect(actions["Close"]).to include("method" => "post", "confirm" => "Close Printer jam?", "api_path" => "/api/admin/tickets/#{ticket.id}/close",
        "placement" => "inline", "kind" => "member")
      expect(actions["Escalate"]).to include("method" => "post", "api_path" => "/api/admin/tickets/#{ticket.id}/escalate")
    end

    it "records further forms as inline form nodes with their own response" do
      form = nodes_of(json["layout"], "form").filter_map { it["form"] }.sole

      expect(form).to include("action" => {"method" => "put", "path" => "/api/admin/tickets/#{ticket.id}/retitle"}, "submit_label" => "Retitle")
      expect(fields_of(form["form"]).keys).to eq %w[title]
      expect(response.body).not_to include("authenticity_token")
    end

    it "keeps a form it can't describe as a frame node" do
      search("offsite")

      frame = nodes_of(json["layout"], "frame").sole
      expect(frame["html"]).to include("<form", "note")
      expect(frame["html"]).not_to include("example.com")
      expect(frame["src"]).to eq "/admin/tickets/#{ticket.id}/lookup"
      expect(nodes_of(json["layout"], "form").filter_map { it["form"] }).to be_empty
    end

    it "shows no results for a term that matches nothing, as classic does" do
      search("zzz")

      expect(response).to have_http_status(:ok)
      expect(nodes_of(json["layout"], "table").first["rows"]).to eq []
    end
  end

  describe "a rejected search" do
    it "answers 422 with the object's errors when its validation fails" do
      api(:post, path, {q: {term: ""}})

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["base"]).to eq ["Term can't be blank"]
      expect(json["form"]).to include("action" => {"method" => "post", "path" => path})
    end

    it "answers 422 for an alert flash" do
      api(:post, path, {q: {term: "down"}})

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["base"]).to eq ["Lookup is down"]
    end
  end

  describe "row actions" do
    it "run through the API like the classic buttons" do
      api(:post, "/api/admin/tickets/#{ticket.id}/close", schema: "ActionResult")

      expect(json).to include("ok" => true, "message" => "Closed")
      expect(ticket.reload.title).to eq "Printer jam (closed)"
    end

    it "report an alert flash as a rejection" do
      api(:post, "/api/admin/tickets/#{ticket.id}/escalate")

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["base"]).to eq ["Cannot escalate"]
    end
  end
end
