RSpec.describe ReactiveAdmin::Paths do
  include_context "with a blog"

  let(:posts) { ReactiveAdmin::Registry.find("posts") }
  let(:comments) { ReactiveAdmin::Registry.find("comments") }

  it "knows which resources only exist under a parent" do
    expect(described_class.nested?(comments)).to be(true)
    expect(described_class.nested?(posts)).to be(false)
  end

  it "builds collection, options and meta paths" do
    expect(described_class.collection(posts)).to eq("/admin/posts")
    expect(described_class.options(posts)).to eq("/admin/posts/_options")
    expect(described_class.meta(posts)).to eq("/admin/posts/_meta")
    expect(described_class.collection(comments, parent_id: "7")).to eq("/admin/posts/7/comments")
  end

  it "puts the API under the mount" do
    expect(described_class.api("/admin/posts")).to eq("/api/admin/posts")
  end

  it "templates the nested index path" do
    expect(described_class.index_template(comments)).to eq("/admin/posts/{parent_id}/comments")
    expect(described_class.index_template(posts)).to be_nil
  end

  it "reads the parent id from params" do
    params = ActiveSupport::HashWithIndifferentAccess.new(post_id: "3")

    expect(described_class.parent_id(comments, params)).to eq("3")
    expect(described_class.parent_id(posts, params)).to be_nil
  end

  describe ".record" do
    it "gives show and edit paths, classic and API" do
      expect(described_class.record(posts, first_post)).to eq(
        show: "/admin/posts/#{first_post.id}", edit: "/admin/posts/#{first_post.id}/edit",
        api_show: "/api/admin/posts/#{first_post.id}", api_edit: "/api/admin/posts/#{first_post.id}/edit"
      )
    end

    it "escapes the joined param of a composite key" do
      level = StockLevel.new(warehouse: "east", sku: "A/1 b")

      expect(described_class.record(ReactiveAdmin::Registry.find("stock_levels"), level)).to include(show: "/admin/stock_levels/east_A%2F1%20b")
    end

    it "nests the paths of nested-only records under the parent without loading it" do
      comment = Comment.create!(post: first_post, body: "x")

      expect(described_class.record(comments, comment)[:show]).to eq("/admin/posts/#{first_post.id}/comments/#{comment.id}")
    end
  end
end
