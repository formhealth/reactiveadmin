RSpec.describe "reactiveadmin.gemspec" do
  root = File.expand_path("../..", __dir__)
  let(:files) { Dir.chdir(root) { Gem::Specification.load("reactiveadmin.gemspec").files } }

  it "packages every file the gem reads at runtime" do
    runtime = [ReactiveAdmin::OpenApi::Core::PATH, ReactiveAdmin::Embed::BRIDGE].map { Pathname(it).relative_path_from(root).to_s }

    expect(files).to include(*runtime)
  end
end
