RSpec.describe ReactiveAdmin::ActionLinks do
  def degraded_kinds
    ReactiveAdmin::Degradation.with_collection do
      yield
      ReactiveAdmin::Degradation.entries.pluck(:kind)
    end
  end

  describe ".controls" do
    it "finds the links and forms in normal markup" do
      expect(described_class.controls(%(<a href="/x">x</a><form action="/y"></form>)).size).to eq 2
    end

    it "finds no controls in markup nested past the parser's depth, never raises" do
      controls = nil
      kinds = degraded_kinds { controls = described_class.controls(%(<div>#{"<div>" * 500}<a href="/x">x</a>)) }

      expect(controls).to eq []
      expect(kinds).to eq %w[html_too_deep]
    end

    it "keeps the controls within the node cap for markup past the byte cap" do
      controls = nil
      kinds = degraded_kinds { controls = described_class.controls(%(<a href="/x">x</a>) * 10_000) }

      expect(controls.size).to be_between(1, ReactiveAdmin::HtmlPolicy::MAX_NODES)
      expect(kinds).to include "html_truncated"
    end
  end

  describe "#action for same-host paths outside the admin namespace" do
    let(:links) { described_class.new(host: "www.example.com", base_url: "http://www.example.com:3003") }

    def action(html) = links.action(Nokogiri::HTML5.fragment(html).at_css("a, form"), placement: "header")

    it "opens a GET as an external link with an absolute href" do
      expect(action('<a href="/sidekiq">Sidekiq Dashboard</a>')).to include(
        kind: "link", href: "http://www.example.com:3003/sidekiq", external: true, enabled: true
      )
    end

    it "keeps a non-GET unsupported, since an anchor can't send it" do
      expect(action('<a href="/sidekiq/x" data-method="delete">Del</a>')).to include(supported: false, enabled: false)
    end

    it "keeps admin links internal" do
      expect(action('<a href="/admin/posts">Posts</a>')).not_to include(:external)
    end

    it "leaves foreign hosts as they were" do
      expect(action('<a href="https://other.test/x">X</a>')).to include(href: "https://other.test/x", external: true)
    end
  end
end
