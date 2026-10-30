RSpec.describe "links to unexposed resources" do
  include_context "with a blog"

  let(:rename) { %(<a href="/admin/posts/#{first_post.id}/rename">Rename</a>) }
  let(:delete) { %(<a href="/admin/posts/#{first_post.id}" data-method="delete" data-confirm="Sure?">Delete</a>) }
  let(:links) { ReactiveAdmin::ActionLinks.new(host: "www.example.com") }

  def action(html) = links.action(ReactiveAdmin::ActionLinks.controls(html).first, placement: "row")

  def link_node(html) = ReactiveAdmin::HtmlNodes.convert(html, host: "www.example.com")

  around do |example|
    ReactiveAdmin::MenuOverlay.reset!
    ReactiveAdmin.config.expose = :listed
    example.run
  ensure
    ReactiveAdmin.config.expose = :all
    ReactiveAdmin.config.exposed_resources = []
    ReactiveAdmin::MenuOverlay.reset!
  end

  context "when the target is exposed" do
    before { ReactiveAdmin.config.exposed_resources = %w[posts] }

    it "maps to an API action and view" do
      expect(action(delete)).to include(kind: "destroy", api_path: "/api/admin/posts/#{first_post.id}")
      expect(action(rename)).to include(kind: "member", view: a_hash_including(mode: "native"))
      expect(link_node(rename)).to include(view: a_hash_including(mode: "native"))
    end
  end

  context "when the target is not exposed" do
    it "is a classic-admin link that the client cannot call" do
      expect(action(delete)).to include(supported: false, enabled: false, disabled_reason: "Available in the classic admin")
      expect(action(delete)).not_to include(:api_path)
      expect(action(rename)).to include(supported: false, disabled_reason: "Available in the classic admin")
    end

    it "leaves the html link without a view or ref" do
      expect(link_node(rename)).to include(type: "link", href: "/admin/posts/#{first_post.id}/rename")
      expect(link_node(rename)).not_to include(:view, :ref)
    end
  end
end
