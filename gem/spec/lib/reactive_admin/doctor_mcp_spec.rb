RSpec.describe ReactiveAdmin::Doctor, "MCP surface" do
  let(:categories) { ReactiveAdmin::Registry.find("categories") }

  def surface(report = described_class.run(sample: false)) = report[:mcp][:resources].index_by { it[:key] }

  around do |example|
    sensitive = ReactiveAdmin.config.sensitive_resources
    saved = categories.reactive_options[:mcp]
    example.run
  ensure
    ReactiveAdmin.config.sensitive_resources = sensitive
    saved ? categories.reactive_options[:mcp] = saved : categories.reactive_options.delete(:mcp)
  end

  it "lists each resource's mode with the tools and actions it leaves agents" do
    rows = surface

    expect(rows["posts"]).to include(kind: "resource", mode: "full")
    expect(rows["posts"][:tools]).to include("list_records", "get_record", "get_form", "create_record", "update_record", "delete_record", "run_action")
    expect(rows["posts"][:actions]).to include("archive", "import", "feature")
    expect(rows["tags"]).to include(mode: "read_only", tools: %w[list_records get_record], actions: [])
    expect(rows["dashboard"]).to include(kind: "page", mode: "full", tools: %w[get_page], actions: [])
  end

  it "reports a permitted batch destroy as an action, and run_action with it" do
    tags = ReactiveAdmin::Registry.find("tags")
    ReactiveAdmin::Mcp::Access.declare(tags, :full)

    expect(surface["tags"]).to include(tools: include("run_action"), actions: ["destroy"])
  ensure
    tags.reactive_options.delete(:mcp)
  end

  it "leaves out of the surface what the api guards refuse" do
    rows = surface

    expect(rows["admin_users"][:tools]).not_to include("create_record", "delete_record")
    expect(rows["admin_users"][:actions]).not_to include("impersonate", "sweep", "promote")
    expect(rows["profiles"]).to include(tools: [], actions: [])
  end

  it "shows a :none resource with nothing" do
    ReactiveAdmin::Mcp::Access.declare(categories, :none)

    expect(surface["categories"]).to include(mode: "none", tools: [], actions: [])
  end

  it "warns on :full for a resource that masks attributes or is sensitive" do
    expect(described_class.run(sample: false)[:diagnostics].pluck(:kind)).not_to include("mcp_full_sensitive")

    ReactiveAdmin::Mcp::Access.declare(categories, :full)
    ReactiveAdmin.config.sensitive_resources = [:posts]
    report = described_class.run(sample: false)
    warned = report[:diagnostics].select { it[:kind] == "mcp_full_sensitive" }.pluck(:resource)

    expect(warned).to contain_exactly("categories", "posts")
    expect(described_class::Table.new(report).to_s).to include("Configuration warnings", "categories is mcp :full")
  end

  it "prints the section, and skips it where MCP is off" do
    expect(described_class::Table.new(described_class.run(sample: false)).to_s).to include("MCP surface (default read_only)", "resource tags: read_only; tools list_records, get_record")

    allow(ReactiveAdmin.config.mcp).to receive(:enabled).and_return(false)
    report = described_class.run(sample: false)
    expect(report[:mcp]).to be_nil
    expect(described_class::Table.new(report).to_s).not_to include("MCP surface")
  end
end
