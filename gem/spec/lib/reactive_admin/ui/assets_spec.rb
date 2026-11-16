RSpec.describe ReactiveAdmin::Ui::Assets do
  around { |example| with_ui { example.run } }

  let(:dir) { Pathname(ReactiveAdmin.config.ui.client_assets) }

  it "names the entry and what it loads first, from the manifest" do
    tags = described_class.tags

    expect(tags.script).to eq("/reactiveadmin/assets/index-abc123.js")
    expect(tags.styles).to eq(%w[/reactiveadmin/assets/index-abc123.css /reactiveadmin/assets/vendor-9f.css])
    expect(tags.preloads).to eq(%w[/reactiveadmin/assets/vendor-9f.js])
  end

  it "names the classic dashboard's script, when the build has one" do
    expect(described_class.toggle_script).to eq("/reactiveadmin/assets/uiToggle-77.js")

    dir.join("manifest.json").write(UiHelpers::MANIFEST.except("src/classic/uiToggle.ts").to_json)
    expect(described_class.toggle_script).to be_nil
  end

  it "follows static imports once, even around a cycle" do
    manifest = UiHelpers::MANIFEST.merge("_vendor-9f.js" => UiHelpers::MANIFEST["_vendor-9f.js"].merge("imports" => ["index.html", "_gone.js"]))
    dir.join("manifest.json").write(manifest.to_json)

    expect(described_class.tags.preloads).to eq(%w[/reactiveadmin/assets/vendor-9f.js])
  end

  it "is ready only with a manifest that has the entry" do
    expect(described_class.ready?).to be(true)

    dir.join("manifest.json").write("{}")
    expect(described_class.ready?).to be(false)

    dir.join("manifest.json").write("[")
    expect(described_class.ready?).to be(false)

    dir.join("manifest.json").delete
    expect(described_class.ready?).to be(false)
    expect(described_class.tags).to be_nil
  end

  it "picks up a new build without a restart" do
    expect(described_class.tags.script).to end_with("index-abc123.js")

    manifest = UiHelpers::MANIFEST.merge("index.html" => UiHelpers::MANIFEST["index.html"].merge("file" => "assets/index-new.js"))
    dir.join("manifest.json").write(manifest.to_json)
    later = Time.now + 60
    File.utime(later, later, dir.join("manifest.json"))

    expect(described_class.tags.script).to end_with("index-new.js")
  end

  context "without a configured directory" do
    let(:packaged) { Pathname(Dir.mktmpdir) }

    before do
      ReactiveAdmin.config.ui.client_assets = nil
      stub_const("ReactiveAdmin::Ui::PackagedClient::DIR", packaged)
      ReactiveAdmin::Ui::PackagedClient.reset!
    end

    after { FileUtils.remove_entry(packaged) }

    it "defaults to public/reactiveadmin and accepts a callable directory" do
      expect(described_class.root).to eq(Rails.root.join("public/reactiveadmin"))
      expect(described_class.build_dir).to eq(described_class.root)

      ReactiveAdmin.config.ui.client_assets = -> { "/somewhere" }
      expect(described_class.root).to eq(Pathname("/somewhere"))
    end

    it "serves the build packaged in the gem when it matches this gem" do
      write_client_build(packaged)
      packaged.join(ReactiveAdmin::Ui::PackagedClient::INFO).write(ReactiveAdmin::Ui::PackagedClient.expected.to_json)

      expect(described_class.root).to eq(packaged)
      expect(described_class.ready?).to be(true)
      expect(described_class.build_dir).to eq(Rails.root.join("public/reactiveadmin"))
    end

    it "falls back to the host's build when the packaged one was made for another version" do
      write_client_build(packaged)
      packaged.join(ReactiveAdmin::Ui::PackagedClient::INFO).write(ReactiveAdmin::Ui::PackagedClient.expected.merge("gem_version" => "0.0.1").to_json)

      expect(described_class.root).to eq(Rails.root.join("public/reactiveadmin"))
    end

    it "serves the host's own build over the packaged one" do
      write_client_build(packaged)
      packaged.join(ReactiveAdmin::Ui::PackagedClient::INFO).write(ReactiveAdmin::Ui::PackagedClient.expected.to_json)
      host = Pathname(Dir.mktmpdir)
      write_client_build(host)
      allow(described_class).to receive(:build_dir).and_return(host)

      expect(described_class.root).to eq(host)
    ensure
      FileUtils.remove_entry(host)
    end

    it "lets a configured directory win over the packaged build" do
      write_client_build(packaged)
      packaged.join(ReactiveAdmin::Ui::PackagedClient::INFO).write(ReactiveAdmin::Ui::PackagedClient.expected.to_json)
      ReactiveAdmin.config.ui.client_assets = "/mine"

      expect(described_class.root).to eq(Pathname("/mine"))
    end
  end

  it "joins the prefix without doubling slashes" do
    ReactiveAdmin.config.ui.asset_prefix = "/ui/"

    expect(described_class.url("assets/a.js")).to eq("/ui/assets/a.js")
  end
end
