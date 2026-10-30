RSpec.describe ReactiveAdmin::HtmlRich do
  def nodes(html, **) = ReactiveAdmin::HtmlNodes.nodes(html, host: "www.example.com", **)

  def text(string, *marks, **extra) = {type: "text", text: string, marks: marks.presence, **extra}.compact

  before { ReactiveAdmin.diagnostics.clear }

  describe "headings" do
    it "maps h1 to h6 with their level and inline children" do
      expect(nodes("<h2>Care <em>team</em></h2>")).to eq([{type: "heading", level: 2, children: [text("Care "), text("team", "em")]}])
      expect(nodes("<h6>Small</h6>").first).to include(level: 6)
    end

    it "drops an empty heading" do
      expect(nodes("<h3> </h3>")).to eq([])
    end
  end

  describe "marks" do
    {"b" => "strong", "strong" => "strong", "i" => "em", "em" => "em", "u" => "underline", "s" => "strike", "del" => "strike",
     "mark" => "mark", "small" => "small", "sub" => "sub", "sup" => "sup", "kbd" => "code"}.each do |tag, mark|
      it "maps #{tag} to #{mark}" do
        expect(nodes("<p>a <#{tag}>b</#{tag}> c</p>")).to eq([{type: "paragraph", children: [text("a "), text("b", mark), text(" c")]}])
      end
    end

    it "stacks nested marks in order, without repeating one, and merges equal neighbours" do
      expect(nodes("<p><b>a <i>b <b>c</b></i></b></p>").first[:children]).to eq([text("a ", "strong"), text("b c", "strong", "em")])
    end

    it "makes a lone formatted element a text node, not a paragraph" do
      expect(nodes("<b>Total</b>")).to eq([text("Total", "strong")])
    end

    it "turns code inside prose into a mark but leaves a lone code as a code node" do
      expect(nodes("<p>Run <code>bin/rails</code> now</p>").first[:children]).to eq([text("Run "), text("bin/rails", "code"), text(" now")])
      expect(nodes("<code>x = 1</code>")).to eq([{type: "code", text: "x = 1"}])
      expect(nodes("<div>Run <code>x</code></div>").first[:children].first).to include(type: "paragraph")
    end

    it "keeps an abbr's expansion" do
      expect(nodes('<p><abbr title="Body mass index">BMI</abbr> is 24</p>').first[:children]).to eq([text("BMI", title: "Body mass index"), text(" is 24")])
    end
  end

  describe "paragraphs" do
    it "keeps spaces around inline elements and collapses runs" do
      html = %(<p>
        See   <a href="/admin/a">this</a>, then
        <strong>that</strong>.</p>)

      expect(nodes(html).first[:children]).to eq([text("See "), {type: "link", label: "this", href: "/admin/a", external: false}, text(", then "), text("that", "strong"), text(".")])
    end

    it "turns br into a break and trims spaces beside it" do
      expect(nodes("<p>one <br> <b>two</b></p>").first[:children]).to eq([text("one"), {type: "break"}, text("two", "strong")])
    end

    it "groups formatted runs inside any container, leaving block siblings alone" do
      html = '<div class="x"><h3>T</h3>Name: <b>Ann</b> (<a href="/a">a</a>)<table><tr><td>1</td></tr></table></div>'
      box = nodes(html).first

      expect(box[:children].pluck(:type)).to eq(%w[heading paragraph table])
      expect(box[:children][1][:children].pluck(:type)).to eq(%w[text text text link text])
    end

    it "leaves plain runs and text-only paragraphs as before" do
      expect(nodes("<p>plain</p>")).to eq([{type: "text", text: "plain"}])
      expect(nodes('a <a href="/a">b</a>').pluck(:type)).to eq(%w[text link])
      expect(nodes('<p class="text-right"><b>x</b></p>').first).to include(type: "box", tag: "p")
    end

    it "keeps status tags and controls in a paragraph as nodes" do
      children = nodes('<p>State: <span class="status_tag yes">Yes</span> <b>now</b></p>').first[:children]

      expect(children).to eq([text("State: "), {type: "status", label: "Yes", variant: "success"}, text(" "), text("now", "strong")])
    end
  end

  describe "other blocks" do
    it "maps hr to a divider" do
      expect(nodes("<p><b>a</b> b</p><hr><p>c</p>").pluck(:type)).to eq(%w[paragraph divider text])
    end

    it "maps blockquote to children" do
      expect(nodes("<blockquote><p>Quoted <b>text</b></p></blockquote>")).to eq([{type: "blockquote", children: [{type: "paragraph", children: [text("Quoted "), text("text", "strong")]}]}])
    end

    it "maps details and summary" do
      node = nodes("<details open><summary>More <b>info</b></summary><p>Body</p></details>").first

      expect(node).to eq(type: "disclosure", open: true, summary_nodes: [text("More "), text("info", "strong")], children: [{type: "text", text: "Body"}])
      expect(nodes("<details><p>x</p></details>").first).to include(open: false, summary_nodes: [text("Details")])
    end

    it "maps dl to rows, through div wrappers and with several details per term" do
      html = "<dl><div><dt>Plan</dt><dd>Gold</dd></div><dt>Notes</dt><dd>One</dd><dd><b>Two</b> x</dd><dt>Empty</dt></dl>"

      expect(nodes(html)).to eq([{type: "definition_list", rows: [
        {label: "Plan", value: [text("Gold")]},
        {label: "Notes", value: [text("One"), {type: "paragraph", children: [text("Two", "strong"), text(" x")]}]},
        {label: "Empty", value: [{type: "empty"}]}
      ]}])
    end
  end

  describe "lists" do
    it "gathers li outside any list into one list" do
      expect(nodes("<div><li>a</li> <li>b <i>c</i></li><p>x</p><li>d</li></div>").first[:children]).to eq([
        {type: "list", ordered: false, children: [
          {type: "list_item", children: [text("a")]},
          {type: "list_item", children: [{type: "paragraph", children: [text("b "), text("c", "em")]}]}
        ]},
        {type: "text", text: "x"},
        {type: "list", ordered: false, children: [{type: "list_item", children: [text("d")]}]}
      ])
    end

    it "nests lists and keeps ol ordered" do
      node = nodes("<ol><li>a<ul><li>b</li></ul></li></ol>").first

      expect(node).to include(type: "list", ordered: true)
      expect(node[:children].first[:children].pluck(:type)).to eq(%w[text list])
    end
  end

  describe "what stays html" do
    it "keeps unmapped tags as sanitized html and names them in a diagnostic" do
      node = nodes('<address onclick="x()">Home</address>', resource: "Author").first

      expect(node[:type]).to eq("html")
      expect(node[:html]).not_to include("onclick")
      expect(ReactiveAdmin.diagnostics.entries).to include(kind: :html_unmapped_tag, resource: "Author", path: "address[0]", tag: "address")
    end

    it "does not report tags that are mapped" do
      nodes("<h2>a</h2><hr><b>x</b><details><summary>s</summary>b</details>", resource: "Author")

      expect(ReactiveAdmin.diagnostics.entries.pluck(:kind)).not_to include(:html_unmapped_tag)
    end

    it "does not let markup inside mapped tags through" do
      node = nodes('<h2 onclick="x()"><script>alert(1)</script>Title<a href="javascript:alert(1)">l</a></h2>').first

      expect(node.to_json).not_to match(/script|onclick|javascript/)
    end
  end
end
