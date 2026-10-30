require "rails_helper"

# Markup nested past HtmlPolicy's depth cap: each site must degrade to a safe outcome, never raise.
RSpec.describe "HTML parse sites under the depth cap" do
  let(:deep) { "<div>" * 500 + "x" }

  def degraded_kinds
    ReactiveAdmin::Degradation.with_collection do
      yield
      ReactiveAdmin::Degradation.entries.pluck(:kind)
    end
  end

  describe ReactiveAdmin::FormSchema do
    def scan(html) = described_class.allocate.tap { it.scan_html(html) }.unsupported_kinds

    it "marks a form whose markup is too deep to scan as unsupported" do
      kinds = nil
      expect(degraded_kinds { kinds = scan(deep) }).to include "html_too_deep"
      expect(kinds).to eq [:raw_inputs]
    end

    it "flags raw inputs and leaves input-free markup alone" do
      expect(scan("<input name='a'>")).to eq [:raw_inputs]
      expect(scan("<p>x</p>")).to eq []
    end
  end

  describe ReactiveAdmin::FormContent do
    subject(:content) { described_class.new(nil, nil) }

    it "declines to split markup too deep to parse, so the recorder shows it as too complex" do
      result = :unset
      expect(degraded_kinds { result = content.split(deep) }).to include "html_too_deep"
      expect(result).to be_nil
    end
  end

  describe ReactiveAdmin::IndexRecorder do
    def strip_selection(html) = described_class.allocate.send(:strip_selection, html)

    it "shows too-deep item markup as too complex text" do
      html = nil
      expect(degraded_kinds { html = strip_selection(deep) }).to include "html_too_deep"
      expect(html).to eq ReactiveAdmin::HtmlPolicy::TOO_COMPLEX
    end

    it "removes selection controls from an item" do
      expect(strip_selection("<p>a</p><span class='collection_selection'>x</span>")).to eq "<p>a</p>"
    end
  end

  describe ReactiveAdmin::IndexViews do
    it "offers no blank-slate link when the link markup is too deep" do
      nested = deep
      presenter = {blank_slate_link: -> { "<a href='/new'>New</a>#{nested}" }}
      views = described_class.new(double(get_page_presenter: presenter))
      result = nil

      expect(degraded_kinds { result = views.blank_slate(Object.new) }).to include "html_too_deep"
      expect(result).to eq(label: nil, href: nil)
    end
  end

  describe "sidebar panels" do
    let(:section) { double(title: "Stats", display_on?: true) }
    let(:context) { double(insert_tag: "<div class='panel_contents'>#{html}</div>") }
    let(:html) { deep }

    before { allow(ReactiveAdmin::AA).to receive(:arbre_context).and_return(context) }

    it "shows a panel too deep to parse as too complex" do
      result = nil
      expect(degraded_kinds { result = ReactiveAdmin::AA.render_sidebar(section, :index, {}, nil) }).to include "html_too_deep"
      expect(result).to eq(title: "Stats", html: ReactiveAdmin::HtmlPolicy::TOO_COMPLEX)
    end

    context "when the panel fits" do
      let(:html) { "<p>ok</p>" }

      it "returns the panel's contents" do
        expect(ReactiveAdmin::AA.render_sidebar(section, :index, {}, nil)).to eq(title: "Stats", html: "<p>ok</p>")
      end
    end
  end
end
