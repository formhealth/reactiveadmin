RSpec.describe ReactiveAdmin::Ui::ClientBuild do
  let(:root) { Pathname(Dir.mktmpdir) }
  let(:source) { root.join("repo/apps/standalone").tap { FileUtils.mkdir_p(it) && it.join("package.json").write("{}") } }
  let(:out) { root.join("public/reactiveadmin") }
  let(:calls) { [] }
  let(:runner) do
    ->(env, command, chdir) do
      calls << [env, command, chdir.to_s]
      FileUtils.mkdir_p(out) && out.join("manifest.json").write("{}") if command.include?("build:host")
    end
  end

  def build(**) = described_class.new(out:, prefix: "/reactiveadmin", source:, root:, runner:, **)

  after { FileUtils.remove_entry(root) }

  it "installs and builds from the workspace, telling Vite where to write and where files are served from" do
    expect(build.call).to eq(out)

    workspace = source.parent.parent.to_s
    expect(calls).to eq([
      [{}, %w[pnpm install --frozen-lockfile], workspace],
      [{"RA_OUT_DIR" => out.to_s, "RA_ASSET_PREFIX" => "/reactiveadmin/"}, %w[pnpm --filter standalone build:host], workspace]
    ])
  end

  it "refuses to write outside the app, since the build empties its target" do
    ["/", root.to_s, "/etc"].each do |dir|
      expect { described_class.new(out: dir, source:, root:, runner:).call }.to raise_error(described_class::Error, /inside/)
    end
    expect(calls).to be_empty
  end

  it "explains a missing client source" do
    expect { described_class.new(out:, source: root.join("nowhere"), root:, runner:).call }.to raise_error(described_class::Error, /REACTIVEADMIN_CLIENT_SRC/)
  end

  it "fails when the build leaves no manifest" do
    quiet = ->(*) {}

    expect { described_class.new(out:, source:, root:, runner: quiet).call }.to raise_error(described_class::Error, /manifest/)
  end
end
