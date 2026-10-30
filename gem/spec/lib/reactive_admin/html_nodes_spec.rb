RSpec.describe ReactiveAdmin::HtmlNodes do
  def nodes(html, **) = described_class.nodes(html, host: "www.example.com", **)

  def convert(html) = described_class.convert(html, host: "www.example.com")

  # What the DSL's own link_to and button_to produce: anchors and forms carrying the request's secret.
  def host_nodes(html, stamped: "a, form", **)
    ReactiveAdmin::Provenance.with_scope do
      secret = ReactiveAdmin::Provenance::STATE[ReactiveAdmin::Provenance::KEY]
      fragment = Nokogiri::HTML5.fragment(html)
      fragment.css(stamped).each { it[ReactiveAdmin::Provenance::ATTRIBUTE] = secret }
      nodes(fragment.to_html, **)
    end
  end

  def a_link(label, href) = {type: "link", label:, href:, external: false}

  def diagnostics = ReactiveAdmin.diagnostics.entries

  before { ReactiveAdmin.diagnostics.clear }

  describe "text and structure" do
    it "turns plain text into a text node and drops blanks" do
      expect(nodes("  hello  ")).to eq([{type: "text", text: "hello"}])
      expect(nodes("   ")).to eq([])
    end

    it "collapses a single node and groups several" do
      expect(convert("<address>x</address>")).to eq(type: "html", html: "<address>x</address>")
      expect(convert("a<address>b</address>")).to eq(type: "group", children: [{type: "text", text: "a"}, {type: "html", html: "<address>b</address>"}])
      expect(convert("")).to eq(type: "empty")
    end

    it "unwraps span and div without children into text" do
      expect(nodes("<span>hi</span><div>there</div>").pluck(:text)).to eq(%w[hi there])
    end

    it "keeps boxes that wrap other elements" do
      box = nodes('<div class="x">Name <a href="/admin/a">A</a></div>').first

      expect(box).to eq(type: "box", tag: "div", children: [{type: "text", text: "Name"}, a_link("A", "/admin/a")])
    end

    it "drops br" do
      expect(nodes("a<br>b").pluck(:text)).to eq(%w[a b])
    end

    it "recognises AA's empty marker" do
      expect(nodes('<span class="empty">Empty</span>')).to eq([{type: "empty"}])
    end
  end

  describe "status tags" do
    {"yes" => "success", "ok" => "success", "warning" => "warning", "error" => "danger", "info" => "info", "other" => "neutral"}.each do |css, variant|
      it "maps .#{css} to #{variant}" do
        expect(nodes(%(<span class="status_tag #{css}">Label</span>))).to eq([{type: "status", label: "Label", variant:}])
      end
    end
  end

  describe "links" do
    it "marks external hosts" do
      expect(nodes('<a href="https://other.test/x">X</a>').first).to include(type: "link", href: "https://other.test/x", external: true)
    end

    it "keeps same-host and relative admin links internal" do
      expect(nodes('<a href="/admin/nowhere">N</a>').first).to include(external: false)
      expect(nodes('<a href="http://www.example.com/admin/y">Y</a>').first).to include(external: false)
    end

    describe "same-host paths outside the admin namespace" do
      def link(href, base_url: "http://www.example.com:3003")
        links = ReactiveAdmin::ActionLinks.new(host: "www.example.com", base_url:)
        described_class.nodes(%(<a href="#{href}">S</a>), host: "www.example.com", links:).first
      end

      it "are external with an absolute href, since the SPA may be on another origin" do
        expect(link("/sidekiq/retries?substr=Foo")).to eq(type: "link", label: "S", href: "http://www.example.com:3003/sidekiq/retries?substr=Foo", external: true)
        expect(link("http://www.example.com/sidekiq")).to include(href: "http://www.example.com/sidekiq", external: true)
      end

      it "keep the relative href without a base url" do
        expect(link("/sidekiq", base_url: nil)).to include(href: "/sidekiq", external: true)
      end

      it "cover the API mount and dot segments out of the namespace" do
        expect(link("/api/admin/posts")).to include(external: true)
        expect(link("/admin/../sidekiq")).to include(external: true)
        expect(link("/administrators")).to include(external: true)
      end

      it "leave fragments and query-only links alone" do
        expect(link("#top")).to include(external: false)
        expect(link("?page=2")).to include(external: false)
      end

      it "get no ref or view" do
        expect(link("/sidekiq/retries")).not_to include(:ref, :view)
      end

      it "never revive unsafe schemes" do
        expect(link("javascript:alert(1)")).to eq(type: "text", text: "S")
      end
    end

    it "drops javascript: and data: links to plain text" do
      expect(nodes('<a href="javascript:alert(1)">bad</a>')).to eq([{type: "text", text: "bad"}])
      expect(nodes('<a href="data:text/html,x">bad</a>')).to eq([{type: "text", text: "bad"}])
    end

    it "keeps mailto and tel" do
      expect(nodes('<a href="mailto:a@b.co">mail</a>').first).to include(type: "link", href: "mailto:a@b.co", external: true)
      expect(nodes('<a href="tel:123">call</a>').first).to include(type: "link", href: "tel:123", external: true)
    end

    it "attaches a ref to links that point at a resource's show page" do
      link = nodes('<a href="/admin/authors/12">A</a>').first

      expect(link[:ref]).to eq(resource: "authors", id: "12")
    end

    it "gives nested-only resources a path in their ref" do
      link = nodes('<a href="/admin/posts/3/comments/9">C</a>').first

      expect(link[:ref]).to eq(resource: "comments", id: "9", path: "/admin/posts/3/comments/9", api_path: "/api/admin/posts/3/comments/9")
    end

    it "does not ref non-show pages or unknown routes" do
      expect(nodes('<a href="/admin/authors">A</a>').first).not_to have_key(:ref)
      expect(nodes('<a href="/nope/1">A</a>').first).not_to have_key(:ref)
    end

    it "does not ref other hosts" do
      expect(nodes('<a href="https://other.test/admin/authors/1">A</a>').first).not_to have_key(:ref)
    end
  end

  describe "controls that act" do
    it "turns data-method links into inline actions" do
      node = host_nodes('<a href="/admin/posts/1/archive" data-method="post" data-confirm="Sure?">Archive</a>').first

      expect(node[:type]).to eq("action")
      expect(node[:action]).to include(key: "archive", kind: "member", method: "post", placement: "inline", confirm: "Sure?",
        api_path: "/api/admin/posts/1/archive")
    end

    it "turns single-button forms into inline actions with the form's verb" do
      html = '<form action="/admin/posts/1/publish" method="post"><input type="hidden" name="_method" value="put"><button type="submit">Go</button></form>'

      expect(host_nodes(html).first[:action]).to include(method: "put", label: "Go", api_path: "/api/admin/posts/1/publish")
    end

    it "marks controls that point nowhere known as unsupported" do
      node = host_nodes('<a href="/somewhere/else" data-method="delete">Del</a>').first

      expect(node[:action]).to include(kind: "link", supported: false, enabled: false)
    end

    it "does not treat forms with real inputs as single-button" do
      html = '<form action="/x" method="post"><input type="text" name="q"><button>Go</button></form>'

      expect(host_nodes(html).first[:type]).to eq("html")
    end
  end

  describe "markup a stored value carried in" do
    let(:delete_link) { '<a href="/admin/posts/1" data-method="delete" data-confirm="Totally safe">Read more</a>' }
    let(:one_button) { '<form class="button_to" method="post" action="/admin/posts/1/publish"><input type="submit" value="Click to continue"></form>' }

    it "never turns a data-method link into an action" do
      expect(nodes(delete_link)).to eq([{type: "text", text: "Read more"}])
      expect(nodes(%(<div>#{delete_link}</div>)).first).to include(type: "box", children: [{type: "text", text: "Read more"}])
    end

    it "shows a data-confirm link as a plain link without the confirm" do
      expect(nodes('<a href="/admin/posts/1" data-confirm="Totally safe">Read more</a>').first)
        .to include(type: "link", label: "Read more", href: "/admin/posts/1").and(satisfy { !it.key?(:confirm) && !it.key?(:action) })
    end

    it "never turns a one-button form into an action or a frame" do
      expect(nodes(one_button).pluck(:type)).not_to include("action", "frame")
      expect(nodes(one_button, frame_src: "/admin/posts/1").pluck(:type)).not_to include("action", "frame")
    end

    it "strips data-method from stored links inside a host form's frame" do
      form = %(<form method="post" action="/admin/posts/1"><input name="a"><a href="/admin/posts/1" data-method="delete">Del</a></form>)
      frame = host_nodes(form, stamped: "form", frame_src: "/admin/posts/1").first

      expect(frame).to include(type: "frame")
      expect(frame[:html]).not_to include("data-method")
    end

    it "ignores a guessed or stale secret" do
      forged = delete_link.sub("<a ", %(<a #{ReactiveAdmin::Provenance::ATTRIBUTE}="guess" ))
      stale = ReactiveAdmin::Provenance.with_scope { ReactiveAdmin::Provenance::STATE[ReactiveAdmin::Provenance::KEY] }

      ReactiveAdmin::Provenance.with_scope do
        expect(nodes(forged).pluck(:type)).to eq(%w[text])
        expect(nodes(delete_link.sub("<a ", %(<a #{ReactiveAdmin::Provenance::ATTRIBUTE}="#{stale}" ))).pluck(:type)).to eq(%w[text])
      end
    end

    it "keeps host-stamped controls as actions beside stored ones" do
      list = host_nodes(%(<div class="text-right">#{delete_link}</div>))

      expect(list.first).to include(type: "toolbar")
      expect(list.first[:children].first).to include(type: "action", action: include(confirm: "Totally safe", method: "delete"))
    end

    it "frames only the pages of registered resources" do
      expect(nodes('<iframe src="/admin/posts/1"></iframe>').first).to include(type: "iframe", src: "/admin/posts/1?embed=1")
      expect(nodes('<iframe src="http://www.example.com/admin/posts/1"></iframe>').first).to include(type: "iframe")
      %w[/rails/active_storage/blobs/x/evil.html /admin/unknown/1 /admin/../rails/x/evil.html /admin/posts/%2e%2e/%2e%2e/x /admin //x.test/admin/posts/1].each do |src|
        expect(nodes(%(<iframe src="#{src}"></iframe>)).first[:type]).not_to eq("iframe"), src
      end
    end
  end

  describe "AA components" do
    it "walks attributes tables" do
      html = '<div class="attributes_table"><table><tbody><tr><th>Name</th><td>Ann</td></tr><tr><th>Empty</th><td></td></tr></tbody></table></div>'

      expect(nodes(html).first).to eq(type: "attributes_table", title: nil, rows: [
        {label: "Name", value: [{type: "text", text: "Ann"}]},
        {label: "Empty", value: [{type: "empty"}]}
      ])
    end

    it "walks panels with titles" do
      html = '<div class="panel"><h3>T</h3><div class="panel_contents">body</div></div>'

      expect(nodes(html).first).to eq(type: "panel", title: "T", children: [{type: "text", text: "body"}])
    end

    it "walks tables into headers and cell nodes" do
      html = "<table><thead><tr><th>A</th></tr></thead><tbody><tr><td>1</td></tr></tbody></table>"

      expect(nodes(html).first).to eq(type: "table", headers: %w[A], rows: [[{type: "text", text: "1"}]])
    end

    it "walks columns" do
      html = '<div class="columns"><div class="column">a</div><div class="column">b</div></div>'

      expect(nodes(html).first[:children].pluck(:type)).to eq(%w[column column])
    end

    it "walks tabs" do
      html = '<div class="tabs"><ul class="nav-tabs"><li>One</li></ul><div class="tab-content"><div>x</div></div></div>'

      expect(nodes(html).first).to eq(type: "tabs", children: [{type: "tab", title: "One", children: [{type: "text", text: "x"}]}])
    end
  end

  describe "layout boxes" do
    let(:html) do
      <<~HTML
        <div class="flex lg:flex-row gap-5">
          <div class="w-2/3"><p>Main <b>bold</b></p></div>
          <div class="w-1/3 text-right"><p>Side <b>bold</b></p></div>
        </div>
      HTML
    end

    it "translates utility classes into hints and drops the classes" do
      box = nodes(html).first

      expect(box).to include(type: "box", layout: {display: "flex", direction: "row", breakpoint: "lg", gap: 5, wrap: false})
      expect(box).not_to have_key(:class_name)
      expect(box[:children].map { it.slice(:width, :text_align) }).to eq([{width: "2/3"}, {width: "1/3", text_align: "right"}])
      expect(diagnostics).to be_empty
    end

    it "keeps a text-only element that carries hints" do
      expect(nodes('<div class="text-right">Total</div>').first).to eq(
        type: "box", tag: "div", text_align: "right", children: [{type: "text", text: "Total"}]
      )
    end

    it "reports unknown utility classes and inline styles with the resource, a structural path and the exact strings" do
      described_class.nodes('<div class="p-4 panel_x"><div style="position: sticky;  top: 20px; margin-top: 8px"><ul><li>x</li></ul></div></div>', resource: "Author")

      expect(diagnostics).to contain_exactly(
        {kind: :unknown_layout_class, resource: "Author", path: "div[0]", class: "p-4"},
        {kind: :inline_style_ignored, resource: "Author", path: "div[0]/div[0]", style: "position: sticky; top: 20px; margin-top: 8px", ignored: "position: sticky; top: 20px"}
      )
    end

    it "translates the safe inline styles instead of reporting them" do
      node = nodes('<div style="margin: 0 0 20px 0; text-align: right; display: flex; gap: 16px; align-items: flex-start"><ul><li>x</li></ul></div>').first

      expect(node).to include(type: "box", text_align: "right", spacing: {bottom: 5},
        layout: {display: "flex", direction: "row", breakpoint: nil, gap: 4, wrap: false, align: "start"})
      expect(diagnostics).to be_empty
    end

    it "carries margins on boxes" do
      expect(nodes('<div class="mt-2 mb-4"><a href="/a">x</a> y</div>').first).to include(type: "box", spacing: {top: 2, bottom: 4})
    end

    it "keeps a styled text-only element as text with marks and tone" do
      expect(nodes('<span style="font-weight: bold; font-style: italic; color: #999">Name</span>').first).to eq(
        type: "text", text: "Name", marks: %w[strong em], tone: "muted"
      )
    end

    it "keeps marks and tone on a box for its content" do
      expect(nodes('<div class="font-bold text-danger"><a href="/a">A</a> x</div>').first).to include(type: "box", marks: %w[strong], tone: "danger")
    end

    it "keeps the margin of a toolbar" do
      bar = nodes('<div class="mt-4"><a href="/a">A</a></div>').first

      expect(bar).to include(type: "toolbar", spacing: {top: 4})
    end
  end

  describe "toolbars" do
    let(:button) { '<form class="button_to" method="post" action="/admin/posts/1/publish"><button type="submit" data-confirm="Sure?">Go</button></form>' }

    it "turns a container of only buttons and links into a toolbar, through wrapper divs" do
      bar = host_nodes(%(<div class="flex flex-row gap-1">\n<div>#{button}</div>\n<div><a href="/a">A</a></div></div>)).first

      expect(bar).to include(type: "toolbar", align: "start")
      expect(bar[:children].pluck(:type)).to eq(%w[action link])
      expect(bar[:children].first[:action]).to include(confirm: "Sure?", method: "post", placement: "inline")
    end

    it "aligns from text-right or justify-end" do
      expect(host_nodes('<div class="text-right"><a href="/a">A</a></div>').first).to include(type: "toolbar", align: "end")
      expect(host_nodes('<div class="flex justify-center"><a href="/a">A</a></div>').first).to include(align: "center")
    end

    it "merges neighbouring toolbars with the same alignment" do
      html = '<div class="text-right"><a href="/a">A</a></div><div class="text-right"><a href="/b">B</a></div><div><a href="/c">C</a></div>'

      expect(host_nodes(html).map { [it[:align], it[:children].pluck(:label)] }).to eq([["end", %w[A B]], ["start", %w[C]]])
    end

    it "stays a box when there is other content, a width or a column direction" do
      expect(host_nodes('<div><a href="/a">A</a> and more</div>').first[:type]).to eq("box")
      expect(host_nodes('<div class="w-1/3"><a href="/a">A</a></div>').first).to include(type: "box", width: "1/3")
      expect(host_nodes('<div class="flex flex-col"><a href="/a">A</a></div>').first[:type]).to eq("box")
      expect(host_nodes('<div><a href="/a">A</a><b>x</b></div>').first[:type]).to eq("box")
    end

    it "does not treat a panel or an unsafe link as a toolbar" do
      expect(host_nodes('<div class="panel"><h3>T</h3><div class="panel_contents"><a href="/a">A</a></div></div>').first[:type]).to eq("panel")
      expect(host_nodes('<div><a href="javascript:x()">bad</a></div>').first[:type]).to eq("box")
    end

    it "keeps a trailing toolbar inside its panel" do
      html = %(<div class="panel"><h3>T</h3><div class="panel_contents">body<div class="flex">#{button}</div></div></div>)

      expect(host_nodes(html).first[:children].pluck(:type)).to eq(%w[text toolbar])
    end
  end

  describe "lists" do
    it "turns ul and ol into list and list_item nodes, nesting included" do
      html = '<ul><li><a href="/admin/a">A</a></li><li><span class="x">Stripe</span><ol><li>One</li></ol></li></ul>'

      expect(nodes(html)).to eq([{type: "list", ordered: false, children: [
        {type: "list_item", children: [a_link("A", "/admin/a")]},
        {type: "list_item", children: [
          {type: "text", text: "Stripe"},
          {type: "list", ordered: true, children: [{type: "list_item", children: [{type: "text", text: "One"}]}]}
        ]}
      ]}])
    end

    it "keeps a list with stray children as items" do
      expect(nodes("<ul><div>x</div></ul>")).to eq([{type: "list", ordered: false, children: [{type: "list_item", children: [{type: "text", text: "x"}]}]}])
    end
  end

  describe "code and json" do
    it "types a pre/code holding a JSON object or array as a json node, inline on show pages" do
      expect(nodes('<pre style="x"><code>{"a": [1, 2], "b": null}</code></pre>', frame_src: "/x")).to eq([{type: "json", value: {"a" => [1, 2], "b" => nil}}])
      expect(nodes('<code>[1, "a"]</code>', frame_src: "/x")).to eq([{type: "json", value: [1, "a"]}])
    end

    it "summarizes json elsewhere, as Values does for index cells" do
      expect(nodes('<pre><code>{"a": 1, "b": 2}</code></pre>')).to eq([{type: "json", summary: {kind: "object", keys: %w[a b], size: 13}}])
    end

    it "summarizes json holding masked keys even on show pages" do
      ReactiveAdmin.config.masked_attributes = [:secret]

      expect(nodes('<pre><code>{"secret": "x"}</code></pre>', frame_src: "/x").first).to include(summary: {kind: "object", keys: ["secret"], size: 14})
    ensure
      ReactiveAdmin.config.masked_attributes = []
    end

    it "types anything else as code, with a language when the markup names one" do
      expect(nodes("<pre><code>nil</code></pre>")).to eq([{type: "code", text: "nil"}])
      expect(nodes('<pre><code class="language-ruby">puts 1</code></pre>')).to eq([{type: "code", text: "puts 1", language: "ruby"}])
      expect(nodes("<pre>{broken</pre>")).to eq([{type: "code", text: "{broken"}])
      expect(nodes("<code>123</code>")).to eq([{type: "code", text: "123"}])
    end

    it "keeps marked-up code as html and blank code as empty" do
      expect(nodes('<pre><code><a href="/x">x</a></code></pre>').first[:type]).to eq("html")
      expect(nodes("<pre><code> </code></pre>")).to eq([{type: "empty"}])
    end

    it "types json inside table cells" do
      table = nodes('<table><tbody><tr><th>k</th><td><pre><code>{"a": 1}</code></pre></td></tr></tbody></table>', frame_src: "/x").first

      expect(table[:rows]).to eq([[{type: "text", text: "k"}, {type: "json", value: {"a" => 1}}]])
    end
  end

  describe "time" do
    it "types a time with a datetime attribute" do
      expect(nodes('<time datetime="2026-05-01T10:00:00Z">May 1</time>')).to eq([{type: "datetime", value: "2026-05-01T10:00:00Z"}])
      expect(nodes('<time datetime="2026-05-01">May 1</time>')).to eq([{type: "date", value: "2026-05-01"}])
    end

    it "leaves a time it can't read as html" do
      expect(nodes('<time datetime="soon">soon</time>').first[:type]).to eq("html")
    end
  end

  describe "media" do
    after { ReactiveAdmin.config.html_trusted_hosts = [] }

    it "turns external images into links and same-site ones into image nodes" do
      expect(nodes('<img src="https://evil.test/a.png">')).to eq([{type: "link", label: "External image", href: "https://evil.test/a.png", external: true}])
      expect(nodes('<img src="/a.png" alt="a" width="40" height="30">')).to eq([{type: "image", src: "/a.png", alt: "a", width_px: 40, height_px: 30}])
    end

    it "keeps a data image as html, since an image node never carries data:" do
      expect(nodes('<img src="data:image/png;base64,iVBORw0KGgo=">').first[:type]).to eq("html")
    end

    it "turns a same-site pdf embed into a document node and links external ones" do
      expect(nodes('<embed src="/a.pdf" type="application/pdf">')).to eq([{type: "document", src: "/a.pdf", mime: "application/pdf"}])
      expect(nodes('<embed src="https://evil.test/a.pdf">').first).to include(type: "link", label: "External document")
    end

    it "emits image and document nodes for a trusted host, with no extension needed for the pdf" do
      ReactiveAdmin.config.html_trusted_hosts = -> { ["cdn.test"] }

      expect(nodes('<img src="https://cdn.test/abc/?token=x" alt="">')).to eq([{type: "image", src: "https://cdn.test/abc/?token=x", alt: ""}])
      expect(nodes('<embed src="https://cdn.test/abc/?token=x" type="application/pdf" height="800px">')).to eq([{type: "document", src: "https://cdn.test/abc/?token=x", mime: "application/pdf"}])
      expect(nodes('<object data="https://cdn.test/abc/" type="application/pdf" title="Lab"></object>')).to eq([{type: "document", src: "https://cdn.test/abc/", mime: "application/pdf", title: "Lab"}])
      expect(nodes('<iframe src="https://cdn.test/a.pdf"></iframe>').first).to include(type: "document")
    end

    it "does not take an extensionless same-site embed or a non-pdf embed from a trusted host" do
      ReactiveAdmin.config.html_trusted_hosts = ["cdn.test"]

      expect(nodes('<embed src="/files/1" type="application/pdf">')).to eq([])
      expect(nodes('<embed src="https://cdn.test/abc/" type="text/html">').first).to include(type: "link", label: "External document")
      expect(nodes('<iframe src="https://cdn.test/page"></iframe>').first).to include(type: "link", label: "Embedded page")
    end

    it "keeps media typed inside a details preview" do
      html = '<details open><summary>Collapse Preview</summary><img src="/a.png" alt="scan"></details>'

      expect(nodes(html).first).to include(type: "disclosure", children: [{type: "image", src: "/a.png", alt: "scan"}])
    end

    it "turns a same-site iframe into an iframe node and links out the rest" do
      expect(nodes('<iframe src="/admin/posts/1" title="X"></iframe>')).to eq([{type: "iframe", src: "/admin/posts/1?embed=1", title: "X"}])
      expect(nodes('<iframe src="/files/a.pdf" title="A"></iframe>')).to eq([{type: "document", src: "/files/a.pdf", mime: "application/pdf", title: "A"}])
      expect(nodes('<iframe src="https://evil.test/"></iframe>').first).to include(type: "link", label: "External page")
    end

    it "sanitizes media nested in html fallbacks" do
      html = nodes('<address><img src="https://evil.test/a.png"> title</address>').first[:html]

      expect(html).to include("External image")
      expect(html).not_to include("<img")
    end

    it "links out external media inside a heading" do
      expect(nodes('<h2><img src="https://evil.test/a.png"> title</h2>').first[:children]).to include(include(type: "link", label: "External image"))
    end
  end

  describe "tables without a header row" do
    it "keeps row headers as cells" do
      expect(nodes("<table><tr><th>Name</th><td>x</td></tr></table>").first).to eq(type: "table", headers: [], rows: [[{type: "text", text: "Name"}, {type: "text", text: "x"}]])
    end
  end

  describe "size limits" do
    def degraded_kinds
      ReactiveAdmin::Degradation.with_collection do
        yield
        ReactiveAdmin::Degradation.entries.pluck(:kind)
      end
    end

    it "shows a section nested too deep as text, never raises" do
      list = nil
      kinds = degraded_kinds { list = nodes("<table><tr><td>ok</td><td>#{"<div>" * 500}</td></tr></table>") }

      expect(list).to eq([{type: "text", text: ReactiveAdmin::HtmlPolicy::TOO_COMPLEX}])
      expect(kinds).to eq(%w[html_too_deep])
    end

    it "bounds a huge section to the node cap" do
      list = nil
      kinds = degraded_kinds { list = nodes("<address>x</address>" * 5_000) }

      expect(list.size).to eq(ReactiveAdmin::HtmlPolicy::MAX_NODES)
      expect(kinds).to include("html_truncated")
    end
  end

  describe ".sanitize" do
    it "strips scripts, event handlers and javascript urls" do
      html = described_class.sanitize('<p onclick="x()">hi<script>alert(1)</script><a href="javascript:alert(1)">l</a></p>')

      expect(html).to include("<p>hi")
      expect(html).not_to include("script", "onclick", "javascript")
    end

    it "keeps tables, images and the safe attributes" do
      html = described_class.sanitize('<table><tr><td class="c">x</td></tr></table><img src="/a.png" alt="a">')

      expect(html).to include("<table>", "<td>x</td>", '<img src="/a.png"')
      expect(html).not_to include("class=")
    end

    it "keeps text of unknown tags but not the tags" do
      expect(described_class.sanitize("<blink>x</blink>")).to eq("x")
    end

    it "is applied to unrecognised elements" do
      expect(nodes('<address onclick="x()">a</address>').first[:html]).not_to include("onclick")
    end
  end
end
