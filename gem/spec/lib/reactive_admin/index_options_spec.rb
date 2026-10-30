RSpec.describe ReactiveAdmin::IndexOptions do
  include_context "with a blog"

  def declared(key) = described_class.declared(ReactiveAdmin::Registry.find(key))

  it "counts what a registration declares" do
    expect(declared("posts")).to include(scope_groups: 1, sidebars: 3)
    expect(declared("notes")).to include(
      extra_views: 3, check_boxes_filters: 2, order_by: 1, title: 1, blank_slate_link: 1, row_class: 1, sidebars: 1
    )
    expect(declared("tags")).to include(download_links: 1, per_page: 1, paginator: 1, pagination_total: 1)
    expect(declared("taggings")).to eq(custom_index_as: 1)
  end

  it "leaves out what is not used" do
    expect(declared("categories")).not_to include(:scope_groups, :sidebars, :title)
  end

  describe "in a doctor run" do
    let(:report) { ReactiveAdmin::Doctor.run(user: admin) }
    let(:row) { report[:resources].find { it[:key] == "notes" } }

    it "adds what the sampled index shows of the index block" do
      Note.create!(title: "!Alpha")

      expect(row[:index_options]).to include(index_column: 1, column_classes: 2, aligned_columns: 4, row_actions_menu: 1, row_tones: 1, extra_views: 3)
      expect(row[:index_options]).not_to include(:default_actions_off)
    end

    it "tallies the options across resources" do
      expect(report[:summary][:index_options]).to include(extra_views: 1, custom_index_as: 1, default_actions_off: 2)
      expect(ReactiveAdmin::Doctor::Table.new(report).to_s).to include("index options (resources using each)")
    end
  end
end
