require "rails_helper"

RSpec.describe ReactiveAdmin::AA do
  it "reports the installed ActiveAdmin version" do
    expect(described_class.version).to eq(Gem::Version.new(ActiveAdmin::VERSION))
  end

  it "uses the AA 3 implementation here" do
    expect(described_class.v4?).to be(false)
    expect(described_class.singleton_class.include?(described_class::V3)).to be(true)
  end

  describe "AA 4 stub" do
    let(:v3) { described_class::V3.public_instance_methods }

    it "only overrides methods of the contract" do
      expect(described_class::V4.public_instance_methods(false) - v3).to be_empty
    end

    it "names the change behind every unimplemented method" do
      described_class::V4::TODO.each do |name, change|
        expect(change).to be_present
        expect(v3).to include(name)
        expect { Object.new.extend(described_class::V4).public_send(name) }.to raise_error(NotImplementedError, /#{Regexp.escape(name.to_s)}/)
      end
    end

    it "asks for AA 4's renamed format guard" do
      expect(described_class::V4.instance_method(:format_guard_names).bind_call(Object.new)).to eq(%i[restrict_download_format_access!])
    end
  end

  describe "default menu membership" do
    def page(key) = ReactiveAdmin::Registry.pages.find { it.underscored_resource_name == key }

    it "leaves out a `menu false` page that `belongs_to`, though AA reports it as included" do
      expect(page("post_digests").include_in_menu?).to be(true)
      expect(described_class.in_menu?(page("post_digests"))).to be(false)
      expect(described_class.menu_placement(page("post_digests"))).to be_nil
    end

    it "keeps listed entries" do
      expect(described_class.in_menu?(page("dashboard"))).to be(true)
    end

    it "treats a menu named by a proc as the default menu" do
      dynamic = ActiveAdmin::Page.new(ActiveAdmin.application.namespace(:admin), "Dynamic", {})
      dynamic.menu_item_options = {menu_name: -> { :user }}

      expect(described_class.in_menu?(dynamic)).to be(true)
    end
  end

  it "hooks the format guard and layout names AA 3 uses" do
    expect(described_class.format_guard_names).to eq(%i[restrict_format_access!])
    expect(ReactiveAdmin::ApiErrors.private_instance_methods).to include(:restrict_format_access!)
    expect(ReactiveAdmin::Frame.private_instance_methods).to include(described_class.layout_hook)
    expect(ReactiveAdmin::Embed.private_instance_methods).to include(described_class.layout_hook)
  end
end
