RSpec.describe "index options", type: :request do
  include_context "with a blog"

  let(:columns) { by_key(json["columns"]) }
  let(:index_meta) { json["meta"] }

  def list(resource, params = nil) = api_get("/api/admin/#{resource}", params, schema: "IndexResponse")

  def meta_of(resource) = api_get("/api/admin/#{resource}/_meta", schema: "ResourceMeta")

  before { sign_in admin }

  describe "scope groups" do
    it "carries each scope's group and lists scopes the way AA renders them" do
      scopes = meta_of("posts")["scopes"]

      expect(scopes.pluck("id")).to eq(%w[all featured draft published archived])
      expect(scopes.to_h { [it["id"], it["group"]] }).to eq("all" => nil, "featured" => nil, "draft" => "status", "published" => "status", "archived" => "status")
    end

    it "does the same in the index response, with counts" do
      list("posts")

      expect(index_meta["scopes"].pluck("id")).to eq(%w[all featured draft published archived])
      expect(index_meta["scopes"].find { it["id"] == "draft" }).to include("group" => "status", "count" => 1)
      expect(index_meta["scopes"].find { it["id"] == "all" }).not_to have_key("group")
    end
  end

  describe "row actions" do
    it "turns `actions defaults: false` into default_row_actions: false" do
      list("posts")

      expect(index_meta["default_row_actions"]).to eq(false)
      expect(index_meta).not_to include("row_actions_label", "row_actions_dropdown")
    end

    it "keeps the defaults for a plain `actions` and for an index without a block" do
      list("tags")
      expect(index_meta["default_row_actions"]).to eq(true)

      list("categories")
      expect(index_meta["default_row_actions"]).to eq(true)
    end

    it "reads the label and the dropdown from `actions name:, dropdown:, dropdown_name:`" do
      Note.create!(title: "Alpha")
      list("notes")

      expect(index_meta).to include("default_row_actions" => true, "row_actions_label" => "More", "row_actions_dropdown" => true)
    end

    it "treats a block without `actions` as having none, as the classic table does" do
      recorder = ReactiveAdmin::IndexRecorder.build(Tag, {}, nil)
      recorder.column(:name)

      expect(recorder.default_row_actions?).to eq(false)
    end

    it "falls back to the dropdown's default label and to `name` without one" do
      recorder = ReactiveAdmin::IndexRecorder.build(Tag, {}, nil)
      recorder.actions(dropdown: true)
      expect(recorder.row_actions_label).to eq("Actions")

      recorder.actions(name: "Row tools")
      expect(recorder.row_actions_label).to eq("Row tools")
    end
  end

  describe "download links" do
    def formats(resource) = meta_of(resource)["download_formats"]

    def with_resource_links(model, value)
      config = ReactiveAdmin::Registry.find(model)
      config.define_singleton_method(:download_links) { value }
      yield
    ensure
      config.singleton_class.send(:remove_method, :download_links)
    end

    it "lets the presenter switch exports off" do
      expect(formats("tags")).to eq([])
    end

    it "falls back to the namespace" do
      expect(formats("posts")).to eq(["csv"])
    end

    it "uses the resource's own setting over the namespace's" do
      with_resource_links("categories", false) { expect(formats("categories")).to eq([]) }
      with_resource_links("categories", [:csv, :pdf]) { expect(formats("categories")).to eq(["csv"]) }
    end

    it "lets the presenter win over the resource" do
      with_resource_links("tags", [:csv]) { expect(formats("tags")).to eq([]) }
    end

    it "evaluates procs" do
      views = ReactiveAdmin::IndexViews.new(ReactiveAdmin::Registry.find("tags"))
      allow(views.presenter).to receive(:has_key?).with(:download_links).and_return(true)
      allow(views.presenter).to receive(:[]).with(:download_links).and_return(-> { false })

      expect(views.download_links.call).to eq(false)
    end
  end

  describe "sidebars" do
    it "serializes the sections shown on the index, but not AA's own or hidden ones" do
      list("posts")

      expect(index_meta["sidebars"].pluck("title")).to eq(["Post Stats"])
      texts = nodes_of(index_meta["sidebars"].first["layout"], "text").pluck("text")
      expect(texts).to include("Total: 3", "Featured: 1")
    end

    it "omits the key without sidebars" do
      list("tags")

      expect(index_meta).not_to have_key("sidebars")
    end

    it "serializes show-page sidebars with their `if:` evaluated, in priority order" do
      api_get("/api/admin/posts/#{first_post.id}", schema: "ShowResponse")

      expect(json["sidebars"].pluck("title")).to eq(["Views"])
      expect(nodes_of(json["sidebars"].first["layout"], "attributes_table").first["rows"].pluck("label")).to eq(["Views Count"])
      expect(json["layout"]).not_to be_empty
    end

    it "leaves them out when `if:` fails" do
      api_get("/api/admin/posts/#{third_post.id}", schema: "ShowResponse")

      expect(json).not_to have_key("sidebars")
    end

    it "keeps a failing section from breaking the page" do
      config = ReactiveAdmin::Registry.find("tags")
      config.sidebar_sections << ActiveAdmin::SidebarSection.new("Broken", only: :index) { raise "boom" }
      list("tags")

      expect(response).to have_http_status(:ok)
      expect(index_meta).not_to have_key("sidebars")
    ensure
      config.sidebar_sections.pop
    end
  end

  describe "check_boxes filters" do
    let(:filters) { by_key(meta_of("notes")["filters"], "name") }

    it "turns `as: :check_boxes` into multiple-choice checkboxes filtering with _in" do
      expect(filters["title"]).to include("control" => "checkboxes", "multiple" => true, "param" => "title_in")
      expect(filters["title"]["options"].pluck("value")).to eq(%w[Alpha Beta])
      expect(filters["weight"]).to include("control" => "checkboxes", "param" => "weight_in")
    end

    it "degrades a relation-backed list to a multiple typeahead" do
      expect(by_key(meta_of("posts")["filters"], "name")["category"]).to include("control" => "typeahead", "multiple" => true, "param" => "category_id_in")
    end

    it "filters with the advertised param" do
      Note.create!(title: "Alpha")
      Note.create!(title: "Beta")
      Note.create!(title: "Gamma")
      list("notes", q: {title_in: %w[Alpha Gamma]})

      expect(json["rows"].size).to eq(2)
    end

    it "marks a single select as not multiple" do
      expect(by_key(meta_of("posts")["filters"], "name")["status"]).not_to have_key("multiple")
    end
  end

  describe "column classes and alignment" do
    before do
      Note.create!(title: "Alpha", weight: 2)
      list("notes")
    end

    it "keeps the class as written and aligns by it" do
      expect(columns["chars"]).to include("class_name" => "col-number", "align" => "right")
      expect(columns["created_at"]).to include("class_name" => "text-center", "align" => "center")
    end

    it "right-aligns numeric database columns, but not text, ids or keys" do
      expect(columns["weight"]).to include("align" => "right")
      expect(columns["title"]).not_to have_key("align")
      expect(columns["index"]).to include("align" => "right")
    end

    it "right-aligns a block column sorted by a numeric column" do
      list("posts")

      expect(columns["views"]).to include("align" => "right")
    end

    it "right-aligns decimals" do
      list("authors")

      expect(columns["rating"]).to include("align" => "right")
    end
  end

  describe "title, blank slate and row classes" do
    it "evaluates `index title:`" do
      Note.create!(title: "Alpha")
      list("notes")

      expect(index_meta["title"]).to eq("Notes (1)")
    end

    it "leaves the title out when none was declared" do
      list("posts")

      expect(index_meta).not_to have_key("title")
    end

    it "reads the link of `blank_slate_link:`" do
      list("notes")

      expect(index_meta["blank_slate"]).to eq("label" => "Write the first note", "href" => "/admin/notes/new")
    end

    it "has no blank_slate without the option" do
      list("posts")

      expect(index_meta).not_to have_key("blank_slate")
    end

    it "gives rows their `row_class:` and a tone for obvious words" do
      flagged = Note.create!(title: "!Alpha")
      plain = Note.create!(title: "Beta")
      list("notes")

      expect(row_for(json["rows"], flagged)).to include("class_name" => "row-warning flagged", "tone" => "warning")
      expect(row_for(json["rows"], plain)).not_to include("class_name", "tone")
    end

    it "maps error, danger, success and info classes to tones" do
      views = ReactiveAdmin::IndexViews.new(ReactiveAdmin::Registry.find("notes"))
      payload = ReactiveAdmin::IndexPayload.allocate
      payload.instance_variable_set(:@views, views)
      payload.instance_variable_set(:@config, ReactiveAdmin::Registry.find("notes"))
      tones = {"error" => "danger", "table-danger" => "danger", "is-success" => "success", "info" => "info", "odd" => nil}

      tones.each do |css, tone|
        allow(views.presenter).to receive(:[]).with(:row_class).and_return(->(_) { css })
        expect(payload.send(:row_style, Note.new)[:tone]).to eq(tone)
      end
    end

    it "renders `index_column` as a running number, continuing across pages" do
      3.times { |i| Note.create!(title: "Note #{i}") }
      list("notes", per_page: 2, page: 2)

      expect(columns["index"]).to include("kind" => "index", "align" => "right", "sortable" => false)
      expect(json["rows"].map { it["cells"]["index"] }).to eq([{"type" => "number", "value" => 3}])
    end
  end

  describe "paging options" do
    it "reads the presenter's per_page list and paginator" do
      list("tags")

      expect(index_meta).to include("paginator" => false, "per_page_options" => [5, 15])
      expect(meta_of("tags")["per_page_options"]).to eq([5, 15])
    end

    it "omits both by default" do
      list("posts")

      expect(index_meta).not_to include("paginator", "per_page_options")
    end
  end

  describe "views" do
    let!(:note) { Note.create!(title: "Alpha", body: "First note", weight: 4) }

    it "is a table by default, with one view listed when several exist" do
      list("notes")

      expect(index_meta).to include("view" => "table", "as" => "table")
      expect(meta_of("notes")["index_views"]).to eq([
        {"as" => "table", "label" => "Table", "default" => true},
        {"as" => "grid", "label" => "Grid", "default" => false},
        {"as" => "blog", "label" => "Blog", "default" => false},
        {"as" => "block", "label" => "List", "default" => false}
      ])
    end

    it "lists no views for a resource with a single one" do
      expect(meta_of("posts")).not_to have_key("index_views")
    end

    it "renders each record of a grid and says how many columns it has" do
      list("notes", as: "grid")
      row = json["rows"].first

      expect(json["columns"]).to eq([])
      expect(index_meta).to include("view" => "grid", "as" => "grid", "grid_columns" => 2)
      expect(row).to include("id" => note.id.to_s, "cells" => {})
      expect(row["layout"].to_json).to include("Alpha")
      expect(nodes_of(row["layout"], "text").pluck("text")).to include("First note")
      expect(index_meta["default_row_actions"]).to eq(false)
    end

    it "renders blog titles and bodies" do
      list("notes", as: "blog")

      expect(index_meta["view"]).to eq("blog")
      layout = json["rows"].first["layout"]
      expect(layout.to_json).to include("Alpha")
      expect(nodes_of(layout, "text").pluck("text")).to include("Weight 4")
    end

    it "renders block views without the selection checkboxes" do
      list("notes", as: "block")
      layout = json["rows"].first["layout"]

      expect(index_meta["view"]).to eq("block")
      expect(layout.to_json).to include("Alpha")
      expect(layout.to_json).not_to include("collection_selection")
    end

    it "falls back to the default view for an unknown or malformed ?as=" do
      list("notes", as: "nope")
      expect(index_meta["view"]).to eq("table")

      api_get("/api/admin/notes", {as: {x: 1}}, schema: "IndexResponse")
      expect(index_meta["view"]).to eq("table")
    end

    it "keeps filters, scopes and paging working in other views" do
      Note.create!(title: "Beta")
      list("notes", as: "grid", q: {title_in: ["Beta"]})

      expect(json["rows"].size).to eq(1)
      expect(index_meta["total_count"]).to eq(1)
    end

    it "renders a custom IndexAs class per record, as a block view" do
      Tagging.create!(post: first_post, tag: ruby)
      list("taggings")

      expect(index_meta).to include("view" => "block", "as" => "taglist")
      expect(nodes_of(json["rows"].first["layout"], "text").pluck("text")).to include("ruby on Hello world")
      expect(meta_of("taggings")).not_to have_key("index_views")
    end
  end

  describe "order_by" do
    before do
      Note.create!(title: "Longest title here")
      Note.create!(title: "Mid title")
      Note.create!(title: "Tiny")
      list("notes")
    end

    it "advertises the custom sort key and sorts by it, both ways" do
      expect(columns["length"]).to include("sortable" => true, "sort_key" => "title_length")

      list("notes", order: "title_length_asc")
      expect(json["rows"].map { it["cells"]["title"]["text"] }).to eq(["Tiny", "Mid title", "Longest title here"])

      list("notes", order: "title_length_desc")
      expect(json["rows"].map { it["cells"]["title"]["text"] }).to eq(["Longest title here", "Mid title", "Tiny"])
    end

    it "round-trips every advertised sort key through AA's order clause" do
      config = ReactiveAdmin::Registry.find("notes")
      keys = json["columns"].filter_map { it["sort_key"] }

      expect(keys).to include("title", "title_length", "weight")
      keys.each do |key|
        %w[asc desc].each { |dir| expect(config.order_clause.new(config, "#{key}_#{dir}")).to be_valid.and have_attributes(field: key) }
      end
    end

    it "does not offer a sort key the order clause can't carry" do
      expect(columns["slug"]).to include("sortable" => false, "sort_key" => nil)
    end
  end
end
