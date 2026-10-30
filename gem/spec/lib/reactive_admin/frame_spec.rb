RSpec.describe ReactiveAdmin::Frame do
  def degraded_kinds
    ReactiveAdmin::Degradation.with_collection do
      yield
      ReactiveAdmin::Degradation.entries.pluck(:kind)
    end
  end

  describe ".sanitize" do
    it "keeps a page nested past the parser's depth as too complex, never raises" do
      html = nil
      kinds = degraded_kinds { html = described_class.sanitize("<html><body>#{"<div>" * 500}x</body></html>") }

      expect(html).to eq ReactiveAdmin::HtmlPolicy::TOO_COMPLEX
      expect(kinds).to eq %w[html_too_deep]
    end

    it "bounds a huge page to the caps, with no error" do
      html = nil
      kinds = degraded_kinds { html = described_class.sanitize("<html><body>#{"<p><b>x</b></p>" * 20_000}</body></html>") }

      expect(Nokogiri::HTML5.fragment(html).css("b").size).to be <= ReactiveAdmin::HtmlPolicy::MAX_NODES
      expect(kinds).to include "html_truncated"
    end

    it "passes a fragment through without a page wrapper" do
      expect(described_class.sanitize("<p>ok</p>")).to eq "<p>ok</p>"
    end
  end
end
