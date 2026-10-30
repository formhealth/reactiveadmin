RSpec.describe "typed content in a form block", type: :request do
  include_context "with a blog"

  let(:notes) { '<a href="/admin/accounts/1" data-method="delete" data-confirm="Totally safe">Read more</a>' }
  let!(:plan) { Plan.create!(name: "Gold", api_token: "tok_live_123", notes:) }

  before do
    Account.create!(author: alice, plan:)
    sign_in admin
  end

  def sections = api_get("/api/admin/accounts/new", schema: "FormResponse")["form"]["sections"]

  def contents = sections.flat_map { it["fields"] }.select { it["control"] == "content" }

  it "walks the block's content into nodes in place, around the inputs" do
    expect(sections.map { |s| s["fields"].map { it["control"] } }).to eq([%w[content], %w[hidden select select]])
    expect(sections.first["fields"].first).to include("param" => nil, "label" => "")

    nodes = contents.first["layout"]
    expect(nodes.first).to include("type" => "heading", "level" => 3)
    expect(nodes.first.to_json).to include("Alice Author")
    expect(nodes_of(nodes, "panel").pluck("title")).to eq(["Current Plan"])
    expect(nodes_of(nodes, "attributes_table").flat_map { it["rows"] }.pluck("label")).to eq(["Name", "Api Token", "Notes", "Remove"])
  end

  it "leaves the title of the panel around the inputs as a heading before them" do
    expect(contents.first["layout"].to_json).to include("New Plan")
    expect(nodes_of(contents.first["layout"], "panel").pluck("title")).not_to include("New Plan")
    expect(contents.size).to eq(1)
  end

  it "carries no html and no frame, so the form counts as typed" do
    expect(sections.flat_map { it["fields"] }.pluck("control")).not_to include("html")
    expect(nodes_of(contents.first["layout"], "html")).to be_empty
    expect(nodes_of(contents.first["layout"], "frame")).to be_empty
  end

  it "counts as typed for the doctor, so the legacy inventory doesn't call the form html-heavy" do
    tally = ReactiveAdmin::Doctor::Tally.fields(sections)
    items = ReactiveAdmin::LegacyInventory.new(user: admin).run

    expect(tally).to include(html: 0, typed: be > 8)
    expect(items.select { it.key == "accounts" && it.category == "html_heavy" }).to be_empty
  end

  it "masks secrets the way a show row does" do
    row = nodes_of(contents.first["layout"], "attributes_table").first["rows"].find { it["label"] == "Api Token" }

    expect(row["value"]).to eq([{"type" => "masked"}])
    expect(response.body).not_to include("tok_live_123")
  end

  it "turns the DSL's own control into an action and stored markup into none" do
    rows = nodes_of(contents.first["layout"], "attributes_table").first["rows"].to_h { [it["label"], it["value"]] }

    expect(rows["Remove"].pluck("type")).to eq(%w[action])
    expect(rows["Notes"].to_json).not_to match(/Totally safe|"type":"(action|frame|iframe)"/)
  end

  it "shows a notice when there is nothing to change" do
    Account.delete_all
    nodes = contents.first["layout"]

    expect(nodes_of(nodes, "text").pluck("text")).to include("Current plan required")
    expect(sections.size).to eq(1)
  end

  it "stays out of the write schema and out of what a write carries" do
    config = ReactiveAdmin::Registry.find("accounts")
    schema = ReactiveAdmin::OpenApi::WriteSchema.new(config, sections.map { it.deep_symbolize_keys }, options_path: "/x").schema

    expect(schema[:properties]["account"][:properties].keys).to eq(%w[author_id plan_id sponsor_id])
  end

  it "takes no part in a write" do
    api(:post, "/api/admin/accounts", {account: {author_id: bob.id, plan_id: plan.id}}, schema: "WriteResult")

    expect(response).to have_http_status(:created)
    expect(Account.last).to have_attributes(author_id: bob.id, plan_id: plan.id)
  end
end
