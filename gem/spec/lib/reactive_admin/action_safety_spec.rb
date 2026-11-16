require "rails_helper"

RSpec.describe ReactiveAdmin::ActionSafety do
  let(:posts) { ReactiveAdmin::Registry.find("posts") }

  it "reads standard actions and GET custom actions that render a page or are listed in safe_gets" do
    expect(described_class.read?(posts, "index", "GET")).to be(true)
    expect(described_class.read?(posts, "preview", "GET")).to be(true)
    expect(described_class.read?(posts, "download", "HEAD")).to be(true)
  end

  it "treats a GET custom action without a page as a write, and every other verb too" do
    expect(described_class.read?(posts, "bump", "GET")).to be(false)
    expect(described_class.read?(posts, "index", "POST")).to be(false)
  end

  it "lists GET actions treated as writes for the doctor" do
    expect(described_class.unsafe_gets(posts)).to include("bump").and(satisfy { (it & %w[preview download rename]).empty? })
    expect(ReactiveAdmin::Doctor.run(sample: false)[:diagnostics])
      .to include(a_hash_including(kind: "get_action_write", resource: "posts", action: "bump"))
  end
end
