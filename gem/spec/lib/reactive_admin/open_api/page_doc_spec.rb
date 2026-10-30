RSpec.describe ReactiveAdmin::OpenApi::PageDoc do
  include_context "with a blog"

  let(:context) { ReactiveAdmin::OpenApi::Context.new(admin, controller: nil, full: false) }
  let(:page) { ReactiveAdmin::Registry.find_page("dashboard") }
  let(:doc) { described_class.new(context, page).call }

  it "documents the page and tags it by key" do
    expect(doc[:tag]).to include(name: "page:dashboard", "x-displayName": "Dashboard")
    expect(doc[:paths]["/api/admin/_pages/dashboard"]["get"]).to include(operationId: "getDashboardPage", tags: ["page:dashboard"])
  end

  it "documents page actions, writes needing the CSRF token" do
    action = doc[:paths]["/api/admin/dashboard/recalc"]["post"]

    expect(action).to include(operationId: "dashboardRecalc", security: [{"sessionCookie" => [], "csrfToken" => []}, {"bearerAuth" => []}])
    expect(action[:requestBody]).to eq("$ref": "#/components/requestBodies/ActionParams")
  end

  it "names the tag from the page's menu key" do
    expect(described_class.tag_name(page)).to eq("page:dashboard")
  end

  it "leaves out an action the user may not take" do
    allow(context).to receive(:authorized?).and_return(true)
    allow(context).to receive(:authorized?).with(:recalc, page, page).and_return(false)

    expect(doc[:paths].keys).to eq(["/api/admin/_pages/dashboard"])
  end
end
