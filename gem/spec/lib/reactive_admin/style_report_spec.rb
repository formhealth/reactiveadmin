RSpec.describe ReactiveAdmin::StyleReport do
  let(:root) { Pathname(Dir.mktmpdir) }
  let(:diagnostics) do
    [
      {kind: "unknown_layout_class", resource: "Author", path: "div[0]", class: "p-4", source: "app/admin/authors.rb:12"},
      {kind: "unknown_layout_class", resource: "Author", path: "div[1]", class: "p-4", source: "app/admin/authors.rb:12"},
      {kind: "inline_style_ignored", resource: "Author", path: "div[2]", style: "position: sticky; top: 20px", ignored: "position: sticky; top: 20px",
       source: "app/admin/authors.rb:30"},
      {kind: "inline_style_ignored", resource: "", path: "div[0]", style: "padding: 12px", ignored: "padding: 12px"},
      {kind: "scan_capped", resource: "Author"}
    ]
  end
  let(:report) { described_class.run(sample: false) }

  before do
    allow(Rails).to receive(:root).and_return(root)
    allow(ReactiveAdmin::Doctor).to receive(:run).and_return(diagnostics:)
    root.join("app/admin").mkpath
    root.join("app/views/admin/authors").mkpath
    root.join("app/admin/authors.rb").write(<<~RUBY)
      div class: "flex gap-2 p-4" do
        div style: "margin-top: 8px;"
        span label, style: "color: #721c24; font-weight: bold;"
        para "x", style: "margin: 0 0 12px 0;"
        div style: "width: \#{pct}%"
      end
    RUBY
    root.join("app/views/admin/authors/_x.html.erb").write(%(<p style='position: sticky; top: 0'>a</p>\n))
    root.join("app/models/ignored.rb").tap { it.dirname.mkpath }.write(%(x class: "p-4"\n))
  end

  after { FileUtils.remove_entry(root) }

  describe "sampled" do
    subject(:sampled) { report[:sampled] }

    it "groups by resource, kind and exact string, with counts and sources" do
      expect(sampled.map { [it.resource, it.kind, it.value, it.count] }).to eq([
        ["(unlabelled)", "inline_style_ignored", "padding: 12px", 1],
        ["Author", "inline_style_ignored", "position: sticky; top: 20px", 1],
        ["Author", "unknown_layout_class", "p-4", 2]
      ])
      expect(sampled.last).to have_attributes(sources: ["app/admin/authors.rb:12"], paths: %w[div[0] div[1]])
    end

    it "suggests a replacement for each untranslated part" do
      expect(sampled.last.advice).to include("p-4: margins go up to 8")
      expect(sampled[1].advice).to include("position: classic-only layout", "top: classic-only layout")
    end

    it "ignores other diagnostics" do
      expect(sampled.map(&:kind).uniq).to contain_exactly("inline_style_ignored", "unknown_layout_class")
    end
  end

  describe "scanned" do
    subject(:scanned) { report[:scanned] }

    it "lists only what has no translation, by file and line, from admin source" do
      expect(scanned.map { [it.file, it.line, it.kind, it.untranslated] }).to eq([
        ["app/admin/authors.rb", 1, "unknown_layout_class", "p-4"],
        ["app/admin/authors.rb", 3, "inline_style_ignored", "color: #721c24"],
        ["app/views/admin/authors/_x.html.erb", 1, "inline_style_ignored", "position: sticky; top: 0"]
      ])
    end

    it "keeps the exact string and skips interpolated ones" do
      expect(scanned.map(&:value)).to include("color: #721c24; font-weight: bold;")
      expect(scanned.map(&:value)).not_to include(a_string_matching(/pct/))
    end
  end

  describe "rendering" do
    let(:renderer) { described_class::Renderer.new(report) }

    it "summarises and groups the markdown by resource and file" do
      markdown = renderer.to_markdown

      expect(markdown).to include("**3** distinct findings (4 occurrences) in 2 sampled resources", "### Author", "### app/admin/authors.rb")
      expect(markdown).to include("| unknown_layout_class | `p-4` | `p-4` | 2 | `app/admin/authors.rb:12` |")
    end

    it "renders json with the same summary" do
      json = JSON.parse(renderer.to_json)

      expect(json["summary"]).to include("sampled_findings" => 3, "sampled_occurrences" => 4, "scanned_untranslated" => 3)
      expect(json["sampled"].first).to include("resource" => "(unlabelled)", "kind" => "inline_style_ignored")
    end

    it "says so when there is nothing to report" do
      allow(ReactiveAdmin::Doctor).to receive(:run).and_return(diagnostics: [])
      root.join("app/admin/authors.rb").delete
      root.join("app/views/admin/authors/_x.html.erb").delete

      expect(renderer.to_markdown.scan("None.").size).to eq(2)
    end
  end

  describe "the rake task entry" do
    it "writes the report to OUT" do
      out = StringIO.new
      path = root.join("styles.md")

      described_class::CLI.run({"OUT" => path.to_s, "SAMPLE" => "0"}, out:)

      expect(path.read).to start_with("# Styles report")
      expect(out.string).to include("styles report written")
    end

    it "prints json on request" do
      out = StringIO.new

      described_class::CLI.run({"FORMAT" => "json", "SAMPLE" => "0"}, out:)

      expect(JSON.parse(out.string)).to have_key("summary")
    end
  end
end
