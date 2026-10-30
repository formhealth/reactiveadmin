RSpec.describe ReactiveAdmin::OpenApi::Context do
  include_context "with a blog"

  let(:context) { described_class.new(admin, controller: nil, full: false) }
  let(:full) { described_class.new(nil, controller: nil, full: true) }
  let(:posts) { ReactiveAdmin::Registry.find("posts") }

  it "lists the resources the user may open, as the manifest does" do
    expect(context.resources.pluck(:key)).to include("posts", "authors")
    expect(context.resources).to equal(context.resources)
  end

  it "authorizes as the user, or permissively in a full document" do
    expect(context.authorizer).to be_a(ReactiveAdmin::Authorizer)
    expect(context.authorizer.user).to eq(admin)
    expect(full.authorizer).to be_a(ReactiveAdmin::Authorizer::Permissive)
    expect(full.authorized?(ReactiveAdmin::AA::Auth::DESTROY, Post, posts)).to be true
  end

  it "probes a resource's controller as the user, once" do
    probe = context.probe(posts)

    expect(probe.controller.current_admin_user).to eq(admin)
    expect(probe.controller).to be_a(posts.controller)
    expect(context.probe(posts)).to equal(probe)
  end

  it "lets a full document's probes see everything their views would check" do
    expect(full.probe(posts).controller.authorized?(ReactiveAdmin::AA::Auth::DESTROY, Post)).to be true
    expect(context.probe(posts).controller.send(:authorized?, ReactiveAdmin::AA::Auth::DESTROY, Post)).to eq(can_destroy_post?(admin))
  end

  it "treats a check that raises as denied" do
    allow(context.authorizer).to receive(:authorized?).and_raise(RuntimeError)

    expect(context.authorized?(:rename, Post, posts)).to be false
  end

  it "hands out unique operation ids" do
    expect([context.ids.claim("a"), context.ids.claim("a")]).to eq(%w[a a2])
  end
end
