RSpec.describe ReactiveAdmin::Authorizer do
  include_context "with a blog"

  let(:posts_config) { ReactiveAdmin::Registry.find("posts") }

  def authorizer(user) = ReactiveAdmin::Authorizer.new(user)

  it "runs the namespace's adapter for a user" do
    expect(authorizer(admin).authorized?(ActiveAdmin::Auth::DESTROY, first_post, config: posts_config)).to eq(can_destroy_post?(admin))
    expect(authorizer(editor).authorized?(ActiveAdmin::Auth::DESTROY, first_post, config: posts_config)).to eq(can_destroy_post?(editor))
  end

  it "checks class-level subjects" do
    expect(authorizer(editor).authorized?(ActiveAdmin::Auth::READ, Category, config: ReactiveAdmin::Registry.find("categories"))).to eq(can_read_categories?(editor))
  end

  it "scopes a relation the way the adapter scopes AA's own queries" do
    expect(authorizer(editor).scope(Post.all).pluck(:id)).to match_array([first_post, second_post, third_post].select { can_see_post?(editor, it) }.map(&:id))
    expect(authorizer(admin).scope(Post.all).count).to eq(3)
  end

  it "leaves relations of unregistered models alone" do
    expect(authorizer(editor).scope(Tagging.all).to_sql).to eq(Tagging.all.to_sql)
  end

  describe ReactiveAdmin::Authorizer::Permissive do
    subject(:permissive) { described_class.new }

    it "permits everything, for a user nobody is, and leaves relations whole" do
      expect(permissive.user).to be_nil
      expect(permissive.authorized?(ActiveAdmin::Auth::DESTROY, Category, config: ReactiveAdmin::Registry.find("categories"))).to be true
      expect(permissive.scope(Post.all)).to eq(Post.all)
    end
  end

  describe ".for" do
    it "builds the authorizer from the controller's current user" do
      controller = instance_double(ApplicationController, current_admin_user: editor)

      expect(described_class.for(controller).user).to eq(editor)
    end
  end

  describe ReactiveAdmin::Permissions do
    it "reports permissions for the actions a resource defines" do
      permissions = described_class.new(posts_config, authorizer(admin))

      expect(permissions.resource).to eq(index: true, show: true, create: true, update: true, destroy: can_destroy_post?(admin))
      expect(permissions.record(first_post)).to eq(show: true, update: true, destroy: can_destroy_post?(admin))
    end

    it "omits keys for actions the resource does not define" do
      allow(ReactiveAdmin::Registry).to receive(:actions).and_return(%i[index show])

      expect(described_class.new(posts_config, authorizer(admin)).resource.keys).to eq(%i[index show])
    end

    it "reflects per-record adapter decisions" do
      permissions = described_class.new(posts_config, authorizer(editor))

      expect(permissions.record(second_post)[:show]).to eq(can_see_post?(editor, second_post))
    end
  end
end
