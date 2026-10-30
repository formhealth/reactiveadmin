RSpec.describe ReactiveAdmin::Configuration do
  subject(:config) { described_class.new }

  it "defaults to the admin namespace mounted at /api" do
    expect(config).to have_attributes(namespace: :admin, mount_path: "/api", inline_options_limit: 100, scope_options_by_policy: true)
  end

  it "keys the cached meta payload by user id" do
    expect(config.meta_cache_key.call(Struct.new(:id).new(5))).to eq(5)
  end

  it "has no OpenAPI overrides, and writes the document to openapi/admin.yaml" do
    expect(config.openapi).to have_attributes(info: {}, output: "openapi/admin.yaml", security_schemes: nil)
  end

  it "serves everything the policy permits by default" do
    expect(config).to have_attributes(expose: :all, exposed_resources: [])
  end

  it "authorizes custom actions up front by default" do
    expect(config.authorize_custom_actions).to be(true)
    expect(config.authorize_custom_actions?).to be(true)
  end

  it "accepts :match_active_admin and nothing else" do
    config.authorize_custom_actions = :match_active_admin
    expect(config.authorize_custom_actions?).to be(false)

    expect { config.authorize_custom_actions = false }.to raise_error(ArgumentError, /authorize_custom_actions/)
  end

  describe "ReactiveAdmin.configure" do
    it "yields the shared configuration" do
      expect { |block| ReactiveAdmin.configure(&block) }.to yield_with_args(ReactiveAdmin.config)
    end
  end

  describe "ReactiveAdmin.current_user" do
    let(:controller) { instance_double(ApplicationController, current_admin_user: :default_user, request: ActionDispatch::TestRequest.create) }

    it "uses the namespace's current_user_method" do
      expect(ReactiveAdmin.current_user(controller)).to eq(:default_user)
    end

    it "prefers the configured resolver" do
      original = ReactiveAdmin.config.current_user
      ReactiveAdmin.config.current_user = ->(_) { :custom_user }

      expect(ReactiveAdmin.current_user(controller)).to eq(:custom_user)
    ensure
      ReactiveAdmin.config.current_user = original
    end
  end
end
