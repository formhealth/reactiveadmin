RSpec.describe ReactiveAdmin::Ui do
  let(:player) { Struct.new(:admin) { def admin? = admin } }
  let(:user) { player.new(true) }

  describe ".available?" do
    around { |example| with_ui(available: ->(user) { user.admin? }) { example.run } }

    it "asks the host, for a user" do
      expect(described_class.available?(user)).to be(true)
      expect(described_class.available?(player.new(false))).to be(false)
      expect(described_class.available?(nil)).to be(false)
    end

    it "is false when the host's callable raises" do
      ReactiveAdmin.config.ui.available = ->(_user) { raise "boom" }

      expect(described_class.available?(user)).to be(false)
    end
  end

  describe ".default_mode" do
    around { |example| with_ui { example.run } }

    it "is a mode or a callable's answer, as a string" do
      ReactiveAdmin.config.ui.default = :new
      expect(described_class.default_mode(user)).to eq("new")

      ReactiveAdmin.config.ui.default = ->(user) { user.admin? ? :new : :classic }
      expect(described_class.default_mode(user)).to eq("new")
      expect(described_class.default_mode(player.new(false))).to eq("classic")
    end

    it "is classic for anything else, or a callable that raises" do
      ReactiveAdmin.config.ui.default = ->(_user) { :bogus }
      expect(described_class.default_mode(user)).to eq("classic")

      ReactiveAdmin.config.ui.default = ->(_user) { raise "boom" }
      expect(described_class.default_mode(user)).to eq("classic")
    end
  end

  describe ".payload" do
    around { |example| with_ui(default: :new) { example.run } }

    it "is what `_session` reports" do
      expect(described_class.payload(user)).to eq(available: true, default: "new")
      expect(described_class.payload(nil)).to eq(available: false, default: "new")
    end
  end

  describe "Configuration::Ui" do
    subject(:ui) { ReactiveAdmin::Configuration.new.ui }

    it "serves the shell, but to nobody's benefit until the host says who is available" do
      expect(ui).to have_attributes(enabled: true, default: :classic, client_assets: nil, asset_prefix: "/reactiveadmin")
      expect(ui.available.call(Object.new)).to be(false)
    end
  end
end
