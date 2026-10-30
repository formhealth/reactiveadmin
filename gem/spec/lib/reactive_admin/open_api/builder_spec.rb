RSpec.describe ReactiveAdmin::OpenApi::Builder do
  include_context "with a blog"

  let(:doc) { described_class.new(admin, controller: nil, full: false).call }

  it "builds what OpenApi.build does" do
    expect(doc).to eq(ReactiveAdmin::OpenApi.build(admin))
  end

  it "leaves out a resource whose document can't be built, and reports it" do
    original = ReactiveAdmin::OpenApi::ResourceDoc.instance_method(:call)
    allow_any_instance_of(ReactiveAdmin::OpenApi::ResourceDoc).to receive(:call) do |resource_doc|
      raise "boom" if resource_doc.instance_variable_get(:@key) == "notes"

      original.bind_call(resource_doc)
    end
    allow(ReactiveAdmin::Degradation).to receive(:record)

    expect(doc["tags"].pluck("name")).to include("posts")
    expect(doc["tags"].pluck("name")).not_to include("notes")
    expect(ReactiveAdmin::Degradation).to have_received(:record).with(hash_including(kind: :openapi_document_dropped))
  end

  it "groups what the menu doesn't place under Other, and always lists Meta last" do
    groups = doc["x-tagGroups"]

    expect(groups.pluck("name").last).to eq("Meta")
    expect(groups.find { it["name"] == "Other" }["tags"]).to include("tickets", "notes")
  end

  it "keeps groups when the menu can't be read" do
    allow_any_instance_of(ReactiveAdmin::Manifest).to receive(:menu).and_raise(RuntimeError)

    expect(doc["x-tagGroups"].to_h { [it["name"], it["tags"]] }["Other"]).to include("posts")
  end

  it "refuses a generated schema that would replace one of core's" do
    allow_any_instance_of(ReactiveAdmin::OpenApi::ResourceDoc).to receive(:schemas).and_return({"Node" => {type: "object"}})

    expect { doc }.to raise_error(/clashes with core's/)
  end
end
