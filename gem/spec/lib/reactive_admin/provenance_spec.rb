RSpec.describe ReactiveAdmin::Provenance do
  let(:view) { ActionView::Base.empty }
  def secret = described_class::STATE[described_class::KEY]

  def walk(html) = ReactiveAdmin::HtmlNodes.nodes(html, host: "www.example.com")

  it "stamps link_to and button_to inside a scope only" do
    expect(view.link_to("Go", "/admin/posts/1")).not_to include(described_class::ATTRIBUTE)

    described_class.with_scope do
      expect(view.link_to("Go", "/admin/posts/1")).to include(%(#{described_class::ATTRIBUTE}="#{secret}"))
      expect(view.link_to("/admin/posts/1") { "x" }).to include(secret)
      expect(view.button_to("Go", "/admin/posts/1")).to start_with("<form").and include(secret)
    end
  end

  it "stamps once and keeps the html safe" do
    described_class.with_scope do
      html = view.link_to_if(true, "Go", "/admin/posts/1")

      expect(html).to be_html_safe
      expect(html.scan(described_class::ATTRIBUTE).size).to eq(1)
    end
  end

  it "stamps the a and form tags the DSL builds, and no other, inside a scope only" do
    build = -> {
      Arbre::Context.new {
        a "x", href: "/admin"
        form(method: "get") { span "y" }
      }.to_s
    }

    expect(build.call).not_to include(described_class::ATTRIBUTE)
    described_class.with_scope do
      html = build.call

      expect(html.scan(%(#{described_class::ATTRIBUTE}="#{secret}")).size).to eq(2)
      expect(html).not_to match(/<span[^>]*origin/)
    end
  end

  it "makes the helpers' controls actions and nothing else's" do
    described_class.with_scope do
      mine = view.link_to("Archive", "/admin/posts/1/archive", method: :post, data: {confirm: "Sure?"})
      stored = '<a href="/admin/posts/1/archive" data-method="post" data-confirm="Sure?">Archive</a>'

      expect(walk(mine).pluck(:type)).to eq(%w[action])
      expect(walk(stored).pluck(:type)).to eq(%w[text])
    end
  end

  it "doesn't trust a stamp from another scope" do
    html = described_class.with_scope { view.link_to("Archive", "/admin/posts/1/archive", method: :post) }

    described_class.with_scope { expect(walk(html).pluck(:type)).to eq(%w[text]) }
  end

  it "restores the outer scope" do
    described_class.with_scope do
      outer = secret
      described_class.with_scope { expect(secret).not_to eq(outer) }
      expect(secret).to eq(outer)
    end
    expect(secret).to be_nil
  end
end
