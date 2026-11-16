RSpec.describe ReactiveAdmin::Mcp::Access do
  let(:posts) { ReactiveAdmin::Registry.find("posts") }
  let(:tags) { ReactiveAdmin::Registry.find("tags") }
  let(:admin_users) { ReactiveAdmin::Registry.find("admin_users") }
  let(:dashboard) { ReactiveAdmin::Registry.find_page("dashboard") }

  around do |example|
    configs = %w[posts tags admin_users].map { ReactiveAdmin::Registry.find(it) }
    saved = configs.to_h { [it, it.reactive_options[:mcp]] }
    default = ReactiveAdmin.config.mcp.default
    example.run
  ensure
    saved.each { |config, mode| mode ? config.reactive_options[:mcp] = mode : config.reactive_options.delete(:mcp) }
    ReactiveAdmin.config.mcp.default = default
  end

  describe "mode resolution" do
    it "takes config.mcp.default, read-only out of the box" do
      expect(ReactiveAdmin::Configuration.new.mcp.default).to eq(:read_only)
      expect(described_class.mode(tags)).to eq(:read_only)

      ReactiveAdmin.config.mcp.default = :none
      expect(described_class.mode(tags)).to eq(:none)
    end

    it "lets a registration override the default either way" do
      ReactiveAdmin.config.mcp.default = :none
      expect(described_class.mode(posts)).to eq(:full)

      described_class.declare(posts, :none)
      ReactiveAdmin.config.mcp.default = :full
      expect(described_class.mode(posts)).to eq(:none)
    end

    it "reads actions: alone as read-only with those actions" do
      described_class.declare(tags, actions: [:approve, "merge"])

      expect(described_class.mode(tags)).to eq(:read_only)
      expect(described_class.listed(tags)).to eq(%w[approve merge])
    end

    it "refuses an unknown mode, actions with any mode but read-only, and an empty call" do
      expect { described_class.declare(tags, :write) }.to raise_error(ArgumentError, /expected one of/)
      expect { described_class.declare(tags, :full, actions: [:approve]) }.to raise_error(ArgumentError, /only add to :read_only/)
      expect { described_class.declare(tags) }.to raise_error(ArgumentError, /needs a mode/)
      expect { ReactiveAdmin.config.mcp.default = :write }.to raise_error(ArgumentError, /mcp.default/)
    end
  end

  describe ".allows?" do
    it "lets :read_only read, but not write or open a write's form" do
      expect(described_class.allows?(tags, %w[index])).to be(true)
      expect(described_class.allows?(tags, %w[show])).to be(true)
      expect(described_class.allows?(tags, %w[create])).to be(false)
      expect(described_class.allows?(tags, %w[new])).to be(false)
      expect(described_class.allows?(tags, %w[edit])).to be(false)
      expect(described_class.allows?(tags, %w[destroy])).to be(false)
    end

    it "runs listed actions and GET actions, but not those in unsafe_gets, under :read_only" do
      described_class.declare(posts, :read_only, actions: [:archive, :feature])

      expect(described_class.allows?(posts, %w[archive])).to be(true)
      expect(described_class.allows?(posts, %w[batch_action feature])).to be(true)
      expect(described_class.allows?(posts, %w[import])).to be(false)
      expect(described_class.allows?(posts, %w[bump])).to be(false)
      expect(described_class.allows?(posts, %w[download])).to be(true)
      expect(described_class.allows?(posts, %w[permalink], verb: "GET")).to be(true)
      expect(described_class.allows?(posts, %w[bump], verb: "GET")).to be(false)
      expect(described_class.allows?(posts, %w[rename], verb: "GET")).to be(true)
      expect(described_class.allows?(posts, %w[rename], verb: "POST")).to be(false)
      expect(described_class.runnable(posts)).to include("archive", "feature")
    end

    it "counts an action declared for several verbs as reachable when any one is allowed" do
      described_class.declare(posts, :read_only)

      expect(described_class.runnable(posts)).to include("rename")
      expect(described_class.runnable(posts)).not_to include("import")
      expect(described_class.allows_any?(posts, %w[rename], %w[GET POST])).to be(true)
      expect(described_class.allows_any?(posts, %w[rename], %w[POST])).to be(false)
    end

    it "scopes listed names to custom and batch actions, never the standard action of the same name" do
      described_class.declare(posts, actions: [:destroy, :update, :archive])

      expect(described_class.allows?(posts, %w[destroy])).to be(false)
      expect(described_class.allows?(posts, %w[update])).to be(false)
      expect(described_class.allows?(posts, %w[edit])).to be(false)
      expect(described_class.allows?(posts, %w[batch_action])).to be(false)
      expect(described_class.allows?(posts, %w[batch_action destroy])).to be(true)
      expect(described_class.allows?(posts, %w[archive])).to be(true)
      expect(described_class.offers?(posts, :destroy)).to be(false)
      expect(described_class.offers?(posts, :update)).to be(false)
      expect(described_class.offers?(posts, :edit)).to be(false)
      expect(ReactiveAdmin::ApiGuards.denial(posts, %w[destroy], verb: "DELETE", channel: :mcp)).to have_attributes(guard: :read_only)
      expect(ReactiveAdmin::ApiGuards.denial(posts, %w[batch_action destroy], verb: "POST", channel: :mcp)).to be_nil
    end

    it "allows nothing under :none and everything under :full" do
      expect(described_class.allows?(posts, %w[destroy])).to be(true)
      described_class.declare(posts, :none)

      expect(described_class.allows?(posts, %w[index])).to be(false)
      expect(described_class.visible?(posts)).to be(false)
    end
  end

  describe "as an api guard" do
    it "applies only to MCP requests" do
      expect(ReactiveAdmin::ApiGuards.denies?(tags, "create")).to be(false)
      expect(ReactiveAdmin::ApiGuards.denial(tags, %w[create], channel: :mcp)).to have_attributes(guard: :read_only)
      expect(ReactiveAdmin::ApiGuards.denial(tags, %w[create], channel: :token)).to be_nil
    end

    it "can't widen what a guard refuses: :full and a listed action leave the guard in force" do
      expect(described_class.mode(admin_users)).to eq(:full)
      expect(ReactiveAdmin::ApiGuards.denial(admin_users, %w[impersonate], channel: :mcp)).to have_attributes(guard: :deny)

      described_class.declare(admin_users, actions: [:impersonate])
      expect(described_class.allows?(admin_users, %w[impersonate])).to be(true)
      expect(ReactiveAdmin::ApiGuards.denial(admin_users, %w[impersonate], channel: :mcp)).to have_attributes(guard: :deny)
    end

    it "keeps a :none resource or page out of MCP whole, and only there" do
      described_class.declare(tags, :none)

      expect(ReactiveAdmin::ApiGuards.whole?(tags, channel: :mcp)).to be(true)
      expect(ReactiveAdmin::ApiGuards.whole?(tags, channel: :token)).to be(false)
      expect(ReactiveAdmin::ApiGuards.whole?(dashboard, channel: :mcp)).to be(false)
    end
  end
end
