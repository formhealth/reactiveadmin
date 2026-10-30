RSpec.describe ReactiveAdmin::Manifest do
  include_context "with a blog"

  let(:controller) { ReactiveAdmin::Doctor::Sample.new(Struct.new(:controller).new(ReactiveAdmin::ManifestController), admin).controller }

  it "lists the resource summaries the user may open" do
    keys = described_class.new(controller).resources.pluck(:key)

    expect(keys).to include("posts", "authors")
    expect(keys.include?("categories")).to eq(can_read_categories?(admin))
  end

  it "lists every resource for a permissive authorizer, whoever the controller's user is" do
    resources = described_class.new(controller, authorizer: ReactiveAdmin::Authorizer::Permissive.new).resources

    expect(resources.pluck(:key)).to include("categories")
    expect(resources.find { it[:key] == "posts" }[:permissions]).to include(index: true, destroy: true)
  end

  it "builds the menu over the resources it is given" do
    manifest = described_class.new(controller)
    ids = manifest.menu(manifest.resources).as_json.flat_map { [it[:id], *it[:children].pluck(:id)] }

    expect(ids).to include("content", "dashboard")
  end

  it "serves the same menu and resources as before through as_json" do
    json = described_class.new(controller).as_json

    expect(json.keys).to eq(%i[schema_version site menu resources])
    expect(json[:resources]).to eq(described_class.new(controller).resources)
  end
end
