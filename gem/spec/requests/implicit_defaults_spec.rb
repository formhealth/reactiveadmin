RSpec.describe "secure implicit defaults", type: :request do
  include_context "with a blog"

  let(:long_text) { "sensitive-summary #{"x" * 2100}" }
  let!(:memo) do
    Memo.create!(title: "Handoff", summary: long_text, payload: {"note" => "sensitive-payload"}, secret: "sensitive-secret",
      priority: :high, author: alice, noted_at: Time.zone.local(2026, 3, 1, 9))
  end
  def degraded = json["degraded"].to_a
  def hidden = degraded.select { it["kind"] == "implicit_column_hidden" }
  let(:member) { "/api/admin/memos/#{memo.id}" }

  before { sign_in admin }

  def index = api_get("/api/admin/memos", schema: "IndexResponse")

  def show = api_get(member, schema: "ShowResponse")

  def labels = rows.map { it["label"] }

  def rows = nodes_of(json["layout"], "attributes_table").flat_map { it["rows"] }

  def row_node(label) = rows.find { it["label"] == label }["value"].first

  def cell(name) = row_for(json["rows"], memo)["cells"][name]

  def hidden_for(where) = hidden.select { it["where"] == where }.map { it["reason"] }

  def expand(node, **query) = api_get(node["expand_path"], query, schema: "ValueResponse")

  describe "index" do
    it "keeps json and text columns, leaving out encrypted ones" do
      index

      expect(json["columns"].pluck("key")).to include("title", "summary", "payload", "priority", "pinned", "author", "noted_at", "created_at")
      expect(json["columns"].pluck("key")).not_to include("secret")
      expect(response.body).not_to include("sensitive-secret", "sensitive-payload")
    end

    it "keeps foreign keys as refs and enums as labels" do
      index

      expect(cell("author")).to include("type" => "ref")
      expect(cell("priority")).to include("type" => "text")
    end

    it "truncates text to a preview that points to the full value" do
      index

      expect(cell("summary")).to match("type" => "text", "text" => long_text.first(120), "truncated" => true,
        "expand_path" => start_with("#{member}/_value?field=summary&token="))
      expect(response.body).not_to include(long_text)
    end

    it "sends text that fits the preview whole" do
      memo.update!(summary: "short note")
      index

      expect(cell("summary")).to eq("type" => "text", "text" => "short note")
    end

    it "summarizes json and points to the full value" do
      index

      expect(cell("payload")).to match("type" => "json", "summary" => {"kind" => "object", "keys" => ["note"], "size" => 28},
        "expand_path" => start_with("#{member}/_value?field=payload&token="))
    end

    it "serves the full text and json through the audited endpoint" do
      index
      text, payload = cell("summary"), cell("payload")

      expand(text)
      expect(json["value"]).to eq(long_text)

      expand(payload)
      expect(json["value"]).to eq("note" => "sensitive-payload")
    end

    it "serves text only whole" do
      index
      api_get(cell("summary")["expand_path"], path: "a")

      expect(response).to have_http_status(:not_found)
    end

    it "serves hidden columns to nobody" do
      api_get("#{member}/_value", field: "secret", token: value_token(memo, "secret", user: admin, via: "index"))

      expect(response).to have_http_status(:not_found)
    end

    it "records only what it hid, without values" do
      index

      expect(hidden_for("index")).to contain_exactly("encrypted column hidden by secure defaults: secret")
    end

    it "hides masked attributes of a resource without an index block" do
      news.update!(api_token: "tok-secret-123")
      api_get("/api/admin/categories")

      expect(json["columns"].pluck("key")).not_to include("api_token")
      expect(response.body).not_to include("tok-secret-123")
    end

    it "does not record an explicitly masked attribute as hidden, since that is the host's decision" do
      api_get("/api/admin/categories")

      expect(hidden_for("index")).to be_empty
    end

    it "records a column masked only through filter_parameters" do
      filters = Rails.application.config.filter_parameters.dup
      Rails.application.config.filter_parameters << :settings
      api_get("/api/admin/categories")

      expect(json["columns"].pluck("key")).not_to include("settings")
      expect(hidden_for("index")).to contain_exactly("masked column hidden by secure defaults: settings")
    ensure
      Rails.application.config.filter_parameters.replace(filters)
    end

    it "does not touch resources with an explicit index block" do
      api_get("/api/admin/posts")

      expect(json["columns"].pluck("key")).to include("title", "views")
      expect(hidden).to be_empty
    end

    it "shows everything under implicit_defaults = :all", :all_defaults do
      index

      expect(json["columns"].pluck("key")).to include("summary", "payload")
      expect(cell("summary")).to eq("type" => "text", "text" => long_text)
      expect(hidden).to be_empty
    end
  end

  describe "show" do
    it "shows json and text rows and leaves out binary and encrypted ones" do
      show

      expect(labels).to include("Title", "Summary", "Payload", "Priority", "Pinned", "Author", "Noted At")
      expect(labels).not_to include("Secret")
      expect(response.body).not_to include("sensitive-secret")
      expect(hidden_for("show")).to contain_exactly("encrypted column hidden by secure defaults: secret")
    end

    it "sends text up to the limit whole and json inline" do
      memo.update!(summary: "x" * 2048)
      show

      expect(row_node("Summary")).to eq("type" => "text", "text" => "x" * 2048)
      expect(row_node("Payload")).to eq("type" => "json", "value" => {"note" => "sensitive-payload"})
    end

    it "truncates longer text with a way to the rest" do
      show

      expect(row_node("Summary")).to match("type" => "text", "text" => long_text.first(120), "truncated" => true,
        "expand_path" => start_with("#{member}/_value?field=summary&token="))
      expand(row_node("Summary"))
      expect(json["value"]).to eq(long_text)
    end

    it "honors inline_text_limit and inline_json_limit" do
      ReactiveAdmin.config.inline_text_limit = ReactiveAdmin.config.inline_json_limit = 10
      memo.update!(summary: "a" * 11 + "b" * 200)
      show

      expect(row_node("Summary")).to include("truncated" => true)
      expect(row_node("Payload")).to include("summary", "expand_path")
    ensure
      ReactiveAdmin.config.inline_text_limit = ReactiveAdmin.config.inline_json_limit = 2048
    end

    it "serves the expansion without a token in legacy mode, for rendered columns only" do
      ReactiveAdmin.config.value_token = false

      %w[summary payload].each do |field|
        api_get("#{member}/_value", field:)
        expect(response).to have_http_status(:ok), field
      end
      api_get("#{member}/_value", field: "secret")
      expect(response).to have_http_status(:not_found)
    ensure
      ReactiveAdmin.config.value_token = true
    end

    it "does not touch resources with an explicit show block" do
      api_get("/api/admin/posts/#{first_post.id}")

      expect(hidden).to be_empty
    end

    it "shows everything under implicit_defaults = :all", :all_defaults do
      show

      expect(row_node("Summary")).to eq("type" => "text", "text" => long_text)
      expect(labels).to include("Summary", "Payload")
    end
  end

  describe "binary columns" do
    let!(:scan) { Scan.create!(title: "Receipt", image: "sensitive-image") }
    def scan_hidden = hidden.map { it["reason"] }

    it "are left out of index and show, and reported" do
      api_get("/api/admin/scans", schema: "IndexResponse")
      expect(json["columns"].pluck("key")).to include("title")
      expect(json["columns"].pluck("key")).not_to include("image")
      expect(scan_hidden).to eq(["binary column hidden by secure defaults: image"])

      api_get("/api/admin/scans/#{scan.id}", schema: "ShowResponse")
      expect(labels).to include("Title")
      expect(labels).not_to include("Image")
      expect(scan_hidden).to include("binary column hidden by secure defaults: image")
      expect(response.body).not_to include("sensitive-image")
    end

    it "are never served through _value" do
      api_get("/api/admin/scans/#{scan.id}/_value", field: "image", token: value_token(scan, "image", user: admin))

      expect(response).to have_http_status(:not_found)
    end

    it "show under implicit_defaults = :all", :all_defaults do
      api_get("/api/admin/scans")

      expect(json["columns"].pluck("key")).to include("image")
    end
  end

  describe "strict_defaults" do
    around do |example|
      ReactiveAdmin.config.strict_defaults = true
      example.run
    ensure
      ReactiveAdmin.config.strict_defaults = false
    end

    it "serves no columns and records the block" do
      index

      expect(json["columns"]).to eq([])
      expect(row_for(json["rows"], memo)["cells"]).to eq({})
      expect(degraded).to include(a_hash_including("kind" => "implicit_view_blocked", "where" => "index"))
    end

    it "serves no layout and records the block" do
      show

      expect(json["layout"]).to eq([])
      expect(degraded).to include(a_hash_including("kind" => "implicit_view_blocked", "where" => "show"))
    end

    it "leaves resources with explicit blocks alone" do
      api_get("/api/admin/posts")

      expect(json["columns"]).not_to be_empty
      expect(degraded.pluck("kind")).not_to include("implicit_view_blocked")
    end
  end

  describe "configuration" do
    it "defaults to secure and lenient" do
      expect(ReactiveAdmin::Configuration.new).to have_attributes(implicit_defaults: :secure, strict_defaults: false)
    end

    it "rejects an unknown mode" do
      expect { ReactiveAdmin::Configuration.new.implicit_defaults = :loose }.to raise_error(ArgumentError, /secure or :all/)
    end
  end

  describe ReactiveAdmin::ImplicitDefaults do
    it "audits sections that fall back to defaults, by hidden column name" do
      expect(described_class.audit(ActiveAdmin.application.namespace(:admin).resource_for(Memo)))
        .to eq(index: %w[secret], show: %w[secret])
    end

    it "reports hidden columns per resource in the doctor, without sampling" do
      report = ReactiveAdmin::Doctor.run(sample: false)

      expect(report[:resources].find { it[:key] == "memos" }[:implicit_view]).to eq(index: %w[secret], show: %w[secret])
      expect(report[:diagnostics]).to include(a_hash_including(kind: "implicit_view", resource: "memos", view: "index", hidden: "secret"))
    end

    it "leaves out sections with a block" do
      expect(described_class.audit(ActiveAdmin.application.namespace(:admin).resource_for(Post))).to eq({})
    end

    it "lists the visible text columns", :aggregate_failures do
      config = ActiveAdmin.application.namespace(:admin).resource_for(Memo)

      expect(described_class.text_columns(config)).to eq(%w[summary])
      expect(described_class.text_column?(config, "secret")).to be(false)
      expect(described_class.text_column?(config, "payload")).to be(false)
    end

    it "shapes text nodes by size and place", :aggregate_failures do
      source = ReactiveAdmin::ValuePayload::Source.new(config: nil, record: nil, field: "summary")

      expect(described_class.text_node(" ", source, inline: true)).to eq(type: "empty")
      expect(described_class.text_node("a" * 120, source, inline: false)).to eq(type: "text", text: "a" * 120)
      expect(described_class.text_node("a" * 121, source, inline: true)).to eq(type: "text", text: "a" * 121)
      expect(described_class.text_node("a" * 121, source, inline: false)).to eq(type: "text", text: "a" * 120, truncated: true)
    end
  end
end
