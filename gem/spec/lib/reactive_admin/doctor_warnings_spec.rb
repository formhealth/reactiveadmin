RSpec.describe ReactiveAdmin::Doctor, ".config_warnings" do
  def kinds = described_class.config_warnings.pluck(:kind)

  def in_env(name)
    allow(Rails).to receive(:env).and_return(ActiveSupport::EnvironmentInquirer.new(name))
  end

  around do |example|
    expose = ReactiveAdmin.config.expose
    example.run
  ensure
    ReactiveAdmin.config.expose = expose
  end

  it "warns about expose = :all in a production-like environment" do
    in_env("production")
    ReactiveAdmin.config.expose = :all

    expect(kinds).to include(:expose_all)
  end

  it "accepts expose = :listed, and :all where the environment is local" do
    in_env("production")
    ReactiveAdmin.config.expose = :listed
    expect(kinds).not_to include(:expose_all)

    in_env("development")
    ReactiveAdmin.config.expose = :all
    expect(kinds).not_to include(:expose_all)
  end

  it "warns when Rails.cache is a null store" do
    allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::NullStore.new)

    expect(kinds).to include(:null_cache_store)
  end

  it "is quiet with a real cache store" do
    allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)

    expect(kinds).not_to include(:null_cache_store)
  end

  it "reaches the report's diagnostics and text" do
    allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::NullStore.new)
    report = described_class.run(sample: false)

    expect(report[:diagnostics].pluck(:kind)).to include("null_cache_store")
    expect(described_class::Table.new(report).to_s).to include("Configuration warnings", "rate limits and the meta cache are disabled")
  end
end
