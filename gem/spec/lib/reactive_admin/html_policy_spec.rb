RSpec.describe ReactiveAdmin::HtmlPolicy do
  let(:host) { "app.test" }

  def display(html, **) = described_class.display(html, host:, **)

  def interactive(html) = described_class.interactive(html, host:)

  def frame_body(html) = described_class.frame_body(html, host:)

  def fragment(html) = Nokogiri::HTML5.fragment(html)

  def degraded = ReactiveAdmin::Degradation.with_collection { yield.then { ReactiveAdmin::Degradation.entries.pluck(:kind) } }

  describe ".same_origin?" do
    it "accepts relative urls and the request host" do
      expect(%w[/a a.png ?x=1 #top http://app.test/x https://APP.test/x]).to all(satisfy { described_class.same_origin?(it, host) })
    end

    it "rejects other hosts, protocol-relative urls, other schemes and tricks" do
      urls = ["https://evil.test/x", "//evil.test/x", "javascript:x()", "data:text/html,x", "/\\evil.test", "/\t/evil.test", "http://app.test.evil.test/"]

      expect(urls.reject { described_class.same_origin?(it, host) }).to eq(urls)
    end

    it "accepts configured trusted hosts" do
      ReactiveAdmin.config.html_trusted_hosts = -> { ["cdn.test"] }

      expect(described_class.same_origin?("https://cdn.test/f.pdf", host)).to be(true)
    ensure
      ReactiveAdmin.config.html_trusted_hosts = []
    end

    it "needs a host after a scheme, so scheme-without-slashes is never same-site" do
      urls = ["https:evil.test/x", "http:/evil.test/x", "https:///evil.test/x", "HTTPS:evil.test", "https:app.test/x", "https:"]

      expect(urls.reject { described_class.same_origin?(it, host) }).to eq(urls)
    end

    it "rejects protocol-relative and backslash forms however they are spelled" do
      urls = ["///evil.test/x", "\\\\evil.test/x", "/\\/evil.test", "\\/evil.test", "https://app.test\\@evil.test/x",
        "https://app.test:443@evil.test/x", "https://app.test./x", "https://app.test.evil.test/x", "javascript:x", "a:b.png"]

      expect(urls.reject { described_class.same_origin?(it, host) }).to eq(urls)
    end

    it "rejects whitespace, control and non-ascii characters inside the url" do
      urls = ["ht\ttps://app.test/x", "https://app.te\nst/x", "/a\u0000b", "/a\u007fb", "/a b.png", "/\u00a0/evil.test", "https://app.test/\u2028x"]

      expect(urls.reject { described_class.same_origin?(it, host) }).to eq(urls)
    end

    it "accepts single-slash paths, relative references and any case of the request host" do
      expect(%w[/a/b?c#d ./a.png HTTPS://APP.TEST/x https://app.test]).to all(satisfy { described_class.same_origin?(it, host) })
    end
  end

  describe ".display" do
    it "keeps same-site and data images, adding a no-referrer lazy policy that the markup can't override" do
      html = display('<img src="/a.png" referrerpolicy="unsafe-url" loading="eager"><img src="data:image/png;base64,iVBORw0KGgo=">')
      images = fragment(html).css("img")

      expect(images.map { it["src"] }).to eq(["/a.png", "data:image/png;base64,iVBORw0KGgo="])
      expect(images.map { [it["referrerpolicy"], it["loading"]] }.uniq).to eq([%w[no-referrer lazy]])
    end

    it "replaces external images with a link and records it" do
      html = nil
      kinds = degraded { html = display('<p><img src="https://evil.test/track.png?u=1" onerror="x()"></p>') }

      expect(html).to eq('<p><a href="https://evil.test/track.png?u=1" target="_blank" rel="noopener noreferrer">External image</a></p>')
      expect(kinds).to eq(%w[external_media_blocked])
    end

    it "drops images with unusable sources, svg data uris included" do
      expect(display('<img src="data:image/svg+xml;base64,PHN2Zz4="><img src="javascript:x()"><img src="ftp://h/x">')).to eq("")
    end

    it "keeps same-site embeds and objects and links out the rest" do
      expect(display('<embed src="/files/a.pdf" type="application/pdf" width="100%">')).to include('<embed src="/files/a.pdf"')
      expect(display('<object data="/files/a.pdf" type="application/pdf"></object>')).to include('<object data="/files/a.pdf"')
      expect(display('<embed src="https://evil.test/a.pdf">')).to include('<a href="https://evil.test/a.pdf"', "External document")
      expect(display('<object data="https://evil.test/a.pdf"></object>')).to include("External document")
    end

    it "never keeps an iframe in html" do
      expect(display('<iframe src="/x"></iframe>')).not_to include("<iframe")
      expect(display('<iframe src="https://evil.test"></iframe>')).to include("External page")
      expect(display('<iframe srcdoc="<script>1</script>" src="javascript:x()"></iframe>')).to eq("")
    end

    it "lets configured hosts load media" do
      ReactiveAdmin.config.html_trusted_hosts = ["cdn.test"]

      expect(display('<img src="https://cdn.test/a.png">')).to include('src="https://cdn.test/a.png"')
    ensure
      ReactiveAdmin.config.html_trusted_hosts = []
    end

    it "only embeds a same-site pdf, by declared type and path" do
      expect(display('<embed src="/a.html" type="text/html">')).to eq("")
      expect(display('<embed src="/a.pdf">')).to eq("")
      expect(display('<embed src="/a.svg" type="image/svg+xml">')).to eq("")
      expect(display('<object data="/admin/authors" type="application/pdf"></object>')).to eq("")
      expect(display('<object data="/A.PDF?x=1#y" type="Application/PDF"></object>')).to include('<object data="/A.PDF?x=1#y"')
    end

    it "lets a trusted host serve a declared pdf without an extension, never a same-site path" do
      ReactiveAdmin.config.html_trusted_hosts = ["cdn.test"]

      expect(display('<embed src="https://cdn.test/abc/?token=x" type="application/pdf">')).to include("<embed")
      expect(display('<embed src="https://cdn.test/abc/">')).to include("External document")
      expect(display('<embed src="/abc/" type="application/pdf">')).to eq("")
    ensure
      ReactiveAdmin.config.html_trusted_hosts = []
    end

    it "treats a scheme-without-slashes image as off-site, never as a same-site image" do
      expect(display('<img src="https:evil.test/a.png"><img src="http:/evil.test/a.png">')).to eq("")
      expect(display('<img src="http:///evil.test/a.png">')).not_to include("<img")
    end

    it "strips referrer and loading attributes from everything but images" do
      expect(display('<a href="/x" referrerpolicy="unsafe-url" loading="lazy">x</a>')).to eq('<a href="/x">x</a>')
    end

    it "strips scripts, handlers and unsafe urls" do
      html = display('<p onclick="x()">hi<script>1</script><style>a{}</style><a href="javascript:x()">l</a></p><form action="/x"><input></form>')

      expect(html).to eq("<p>hi<a>l</a></p>")
    end
  end

  describe ".interactive" do
    it "keeps forms, inputs and csrf fields" do
      html = interactive('<form action="/things" method="post"><input type="hidden" name="authenticity_token" value="t"><input name="a"><select name="b"><option>1</option></select><button>Go</button></form>')

      expect(html).to include('action="/things"', 'name="authenticity_token"', "<select", "<button>")
    end

    it "points off-site form actions at # and records it" do
      html = nil
      kinds = degraded { html = interactive('<form action="https://evil.test/x" method="post"><button>Go</button></form>') }

      expect(fragment(html).at_css("form")["action"]).to eq("#")
      expect(kinds).to eq(%w[frame_offsite_target])
    end

    it "has no allowlisted way to submit elsewhere" do
      expect(interactive('<button formaction="//evil.test/y">Go</button><form formtarget="_blank"></form>')).not_to match(/formaction|formtarget/)
    end

    it "keeps a same-site image button source and drops an off-site one" do
      kept = fragment(interactive('<input type="image" src="/ok.png" name="go">')).at_css("input")
      dropped = fragment(interactive('<input type="image" src="https:evil.test/t.png">')).at_css("input")

      expect(kept["src"]).to eq("/ok.png")
      expect(dropped.key?("src")).to be(false)
      expect(dropped["type"]).to eq("image")
    end

    it "keeps name only on form controls and drops names and ids that clobber the document" do
      html = interactive('<input name="a"><select name="ok"></select><a name="x">l</a><button name="location">b</button><img id="cookie" src="/a.png">')

      expect(html).to include('name="a"', 'name="ok"')
      expect(html).not_to include('name="x"', 'name="location"', 'id="cookie"')
    end

    it "removes scripts, base, meta refresh, handlers and javascript urls" do
      html = interactive('<base href="//evil.test/"><meta http-equiv="refresh" content="0;url=//evil.test"><script>1</script><a href=" java&#9;script:1" onclick="x()">j</a><button formaction="javascript:x()">b</button>')

      expect(html).not_to match(/base|meta|script|onclick|formaction/i)
    end

    it "keeps links to other sites but not for referrers" do
      expect(interactive('<a href="https://other.test/x">x</a>')).to include('href="https://other.test/x"', 'rel="noopener noreferrer"')
    end

    it "drops off-site embedded content and forces image referrer policy" do
      html = interactive('<embed src="https://evil.test/a.pdf"><img src="https://img.test/a.png">')

      expect(html).not_to include("embed")
      expect(html).to include('referrerpolicy="no-referrer"')
    end
  end

  describe "widget markers" do
    let(:marked) { 'data-reactiveadmin-widget="date"' }

    it "marks a classic datepicker input while still stripping class" do
      html = interactive('<input class="datepicker fixed inset-0" name="d"><input class="fixed" name="e">')
      inputs = fragment(html).css("input")

      expect(inputs.map { it["data-reactiveadmin-widget"] }).to eq(["date", nil])
      expect(html).not_to include("class=")
    end

    it "marks widgets in a whole classic response too" do
      expect(frame_body('<input class="datepicker" name="d">')).to include(marked)
    end

    it "does not let markup claim a widget" do
      html = interactive('<input data-reactiveadmin-widget="date" name="a"><div data-reactiveadmin-widget="date">x</div>')

      expect(html).not_to include("data-reactiveadmin-widget")
    end

    it "does not apply in display html" do
      expect(display('<input class="datepicker" data-reactiveadmin-widget="date">')).not_to include("data-reactiveadmin")
    end
  end

  describe ".frame_body" do
    it "points off-site formactions at # and keeps same-site ones" do
      html = frame_body('<form><button formaction="//evil.test/y">Go</button><input type="image" formaction="/ok"></form>')

      expect(fragment(html).css("[formaction]").map { it["formaction"] }).to eq(["#", "/ok"])
    end

    it "neutralizes a classic response without cutting it to an allowlist" do
      html = frame_body('<style>.a{}</style><form action="//evil.test"><input name="x"></form><script>1</script><p onclick="x()">t</p>')

      expect(html).to include("<style>", '<form action="#">', "<p>t</p>")
      expect(html).not_to match(/script|onclick/)
    end
  end

  describe ".style" do
    def style(css) = described_class.style(css)

    it "keeps layout declarations, normalized" do
      expect(style("Margin: 0  AUTO ;padding:4px 8px;display:flex;gap:.5rem;flex:1 1 0%;text-align:center")).to eq(
        "margin: 0 auto; padding: 4px 8px; display: flex; gap: .5rem; flex: 1 1 0%; text-align: center"
      )
      expect(style("margin-left:2px;width:100%;max-width:none;font-weight:700;white-space:nowrap;float:left")).to eq(
        "margin-left: 2px; width: 100%; max-width: none; font-weight: 700; white-space: nowrap; float: left"
      )
    end

    it "normalizes unit case" do
      expect(style("WIDTH:10PX;margin:1EM 2Rem;padding:50%")).to eq("width: 10px; margin: 1em 2rem; padding: 50%")
    end

    it "rejects negative lengths, viewport units and lengths beyond the digit cap" do
      css = ["margin-left:-2px", "margin:0 -1px", "margin:-0.5em", "top:-1px", "width:100vw", "height:100vh", "width:100VW",
        "padding:1vmin", "margin:1vmax", "width:10000px", "margin:1cm", "margin:1in", "margin:1pt"]

      expect(css.map { style(it) }).to all(eq("")), css.inspect
    end

    it "drops properties outside the allowlist" do
      css = "position:fixed;z-index:9999;opacity:0;transform:scale(9);background:red;background-color:red;content:'x';filter:blur(1px);cursor:pointer;color:red;top:0"

      expect(style(css)).to eq("")
    end

    it "rejects values that can load, execute or hide something" do
      css = ["background-image:url(http://evil.test/x)", "width:expression(alert(1))", "margin:0 \\30", "margin: 0/**/",
        "behavior:url(x)", "width:calc(100% - url(x))", "margin:0 !important", "padding:10",
        "display:contents", "margin:1px 2px 3px 4px 5px"]

      expect(css.map { style(it) }).to all(eq("")), css.inspect
    end

    it "keeps the good declarations of a mixed attribute" do
      expect(style("margin: 0; position: absolute; /* c */ padding: 1px; width: 10px; background: url(x); display: grid")).to eq("margin: 0; width: 10px; display: grid")
    end

    it "ignores broken declarations and non-ascii whitespace tricks" do
      expect(style(";;color;margin;:0;margin:0; padding:0 ")).to eq("margin: 0")
      expect(style("margin: 0")).to eq("")
    end
  end

  describe "size limits" do
    def degraded_kinds
      ReactiveAdmin::Degradation.with_collection do
        yield
        ReactiveAdmin::Degradation.entries.pluck(:kind)
      end
    end

    it "shows markup nested past the parser's depth as too complex, never raises" do
      html = nil
      kinds = degraded_kinds { html = display("<div>" * 500 + "x") }

      expect(html).to eq(described_class::TOO_COMPLEX)
      expect(kinds).to eq(%w[html_too_deep])
      expect(interactive("<div>" * 500)).to eq(described_class::TOO_COMPLEX)
      expect(frame_body("<div>" * 500)).to eq(described_class::TOO_COMPLEX)
    end

    it "keeps nesting the parser accepts" do
      expect(fragment(display("<div>" * 200 + "x")).css("div").size).to eq(200)
    end

    it "truncates past the node cap and records it" do
      html = nil
      kinds = degraded_kinds { html = display("<b>x</b>" * (described_class::MAX_NODES + 500)) }

      expect(fragment(html).css("b").size).to eq(described_class::MAX_NODES)
      expect(kinds).to eq(%w[html_truncated])
    end

    it "truncates past the byte cap without splitting a character" do
      html = nil
      kinds = degraded_kinds { html = display("é" * described_class::MAX_BYTES) }

      expect(html).to be_valid_encoding
      expect(kinds).to include("html_truncated")
    end

    it "bounds a huge cell to the caps, with no error" do
      html = nil
      kinds = degraded_kinds { html = display("<p><b>x</b></p>" * 20_000) }

      expect(fragment(html).css("b").size).to be <= described_class::MAX_NODES
      expect(kinds).to include("html_truncated")
    end
  end

  describe "inline style in html" do
    it "keeps allowed declarations in display and interactive html and drops the rest" do
      html = '<div style="margin:0 auto;position:fixed;color:red">x</div><form style="padding:4px"><input style="display:block;background:url(x)"></form>'

      expect(display('<div style="margin:0 auto;position:fixed;color:red">x</div>')).to eq('<div style="margin: 0 auto">x</div>')
      expect(interactive(html)).to include('<div style="margin: 0 auto">', '<form style="padding: 4px">', '<input style="display: block">')
    end

    it "removes a style that has nothing left" do
      expect(display('<p style="position:fixed;z-index:9">x</p>')).to eq("<p>x</p>")
    end

    it "filters style in a whole frame body, keeping its other markup" do
      html = frame_body('<table style="border-collapse:collapse;position:fixed"><tr><td style="background:url(x)">x</td></tr></table>')

      expect(html).to include('<table style="border-collapse: collapse">', "<td>x</td>")
    end
  end

  describe "bypass attempts" do
    it "neutralizes common markup bypasses in display and frame html" do
      payloads = ['<a href="jav&#x09;ascript:x()">x</a>', '<a href=" &#14;javascript:x()">x</a>', "<svg><script>x()</script></svg>",
        "<math><mtext><table><mglyph><style><img src=x onerror=x()>", '<img srcset="https://evil.test/a.png 1x" src="/a.png">',
        '<details open ontoggle="x()">d</details>', '<a href="data:text/html;base64,PHNjcmlwdD4=">x</a>',
        '<base href="https://evil.test/">x', '<meta http-equiv="refresh" content="0;url=https://evil.test">x',
        '<form><form action="https://evil.test/x"><button formaction="https://evil.test/y">g</button></form>']

      payloads.each do |payload|
        [display(payload), interactive(payload)].each { expect(it).not_to match(/script|onerror|ontoggle|javascript|data:|base|meta|svg|math|srcset|evil/i), payload }
      end
    end

    it "drops class everywhere so stored markup cannot overlay the app" do
      expect(display('<div class="fixed inset-0 z-50">x</div>')).to eq("<div>x</div>")
      expect(interactive('<form class="fixed"><input class="z-50" name="a"></form>')).not_to include("class=")
    end

    it "strips name from non-controls in display html" do
      expect(display('<a name="x" href="/a">a</a>')).to eq('<a href="/a">a</a>')
    end
  end

  describe ".export" do
    let(:policy) { JSON.parse(JSON.generate(described_class.export)) }

    it "exports the style allowlist and forbidden values" do
      expect(policy.dig("style", "properties").keys).to include("margin", "padding-left", "display", "gap", "flex", "float")
      expect(policy.dig("style", "properties").keys).not_to include("position", "z-index", "background", "color", "opacity")
      expect(policy.dig("style", "forbidden_values")).to include("url(", "expression", "@import", "\\", "javascript:", "/*")
      expect(policy.dig("display", "attributes")).to include("style")
      expect(policy.dig("frame", "attributes")).to include("style")
    end

    it "describes both policies from the lists the server enforces" do
      expect(policy).to include("version" => 6)
      expect(policy.dig("display", "tags")).to include("img", "embed", "pre")
      expect(policy.dig("display", "tags")).not_to include("form", "script", "iframe")
      expect(policy.dig("frame", "tags")).to include("form", "input", "button")
      expect(policy.dig("display", "media", "img")).to include("attribute" => "src", "same_origin" => true, "data_image" => true)
      expect(policy.dig("frame", "same_origin_attributes")).to eq(%w[action formaction])
      expect(policy.dig("frame", "named_tags")).to eq(%w[button input select textarea])
      expect(policy.dig("frame", "widget_attribute")).to eq("data-reactiveadmin-widget")
      expect(policy.dig("frame", "widgets")).to eq("date" => "input.datepicker")
      expect(policy.dig("frame", "attributes")).to include("data-reactiveadmin-widget")
      expect(policy.dig("display", "attributes")).not_to include("class", "name")
      expect(policy.dig("display", "embed")).to eq("types" => ["application/pdf"], "extensions" => [".pdf"])
    end
  end
end
