RSpec.describe ReactiveAdmin::LayoutClasses do
  def parse(classes, **) = described_class.parse(classes, **)

  def flex(**) = {display: "flex", direction: "row", breakpoint: nil, gap: 0, wrap: false, **}

  describe "flex" do
    it "defaults to a row at every width" do
      expect(parse("flex").layout).to eq(flex)
    end

    it "reads direction, gap, wrap, align and justify" do
      result = parse("flex flex-col gap-3 flex-wrap items-center justify-between")

      expect(result.layout).to eq(flex(direction: "column", gap: 3, wrap: true, align: "center", justify: "between"))
    end

    it "stacks below the breakpoint of a responsive row" do
      expect(parse("flex lg:flex-row gap-5").layout).to eq(flex(breakpoint: "lg", gap: 5))
      expect(parse("flex flex-col md:flex-row").layout).to eq(flex(breakpoint: "md"))
    end

    it "takes the narrowest breakpoint" do
      expect(parse("flex xl:flex-row md:flex-row").layout[:breakpoint]).to eq("md")
    end

    it "ignores a responsive row on an explicit row" do
      expect(parse("flex flex-row lg:flex-row").layout[:breakpoint]).to be_nil
    end

    it "clamps the gap" do
      expect(parse("flex gap-12").layout[:gap]).to eq(8)
    end

    it "has no layout without a display class" do
      expect(parse("flex-row gap-2 items-center").layout).to be_nil
    end
  end

  describe "grid" do
    it "reads columns and the responsive count" do
      expect(parse("grid grid-cols-3").layout).to eq(display: "grid", columns: 3, breakpoint: nil, gap: 0)
      expect(parse("grid grid-cols-1 md:grid-cols-4 gap-2").layout).to eq(display: "grid", columns: 4, breakpoint: "md", gap: 2)
      expect(parse("grid grid-cols-2 lg:grid-cols-6").layout).to include(columns: 6, breakpoint: "lg", base_columns: 2)
    end

    it "reads col-span, preferring the responsive value" do
      expect(parse("col-span-2").span).to eq(2)
      expect(parse("col-span-1 md:col-span-3").span).to eq(3)
    end
  end

  describe "width and text alignment" do
    %w[1/4 1/3 1/2 2/3 3/4 full].each do |fraction|
      it "maps w-#{fraction} and basis-#{fraction}" do
        expect(parse("w-#{fraction}").width).to eq(fraction)
        expect(parse("basis-#{fraction}").width).to eq(fraction)
      end
    end

    it "prefers the responsive width over a full-width base" do
      expect(parse("w-full lg:w-1/3").width).to eq("1/3")
    end

    it "maps text alignment" do
      expect(parse("text-right").text_align).to eq("right")
      expect(parse("text-center").text_align).to eq("center")
    end
  end

  describe "spacing" do
    it "reads margins per side on the 4px scale" do
      expect(parse("mt-2 mb-4").spacing).to eq(top: 2, bottom: 4)
      expect(parse("mx-3").spacing).to eq(left: 3, right: 3)
      expect(parse("my-1").spacing).to eq(top: 1, bottom: 1)
      expect(parse("m-2").spacing).to eq(top: 2, right: 2, bottom: 2, left: 2)
    end

    it "treats zero as nothing to say" do
      result = parse("mt-0 mb-0")

      expect(result.spacing).to be_nil
      expect(result.unknown).to eq([])
    end

    it "reports margins beyond the scale, responsive ones and negatives" do
      expect(parse("mt-9 md:mt-2 -mt-2 p-2").unknown).to eq(%w[mt-9 md:mt-2 -mt-2 p-2])
    end

    it "lets the last class on a side win" do
      expect(parse("mt-2 mt-4").spacing).to eq(top: 4)
    end

    it "is part of the hints" do
      expect(parse("mt-2").hints).to eq(spacing: {top: 2})
    end
  end

  describe "text style" do
    it "reads marks and tone, apart from the box hints" do
      result = parse("font-bold italic text-red-600")

      expect(result.text_style).to eq(marks: %w[strong em], tone: "danger")
      expect(result.hints).to eq({})
      expect(result.unknown).to eq([])
    end

    it "reads no-wrap as text style" do
      expect(parse("whitespace-nowrap").text_style).to eq(nowrap: true)
      expect(parse("text-nowrap").unknown).to eq([])
      expect(parse("whitespace-pre-wrap").unknown).to eq(%w[whitespace-pre-wrap])
    end

    it "maps colors to a tone and leaves sizes unknown" do
      expect(parse("text-gray-600").tone).to eq("muted")
      expect(parse("text-success").tone).to eq("success")
      expect(parse("text-yellow-500").tone).to eq("warning")
      expect(parse("text-sm text-purple-500").unknown).to eq(%w[text-sm text-purple-500])
    end

    it "does not repeat a mark" do
      expect(parse("font-bold font-semibold").marks).to eq(%w[strong])
    end
  end

  describe "grow and max width" do
    it "reads grow in its spellings" do
      %w[grow flex-grow flex-1].each { expect(parse(it).grow).to be(true) }
      expect(parse("flex").grow).to be_nil
    end

    it "reads max-w sizes and reports others" do
      expect(parse("max-w-xl").max_width).to eq("xl")
      expect(parse("max-w-screen-xl").unknown).to eq(%w[max-w-screen-xl])
    end

    it "accepts w-auto as a no-op" do
      expect(parse("w-auto").unknown).to eq([])
    end
  end

  describe "inline styles" do
    it "translates what lands on the vocabulary and reports the rest" do
      result = parse("flex", style: "gap: 20px; margin-top: 8px; position: sticky; top: 20px")

      expect(result.layout).to include(gap: 5)
      expect(result.spacing).to eq(top: 2)
      expect(result.unknown_styles).to eq(["position: sticky", "top: 20px"])
    end

    it "has none to report without a style" do
      expect(parse("flex").unknown_styles).to eq([])
    end
  end

  describe ".advice" do
    it "says what to use instead" do
      expect(described_class.advice("p-4")).to include("padding")
      expect(described_class.advice("mt-12")).to include("margins go up to 8")
      expect(described_class.advice("text-sm")).to include("no typed text size")
      expect(described_class.advice("whatever")).to eq("no typed equivalent")
    end
  end

  describe "toolbar_align" do
    it "reads text alignment or justify" do
      expect(parse("text-right").toolbar_align).to eq("end")
      expect(parse("flex justify-end").toolbar_align).to eq("end")
      expect(parse("flex justify-center").toolbar_align).to eq("center")
      expect(parse("flex").toolbar_align).to be_nil
    end
  end

  describe "unknown classes" do
    it "reports unsupported utilities, but not AA's semantic classes" do
      result = parse("p-4 w-1/5 hover:flex 2xl:grid-cols-3 md:flex-col md:text-right justify-around hidden button panel_contents nav-tabs")

      expect(result.unknown).to eq(%w[p-4 w-1/5 hover:flex 2xl:grid-cols-3 md:flex-col md:text-right justify-around hidden])
    end

    it "leaves the host's own dashed classes alone and flags utility look-alikes" do
      result = parse("button-secondary form-control panel-contents has-tooltip featured-regions page-title text-sm border-t sr-only space-y-2 min-w-0")

      expect(result.unknown).to eq(%w[text-sm border-t sr-only space-y-2 min-w-0])
    end

    it "yields no hints for classes it does not translate" do
      expect(parse("font-bold bg-red-500").hints).to eq({})
    end

    it "copes with nil and blank" do
      expect(parse(nil).hints).to eq({})
      expect(parse("  ").unknown).to eq([])
    end
  end
end
