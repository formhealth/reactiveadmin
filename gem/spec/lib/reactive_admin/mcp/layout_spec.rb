RSpec.describe ReactiveAdmin::Mcp::Layout do
  def text(value) = {"type" => "text", "text" => value}

  describe ".value" do
    it "reduces scalar nodes to plain values" do
      expect(described_class.value(text("Hi"))).to eq("Hi")
      expect(described_class.value({"type" => "number", "value" => 3})).to eq(3)
      expect(described_class.value({"type" => "boolean", "value" => false})).to be(false)
      expect(described_class.value({"type" => "datetime", "value" => "2026-01-05T12:00:00Z"})).to eq("2026-01-05T12:00:00Z")
      expect(described_class.value({"type" => "status", "label" => "Published", "variant" => "neutral"})).to eq("Published")
      expect(described_class.value({"type" => "empty"})).to be_nil
    end

    it "keeps references as resource/id with a label" do
      ref = {"type" => "ref", "label" => "Alice", "ref" => {"resource" => "authors", "id" => "1"}}

      expect(described_class.value(ref)).to eq(ref: "authors/1", label: "Alice")
      expect(described_class.value({"type" => "link", "label" => "Open", "href" => "/admin/posts/1", "external" => false, "ref" => {"resource" => "posts", "id" => "1"}})).to eq(ref: "posts/1", label: "Open")
    end

    it "keeps external links as label and url, and internal ones without a ref as a label" do
      expect(described_class.value({"type" => "link", "label" => "Docs", "href" => "https://x.test", "external" => true})).to eq(label: "Docs", url: "https://x.test")
      expect(described_class.value({"type" => "link", "label" => "Go", "href" => "/admin", "external" => false})).to eq("Go")
    end

    it "keeps a small json value and only the summary of a withheld one" do
      expect(described_class.value({"type" => "json", "value" => {"a" => 1}})).to eq({"a" => 1})
      summarized = {"type" => "json", "summary" => {"kind" => "object", "keys" => ["a"], "size" => 9_000}, "expand_path" => "/api/admin/posts/1/_value?field=x"}

      expect(described_class.value(summarized)).to eq(summary: summarized["summary"], expand_path: summarized["expand_path"])
    end

    it "says a truncated text is truncated and where the rest is" do
      node = text("Draft notes").merge("truncated" => true, "expand_path" => "/api/admin/notes/1/_value?field=body")

      expect(described_class.value(node)).to eq(text: "Draft notes", truncated: true, expand_path: "/api/admin/notes/1/_value?field=body")
    end

    it "never shows a masked value, and says what an image or document is" do
      expect(described_class.value({"type" => "masked"})).to eq("[masked]")
      expect(described_class.value({"type" => "image", "src" => "https://cdn.test/a.png", "alt" => "Scan"})).to eq("[image: Scan]")
      expect(described_class.value({"type" => "document", "src" => "https://cdn.test/a.pdf", "mime" => "application/pdf"})).to eq("[document: PDF]")
    end

    it "reduces html to its text" do
      expect(described_class.value({"type" => "html", "html" => "<p>One <strong>two</strong></p><script>x()</script>"})).to eq("One two")
    end

    it "describes an action node" do
      node = {"type" => "action", "action" => {"key" => "flag", "label" => "Flag", "method" => "post"}}

      expect(described_class.value(node)).to eq("[action flag: Flag (POST)]")
    end

    it "falls back to the text, label or type of a node it doesn't know" do
      expect(described_class.value({"type" => "mystery", "label" => "L"})).to eq("L")
      expect(described_class.value({"type" => "mystery"})).to eq("mystery")
    end
  end

  describe ".render" do
    let(:layout) do
      [
        {"type" => "heading", "level" => 1, "children" => [text("Report")]},
        {"type" => "panel", "title" => "Totals", "children" => [
          {"type" => "attributes_table", "rows" => [{"label" => "Count", "value" => [text("4")]}]},
          {"type" => "table", "headers" => %w[Name Qty], "rows" => [[text("Bolt"), {"type" => "number", "value" => 2}]]},
          {"type" => "list", "ordered" => true, "children" => [{"type" => "list_item", "children" => [text("first")]}]}
        ]},
        {"type" => "panel", "title" => "Empty", "children" => []},
        {"type" => "paragraph", "children" => [text("Hello "), {"type" => "link", "label" => "there", "href" => "/x", "external" => false}]},
        {"type" => "divider"},
        {"type" => "frame", "html" => "<form></form>", "src" => "/admin/x"}
      ]
    end

    it "writes headings, panels, tables, lists and paragraphs as text, and leaves out empty panels" do
      expect(described_class.render(layout)).to eq(<<~TEXT.strip)
        # Report
        ## Totals
        - Count: 4
        Name | Qty
        Bolt | 2
        1. first
        Hello there
        ---
        [interactive content omitted: open it in the admin UI]
      TEXT
    end

    it "leaves attribute tables to `attributes` when asked" do
      expect(described_class.render(layout, rows: false)).not_to include("Count")
    end
  end

  describe ".attributes" do
    it "collects the rows of every attributes table and definition list, however deep" do
      layout = [{"type" => "tabs", "children" => [{"type" => "tab", "title" => "A", "children" => [
        {"type" => "attributes_table", "rows" => [{"label" => "Name", "value" => [text("Ann")]}, {"label" => "Plan", "value" => [text("a"), text("b")]}]},
        {"type" => "definition_list", "rows" => [{"label" => "Name", "value" => [text("Again")]}]}
      ]}]}]

      expect(described_class.attributes(layout)).to eq("Name" => "Ann", "Plan" => "a b", "Name (2)" => "Again")
    end
  end

  describe ".actions" do
    it "finds action nodes in the layout" do
      layout = [{"type" => "panel", "children" => [{"type" => "action", "action" => {"key" => "flag"}}]}]

      expect(described_class.actions(layout)).to eq([{"key" => "flag"}])
    end
  end
end
