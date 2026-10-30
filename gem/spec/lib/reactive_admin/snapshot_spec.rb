RSpec.describe ReactiveAdmin::TestSupport do
  describe "configuration" do
    subject(:config) { ReactiveAdmin::Configuration.new }

    it "restores settings, including collections edited in place" do
      snapshot = described_class.snapshot_config(config)

      config.require_lock = false
      config.masked_attributes << :secret
      described_class.restore_config(config, snapshot)

      expect(config.require_lock).to be true
      expect(config.masked_attributes).to eq []
    end

    it "is not changed by later edits to the snapshot's source" do
      config.masked_attributes << :a
      snapshot = described_class.snapshot_config(config)
      config.masked_attributes << :b

      described_class.restore_config(config, snapshot)
      config.masked_attributes << :c

      expect(snapshot[:@masked_attributes]).to eq [:a]
    end
  end

  describe "option sources" do
    subject(:sources) { ReactiveAdmin::OptionSources.new }

    it "drops sources registered after the snapshot" do
      sources.source(:kept, -> { [] })
      snapshot = described_class.snapshot_sources(sources)

      sources.source(:added, -> { [] })
      described_class.restore_sources(sources, snapshot)

      expect(sources.names).to eq [:kept]
    end
  end

  describe "menu overlay" do
    around do |example|
      snapshot = described_class.snapshot_overlay
      ReactiveAdmin::MenuOverlay.reset!
      example.run
    ensure
      described_class.restore_overlay(snapshot)
    end

    it "restores the declared overlay and invalidates what was cached against it" do
      ReactiveAdmin::MenuOverlay.define { resources :notes }
      snapshot = described_class.snapshot_overlay
      version = ReactiveAdmin::MenuOverlay.version

      ReactiveAdmin::MenuOverlay.define { resources :tickets }
      described_class.restore_overlay(snapshot)

      expect(ReactiveAdmin::MenuOverlay.keys(:resource)).to eq %w[notes]
      expect(ReactiveAdmin::MenuOverlay.version).to be > version
    end
  end
end
