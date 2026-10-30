RSpec.describe ReactiveAdmin::InlineStyle do
  def parse(style) = described_class.parse(style)

  def tokens(style) = parse(style).tokens

  describe "margins" do
    {
      "margin-top: 8px" => %w[mt-2],
      "margin-bottom: 1rem" => %w[mb-4],
      "margin-left: 0.5rem" => %w[ml-2],
      "margin-right: 32px" => %w[mr-8],
      "margin-top: 0" => %w[mt-0]
    }.each do |style, expected|
      it "translates #{style}" do
        expect(tokens(style)).to eq(expected)
      end
    end

    it "expands the shorthand like CSS does" do
      expect(tokens("margin: 0 0 20px 0")).to eq(%w[mt-0 mr-0 mb-5 ml-0])
      expect(tokens("margin: 8px 12px")).to eq(%w[mt-2 mr-3 mb-2 ml-3])
      expect(tokens("margin: 4px 8px 12px")).to eq(%w[mt-1 mr-2 mb-3 ml-2])
      expect(tokens("margin: 8px")).to eq(%w[mt-2 mr-2 mb-2 ml-2])
    end

    ["margin-top: 10px", "margin-top: 40px", "margin-top: -10px", "margin-top: auto", "margin-top: 1em", "margin: 0 auto"].each do |declaration|
      it "reports #{declaration}, which is off the scale, beyond it, negative, auto or in em" do
        expect(parse(declaration).unknown).to eq([declaration])
      end
    end
  end

  describe "layout" do
    it "reads flex rows and their gap and alignment" do
      expect(tokens("display: flex; flex-direction: row; gap: 20px; align-items: flex-start; justify-content: space-between; flex-wrap: wrap"))
        .to eq(%w[flex flex-row gap-5 items-start justify-between flex-wrap])
    end

    it "reads column direction, text alignment and widths" do
      expect(tokens("flex-direction: column; text-align: center; width: 50%")).to eq(%w[flex-col text-center w-1/2])
      expect(tokens("width: 33.33%")).to eq(%w[w-1/3])
      expect(tokens("width: 100%")).to eq(%w[w-full])
    end

    it "reads grow from flex: 1 only" do
      expect(tokens("flex: 1")).to eq(%w[grow])
      expect(parse("flex: 0 0 35%").unknown).to eq(["flex: 0 0 35%"])
    end

    it "reports widths off the fractions and other displays" do
      expect(parse("width: 40rem; display: inline-block; width: 600px").unknown).to eq(["width: 40rem", "display: inline-block", "width: 600px"])
    end
  end

  describe "text" do
    it "reads weight, style and color" do
      expect(tokens("font-weight: bold; font-style: italic; color: #999")).to eq(%w[font-bold italic text-muted])
      expect(tokens("color: red")).to eq(%w[text-danger])
      expect(tokens("color: green")).to eq(%w[text-success])
    end

    it "says nothing for the defaults" do
      result = parse("font-weight: normal; font-style: normal; flex-wrap: nowrap; white-space: normal")

      expect(result.tokens).to eq([])
      expect(result.unknown).to eq([])
    end

    it "reads white-space: nowrap and reports other values" do
      expect(tokens("white-space: nowrap")).to eq(%w[whitespace-nowrap])
      expect(parse("white-space: pre-wrap").unknown).to eq(["white-space: pre-wrap"])
    end

    it "reports colors it cannot name a tone for" do
      expect(parse("color: #721c24").unknown).to eq(["color: #721c24"])
    end
  end

  describe "parsing" do
    it "ignores case, !important and stray semicolons" do
      expect(tokens("  MARGIN-TOP: 8px !important;; ")).to eq(%w[mt-2])
    end

    it "keeps the untranslatable declarations in order" do
      expect(parse("padding: 12px; margin-top: 8px; position: sticky").unknown).to eq(["padding: 12px", "position: sticky"])
    end

    it "copes with nil and blank" do
      expect(parse(nil)).to have_attributes(tokens: [], unknown: [])
      expect(parse(" ; ")).to have_attributes(tokens: [], unknown: [])
    end
  end

  describe ".redact" do
    it "squishes, drops urls and caps the length" do
      expect(described_class.redact("background:  url(/avatars/jane-doe.png) ;  top: 0")).to eq("background: url(…) ; top: 0")
      expect(described_class.redact("x" * 500).size).to eq(described_class::MAX_REPORTED)
      expect(described_class.redact(nil)).to eq("")
    end
  end

  describe ".advice" do
    it "says what to use instead, per property" do
      expect(described_class.advice("padding: 12px")).to include("panel")
      expect(described_class.advice("margin-top: -10px")).to include("4px scale")
      expect(described_class.advice("zoom: 2")).to eq("no typed equivalent")
    end
  end
end
