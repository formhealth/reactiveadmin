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

  it "defaults to public/reactiveadmin and accepts a callable directory" do
    ReactiveAdmin.config.ui.client_assets = nil
    expect(described_class.root).to eq(Rails.root.join("public/reactiveadmin"))

    ReactiveAdmin.config.ui.client_assets = -> { "/somewhere" }
    expect(described_class.root).to eq(Pathname("/somewhere"))
  end

  it "joins the prefix without doubling slashes" do
    ReactiveAdmin.config.ui.asset_prefix = "/ui/"

    expect(described_class.url("assets/a.js")).to eq("/ui/assets/a.js")
  end
end
