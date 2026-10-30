RSpec.describe ReactiveAdmin::Filters do
  include_context "with a blog"

  let(:config) { ReactiveAdmin::Registry.find("posts") }
  let(:view) { ReactiveAdmin::Doctor::Sample.new(config, admin).view }

  def filters(**) = described_class.new(config, view, **).call.index_by { it[:name] }

  it "carries option lists by default" do
    expect(filters["status"]).to include(control: "select", options: a_collection_including(a_hash_including(:label, :value)))
  end

  it "points choice controls at _options instead, without reading or listing options" do
    declared = filters(options: false)

    expect(declared["status"]).to include(control: "select", options_path: "/api/admin/posts/_options?context=filter&field=status")
    expect(declared["status"]).not_to have_key(:options)
    expect(declared["category"]).to include(control: "checkboxes", param: "category_id_in", multiple: true)
    expect(declared["title"]).to include(control: "text")
    expect(declared["featured"]).to include(control: "boolean", options: [{label: "Yes", value: "true"}, {label: "No", value: "false"}])
  end
end
