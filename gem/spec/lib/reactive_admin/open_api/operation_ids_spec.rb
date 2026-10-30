RSpec.describe ReactiveAdmin::OpenApi::OperationIds do
  subject(:ids) { described_class.new }

  it "hands out a name once and counts clashes in the order they arrive" do
    expect([ids.claim("listPosts"), ids.claim("listPosts"), ids.claim("listPosts"), ids.claim("getPost")]).to eq(%w[listPosts listPosts2 listPosts3 getPost])
  end

  it "does not hand out a counted name a second time" do
    ids.claim("a2")

    expect([ids.claim("a"), ids.claim("a")]).to eq(%w[a a3])
  end
end
