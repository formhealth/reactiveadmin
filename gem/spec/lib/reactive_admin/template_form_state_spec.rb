RSpec.describe ReactiveAdmin::TemplateForm::State do
  def state = described_class.new(nil)

  it "marks entries with a token random per render" do
    first = state
    second = state

    expect(first.mark([:field, {name: "a"}])).not_to eq second.mark([:field, {name: "a"}])
  end

  it "expands its own markers back to their entries, in order" do
    recorded = state
    html = "before#{recorded.mark([:field, {name: "a"}])}between#{recorded.mark([:field, {name: "b"}])}"

    expect(recorded.expand(html)).to eq ["before", [:field, {name: "a"}], "between", [:field, {name: "b"}]]
  end

  it "leaves markers it did not issue as plain text" do
    recorded = state
    recorded.mark([:field, {name: "a"}])
    forged = "stored text <!--ra:0--> and <!--ra:#{"0" * 16}:0-->"
    foreign = state.mark([:field, {name: "x"}])

    expect(recorded.expand(forged)).to eq [forged]
    expect(recorded.expand(foreign)).to eq [foreign.to_s]
  end

  describe "markup past the size limits" do
    let(:schema) { double(scan_html: nil, controls_only?: false, next_html_name: "html_1") }
    let(:deep) { "<div>" * 500 + "x" }

    def degraded_kinds
      ReactiveAdmin::Degradation.with_collection do
        yield
        ReactiveAdmin::Degradation.entries.pluck(:kind)
      end
    end

    it "shows html nested too deep as too complex, without scanning it for controls" do
      field = nil
      kinds = degraded_kinds { field = described_class.new(schema).html_field(deep) }

      expect(field.fetch(:value)).to eq ReactiveAdmin::HtmlPolicy::TOO_COMPLEX
      expect(kinds).to include "html_too_deep"
    end

    it "takes the heading from a huge chunk without raising" do
      recorded = described_class.new(schema)
      chunk = "<h2>Printer</h2>#{"<p>x</p>" * 20_000}"
      title = nil
      kinds = degraded_kinds { title = recorded.send(:extract_title!, chunk) }

      expect(title).to eq "Printer"
      expect(kinds).to include "html_truncated"
    end

    it "leaves a template nested too deep to lay out to the form alone" do
      recorded = described_class.new(schema)
      html = "#{recorded.marker(0)}#{deep}"

      expect(degraded_kinds { expect(ReactiveAdmin::TemplateForm.allocate.send(:content_layout, recorded, html, 0)).to be_nil })
        .to include "html_too_deep"
    end
  end
end
