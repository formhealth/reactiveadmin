module Builders
  def create_author(**attrs) = Author.create!({name: "Alice Author", email: "alice@example.com"}.merge(attrs))

  def create_post(author:, **attrs) = Post.create!({title: "A post", author:}.merge(attrs))

  def create_admin(**attrs) = AdminUser.create!({name: "Ada Admin", email: "ada@example.com", role: "admin"}.merge(attrs))

  def create_editor(author:, **attrs) = AdminUser.create!({name: "Ed Editor", email: "ed@example.com", role: "editor", author:}.merge(attrs))
end

# alice's and bob's posts; `editor` edits as alice.
RSpec.shared_context "with a blog" do
  let!(:alice) { create_author(name: "Alice Author", email: "alice@example.com", rating: 4.5, born_on: Date.new(1990, 1, 2)) }
  let!(:bob) { create_author(name: "Bob Builder", email: "bob@example.com", rating: 2.0) }
  let!(:news) { Category.create!(name: "News") }
  let!(:ruby) { Tag.create!(name: "ruby") }
  let!(:admin) { create_admin }
  let!(:editor) { create_editor(author: alice) }
  let!(:first_post) do
    create_post(author: alice, title: "Hello world", status: :published, published_at: Time.zone.local(2026, 1, 5, 12), views_count: 1200,
      featured: true, category: news, metadata: {"seo" => {"slug" => "hello"}}, tags: [ruby])
  end
  let!(:second_post) { create_post(author: bob, title: "Bob's draft", status: :draft, views_count: 3) }
  let!(:third_post) { create_post(author: alice, title: "Old news", status: :archived, published_at: Time.zone.local(2025, 6, 1, 8)) }
end
