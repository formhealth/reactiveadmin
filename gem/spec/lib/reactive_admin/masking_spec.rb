RSpec.describe ReactiveAdmin::Masking do
  around do |example|
    config = ReactiveAdmin.config
    filters = Rails.application.config.filter_parameters.dup
    example.run
  ensure
    config.masked_attributes = []
    config.mask_filter_parameters = true
    Rails.application.config.filter_parameters.replace(filters)
  end

  let(:categories) { ReactiveAdmin::Registry.find("categories") }

  it "matches Rails filter_parameters by name, the way the log filter does" do
    Rails.application.config.filter_parameters << :token << /\Asecret_\w+\z/

    expect(described_class.attribute?(:refresh_token)).to be(true)
    expect(described_class.attribute?("secret_word")).to be(true)
    expect(described_class.attribute?(:title)).to be(false)
  end

  it "ignores filter_parameters when turned off" do
    Rails.application.config.filter_parameters << :token
    ReactiveAdmin.config.mask_filter_parameters = false

    expect(described_class.attribute?(:refresh_token)).to be(false)
  end

  it "masks config.masked_attributes exactly or by pattern" do
    ReactiveAdmin.config.mask_filter_parameters = false
    ReactiveAdmin.config.masked_attributes = [:ssn, /_secret\z/]

    expect([:ssn, :client_secret, :ssn_last4].map { described_class.attribute?(it) }).to eq([true, true, false])
  end

  it "masks what a resource declares with reactive { mask }" do
    expect(described_class.attribute?(:api_token, categories)).to be(true)
    expect(described_class.attribute?(:api_token, ReactiveAdmin::Registry.find("posts"))).to be(false)
  end

  describe ".node" do
    it "masks present values only" do
      expect(described_class.node(categories, :api_token, "abc")).to eq(type: "masked")
      expect(described_class.node(categories, :api_token, "")).to be_nil
      expect(described_class.node(categories, :name, "abc")).to be_nil
    end
  end

  describe ".keep_unchanged" do
    it "drops blank masked values, nested ones included, and keeps the rest" do
      params = ActionController::Parameters.new(name: "", api_token: "", children_attributes: {"0" => {api_token: "", label: ""}}, other: [{api_token: nil}])
      described_class.keep_unchanged(params, categories)

      expect(params.to_unsafe_h).to eq("name" => "", "children_attributes" => {"0" => {"label" => ""}}, "other" => [{}])
    end

    it "protects only what the record holds" do
      params = ActionController::Parameters.new(api_token: "")
      described_class.keep_unchanged(params, categories, Category.new(api_token: nil))
      expect(params.to_unsafe_h).to eq("api_token" => "")

      described_class.keep_unchanged(params, categories, Category.new(api_token: "stored"))
      expect(params.to_unsafe_h).to eq({})
    end

    it "keeps a masked value that was actually submitted" do
      params = ActionController::Parameters.new(api_token: "new")
      described_class.keep_unchanged(params, categories)

      expect(params[:api_token]).to eq("new")
    end
  end
end
