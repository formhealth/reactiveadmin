RSpec.describe ReactiveAdmin::Mcp::Shapes do
  describe ".param_key" do
    it "reads the key an agent sends from a form param" do
      expect(described_class.param_key("post[title]")).to eq("title")
      expect(described_class.param_key("post[tag_ids][]")).to eq("tag_ids")
      expect(described_class.param_key("post[comments_attributes][__INDEX__][body]")).to eq("body")
      expect(described_class.param_key("title")).to eq("title")
    end
  end

  describe ".field" do
    it "keeps what an agent needs and drops the rest" do
      field = {"name" => "author", "param" => "post[author_id]", "label" => "Author", "control" => "typeahead", "value" => "1", "required" => false,
               "options" => [{"label" => "Alice", "value" => "1", "extra" => "x"}], "free_text" => true}

      expect(described_class.field(field)).to eq(key: "author_id", label: "Author", control: "typeahead", value: "1", options: [{"label" => "Alice", "value" => "1"}], search: "author")
    end

    it "marks a masked field and offers no value" do
      expect(described_class.field({"name" => "token", "param" => "x[token]", "label" => "Token", "control" => "text", "masked" => true})).to include(masked: true)
    end

    it "carries the summary and path of a json value the server withheld" do
      field = {"name" => "meta", "param" => "p[meta]", "label" => "Meta", "control" => "json", "value" => nil, "summary" => {"kind" => "object"}, "expand_path" => "/api/admin/x/_value"}

      expect(described_class.field(field)).to include(summary: {"kind" => "object"}, expand_path: "/api/admin/x/_value")
    end

    it "keeps the param when asked, for forms whose body the agent must build" do
      expect(described_class.field({"name" => "t", "param" => "post[title]", "label" => "T", "control" => "text"}, with_params: true)).to include(param: "post[title]")
    end
  end

  describe ".options" do
    it "shows the first few and counts the rest" do
      options = Array.new(20) { {"label" => "L#{it}", "value" => it.to_s} }

      shown = described_class.options(options)

      expect(shown.size).to eq(16)
      expect(shown.last).to eq(more: 5)
    end

    it "is nil without options" do
      expect(described_class.options(nil)).to be_nil
      expect(described_class.options([])).to be_nil
    end
  end

  describe ".resources" do
    let(:manifest) do
      {
        "site" => {"current_user" => {"display_name" => "Ada"}},
        "menu" => [
          {"kind" => "group", "label" => "Content", "children" => [
            {"kind" => "resource", "resource" => "authors", "description" => "People who write for us"},
            {"kind" => "page", "page" => "census", "label" => "Census"}
          ]}
        ],
        "resources" => [
          {"key" => "authors", "plural_label" => "Authors", "permissions" => {"index" => true, "show" => true, "create" => false}},
          {"key" => "comments", "plural_label" => "Comments", "menu_parent" => "Content", "permissions" => {"index" => true}, "belongs_to" => {"parent" => "authors"}}
        ]
      }
    end

    it "joins the menu's group and description to each resource and lists pages" do
      result = described_class.resources(manifest)

      expect(result[:user]).to eq("Ada")
      expect(result[:resources]).to eq([
        {key: "authors", label: "Authors", group: "Content", description: "People who write for us", can: %w[index show]},
        {key: "comments", label: "Comments", group: "Content", can: %w[index], nested_under: "authors"}
      ])
      expect(result[:pages]).to eq([{page: "census", label: "Census", group: "Content"}])
    end
  end

  describe ".index" do
    let(:payload) do
      {
        "resource" => "posts", "columns" => [{"key" => "id", "label" => "Id"}, {"key" => "title", "label" => "Title"}],
        "rows" => [{"id" => "5", "display_name" => "Hello", "cells" => {"id" => {"type" => "text", "text" => "5"}, "title" => {"type" => "text", "text" => "Hello"}}}],
        "meta" => {"page" => 1, "per_page" => 1, "total_count" => 2, "total_pages" => 2, "has_next_page" => true, "current_scope" => "all", "order" => "id_desc"},
        "degraded" => [{"kind" => "implicit_column_hidden"}]
      }
    end

    it "gives rows as id, label and typed values, with paging and a way to the next page" do
      expect(described_class.index(payload)).to eq(
        resource: "posts", columns: {"id" => "Id", "title" => "Title"}, records: [{id: "5", label: "Hello", values: {"title" => "Hello"}}],
        page: 1, per_page: 1, total_count: 2, total_pages: 2, has_next_page: true, next: {page: 2}, scope: "all", order: "id_desc", degraded: ["implicit_column_hidden"]
      )
    end
  end

  describe ".show" do
    it "splits attribute rows into fields and everything else into text, and lists custom actions only" do
      payload = {
        "resource" => "posts", "id" => "1", "display_name" => "Hello", "permissions" => {"show" => true, "update" => false},
        "actions" => [{"key" => "edit", "kind" => "edit"}, {"key" => "destroy", "kind" => "destroy"}, {"key" => "archive", "kind" => "member", "label" => "Archive", "method" => "post", "confirm" => "Sure?"}],
        "layout" => [{"type" => "panel", "title" => "P", "children" => [
          {"type" => "attributes_table", "rows" => [{"label" => "Title", "value" => [{"type" => "text", "text" => "Hello"}]}]},
          {"type" => "text", "text" => "More"}
        ]}]
      }

      expect(described_class.show(payload)).to eq(
        resource: "posts", id: "1", label: "Hello", can: %w[show], fields: {"Title" => "Hello"}, sections: "## P\nMore",
        actions: [{key: "archive", label: "Archive", kind: "member", method: "post", confirm: "Sure?"}]
      )
    end
  end

  describe ".meta" do
    it "describes filters by the params an agent can send" do
      meta = {
        "key" => "posts", "plural_label" => "Posts", "permissions" => {"index" => true}, "scopes" => [{"id" => "all", "name" => "All"}], "default_scope" => "all",
        "filters" => [
          {"name" => "title", "label" => "Title", "control" => "text", "predicates" => [{"param" => "title_cont", "label" => "Contains"}]},
          {"name" => "when", "label" => "When", "control" => "date_range", "range" => {"from" => "when_gteq", "to" => "when_lteq"}},
          {"name" => "author", "label" => "Author", "control" => "typeahead", "param" => "author_id_eq", "options_path" => "/api/admin/posts/_options?context=filter&field=author"}
        ],
        "batch_actions" => [{"key" => "feature", "label" => "Feature", "confirm" => "Sure?", "inputs" => []}],
        "action_items" => [{"key" => "import", "label" => "Import", "kind" => "collection", "method" => "post"}], "download_formats" => ["csv"]
      }
      result = described_class.meta(meta)

      expect(result[:filters]).to eq([
        {name: "title", label: "Title", control: "text", params: ["title_cont"]},
        {name: "when", label: "When", control: "date_range", range: %w[when_gteq when_lteq]},
        {name: "author", label: "Author", control: "typeahead", params: ["author_id_eq"], search: "author"}
      ])
      expect(result[:batch_actions]).to eq([{key: "feature", label: "Feature", confirm: "Sure?"}])
      expect(result[:actions]).to eq([{key: "import", label: "Import", kind: "collection", method: "post"}])
    end
  end
  describe "what the API marks api_denied" do
    it "is not offered as an action, a batch action or a field" do
      meta = {
        "key" => "users", "plural_label" => "Users", "permissions" => {"index" => true, "create" => true, "destroy" => true}, "scopes" => [], "filters" => [],
        "api_denied" => {"actions" => %w[new create destroy]},
        "batch_actions" => [{"key" => "tidy", "label" => "Tidy"}, {"key" => "promote", "label" => "Promote", "api_denied" => true}],
        "action_items" => [{"key" => "sweep", "label" => "Sweep", "kind" => "collection", "api_denied" => true}], "download_formats" => []
      }
      result = described_class.meta(meta)

      expect(result[:can]).to eq(%w[index])
      expect(result[:batch_actions].pluck(:key)).to eq(%w[tidy])
      expect(result[:actions]).to eq([])
    end

    it "leaves reserved fields out of a form, nested ones too" do
      field = ->(name, **extra) { {"name" => name, "param" => "u[#{name}]", "label" => name, "control" => "text", **extra} }
      payload = {"resource" => "users", "form" => {"sections" => [
        {"kind" => "inputs", "fields" => [field.call("name"), field.call("role", "api_denied" => true, "disabled" => true)]},
        {"kind" => "has_many", "param_key" => "rows", "template_fields" => [field.call("title"), field.call("grade", "api_denied" => true)]}
      ]}}
      result = described_class.form(payload)

      expect(result[:fields].pluck(:key)).to eq(%w[name])
      expect(result[:nested].first[:fields].pluck(:key)).to eq(%w[title])
    end

    it "keeps reserved pages out of the resource list" do
      manifest = {"menu" => [{"kind" => "page", "page" => "danger", "label" => "Danger", "api_denied" => true}, {"kind" => "page", "page" => "ok", "label" => "Ok"}],
                  "resources" => [], "site" => {}}

      expect(described_class.resources(manifest)[:pages]).to eq([{page: "ok", label: "Ok"}])
    end

    it "leaves reserved actions out of a record and a page" do
      layout = [{"type" => "action", "action" => {"key" => "wipe", "label" => "Wipe", "kind" => "custom", "api_denied" => true}}]
      shown = described_class.show({"resource" => "x", "id" => "1", "permissions" => {}, "layout" => layout, "actions" => [{"key" => "greet", "label" => "Greet", "kind" => "member"}]})
      page = described_class.page({"key" => "p", "title" => "P", "layout" => layout, "actions" => []})

      expect(shown[:actions].pluck(:key)).to eq(%w[greet])
      expect(page).not_to have_key(:actions)
    end
  end
end
