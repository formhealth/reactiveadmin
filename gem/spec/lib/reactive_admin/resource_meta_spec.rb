RSpec.describe ReactiveAdmin::ResourceMeta do
  include_context "with a blog"

  let(:config) { ReactiveAdmin::Registry.find("posts") }
  let(:controller) { ReactiveAdmin::Doctor::Sample.new(config, admin).controller }
  let(:meta) { described_class.new(controller) }

  describe "#declared" do
    it "is what the resource declares, without action items or option lists" do
      declared = meta.declared

      expect(declared.keys).to match_array(%i[filters batch_actions scopes default_scope download_formats])
      expect(declared[:scopes].pluck(:id)).to include("all", "draft")
      expect(declared[:default_scope]).to eq("all")
      expect(declared[:download_formats]).to eq(%w[csv])
      expect(declared[:filters].find { it[:name] == "status" }).not_to have_key(:options)
    end

    it "is the base of what `dynamic` serves, which adds option lists and action items" do
      dynamic = meta.dynamic

      expect(dynamic.keys).to include(:action_items, :filters, :scopes)
      expect(dynamic[:filters].find { it[:name] == "status" }).to have_key(:options)
    end
  end

  describe ".code_version" do
    it "is the configured version when there is one" do
      ReactiveAdmin.config.meta_cache_version = -> { "v7" }

      expect(described_class.code_version(config)).to eq("v7")
    ensure
      ReactiveAdmin.config.meta_cache_version = nil
    end

    it "follows the seed's identity while code reloads, and the process otherwise" do
      allow(Rails.application.config).to receive(:enable_reloading).and_return(true)
      expect(described_class.code_version(config)).to eq(config.object_id)

      allow(Rails.application.config).to receive(:enable_reloading).and_return(false)
      expect(described_class.code_version(config)).to eq(described_class.code_version(Object.new))
    end
  end
end
