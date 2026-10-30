RSpec.describe "MCP reads of views with a GET form", type: :request do
  let(:admin) { create_admin }
  let(:token) { token_for(admin) }
  let!(:ticket) { Ticket.create!(title: "Alpha 0") }

  def related(**args) = call_tool("run_action", {resource: "tickets", action: "related", kind: "member", id: ticket.id.to_s, method: "get", **args}, token:)

  describe "get_page" do
    def report(**args) = call_tool("get_page", {page: "ticket_report", **args}, token:)

    it "lists the form's fields, named as the query takes them" do
      result = report

      expect(result["query_fields"].map { it.slice("param", "control") }).to eq([{"param" => "report[term]", "control" => "text"}, {"param" => "report[pick]", "control" => "select"}])
      expect(result["sections"]).to eq "[filter form: its fields are the query_fields]"
    end

    it "takes a query nested by param and answers the results" do
      result = report(query: {report: {term: "Alpha"}})

      expect(result["sections"]).to include("Matches", "Alpha 0")
      expect(result["query_fields"].first).to include("value" => "Alpha")
    end

    it "takes the flat bracket names too" do
      expect(report(query: {"report[term]" => "Alpha"})["sections"]).to include("Alpha 0")
    end

    it "refuses a field the form doesn't declare, naming the ones it does" do
      result = report(query: {report: {term: "Alpha"}, admin: "1"})

      expect(tool_error?).to be true
      expect(result).to include("Unknown query field \"admin\"", "report[term]", "report[pick]")
    end

    it "refuses values that aren't plain" do
      report(query: {report: {term: {deep: [{x: 1}]}}})

      expect(tool_error?).to be true
    end

    it "refuses a query on a page that has no GET form" do
      result = call_tool("get_page", {page: "dashboard", query: {a: "1"}}, token:)

      expect(tool_error?).to be true
      expect(result).to include("no GET form")
    end

    it "is audited as the same tool call, never with the query" do
      events = capture_events("mcp_call.reactiveadmin") { report(query: {report: {term: "Alpha"}}) }

      expect(events.sole).to include(tool: "get_page", status: "ok")
      expect(events.sole.to_s).not_to include("Alpha")
    end
  end

  describe "run_action on a GET action with a form" do
    it "answers the form with its fields keyed by param, and the results for a query" do
      first = related
      expect(first["method"]).to eq "get"
      expect(first["fields"].pluck("param")).to eq(%w[filter[term] filter[pick]])

      result = related(query: {filter: {term: "Alpha"}})

      expect(result["results"]).to include("Alpha 0")
    end

    it "refuses an undeclared field" do
      result = related(query: {filter: {term: "Alpha"}, evil: "1"})

      expect(tool_error?).to be true
      expect(result).to include("Unknown query field \"evil\"")
    end

    it "refuses a query on an action that isn't a GET, or together with inputs" do
      call_tool("run_action", {resource: "tickets", action: "close", kind: "member", id: ticket.id.to_s, method: "post", confirm: true, query: {a: "1"}}, token:)
      expect(tool_error?).to be true

      related(query: {filter: {term: "Alpha"}}, inputs: {a: 1})
      expect(tool_error?).to be true
    end
  end

  it "advertises query on the two read tools only" do
    tools = rpc("tools/list", token:).dig("result", "tools").to_h { [it["name"], it.dig("inputSchema", "properties").keys] }

    expect(tools.select { |_, properties| properties.include?("query") }.keys).to eq(%w[get_page run_action])
  end
end
