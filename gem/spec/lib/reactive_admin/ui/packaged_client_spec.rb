RSpec.describe ReactiveAdmin::Ui::PackagedClient do
  let(:root) { Pathname(Dir.mktmpdir) }
  let(:dir) { root.join("vendor/client") }
  let(:current) { described_class.expected }

  after { FileUtils.remove_entry(root) }

  def install(info = current)
    write_client_build(dir)
    dir.join(described_class::INFO).write(info.to_json) if info
  end

  describe ".usable?" do
    it "accepts a build stamped for this gem version, schema version and prefix" do
      install

      expect(described_class.usable?(dir)).to be(true)
    end

    it "refuses a build with no manifest, no stamp or an unreadable stamp" do
      expect(described_class.usable?(dir)).to be(false)

      install(nil)
      expect(described_class.usable?(dir)).to be(false)

      dir.join(described_class::INFO).write("[")
      described_class.reset!
      expect(described_class.usable?(dir)).to be(false)
    end

    it "refuses a build made for another gem version, schema version or prefix, and says so without values" do
      allow(Rails.logger).to receive(:warn)

      {"gem_version" => "0.0.1", "schema_version" => 1, "prefix" => "/other"}.each do |key, value|
        install(current.merge(key => value))
        described_class.reset!

        expect(described_class.usable?(dir)).to be(false)
      end
      expect(Rails.logger).to have_received(:warn).with(/ignoring the packaged client/).exactly(3).times
    end

    it "serves under any prefix, since the build refers to its files relatively" do
      install
      ReactiveAdmin.config.ui.asset_prefix = "/admin-ui"

      expect(described_class.usable?(dir)).to be(true)
    ensure
      ReactiveAdmin.config.ui.asset_prefix = "/reactiveadmin"
    end
  end

  describe ".build!" do
    let(:source) { root.join("repo/apps/standalone").tap { FileUtils.mkdir_p(it.join("src/lib")) && it.join("package.json").write("{}") } }
    let(:runner) { ->(_env, command, _chdir) { write_client_build(dir) if command.include?("build:host") } }

    def schema(version) = source.join(described_class::SCHEMA_SOURCE).write("export const SCHEMA_VERSION = #{version}\n")

    it "builds under the gem's root and stamps the result" do
      schema(ReactiveAdmin::Manifest::SCHEMA_VERSION)

      expect(described_class.build!(dir:, source:, runner:)).to eq(dir)
      expect(described_class.info(dir)).to eq(current)
    end

    it "fails when the client expects another manifest schema version" do
      schema(ReactiveAdmin::Manifest::SCHEMA_VERSION + 1)

      expect { described_class.build!(dir:, source:, runner:) }.to raise_error(described_class::Error, /schema_version/)
      expect(described_class.info(dir)).to be_nil
    end
  end

  it "agrees with the client source in this repository" do
    source = ReactiveAdmin::Ui::ClientBuild.source.join(described_class::SCHEMA_SOURCE)
    skip "no client source next to the gem" unless source.exist?

    expect(source.read[/SCHEMA_VERSION\s*=\s*(\d+)/, 1].to_i).to eq(ReactiveAdmin::Manifest::SCHEMA_VERSION)
  end
end
