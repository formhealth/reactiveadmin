RSpec.describe ReactiveAdmin::LegacyInventory do
  include_context "with a blog"

  let(:inventory) { described_class.new(user: admin) }
  let(:items) { inventory.run }

  def find(category, key, item = nil) = items.find { it.category == category && it.key == key && (item.nil? || it.item.include?(item)) }

  # Answers the doctor's sampled requests with canned payloads: handler.call(config, action, opts) -> [status, payload].
  def stub_samples(&handler)
    allow(ReactiveAdmin::Doctor::Sample).to receive(:new).and_wrap_original do |original, config, user|
      original.call(config, user).tap do |sample|
        sample.define_singleton_method(:call) { |action, **opts| handler.call(config, action, opts) || [404, {}] }
      end
    end
  end

  def override(config, mode, **)
    (@originals ||= {})[config] ||= config.reactive_options.deep_dup
    ReactiveAdmin::ReactiveDSL.new(config).render_as(mode, **)
  end

  after do
    @originals&.each { |config, before| config.reactive_options.replace(before) }
    ReactiveAdmin::Ladder.reset!
  end

  describe "custom views" do
    let(:posts) { ReactiveAdmin::Registry.find("posts") }

    it "lists templates with raw controls and no Formtastic form as frames" do
      item = find("view_frame", "posts", "action audit")

      expect(item).to have_attributes(impact: "high", mode: "frame", reason: "no Formtastic form")
      expect(item.id).to eq("view_frame|posts|action audit")
    end

    it "does not list read-only templates, which render natively" do
      expect(find("view_frame", "posts", "action preview")).to be_nil
      expect(find("view_frame", "posts", "action stats")).to be_nil
    end

    it "scores a frame forced onto read-only content as low impact" do
      override(posts, :frame, action: :preview)

      expect(find("view_frame", "posts", "action preview")).to have_attributes(impact: "low", reason: "render_as frame")
    end

    it "scores a frame holding a write form as high impact" do
      override(posts, :frame, action: :rename)

      expect(find("view_frame", "posts", "action rename")).to have_attributes(impact: "high", reason: "render_as frame")
    end

    it "scores iframes by whether they write, and host components low" do
      override(posts, :iframe, action: :preview)
      override(posts, :custom, action: :stats, custom_key: "stats")

      expect(find("view_iframe", "posts", "action preview")).to have_attributes(impact: "med", mode: "iframe")
      expect(find("view_custom", "posts", "action stats")).to have_attributes(impact: "low")
    end

    it "reports a native action that answers 501 as high impact" do
      stub_samples { |config, action, _| [501, {}] if config == posts && action == "rename" }

      expect(find("view_unsupported", "posts", "action rename")).to have_attributes(impact: "high", mode: "unsupported")
    end

    describe "GET forms" do
      let(:tickets) { ReactiveAdmin::Registry.find("tickets") }

      before { Ticket.create!(title: "Printer jam") }

      it "doesn't list a filter form that renders natively" do
        expect(find("view_unsupported", "tickets", "action related")).to be_nil
        expect(find("view_frame", "tickets", "action related")).to be_nil
        expect(items.select { it.key == "page ticket_report" }).to be_empty
      end

      it "lists one that goes to another page as a 501, with the GET form's rule in the fix" do
        expect(find("view_unsupported", "tickets", "action elsewhere")).to have_attributes(mode: "unsupported", impact: "high", fix: a_string_including("GET form must target this same action"))
      end

      it "suggests a GET form for the raw controls and the frame nodes of a page" do
        expect(find("view_frame", "page legacy_forms")).to have_attributes(fix: a_string_including("method: :get"))
        expect(described_class::VIEW_FIXES.find { |pattern, _| "raw form controls (form_tag)".match?(pattern) }.last).to include("method: :get")
      end
    end

    it "reads only declarations without a sample user" do
      static = described_class.new(user: nil, sample: false)

      expect(static.run.map(&:category).uniq).to include("view_frame")
      expect(static.sampled).to be false
    end
  end

  describe "sampled payloads" do
    let(:posts) { ReactiveAdmin::Registry.find("posts") }
    let(:action) do
      {"label" => "Close Jane Roe's file", "kind" => "link", "supported" => false, "enabled" => false, "placement" => "inline",
       "method" => "post", "href" => "/admin/posts/#{first_post.id}/close?x=1", "disabled_reason" => "Not available here"}
    end
    let(:html) { {"type" => "html", "html" => "<p>x</p>"} }
    let(:text) { {"type" => "text", "text" => "x"} }

    def stub_posts(show: {}, form: {}, index: {})
      stub_samples do |config, action, _|
        next [404, {}] unless config == posts

        case action
        when :show then [200, show]
        when :new then [200, form]
        when :index then [200, {"rows" => [], **index}]
        end
      end
    end

    it "lists degradations by kind per view, with the structural path in the reason" do
      stub_posts(show: {"degraded" => [{"kind" => "sidebar_dropped", "where" => "show/sidebar[Notes]", "reason" => "Sidebar raised NoMethodError; left out"}]})

      expect(find("degradation", "posts", "sidebar_dropped")).to have_attributes(
        item: "show: sidebar_dropped", impact: "med", wp: "S5", reason: "show/sidebar[Notes]: Sidebar raised NoMethodError; left out"
      )
    end

    it "collapses repeats of a kind into one item with a count" do
      repeats = %w[show/div[0] show/div[1] show/div[2]].map { {"kind" => "sidebar_dropped", "where" => it, "reason" => "ignored"} }
      stub_posts(show: {"degraded" => repeats})

      matches = items.select { it.category == "degradation" && it.key == "posts" }
      expect(matches.size).to eq(1)
      expect(matches.first).to have_attributes(impact: "med", reason: "show/div[0]: ignored (+2 more)")
    end

    it "leaves out diagnostics a payload already reports as a degradation" do
      stub_posts(show: {"degraded" => [{"kind" => "sidebar_dropped", "where" => "show/sidebar[Notes]", "reason" => "x"}]})
      allow(ReactiveAdmin.diagnostics).to receive(:entries).and_return([{kind: :sidebar_dropped, resource: "Post", path: "sidebar[Notes]"}])

      expect(items.count { it.category == "degradation" && it.mode == "sidebar_dropped" }).to eq(1)
    end

    it "does not list cosmetic style misses, which only the styles report covers" do
      allow(ReactiveAdmin.diagnostics).to receive(:entries).and_return([
        {kind: :unknown_layout_class, resource: "Post", path: "div[0]", class: "p-4"},
        {kind: :inline_style_ignored, resource: "Post", path: "div[1]", style: "padding: 4px", ignored: "padding: 4px"}
      ])

      expect(items.select { it.category == "degradation" }.map(&:mode)).not_to include("unknown_layout_class", "inline_style_ignored")
    end

    it "lists classic-only actions by route, never by label, and scores writes high" do
      stub_posts(show: {"layout" => [{"type" => "action", "action" => action}, {"type" => "action", "action" => action.merge("method" => "get")}]})

      write = find("action_unsupported", "posts", "POST")
      expect(write).to have_attributes(item: "show: inline POST /admin/posts/:id/close", impact: "high")
      expect(find("action_unsupported", "posts", "GET")).to have_attributes(impact: "med")
      expect(items.map(&:item).join).not_to include("Jane")
    end

    it "flags forms that cannot be submitted, naming the cause" do
      stub_posts(form: {"submittable" => false, "unsupported_reason" => "Open it in the classic admin", "degraded" => [{"kind" => "form_partial", "reason" => "x"}], "form" => {"sections" => []}})

      expect(find("form_not_submittable", "posts")).to have_attributes(impact: "high", mode: "form partial", item: "form")
      expect(find("degradation", "posts", "form_partial")).to be_nil
    end

    describe "form partials" do
      let(:sketches) { ReactiveAdmin::Registry.find("sketches") }

      def sketch_form(payload)
        stub_samples { |config, action, _| [200, payload] if config == sketches && action == :new }
      end

      it "leaves out a partial the form records as submittable" do
        sketch_form("submittable" => true, "form" => {"sections" => []})

        expect(find("form_not_submittable", "sketches")).to be_nil
      end

      it "lists a partial the form calls not submittable" do
        sketch_form("submittable" => false, "degraded" => [{"kind" => "form_partial", "reason" => "x"}], "form" => {"sections" => []})

        expect(find("form_not_submittable", "sketches")).to have_attributes(impact: "high", mode: "form partial")
      end

      it "checks partials even when the full sample pass is off" do
        sketch_form("submittable" => false, "form" => {"sections" => []})

        expect(described_class.new(user: admin, sample: false).run.map(&:key)).to include("sketches")
      end
    end

    it "flags views whose html leaves pass the threshold" do
      stub_posts(show: {"layout" => [html, html, html, text, text, text, text, text]}, index: {"rows" => [{"cells" => {"a" => text}, "layout" => [html]}]})

      expect(find("html_heavy", "posts", "show")).to have_attributes(impact: "low", reason: "3 of 8 leaves are html (38%)", wp: "L1")
      expect(find("html_heavy", "posts", "index")).to be_nil
    end

    it "respects a custom html threshold" do
      stub_posts(show: {"layout" => [html, html, *[text] * 18]})

      expect(find("html_heavy", "posts", "show")).to be_nil
      expect(described_class.new(user: admin, html_threshold: 0.05).run.find { it.category == "html_heavy" }).to be_present
    end

    it "lists menu links that go to classic, not external ones" do
      stub_samples do |config, _, _|
        next [404, {}] unless config.respond_to?(:controller) && config.controller == ReactiveAdmin::ManifestController

        [200, {"menu" => [{"label" => "Tools", "kind" => "group", "children" => [
          {"label" => "Legacy report", "kind" => "link", "url" => "/admin/legacy", "children" => []},
          {"label" => "Status", "kind" => "link", "url" => "https://status.example.com", "children" => []}
        ]}]}]
      end

      expect(items.select { it.category == "menu_link" }.map(&:item)).to eq(["Tools > Legacy report"])
    end

    context "with overlay links" do
      before { ReactiveAdmin.menu { group("Tools") { link "Reports", url: "/admin/reports" } } }

      after { ReactiveAdmin::MenuOverlay.reset! }

      it "treats an explicit overlay link as the host's decision, and lists only the links the menu inherited" do
        stub_samples do |config, _, _|
          next [404, {}] unless config.respond_to?(:controller) && config.controller == ReactiveAdmin::ManifestController

          [200, {"menu" => [{"id" => "tools", "label" => "Tools", "kind" => "group", "children" => [
            {"id" => "tools/reports", "label" => "Reports", "kind" => "link", "url" => "/admin/reports", "children" => []},
            {"id" => "legacy_report", "label" => "Legacy report", "kind" => "link", "url" => "/admin/legacy", "children" => []}
          ]}]}]
        end

        expect(items.select { it.category == "menu_link" }.map(&:item)).to eq(["Tools > Legacy report"])
      end
    end
  end

  describe "diagnostics" do
    it "turns a capped typeahead scan into a low impact item" do
      allow(ReactiveAdmin.diagnostics).to receive(:entries).and_return([{kind: :scan_capped, source: "authors", cap: 500}])

      expect(find("typeahead_scan_capped", "authors")).to have_attributes(impact: "low", reason: "source=authors cap=500")
    end

    it "lists resources the policy permits but the host has not exposed" do
      allow(ReactiveAdmin.diagnostics).to receive(:entries).and_return([{kind: :exposure_permitted_not_exposed, keys: "memos, notes"}])

      expect(items.select { it.category == "not_exposed" }.map(&:key)).to eq(%w[memos notes])
    end
  end

  describe "ordering and identity" do
    it "sorts by impact, then resource, with unique ids" do
      impacts = items.map { described_class::IMPACTS.index(it.impact) }

      expect(impacts).to eq(impacts.sort)
      expect(items.map(&:id).uniq.size).to eq(items.size)
    end
  end

  describe "baseline" do
    let(:one) { described_class::Item.new("view_frame", "a", "action x", "frame", "r", "low", "f", nil) }
    let(:two) { described_class::Item.new("form_not_submittable", "b", "form", "raw inputs", "r", "high", "f", "S7") }
    let(:baseline) { described_class.baseline([one, two]) }

    it "records ids with their impact and counts per category" do
      expect(baseline).to include("version" => 1, "summary" => {"form_not_submittable" => 1, "view_frame" => 1})
      expect(baseline["items"]).to eq(one.id => "low", two.id => "high")
    end

    it "separates new items from cleared ones" do
      third = one.with(key: "c")
      diff = described_class.compare([two, third], baseline)

      expect(diff[:new]).to eq([third])
      expect(diff[:cleared]).to eq([{id: one.id, category: "view_frame", key: "a", item: "action x", impact: "low"}])
    end

    it "treats an unchanged inventory as no change" do
      expect(described_class.compare([one, two], baseline)).to eq(new: [], cleared: [])
    end
  end

  describe ReactiveAdmin::LegacyInventory::Report do
    let(:one) { ReactiveAdmin::LegacyInventory::Item.new("view_frame", "a", "action x", "frame", "no Formtastic form", "low", "accept it", nil) }
    let(:two) { ReactiveAdmin::LegacyInventory::Item.new("form_not_submittable", "b", "form", "raw inputs", "reason", "high", "fix it", "S7") }
    let(:baseline) { {"items" => {one.id => "low", "view_iframe|c|action old" => "med"}} }
    let(:report) { described_class.new([one, two], sampled: true, baseline:) }

    it "groups the checklist by impact, then resource" do
      markdown = report.to_markdown

      expect(markdown.index("## High impact (1)")).to be < markdown.index("## Low impact (1)")
      expect(markdown).to include("### b\n- [ ] `form_not_submittable` form (raw inputs): `reason`. Fix: fix it. [S7]")
    end

    it "summarizes counts and the trend against the baseline" do
      categories = report.summary[:categories]

      expect(categories["form_not_submittable"]).to include("total" => 1, "high" => 1, "trend" => "▲ +1")
      expect(categories["view_frame"]).to include("total" => 1, "trend" => "=")
      expect(categories["view_iframe"]).to include("total" => 0, "trend" => "▼ -1")
      expect(report.to_markdown).to include("| Forms that cannot be submitted (`form_not_submittable`) | 1 | 1 | 0 | 0 | ▲ +1 |")
    end

    it "lists what was cleared since the baseline" do
      expect(report.to_markdown).to include("## Recently cleared", "- [x] `view_iframe` c: action old (med)")
    end

    it "has no trend without a baseline" do
      plain = described_class.new([one], sampled: false)

      expect(plain.summary[:categories]["view_frame"]["trend"]).to eq("n/a")
      expect(plain.to_markdown).to include("static: no sample user")
      expect(plain.to_markdown).not_to include("Recently cleared")
    end

    it "renders JSON for CI" do
      json = JSON.parse(report.to_json)

      expect(json).to include("version" => 1, "sampled" => true, "new" => [two.id], "cleared" => ["view_iframe|c|action old"])
      expect(json["summary"]).to include("total" => 2, "new" => 1, "cleared" => 1)
      expect(json["items"].find { it["id"] == two.id }).to include("id" => two.id, "impact" => "high", "wp" => "S7")
    end
  end

  describe "CLI" do
    let(:out) { StringIO.new }
    let(:dir) { Dir.mktmpdir }
    let(:baseline_path) { File.join(dir, "baseline.yml") }
    let(:env) { {"SAMPLE" => "0"} }

    before { allow(ReactiveAdmin.config).to receive(:doctor_user).and_return(-> { admin }) }

    after { FileUtils.remove_entry(dir) }

    def run(**extra) = described_class::CLI.run(env.merge(extra.transform_keys(&:to_s)), out:)

    it "exits clean against its own baseline" do
      run("WRITE_BASELINE" => baseline_path)

      expect(run("BASELINE" => baseline_path)).to eq(0)
      expect(out.string).to include("baseline written to #{baseline_path}")
    end

    it "counts new items and names them" do
      run("WRITE_BASELINE" => baseline_path)
      baseline = YAML.safe_load_file(baseline_path)
      removed = baseline["items"].keys.first
      File.write(baseline_path, baseline.merge("items" => baseline["items"].except(removed)).to_yaml)

      expect(run("BASELINE" => baseline_path)).to eq(1)
      expect(out.string).to include("new legacy item: #{removed}")
    end

    it "does not fail when items disappear" do
      run("WRITE_BASELINE" => baseline_path)
      baseline = YAML.safe_load_file(baseline_path)
      File.write(baseline_path, baseline.merge("items" => baseline["items"].merge("view_frame|gone|action gone" => "low")).to_yaml)

      expect(run("BASELINE" => baseline_path)).to eq(0)
      expect(out.string).not_to include("new legacy item")
    end

    it "writes the report to OUT and prints a one-line summary" do
      path = File.join(dir, "inventory.md")
      run("OUT" => path)

      expect(File.read(path)).to start_with("# Legacy inventory")
      expect(out.string).to match(/legacy inventory written to .*: \d+ open \(\d+ high, \d+ med, \d+ low\)/)
    end

    it "prints JSON" do
      run("FORMAT" => "json")

      expect(JSON.parse(out.string)).to include("version" => 1, "items" => be_an(Array))
    end
  end

  it "never prints record values" do
    markdown = ReactiveAdmin::LegacyInventory::Report.new(items, sampled: true).to_markdown

    expect(markdown).not_to include("Hello world", "alice@example.com")
  end
end
