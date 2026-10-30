RSpec.describe "degraded signal", type: :request do
  include_context "with a blog"

  let(:degraded) { json["degraded"].to_a }
  let(:kinds) { degraded.pluck("kind") }

  def entry(kind) = degraded.find { it["kind"] == kind }

  def first_call_raises(klass, method)
    calls = 0
    allow_any_instance_of(klass).to receive(method).and_wrap_original do |original, *args, &block|
      raise "secret draft detail" if (calls += 1) == 1

      original.call(*args, &block)
    end
  end

  def events
    [].tap do |seen|
      subscriber = ActiveSupport::Notifications.subscribe("degraded.reactiveadmin") { |*, payload| seen << payload }
      yield
    ensure
      ActiveSupport::Notifications.unsubscribe(subscriber)
    end
  end

  before { sign_in admin }

  it "reports nothing, with a zero header, when nothing fell back" do
    api_get("/api/admin/tags", schema: "IndexResponse")

    expect(json).not_to have_key("degraded")
    expect(response.headers["X-Reactiveadmin-Degraded"]).to eq("0")
  end

  describe "index" do
    it "records a failing index block and falls back to default columns" do
      first_call_raises(ReactiveAdmin::IndexRecorder, :column)

      api_get("/api/admin/posts", schema: "IndexResponse")

      expect(entry("index_block_failed")).to include("where" => "index", "reason" => a_string_including("RuntimeError"))
      expect(response.headers["X-Reactiveadmin-Degraded"]).to eq(degraded.size.to_s)
    end

    it "shows an error node, not an empty one, for a cell that fails, and records the column" do
      allow(ReactiveAdmin::Values).to receive(:for).and_raise(RuntimeError, "secret draft detail")

      api_get("/api/admin/authors", schema: "IndexResponse")

      cell = json["rows"].first["cells"]["name"]
      expect(cell).to eq("type" => "error", "label" => "Couldn't display this value")
      expect(entry("cell_failed")).to include("where" => "index/column[name]", "reason" => "Cell raised RuntimeError")
    end

    it "keeps genuinely empty values as empty nodes" do
      api_get("/api/admin/posts", schema: "IndexResponse")

      cells = json["rows"].flat_map { it["cells"].values }
      expect(cells.pluck("type")).to include("empty")
      expect(cells.pluck("type")).not_to include("error")
    end

    it "records a sidebar that fails" do
      config = ReactiveAdmin::Registry.find("tags")
      config.sidebar_sections << ActiveAdmin::SidebarSection.new("Broken", only: :index) { raise "secret draft detail" }

      api_get("/api/admin/tags", schema: "IndexResponse")

      expect(entry("sidebar_dropped")).to include("where" => "index/sidebar[Broken]", "reason" => "Sidebar raised RuntimeError; left out")
    ensure
      config.sidebar_sections.pop
    end

    it "never carries exception messages or record values" do
      allow(ReactiveAdmin::Values).to receive(:for).and_raise(RuntimeError, "secret draft detail")

      api_get("/api/admin/authors", schema: "IndexResponse")

      expect(degraded.to_json).not_to include("secret", "Alice")
    end
  end

  describe "show" do
    it "records a failing show block and falls back to default attributes" do
      first_call_raises(ReactiveAdmin::ShowPayload::Page, :attributes_table)

      api_get("/api/admin/posts/#{first_post.id}", schema: "ShowResponse")

      expect(entry("show_block_failed")).to include("where" => "show", "reason" => a_string_including("RuntimeError"))
    end

    it "counts html fallback nodes in one entry per response" do
      allow(ReactiveAdmin::ShowPayload::Page).to receive(:new).and_call_original
      allow_any_instance_of(ReactiveAdmin::ShowPayload).to receive(:render_layout).and_return("<address>a</address><address>b</address><address>c</address>")

      api_get("/api/admin/posts/#{first_post.id}", schema: "ShowResponse")

      html = degraded.select { it["kind"] == "html_fallback" }
      expect(html.size).to eq(1)
      expect(html.first).to include("reason" => "3 elements shown as sanitized html", "where" => a_string_starting_with("show/"))
    end

    it "records an action item that fails" do
      config = ReactiveAdmin::Registry.find("tags")
      config.action_items << ActiveAdmin::ActionItem.new(:boom, only: :show) { raise "secret draft detail" }

      api_get("/api/admin/tags/#{ruby.id}", schema: "ShowResponse")

      expect(entry("action_item_dropped")).to include("where" => "show/action_item[boom]")
    ensure
      config.action_items.pop
    end

    it "does not degrade for layout classes or inline styles the walker cannot translate" do
      allow_any_instance_of(ReactiveAdmin::ShowPayload).to receive(:render_layout)
        .and_return('<div class="flex rounded-lg"><p>x</p></div><div style="position: sticky"><ul><li>y</li></ul></div>')

      api_get("/api/admin/posts/#{first_post.id}", schema: "ShowResponse")

      expect(degraded.pluck("kind")).not_to include("unknown_layout_class", "inline_style_ignored")
      expect(ReactiveAdmin.diagnostics.entries.pluck(:kind)).to include(:unknown_layout_class, :inline_style_ignored)
    end

    it "records content that has to be embedded for its JS" do
      allow_any_instance_of(ReactiveAdmin::ShowPayload).to receive(:render_layout).and_return("<script>1</script>")

      api_get("/api/admin/posts/#{first_post.id}", schema: "ShowResponse")

      expect(entry("layout_iframe")).to include("where" => "show")
    end
  end

  describe "form" do
    it "records a form block that fails and falls back to defaults" do
      first_call_raises(ReactiveAdmin::FormRecorder, :inputs)

      api_get("/api/admin/posts/new", schema: "FormResponse")

      expect(entry("form_block_failed")).to include("where" => "form", "reason" => a_string_including("RuntimeError"))
    end

    it "reports nothing for a `form partial:` that records into typed fields" do
      api_get("/api/admin/sketches/new", schema: "FormResponse")

      expect(json).not_to have_key("degraded")
    end

    it "records a `form partial:` that cannot be rendered as not faithfully editable" do
      allow(ReactiveAdmin::TemplateForm).to receive(:recording).and_raise("secret draft detail")

      api_get("/api/admin/sketches/new", schema: "FormResponse")

      expect(entry("form_partial_failed")).to include("where" => "form", "reason" => "Form partial raised RuntimeError; shown empty")
      expect(entry("form_partial")).to include("where" => "form")
      expect(json["submittable"]).to be(false)
    end

    it "records a section whose block raises, by position" do
      allow_any_instance_of(ReactiveAdmin::FormRecorder).to receive(:collect).and_raise("secret draft detail")

      api_get("/api/admin/posts/new", schema: "FormResponse")

      expect(entry("form_section_failed")).to include("where" => a_string_matching(/\Aform\/section\[\d+\]\z/))
    end

    it "records a field whose input raises" do
      allow_any_instance_of(ReactiveAdmin::FormField).to receive(:control_for).and_raise("secret draft detail")

      api_get("/api/admin/posts/new", schema: "FormResponse")

      expect(kinds).to include("form_field_failed")
      expect(entry("form_field_failed")["where"]).to start_with("form/field[")
    end
  end

  describe "page" do
    it "attaches degraded to a PageResponse" do
      allow_any_instance_of(ReactiveAdmin::PagePayload).to receive(:render_content).and_return("<address>a</address>")

      api_get("/api/admin/_pages/dashboard", schema: "PageResponse")

      expect(entry("html_fallback")).to include("where" => a_string_starting_with("page/"))
    end

    it "records a page whose content raises and is embedded instead" do
      allow_any_instance_of(ReactiveAdmin::PagePayload).to receive(:render_content).and_raise("secret draft detail")

      api_get("/api/admin/_pages/dashboard", schema: "PageResponse")

      expect(entry("page_iframe_fallback")).to include("where" => "page")
    end
  end

  describe "_meta" do
    it "publishes a dropped filter, though the response has nowhere to list it" do
      allow_any_instance_of(ReactiveAdmin::Filters).to receive(:build).and_raise("secret draft detail")

      seen = events { api_get("/api/admin/posts/_meta", schema: "ResourceMeta") }

      expect(seen).to include(a_hash_including(resource: "Post", action: "meta", kind: "filter_dropped", where: "index/filter[title]"))
      expect(json).not_to have_key("degraded")
    end
  end

  describe "notifications" do
    it "publishes one per entry with resource, action, kind and where, and no messages" do
      allow(ReactiveAdmin::Values).to receive(:for).and_raise(RuntimeError, "secret draft detail")

      seen = events { api_get("/api/admin/authors", schema: "IndexResponse") }

      expect(seen).to include(resource: "Author", action: "index", kind: "cell_failed", where: "index/column[name]")
      expect(seen.to_s).not_to include("secret")
    end
  end

  it "keeps one request's entries out of the next" do
    allow(ReactiveAdmin::Values).to receive(:for).and_raise(RuntimeError, "boom")
    api_get("/api/admin/authors", schema: "IndexResponse")
    expect(kinds).to include("cell_failed")

    RSpec::Mocks.space.proxy_for(ReactiveAdmin::Values).reset
    api_get("/api/admin/tags", schema: "IndexResponse")

    expect(json).not_to have_key("degraded")
  end
end
