RSpec.describe ReactiveAdmin::Readiness do
  let(:clean) { {typed: 4, html: 0, rows: 1} }
  let(:filters) { {total: 2, built: 2, by_control: {}, skipped: []} }

  def resource(key, **overrides)
    {key:, actions: [], failures: [], filters:, index: clean, show: clean, form: clean}.merge(overrides)
  end

  def report(resources: [], pages: [], sampled: true) = {sampled:, resources:, pages:}

  def row(result, key) = result[:rows].find { it[:key] == key }

  def statuses(row) = row[:checks].to_h { [it[:name], it[:status]] }

  describe ".build" do
    it "calls a resource native when nothing falls back, and ready when every signal passes" do
      result = described_class.build(report(resources: [resource("authors")]), counts: ->(*) { 0 })

      expect(row(result, "authors")).to include(mode: "native", ready: true)
      expect(statuses(row(result, "authors")).values.uniq).to eq([:pass])
      expect(result[:summary]).to eq(total: 1, native: 1, degraded: 0, fallback: 0, ready: 1)
    end

    it "calls a resource degraded for html leaves or skipped filters" do
      result = described_class.build(report(resources: [
        resource("posts", show: {typed: 3, html: 2, rows: 1}),
        resource("tags", filters: filters.merge(skipped: ["custom_q"]))
      ]), counts: nil)

      expect(row(result, "posts")).to include(mode: "degraded", ready: false)
      expect(statuses(row(result, "posts"))).to include("no html leaves" => :fail)
      expect(row(result, "tags")).to include(mode: "degraded", ready: false)
      expect(statuses(row(result, "tags"))).to include("all filters built" => :fail)
    end

    it "calls a resource fallback when an action renders through a frame, or a sample fails" do
      result = described_class.build(report(resources: [
        resource("comments", actions: [{name: "preview", mode: "iframe"}, {name: "archive", mode: "api"}]),
        resource("authors", failures: ["index 500 error: boom"])
      ]), counts: nil)

      expect(row(result, "comments")).to include(mode: "fallback", ready: false)
      expect(row(result, "comments")[:checks].find { it[:name] == "typed views" }[:detail]).to eq("preview through frame or iframe")
      expect(row(result, "authors")).to include(mode: "fallback", ready: false)
    end

    it "reads pages the same way" do
      result = described_class.build(report(pages: [
        {key: "dashboard", mode: "native", actions: [], nodes: {typed: 3, html: 0}},
        {key: "reports", mode: "iframe", actions: [], nodes: nil},
        {key: "broken", mode: "native", actions: [], failure: "500 error: boom"}
      ]), counts: ->(*) { 0 })

      expect(result[:rows].to_h { [it[:key], it[:mode]] }).to eq("dashboard" => "native", "reports" => "fallback", "broken" => "fallback")
      expect(row(result, "dashboard")).to include(kind: "page", ready: true)
    end

    it "reads a screen the doctor didn't sample as unknown, not passing, while keeping what failed" do
      skipped = {skipped: "nested under a parent"}
      result = described_class.build(report(
        resources: [resource("nested", index: skipped, show: skipped, form: skipped), resource("broken", index: nil, show: nil, form: nil, failures: ["index 500 error: boom"])],
        pages: [{key: "nested_page", mode: "native", actions: []}, {key: "broken_page", mode: "native", actions: [], failure: "500 error: boom"}]
      ), counts: ->(*) { 0 })

      %w[nested nested_page].each do |key|
        expect(statuses(row(result, key))).to include("samples render" => :unknown, "no html leaves" => :unknown)
        expect(row(result, key)[:ready]).to be(true)
      end
      %w[broken broken_page].each do |key|
        expect(statuses(row(result, key))).to include("samples render" => :fail, "no html leaves" => :unknown)
        expect(row(result, key)).to include(mode: "fallback", ready: false)
      end
    end

    it "fails 'samples render' for a form the doctor sampled but the new admin can't submit" do
      result = described_class.build(report(resources: [resource("posts", form: clean.merge(submittable: false))]), counts: nil)

      expect(statuses(row(result, "posts"))).to include("samples render" => :fail)
      expect(row(result, "posts")).to include(mode: "fallback", ready: false)
    end

    it "fails 'samples render' for values that failed inside a sample that answered" do
      result = described_class.build(report(resources: [resource("authors", index: {typed: 4, html: 0, errors: 2, rows: 2})], pages: [{key: "stats", mode: "native", actions: [], nodes: {typed: 1, html: 0, errors: 1}}]), counts: ->(*) { 0 })

      expect(row(result, "authors")).to include(mode: "fallback", ready: false)
      expect(row(result, "authors")[:checks].find { it[:name] == "samples render" }).to include(status: :fail, detail: a_string_including("index 2 failed to render"))
      expect(row(result, "stats")).to include(mode: "fallback", ready: false)
      expect(result[:summary]).to include(native: 0, fallback: 2)
    end

    it "calls a resource or page whose sample embeds a classic page fallback, failing typed views" do
      result = described_class.build(report(resources: [resource("authors", show: {typed: 2, html: 0, frames: 1})], pages: [{key: "stats", mode: "native", actions: [], nodes: {typed: 1, html: 0, frames: 1}}]), counts: ->(*) { 0 })

      expect(row(result, "authors")).to include(mode: "fallback", ready: false)
      expect(row(result, "authors")[:checks].find { it[:name] == "typed views" }).to include(status: :fail, detail: a_string_including("show"))
      expect(row(result, "stats")).to include(mode: "fallback", ready: false)
    end

    it "reads a show with no record to render as unknown" do
      result = described_class.build(report(resources: [resource("posts", index: {skipped: "api guard"}, show: {skipped: "no record to show"}, form: {skipped: "api guard"})]), counts: nil)

      expect(statuses(row(result, "posts"))).to include("samples render" => :unknown, "no html leaves" => :unknown)
    end

    it "doesn't count a sample that rendered nothing as evidence, and names what it couldn't inspect" do
      empty = {typed: 0, html: 0}
      result = described_class.build(report(
        resources: [resource("posts", index: empty.merge(rows: 0, columns: 3), show: {skipped: "no record to show"}, form: {skipped: "api guard"}),
          resource("tags", show: {skipped: "no record to show"})],
        pages: [{key: "blank", mode: "native", actions: [], nodes: empty}]
      ), counts: nil)

      %w[posts blank].each { expect(statuses(row(result, it))).to include("samples render" => :unknown, "no html leaves" => :unknown) }
      expect(row(result, "posts")[:checks].find { it[:name] == "samples render" }[:detail]).to include("index, show, form")
      expect(statuses(row(result, "tags"))).to include("samples render" => :pass, "no html leaves" => :pass)
      expect(row(result, "tags")[:checks].find { it[:name] == "samples render" }[:detail]).to include("show")
    end

    it "counts a page action that renders through a frame against the page" do
      result = described_class.build(report(pages: [
        {key: "reports", mode: "native", actions: [{name: "export", verb: "get", mode: "frame"}, {name: "run", verb: "post", mode: "api"}], nodes: {typed: 3, html: 0}}
      ]), counts: ->(*) { 0 })

      expect(row(result, "reports")).to include(mode: "fallback", ready: false)
      expect(row(result, "reports")[:checks].find { it[:name] == "typed views" }).to include(status: :fail, detail: "export through frame")
    end

    it "doesn't pass what it can't see: no counts and no sample read unknown, and don't block" do
      result = described_class.build(report(resources: [resource("authors", index: nil, show: nil, form: nil)], sampled: false), counts: nil)

      expect(statuses(row(result, "authors"))).to include("samples render" => :unknown, "no html leaves" => :unknown, "no degraded" => :unknown, "no client errors" => :unknown)
      expect(row(result, "authors")[:ready]).to be(true)
      expect(result[:counted]).to be(false)
    end

    it "asks the host for each event, naming the resource as that event publishes it" do
      asked = []
      counts = ->(event, resource) { asked << [event, resource] && 0 }

      described_class.build(report(resources: [resource("posts")]), counts:)

      expect(asked).to contain_exactly(["degraded.reactiveadmin", "Post"], ["client_error.reactiveadmin", "posts"])
    end

    it "fails a signal the host counted above zero" do
      counts = ->(event, _) { (event == "client_error.reactiveadmin") ? 3 : 0 }
      result = described_class.build(report(resources: [resource("posts")]), counts:)

      expect(statuses(row(result, "posts"))).to include("no degraded" => :pass, "no client errors" => :fail)
      expect(row(result, "posts")[:checks].find { it[:name] == "no client errors" }[:detail]).to eq("3 recent")
    end

    it "treats a counter that raises or answers nonsense as not recorded" do
      raising = described_class.build(report(resources: [resource("posts")]), counts: ->(*) { raise "cache down" })
      nonsense = described_class.build(report(resources: [resource("posts")]), counts: ->(*) { "many" })

      [raising, nonsense].each { expect(statuses(row(it, "posts"))).to include("no degraded" => :unknown) }
    end
  end

  describe "against the dummy app" do
    include_context "with a blog"

    it "renders a table and JSON for what the doctor sampled" do
      out = StringIO.new
      result = described_class::CLI.run({"FORMAT" => nil}, out:)

      expect(result[:summary][:total]).to be_positive
      expect(out.string).to include("reactiveadmin readiness", "Not visible to the gem", "event counts are not recorded")

      json = StringIO.new
      described_class::CLI.run({"FORMAT" => "json", "SAMPLE" => "0"}, out: json)
      expect(JSON.parse(json.string)).to include("sampled" => false, "rows" => be_an(Array))
    end
  end
end
