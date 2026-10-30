RSpec.describe ReactiveAdmin::Exposure do
  let(:config) { ReactiveAdmin.config }
  let(:posts) { ReactiveAdmin::Registry.find("posts") }
  let(:comments) { ReactiveAdmin::Registry.find("comments") }
  let(:dashboard) { ReactiveAdmin::Registry.find_page("dashboard") }

  around do |example|
    ReactiveAdmin::MenuOverlay.reset!
    example.run
  ensure
    config.expose = :all
    config.exposed_resources = []
    ReactiveAdmin::Registry.resources.each { it.reactive_options.delete(:expose) }
    ReactiveAdmin::MenuOverlay.reset!
  end

  it "allows everything by default" do
    expect([posts, comments, dashboard].map { described_class.allowed?(it) }).to eq([true, true, true])
  end

  it "rejects other modes" do
    expect { config.expose = :some }.to raise_error(ArgumentError, /expose must be/)
  end

  context "when listed" do
    before do
      config.expose = :listed
      allow(ReactiveAdmin::Registry.namespace).to receive(:root_to).and_return("posts#index")
    end

    it "denies what nothing names" do
      expect([posts, comments, dashboard].map { described_class.allowed?(it) }).to eq([false, false, false])
    end

    it "allows the namespace's root page without a listing" do
      allow(ReactiveAdmin::Registry.namespace).to receive(:root_to).and_return("dashboard#index")

      expect(described_class.allowed?(dashboard)).to be(true)
    end

    it "allows resources and pages placed in the overlay" do
      ReactiveAdmin.menu do
        resources :posts
        page :dashboard
      end

      expect([posts, dashboard].map { described_class.allowed?(it) }).to eq([true, true])
    end

    it "allows keys in exposed_resources, symbols included" do
      config.exposed_resources = [:posts]

      expect(described_class.allowed?(posts)).to be(true)
    end

    it "follows later changes to the list" do
      expect(described_class.allowed?(posts)).to be(false)
      config.exposed_resources = %w[posts]

      expect(described_class.allowed?(posts)).to be(true)
    end

    it "honours `expose true` and lets `expose false` win over a listing" do
      posts.reactive_options[:expose] = true
      expect(described_class.allowed?(posts)).to be(true)

      config.exposed_resources = %w[posts]
      posts.reactive_options[:expose] = false
      expect(described_class.allowed?(posts)).to be(false)
    end

    it "needs a nested-only resource to be listed and its parent exposed" do
      config.exposed_resources = %w[comments]
      expect(described_class.allowed?(comments)).to be(false)

      config.exposed_resources = %w[comments posts]
      expect(described_class.allowed?(comments)).to be(true)

      config.exposed_resources = %w[posts]
      expect(described_class.allowed?(comments)).to be(false)
    end
  end

  describe ".audit" do
    let(:user) { create_admin }

    it "reports listed keys that match nothing" do
      config.exposed_resources = %w[posts nonsense]

      expect(described_class.audit).to eq([{kind: :exposure_unknown_key, key: "nonsense"}])
    end

    it "lists what the policy permits but the host has not exposed" do
      config.expose = :listed
      config.exposed_resources = %w[posts]
      finding = described_class.audit(user:).find { it[:kind] == :exposure_permitted_not_exposed }

      keys = finding[:keys].split(", ")
      expect(keys).to include("categories", "tags")
      expect(keys).not_to include("posts")
    end

    it "reports nothing permitted-but-unexposed when everything is served" do
      expect(described_class.audit(user:)).to be_empty
    end
  end
end
