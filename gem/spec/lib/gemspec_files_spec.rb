RSpec.describe "reactiveadmin.gemspec" do
  root = File.expand_path("../..", __dir__)
  let(:files) { Dir.chdir(root) { Gem::Specification.load("reactiveadmin.gemspec").files } }

  it "packages every file the gem reads at runtime" do
    runtime = [ReactiveAdmin::OpenApi::Core::PATH, ReactiveAdmin::Embed::BRIDGE].map { Pathname(it).relative_path_from(root).to_s }

    expect(files).to include(*runtime)
  end

  it "packages the README, LICENSE and CHANGELOG once `rake package` has copied them in" do
    Dir.mktmpdir do |dir|
      docs = %w[README.md LICENSE CHANGELOG.md]
      FileUtils.touch(docs.map { File.join(dir, it) })
      gemspec = File.read(File.join(root, "reactiveadmin.gemspec")).sub(/^require_relative.*\n/, "")
      File.write(File.join(dir, "reactiveadmin.gemspec"), gemspec)

      expect(Dir.chdir(dir) { Gem::Specification.load(File.join(dir, "reactiveadmin.gemspec")).files }).to include(*docs)
    end
  end

  it "packages the prebuilt client when it has been built" do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "vendor/client"))
      FileUtils.touch(File.join(dir, "vendor/client/manifest.json"))
      gemspec = File.read(File.join(root, "reactiveadmin.gemspec")).sub(/^require_relative.*\n/, "")
      File.write(File.join(dir, "reactiveadmin.gemspec"), gemspec)

      expect(Dir.chdir(dir) { Gem::Specification.load(File.join(dir, "reactiveadmin.gemspec")).files }).to include("vendor/client/manifest.json")
    end
  end
end
