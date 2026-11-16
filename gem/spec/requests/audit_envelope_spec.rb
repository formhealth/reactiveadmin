RSpec.describe "audit envelope", type: :request do
  include_context "with a blog"

  let(:ssn) { "123-45-6789" }
  let(:envelopes) { [] }

  before do
    @subscriber = ReactiveAdmin.on_audit { envelopes << it }
    sign_in admin
  end

  after do
    ActiveSupport::Notifications.unsubscribe(@subscriber)
    ReactiveAdmin.config.audit_views = false
    ReactiveAdmin.config.sensitive_resources = []
  end

  def of(kind) = envelopes.select { it.kind == kind }

  def legacy(name)
    events = []
    subscriber = ActiveSupport::Notifications.subscribe("#{name}.reactiveadmin") { |*, payload| events << payload }
    yield
    events
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end

  it "is an immutable value with the documented fields" do
    api(:post, "/api/admin/posts", {post: {title: ssn, author_id: alice.id}})

    event = of("write").sole
    expect(event).to be_frozen
    expect(event.to_h.keys).to eq(%i[kind user_id resource action record_ids channel client_id request_id correlation_id outcome at details])
    expect([event.record_ids, event.details]).to all(be_frozen)
    expect(event.at).to be_within(5.seconds).of(Time.current)
    expect(envelopes.to_s).not_to include(ssn)
  end

  it "freezes every field, scalars included" do
    api(:post, "/api/admin/posts", {post: {title: "T", author_id: alice.id}})

    expect(of("write").sole.to_h.values.compact).to all(be_frozen)
    expect { of("write").sole.request_id.replace("x") }.to raise_error(FrozenError)
  end

  it "covers writes, with the request and the session channel" do
    api(:post, "/api/admin/posts", {post: {title: "T", author_id: alice.id}})

    request_id = response.headers["X-Request-Id"]
    expect(of("write").sole.to_h).to include(user_id: admin.id, resource: "posts", action: "create", record_ids: [json["id"]], channel: "session",
      client_id: nil, request_id:, correlation_id: request_id, outcome: "ok", details: {})
  end

  it "covers rejected writes with their code" do
    api(:post, "/api/admin/posts", {post: {title: ""}})

    expect(of("write_rejected").sole.to_h).to include(resource: "posts", action: "create", record_ids: [], outcome: "rejected", details: {code: "invalid"})
  end

  describe "batch writes" do
    it "carry the selected ids, in the envelope and as a new key of the write event" do
      writes = legacy("write") { api(:post, "/api/admin/posts/batch_action", {batch_action: "feature", collection_selection: [second_post.id, third_post.id]}) }

      ids = [second_post.id.to_s, third_post.id.to_s]
      expect(writes).to eq([{resource: "posts", action: "batch_action", id: nil, user_id: admin.id, record_ids: ids}])
      expect(of("write").sole.record_ids).to eq(ids)
    end

    it "leave out a selection that isn't plainly an id, even when rejected" do
      rejections = legacy("write_rejected") { api(:post, "/api/admin/posts/batch_action", {batch_action: "feature", collection_selection: [second_post.id, "#{ssn} x"]}) }

      expect(rejections.sole[:record_ids]).to eq([second_post.id.to_s])
      expect(of("write_rejected").sole.record_ids).to eq([second_post.id.to_s])
      expect(envelopes.to_s).not_to include(ssn)
    end
  end

  it "covers exports, with filter keys and no values" do
    api_get("/api/admin/posts.csv", q: {title_cont: ssn})

    expect(of("export").sole.to_h).to include(resource: "posts", action: "index", user_id: admin.id, outcome: "ok", details: {filters: %w[title_cont], scope: "all", row_count: 0})
    expect(envelopes.to_s).not_to include(ssn)
  end

  it "covers value views, without the value" do
    comment = Comment.create!(post: first_post, body: "Nice", context: {"secret" => ssn, "pad" => "x" * 3000})
    path = "/api/admin/posts/#{first_post.id}/comments"
    link = row_for(api_get(path)["rows"], comment)["cells"]["context"]["expand_path"]

    api_get(link)

    expect(response).to have_http_status(:ok)
    expect(of("value_viewed").sole.to_h).to include(resource: "comments", record_ids: [comment.id.to_s], user_id: admin.id, details: {field: "context"})
    expect(envelopes.to_s).not_to include(ssn)
  end

  it "covers value views of a record whose to_param isn't plainly an id, without it" do
    Comment.create!(post: first_post, body: "Nice", context: {"pad" => "x" * 3000})
    allow_any_instance_of(Comment).to receive(:to_param) { "#{it.id}-jane@example" }
    link = api_get("/api/admin/posts/#{first_post.id}/comments")["rows"].sole["cells"]["context"]["expand_path"]

    legacy_events = legacy("value_viewed") { api_get(link) }

    expect(of("value_viewed").sole.record_ids).to be_empty
    expect(legacy_events.to_s + envelopes.to_s).not_to include("jane@example")
  end

  it "hands each subscriber a copy no one can alter, deeply" do
    ids, filters = [+"1"], [+"title_cont"]
    ReactiveAdmin::Audit.publish(:export, nil, resource: "posts", record_ids: ids, filters:)

    event = of("export").sole
    expect { event.record_ids.first << "x" }.to raise_error(FrozenError)
    expect { event.details[:filters] << "x" }.to raise_error(FrozenError)
    expect([ids, filters]).to eq([["1"], ["title_cont"]])
  end

  it "publishes the envelope even when a legacy subscriber raises" do
    subscriber = ActiveSupport::Notifications.subscribe("export.reactiveadmin") { raise "boom" }

    expect { ReactiveAdmin::Audit.instrument("export", nil, {resource: "posts", user_id: admin.id}) }.to raise_error("boom")

    expect(of("export").sole.user_id).to eq(admin.id)
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end

  it "covers sensitive lookups, without the term or names" do
    ReactiveAdmin.config.sensitive_resources = %w[authors]

    api_get("/api/admin/posts/_options", field: "author_id_eq", context: "filter", term: "Alice")

    expect(of("lookup").sole.to_h).to include(resource: "posts", user_id: admin.id,
      details: {field: "author_id_eq", type: :search, target: "authors", result_count: 1})
    expect(envelopes.to_s).not_to include("Alice")
  end

  it "covers degradations, outside any request" do
    ReactiveAdmin::Degradation.with_collection(resource: "posts", action: "show") do
      ReactiveAdmin::Degradation.record(kind: :sidebar_dropped, where: "show/sidebar[x]", reason: "Sidebar raised #{ssn}")
    end

    expect(of("degraded").sole.to_h).to include(resource: "posts", action: "show", user_id: nil, channel: nil, request_id: nil, outcome: "degraded",
      details: {type: "sidebar_dropped", where: "show/sidebar[x]"})
    expect(envelopes.to_s).not_to include(ssn)
  end

  it "reports a degradation under the route key, leaving the legacy event's resource name" do
    calls = 0
    allow_any_instance_of(ReactiveAdmin::IndexRecorder).to receive(:column).and_wrap_original do |original, *args, &block|
      ((calls += 1) == 1) ? raise("boom") : original.call(*args, &block)
    end

    legacy_events = legacy("degraded") { api_get("/api/admin/posts") }

    expect(legacy_events.pluck(:resource).uniq).to eq(["Post"])
    expect(of("degraded").map(&:resource).uniq).to eq(["posts"])
  end

  it "joins a degradation inside a request to that request, without a user" do
    calls = 0
    allow_any_instance_of(ReactiveAdmin::IndexRecorder).to receive(:column).and_wrap_original do |original, *args, &block|
      ((calls += 1) == 1) ? raise("boom") : original.call(*args, &block)
    end

    api_get("/api/admin/posts")

    request_id = response.headers["X-Request-Id"]
    expect(of("degraded").first.to_h).to include(channel: "session", user_id: nil, request_id:, correlation_id: request_id)
  end

  describe "MCP" do
    let(:token) { token_for(admin, client_id: "claude-code") }

    it "ties a degradation during a tool call to that call" do
      calls = 0
      allow_any_instance_of(ReactiveAdmin::IndexRecorder).to receive(:column).and_wrap_original do |original, *args, &block|
        ((calls += 1) == 1) ? raise("boom") : original.call(*args, &block)
      end

      call_tool("list_records", {resource: "posts"}, token:)

      call = of("mcp_call").sole
      expect(of("degraded").first.to_h).to include(channel: "mcp", client_id: "claude-code", user_id: nil,
        correlation_id: call.correlation_id, request_id: a_string_matching(/\S/))
    end

    it "ties an agent's write to the tool call that made it" do
      call_tool("create_record", {resource: "posts", values: {title: ssn, author_id: alice.id.to_s}}, token:)

      call, write = of("mcp_call").sole, of("write").sole
      expect(call.to_h).to include(user_id: admin.id, resource: "posts", action: "create", channel: "mcp", client_id: "claude-code", outcome: "ok",
        details: hash_including(tool: "create_record", http_status: 201))
      expect(write.to_h).to include(channel: "mcp", client_id: "claude-code", record_ids: [Post.last.id.to_s])
      expect(write.correlation_id).to eq(call.correlation_id).and(eq(call.request_id))
      expect(envelopes.to_s).not_to include(ssn)
    end

    it "gives each tool call its own correlation id" do
      2.times { call_tool("get_record", {resource: "posts", id: first_post.id.to_s}, token:) }

      expect(of("mcp_call").map(&:correlation_id).uniq.size).to eq(2)
    end

    it "records a failed call as an error" do
      call_tool("get_record", {resource: "posts", id: "0"}, token:)

      expect(of("mcp_call").sole.outcome).to eq("error")
    end
  end

  it "marks a bearer token's own requests as the token channel" do
    reset!
    ReactiveAdmin.config.audit_views = true
    api_get("/api/admin/posts/#{first_post.id}", headers: bearer(token_for(admin, client_id: "script")))

    expect(of("view").sole.to_h).to include(channel: "token", client_id: "script", user_id: admin.id)
  end

  describe "record views" do
    it "are off by default" do
      api_get("/api/admin/posts/#{first_post.id}")
      api_get("/api/admin/posts/#{first_post.id}/edit")

      expect(of("view")).to be_empty
    end

    it "cover show and edit when audit_views is on" do
      ReactiveAdmin.config.audit_views = true

      api_get("/api/admin/posts/#{first_post.id}")
      api_get("/api/admin/posts/#{first_post.id}/edit")
      api_get("/api/admin/posts")

      expect(of("view").map { it.to_h.slice(:resource, :action, :record_ids, :user_id, :outcome) }).to eq([
        {resource: "posts", action: "show", record_ids: [first_post.id.to_s], user_id: admin.id, outcome: "ok"},
        {resource: "posts", action: "edit", record_ids: [first_post.id.to_s], user_id: admin.id, outcome: "ok"}
      ])
    end

    it "cover an action that leaves rendering implicit, once" do
      ReactiveAdmin.config.audit_views = true
      tag = Tag.create!(name: "t")

      api_get("/api/admin/tags/#{tag.id}")
      api_get("/api/admin/tags/#{tag.id}/edit")

      expect(of("view").map { it.to_h.slice(:resource, :action, :record_ids) }).to eq([
        {resource: "tags", action: "show", record_ids: [tag.id.to_s]},
        {resource: "tags", action: "edit", record_ids: [tag.id.to_s]}
      ])
    end

    it "cover an action that renders JSON itself, once" do
      ReactiveAdmin.config.audit_views = true
      tag = Tag.create!(name: "t")

      # The override's body deliberately isn't a ShowResponse, so skip api_get's contract check.
      get "/api/admin/tags/#{tag.id}", params: {explicit: 1}, headers: ApiHelpers::JSON_HEADERS

      expect(json).to eq("name" => "t")
      expect(of("view").map { it.to_h.slice(:resource, :action, :record_ids) }).to eq([{resource: "tags", action: "show", record_ids: [tag.id.to_s]}])
    end

    it "leave out an identifier that isn't plainly an id" do
      ReactiveAdmin.config.audit_views = true
      allow_any_instance_of(Post).to receive(:to_param) { "#{it.id}-jane@example" }

      api_get("/api/admin/posts/#{first_post.id}")

      expect(of("view").sole.record_ids).to be_empty
      expect(envelopes.to_s).not_to include("jane@example")
    end

    it "skip a record that isn't found" do
      ReactiveAdmin.config.audit_views = true

      api_get("/api/admin/posts/0")

      expect(of("view")).to be_empty
    end

    it "leave the classic pages alone" do
      ReactiveAdmin.config.audit_views = true

      get "/admin/posts/#{first_post.id}"

      expect(of("view")).to be_empty
    end
  end

  describe "UI switch" do
    def switches = of("ui_switch").map { it.details.slice(:from, :to) }

    it "stays quiet for a browser that never chose" do
      get "/admin/posts"
      api_get("/api/admin/_session")

      expect(switches).to be_empty
    end

    it "notices each switch on the next request, once" do
      get "/admin/dashboard"
      cookies["reactiveadmin_ui"] = "new"
      2.times { api_get("/api/admin/_session") }
      cookies["reactiveadmin_ui"] = "classic"
      get "/admin/posts"
      get "/admin/posts"

      expect(switches).to eq([{from: "classic", to: "new"}, {from: "new", to: "classic"}])
      expect(of("ui_switch").first.to_h).to include(user_id: admin.id, resource: nil, action: nil, channel: "session", outcome: "ok")
    end

    it "doesn't count another user's choice in the same browser" do
      cookies["reactiveadmin_ui"] = "new"
      api_get("/api/admin/_session")
      sign_in editor
      api_get("/api/admin/_session")

      expect(of("ui_switch").map(&:user_id)).to eq([admin.id])
    end
  end
end
