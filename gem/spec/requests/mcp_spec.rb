RSpec.describe "MCP endpoint", type: :request do
  include_context "with a blog"

  let(:token) { token_for(admin) }
  let(:editor_token) { token_for(editor) }

  def with_mcp(**settings)
    mcp = ReactiveAdmin.config.mcp
    original = settings.keys.index_with { mcp.public_send(it) }
    settings.each { |name, value| mcp.public_send("#{name}=", value) }
    yield
  ensure
    original.each { |name, value| mcp.public_send("#{name}=", value) }
  end

  describe "protocol" do
    it "negotiates the protocol version and describes the server" do
      reply = rpc("initialize", {protocolVersion: "2025-06-18", capabilities: {}, clientInfo: {name: "spec", version: "1"}}, token:)

      expect(response).to have_http_status(:ok)
      expect(reply).to include("jsonrpc" => "2.0", "id" => 1)
      expect(reply["result"]).to include("protocolVersion" => "2025-06-18", "capabilities" => {"tools" => {"listChanged" => false}})
      expect(reply["result"]["serverInfo"]).to include("name" => "reactiveadmin")
      expect(reply["result"]["instructions"]).to be_present
    end

    it "answers an older version it speaks in kind, and an unknown one with its latest" do
      expect(rpc("initialize", {protocolVersion: "2025-03-26"}, token:).dig("result", "protocolVersion")).to eq("2025-03-26")
      expect(rpc("initialize", {protocolVersion: "1999-01-01"}, token:).dig("result", "protocolVersion")).to eq("2025-06-18")
    end

    it "accepts the initialized notification without a body" do
      post mcp_path, params: {jsonrpc: "2.0", method: "notifications/initialized"}.to_json, headers: {"CONTENT_TYPE" => "application/json"}.merge(bearer(token))

      expect(response).to have_http_status(:accepted)
      expect(response.body).to be_empty
    end

    it "accepts a client response without a body" do
      post mcp_path, params: {jsonrpc: "2.0", id: 9, result: {}}.to_json, headers: {"CONTENT_TYPE" => "application/json"}.merge(bearer(token))

      expect(response).to have_http_status(:accepted)
    end

    it "answers ping" do
      expect(rpc("ping", token:)["result"]).to eq({})
    end

    it "lists tools with a schema and annotations" do
      tools = rpc("tools/list", token:).dig("result", "tools").index_by { it["name"] }

      expect(tools.keys).to eq(%w[list_resources describe_resource list_records get_record get_page get_form create_record update_record delete_record run_action field_options reveal_value])
      expect(tools.values).to all(include("title", "description", "inputSchema", "annotations"))
      expect(tools["list_records"]["inputSchema"]).to include("type" => "object", "required" => ["resource"])
    end

    it "marks reads read-only, deletes and actions destructive, creates additive" do
      tools = rpc("tools/list", token:).dig("result", "tools").index_by { it["name"] }
      hint = ->(name, key) { tools.dig(name, "annotations", key) }

      %w[list_resources describe_resource list_records get_record get_page get_form field_options reveal_value].each do |name|
        expect(hint.call(name, "readOnlyHint")).to be(true), name
      end
      expect(hint.call("delete_record", "destructiveHint")).to be(true)
      expect(hint.call("run_action", "destructiveHint")).to be(true)
      expect(hint.call("create_record", "destructiveHint")).to be(false)
      expect(hint.call("update_record", "readOnlyHint")).to be(false)
    end

    it "answers an unknown method and an unknown tool as JSON-RPC errors" do
      expect(rpc("resources/list", token:)["error"]).to include("code" => -32601)
      expect(rpc("tools/call", {name: "drop_database"}, token:)["error"]).to include("code" => -32602)
    end

    it "refuses batches and bad JSON" do
      post mcp_path, params: [{jsonrpc: "2.0", method: "ping", id: 1}].to_json, headers: {"CONTENT_TYPE" => "application/json"}.merge(bearer(token))
      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body["error"]).to include("code" => -32600)

      post mcp_path, params: "{nope", headers: {"CONTENT_TYPE" => "application/json"}.merge(bearer(token))
      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body["error"]).to include("code" => -32700)
    end

    it "rejects an unsupported MCP-Protocol-Version header" do
      rpc("ping", token:, headers: {"MCP-Protocol-Version" => "1999-01-01"})

      expect(response).to have_http_status(:bad_request)
      expect(rpc("ping", token:, headers: {"MCP-Protocol-Version" => "2025-06-18"})).to include("result")
    end

    it "has no event stream or session to end" do
      get mcp_path, headers: bearer(token)
      expect(response).to have_http_status(:method_not_allowed)
      expect(response.headers["Allow"]).to eq("POST")

      delete mcp_path, headers: bearer(token)
      expect(response).to have_http_status(:method_not_allowed)
    end
  end

  describe "authentication" do
    it "challenges a request with no credentials" do
      with_mcp(resource_metadata_url: "https://admin.example.com/.well-known/oauth-protected-resource") do
        rpc("ping", token: "ignored", headers: {"Authorization" => nil})
      end

      expect(response).to have_http_status(:unauthorized)
      expect(response.headers["WWW-Authenticate"]).to eq('Bearer resource_metadata="https://admin.example.com/.well-known/oauth-protected-resource"')
    end

    it "refuses an invalid token" do
      rpc("ping", token: "nope")

      expect(response).to have_http_status(:unauthorized)
      expect(response.headers["WWW-Authenticate"]).to start_with('Bearer error="invalid_token"')
    end

    it "refuses a session cookie, so a page the operator has open can't drive it" do
      sign_in admin
      post mcp_path, params: {jsonrpc: "2.0", method: "ping", id: 1}.to_json, headers: json_headers

      expect(response).to have_http_status(:unauthorized)
      expect(response.headers["WWW-Authenticate"]).to start_with("Bearer")
    end

    it "ignores the session when a token is present" do
      sign_in admin

      expect(rpc("ping", token: "nope")).to include("code" => "unauthorized")
    end

    it "is unavailable where the host has no token adapter" do
      original = ReactiveAdmin.config.auth
      ReactiveAdmin.config.auth = nil
      sign_in admin
      post mcp_path, params: {jsonrpc: "2.0", method: "ping", id: 1}.to_json, headers: json_headers.merge(bearer(token))

      expect(response).to have_http_status(:unauthorized)
    ensure
      ReactiveAdmin.config.auth = original
    end
  end

  describe "Origin validation" do
    it "refuses a foreign origin before authenticating" do
      rpc("ping", token: "nope", headers: {"Origin" => "https://evil.example"})

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body).to include("code" => "forbidden")
    end

    it "accepts this site, a listed origin, and a request with no Origin" do
      expect(rpc("ping", token:, headers: {"Origin" => "http://www.example.com"})).to include("result")
      expect(rpc("ping", token:)).to include("result")
      with_mcp(allowed_origins: ["https://app.example.com"]) do
        expect(rpc("ping", token:, headers: {"Origin" => "https://app.example.com"})).to include("result")
        expect(rpc("ping", token:, headers: {"Origin" => "https://other.example.com"})).to include("code" => "forbidden")
      end
    end
  end

  describe "enabling" do
    it "answers 404 when disabled, before authenticating" do
      with_mcp(enabled: false) { rpc("ping", token: "nope") }

      expect(response).to have_http_status(:not_found)
      expect(response.headers["WWW-Authenticate"]).to be_nil
    end

    it "asks a callable per user" do
      with_mcp(enabled: ->(user) { user.role == "admin" }) do
        expect(rpc("ping", token:)).to include("result")

        rpc("ping", token: editor_token)
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe "scopes" do
    let(:read_only) { token_for(admin, scopes: ["admin:read"]) }

    it "offers a read-only token only the read tools" do
      names = rpc("tools/list", token: read_only).dig("result", "tools").pluck("name")

      expect(names).to eq(%w[list_resources describe_resource list_records get_record get_page get_form field_options reveal_value])
    end

    it "refuses a write with a clear message and changes nothing" do
      expect { call_tool("create_record", {resource: "posts", values: {title: "No", author_id: alice.id.to_s}}, token: read_only) }.not_to change(Post, :count)

      expect(tool_error?).to be(true)
      expect(call_tool("delete_record", {resource: "posts", id: first_post.id.to_s, confirm: true}, token: read_only)).to include("admin:write")
      expect(Post.exists?(first_post.id)).to be(true)
    end

    it "lets a token with both scopes write" do
      both = token_for(admin, scopes: %w[admin:read admin:write])

      expect { call_tool("create_record", {resource: "posts", values: {title: "Yes", author_id: alice.id.to_s}}, token: both) }.to change(Post, :count).by(1)
    end
  end

  describe "tools" do
    it "lists what the user may open, with permissions" do
      result = call_tool("list_resources", token:)

      posts = result["resources"].find { it["key"] == "posts" }
      expect(posts).to include("label" => "Posts", "group" => "Content")
      expect(posts["can"]).to include("index", "show", "create", "update")
      expect(result["pages"]).to include(include("page" => "dashboard"))
      expect(result["resources"].find { it["key"] == "comments" }).to include("nested_under" => "posts")
    end

    it "leaves out what the policy denies" do
      keys = call_tool("list_resources", token: editor_token)["resources"].pluck("key")

      expect(keys.include?("categories")).to eq(can_read_categories?(editor))
    end

    it "describes a resource: filters with their params, scopes, columns, sorting, actions and the create form" do
      result = call_tool("describe_resource", {resource: "posts"}, token:)

      title = result["filters"].find { it["name"] == "title" }
      expect(title["params"]).to include("title_cont", "title_eq")
      expect(result["filters"].find { it["name"] == "published_at" }["range"]).to eq(%w[published_at_gteq published_at_lteq])
      expect(result["filters"].find { it["name"] == "author_id_eq" }).to include("search" => "author_id_eq")
      expect(result["scopes"].pluck("id")).to include("published", "draft")
      expect(result["columns"]).to include(include("key" => "views", "sort" => "views_count"))
      expect(result["batch_actions"].pluck("key")).to include("set_status", "feature")
      expect(result["actions"].pluck("key")).to include("import")
      expect(result["form"]["fields"].pluck("key")).to include("title", "author_id", "tag_ids")
    end

    it "skips the sample row when asked" do
      events = capture_events("process_action.action_controller") { @result = call_tool("describe_resource", {resource: "posts", columns: false}, token:) }

      expect(events.map { it[:action] }).not_to include("index")
      expect(@result).not_to include("columns")
    end

    it "lists records as typed values with paging" do
      result = call_tool("list_records", {resource: "posts", per_page: 2}, token:)

      expect(result["records"].size).to eq(2)
      expect(result).to include("total_count" => 3, "has_next_page" => true, "next" => {"page" => 2})
      row = result["records"].find { it["id"] == first_post.id.to_s } || result["records"].first
      expect(row["values"]).to include("published_at", "author")
    end

    it "filters by declared filters, scopes and order" do
      result = call_tool("list_records", {resource: "posts", filters: {title_cont: "Hello"}, scope: "published", order: "id_asc"}, token:)

      expect(result["records"].pluck("label")).to eq(["Hello world"])
      expect(result["values"]).to be_nil
      expect(result).to include("scope" => "published")
    end

    it "refuses a filter nothing declares" do
      result = call_tool("list_records", {resource: "posts", filters: {body_cont: "x"}}, token:)

      expect(tool_error?).to be(true)
      expect(result).to include("Unsupported filter: body_cont")
    end

    it "caps per_page at the configured maximum" do
      with_mcp(max_per_page: 1) do
        result = call_tool("list_records", {resource: "posts", per_page: 50}, token:)

        expect(result["records"].size).to eq(1)
        expect(result["per_page"]).to eq(1)
      end
    end

    it "cuts a long result with an explicit note instead of overflowing" do
      with_mcp(max_response_bytes: 800) do
        result = call_tool("list_records", {resource: "posts", per_page: 3}, token:)

        expect(result["records"].size).to be < 3
        expect(result["truncated"]).to match(/Showing \d of 3 records .* smaller per_page/)
      end
    end

    it "reduces a record's layout to fields and text, and lists its actions" do
      result = call_tool("get_record", {resource: "posts", id: first_post.id.to_s}, token:)

      expect(result["label"]).to eq("Hello world")
      expect(result["fields"]).to include("Title" => "Hello world", "Author" => {"ref" => "authors/#{alice.id}", "label" => "Alice Author"}, "Metadata" => {"seo" => {"slug" => "hello"}})
      expect(result["sections"]).to include("## Comments", "Views: 1200", "- ruby")
      expect(result["actions"].pluck("key")).to include("archive", "rename")
      expect(result.to_s).not_to include("<")
    end

    it "keeps a large json value as a summary with a way to read it" do
      first_post.update!(metadata: {"notes" => "n" * 3_000, "plan" => {"a" => 1}})
      result = call_tool("get_record", {resource: "posts", id: first_post.id.to_s}, token:)

      summary = result["fields"]["Metadata"]
      expect(summary).to include("summary" => include("kind" => "object", "keys" => %w[notes plan]), "expand_path" => match(%r{\A/api/admin/posts/\d+/_value\?}))
      expect(result.to_s).not_to include("nnnnnnnnnn")

      events = capture_events("value_viewed.reactiveadmin") { @revealed = call_tool("reveal_value", {expand_path: summary["expand_path"], path: "plan"}, token:) }
      expect(@revealed).to eq("value" => {"a" => 1})
      expect(events).to contain_exactly(include(resource: "posts", field: "metadata", user_id: admin.id))
    end

    it "refuses to reveal anything that isn't an issued _value path" do
      ["/api/admin/posts", "http://evil.example/api/admin/posts/1/_value?field=x", "/api/admin/posts/../../x/_value", "/api/other/posts/1/_value"].each do |path|
        expect(call_tool("reveal_value", {expand_path: path}, token:)).to include("expand_path")
        expect(tool_error?).to be(true), path
      end
    end

    it "returns a page as text with its actions" do
      result = call_tool("get_page", {page: "dashboard"}, token:)

      expect(result).to include("title" => "Dashboard", "sections" => "## Stats\nPosts: 3")
      expect(result["actions"].pluck("key")).to include("recalc")
    end

    it "describes the new and edit forms, with the lock" do
      new_form = call_tool("get_form", {resource: "posts"}, token:)
      edit_form = call_tool("get_form", {resource: "posts", id: first_post.id.to_s}, token:)

      expect(new_form).to include("mode" => "new")
      expect(edit_form).to include("mode" => "edit", "lock" => include("field"))
      title = edit_form["fields"].find { it["key"] == "title" }
      expect(title).to include("control" => "text", "required" => true, "value" => "Hello world")
      expect(edit_form["fields"].find { it["key"] == "author_id" }).to include("search" => "author")
      expect(edit_form["nested"].first).to include("key" => "comments_attributes")
    end

    it "searches a field's options" do
      result = call_tool("field_options", {resource: "posts", field: "author_id_eq", term: "bob"}, token:)

      expect(result["options"]).to eq([{"value" => bob.id.to_s, "label" => "Bob Builder"}])
      expect(call_tool("field_options", {resource: "posts", field: "author_id_eq", value: [alice.id.to_s]}, token:)["options"].pluck("label")).to eq(["Alice Author"])
    end

    it "needs the parent for a nested resource" do
      expect(call_tool("list_records", {resource: "comments"}, token:)).to include("nested under posts")
      Comment.create!(post: first_post, body: "Nice")

      expect(call_tool("list_records", {resource: "comments", parent_id: first_post.id.to_s}, token:)["records"].size).to eq(1)
    end

    it "explains an unknown resource" do
      expect(call_tool("list_records", {resource: "nope"}, token:)).to include("Call list_resources")
      expect(tool_error?).to be(true)
    end

    it "checks arguments before calling anything" do
      expect(call_tool("list_records", {}, token:)).to include("Missing required argument: resource")
      expect(call_tool("list_records", {resource: "posts", page: "two"}, token:)).to include("page must be a integer")
      expect(call_tool("list_records", {resource: "posts", sql: "x"}, token:)).to include("Unknown argument")
      expect(call_tool("run_action", {resource: "posts", action: "archive", kind: "sideways"}, token:)).to include("one of: member, collection, batch")
    end
  end

  describe "writes" do
    it "creates a record from field keys" do
      result = call_tool("create_record", {resource: "posts", values: {title: "From an agent", author_id: alice.id.to_s, tag_ids: [ruby.id.to_s]}}, token:)

      post = Post.find_by!(title: "From an agent")
      expect(result).to include("ok" => true, "record" => "posts/#{post.id}")
      expect(post.tags).to eq([ruby])
    end

    it "reports validation failures with the field" do
      expect { call_tool("create_record", {resource: "posts", values: {title: "", author_id: alice.id.to_s}}, token:) }.not_to change(Post, :count)

      expect(tool_error?).to be(true)
      expect(call_tool("create_record", {resource: "posts", values: {title: ""}}, token:)).to match(/Validation failed: .*title can't be blank/)
    end

    it "doesn't write a field the form doesn't offer" do
      call_tool("create_record", {resource: "posts", values: {title: "x", author_id: alice.id.to_s, views_count: 99}}, token:)

      expect(Post.find_by(title: "x")&.views_count.to_i).not_to eq(99)
    end

    it "updates with the lock from get_form, passed through" do
      form = call_tool("get_form", {resource: "posts", id: first_post.id.to_s}, token:)
      call_tool("update_record", {resource: "posts", id: first_post.id.to_s, values: {title: "Retitled"}, lock: form["lock"]}, token:)

      expect(tool_error?).to be(false)
      expect(first_post.reload.title).to eq("Retitled")
    end

    it "refuses a stale lock, telling the agent to reload" do
      form = call_tool("get_form", {resource: "posts", id: first_post.id.to_s}, token:)
      first_post.update!(title: "Someone else", updated_at: 1.minute.from_now)
      message = call_tool("update_record", {resource: "posts", id: first_post.id.to_s, values: {title: "Mine"}, lock: form["lock"]}, token:)

      expect(tool_error?).to be(true)
      expect(message).to include("Stale", "get_form")
      expect(first_post.reload.title).to eq("Someone else")
    end

    it "refuses an update with no lock" do
      call_tool("update_record", {resource: "posts", id: first_post.id.to_s, values: {title: "Blind"}}, token:)

      expect(tool_error?).to be(true)
      expect(first_post.reload.title).to eq("Hello world")
    end

    it "sends lock_version as the lock, which a model without one refuses as stale" do
      message = call_tool("update_record", {resource: "posts", id: first_post.id.to_s, values: {title: "x"}, lock_version: "3"}, token:)

      expect(message).to include("Stale")
      expect(first_post.reload.title).to eq("Hello world")
    end
  end

  describe "destructive tools" do
    it "explains what delete would do and does nothing without confirm" do
      message = call_tool("delete_record", {resource: "posts", id: second_post.id.to_s}, token:)

      expect(tool_error?).to be(true)
      expect(message).to include("would delete posts/#{second_post.id}", "confirm: true")
      expect(Post.exists?(second_post.id)).to be(true)
    end

    it "refuses confirm that isn't true" do
      call_tool("delete_record", {resource: "posts", id: second_post.id.to_s, confirm: "yes"}, token:)

      expect(Post.exists?(second_post.id)).to be(true)
    end

    it "deletes once confirmed, as far as the policy allows" do
      message = call_tool("delete_record", {resource: "posts", id: second_post.id.to_s, confirm: true}, token:)

      expect(Post.exists?(second_post.id)).to eq(!can_destroy_post?(admin))
      expect(tool_error?).to eq(!can_destroy_post?(admin))
      expect(message).to include("Not authorized") unless can_destroy_post?(admin)
    end

    it "explains a member action, with the app's own confirmation text, and does nothing without confirm" do
      message = call_tool("run_action", {resource: "posts", id: first_post.id.to_s, action: "archive", kind: "member"}, token:)

      expect(message).to include("would run member action archive", "POST /api/admin/posts/#{first_post.id}/archive", "Archive this post?")
      expect(first_post.reload.status).to eq("published")
    end

    it "runs a confirmed member action" do
      result = call_tool("run_action", {resource: "posts", id: first_post.id.to_s, action: "archive", kind: "member", confirm: true}, token:)

      expect(result).to include("ok" => true, "message" => "Archived")
      expect(first_post.reload.status).to eq("archived")
    end

    it "runs a confirmed collection action" do
      expect(call_tool("run_action", {resource: "posts", action: "import", kind: "collection", confirm: true}, token:)).to include("message" => "Imported")
    end

    it "runs a batch action over ids with its inputs" do
      call_tool("run_action", {resource: "posts", action: "set_status", kind: "batch", ids: [first_post.id.to_s], inputs: {status: "draft"}}, token:)
      expect(tool_error?).to be(true)
      expect(first_post.reload.status).to eq("published")

      result = call_tool("run_action", {resource: "posts", action: "set_status", kind: "batch", ids: [first_post.id.to_s], inputs: {status: "draft"}, confirm: true}, token:)
      expect(result["message"]).to eq("Updated 1 posts to draft")
      expect(first_post.reload.status).to eq("draft")
    end

    it "needs no confirmation to read a GET action's form" do
      result = call_tool("run_action", {resource: "posts", id: first_post.id.to_s, action: "rename", kind: "member", method: "get"}, token:)

      expect(tool_error?).to be(false)
      expect(result["fields"].first).to include("param" => "post[title]")
    end

    it "takes the body of an action with a form exactly as given" do
      result = call_tool("run_action", {resource: "posts", id: first_post.id.to_s, action: "rename", kind: "member", method: "post", inputs: {post: {title: "Renamed"}}, confirm: true}, token:)

      expect(result).to include("ok" => true)
      expect(first_post.reload.title).to eq("Renamed")
    end

    it "caps a batch" do
      expect(call_tool("run_action", {resource: "posts", action: "feature", kind: "batch", ids: (1..101).map(&:to_s), confirm: true}, token:)).to include("at most 100")
    end
  end

  describe "authorization stays with the host's policy" do
    it "surfaces a denial as a tool error, not a protocol error" do
      reply = rpc("tools/call", {name: "list_records", arguments: {resource: "categories"}}, token: editor_token)

      expect(response).to have_http_status(:ok)
      if can_read_categories?(editor)
        expect(reply["result"]["isError"]).to be(false)
      else
        expect(reply["result"]).to include("isError" => true)
        expect(reply.dig("result", "content", 0, "text")).to include("Not authorized")
      end
    end

    it "shows an editor only what the policy scopes to them" do
      ids = call_tool("list_records", {resource: "posts"}, token: editor_token)["records"].pluck("id")

      expect(ids.sort).to eq([first_post, second_post, third_post].select { can_see_post?(editor, it) }.map { it.id.to_s }.sort)
    end

    it "refuses a record outside the policy's scope" do
      next unless adapter?(:custom, :pundit)

      call_tool("get_record", {resource: "posts", id: second_post.id.to_s}, token: editor_token)

      expect(tool_error?).to be(true)
    end

    it "refuses a write the policy forbids" do
      next unless adapter?(:custom, :pundit)

      expect(call_tool("run_action", {resource: "posts", action: "import", kind: "collection", confirm: true}, token: editor_token)).to include("Not authorized")
    end
  end

  describe "internal dispatch" do
    it "runs the host's audit events as the token's user, with the request id" do
      events = capture_events("write.reactiveadmin") do
        call_tool("create_record", {resource: "posts", values: {title: "Audited", author_id: alice.id.to_s}}, token:)
      end

      expect(events).to contain_exactly(include(resource: "posts", action: "create", user_id: admin.id))
    end

    it "emits rejected writes" do
      events = capture_events("write_rejected.reactiveadmin") do
        call_tool("create_record", {resource: "posts", values: {title: ""}}, token:)
      end

      expect(events).to contain_exactly(include(resource: "posts", code: "invalid", user_id: admin.id))
    end

    it "marks its requests for hosts that tell MCP traffic apart" do
      seen = []
      subscriber = ActiveSupport::Notifications.subscribe("start_processing.action_controller") { |*, payload| seen << payload[:headers].env["reactiveadmin.mcp"] }
      call_tool("list_resources", token:)
      ActiveSupport::Notifications.unsubscribe(subscriber)

      expect(seen).to include(true, nil)
    end

    it "applies the API's own rate limits to the calls a tool makes" do
      with_rate_limits(options: [1, 1.minute], mcp: nil) do
        call_tool("field_options", {resource: "posts", field: "author_id_eq"}, token:)
        message = call_tool("field_options", {resource: "posts", field: "author_id_eq"}, token:)

        expect(message).to include("Rate limited")
      end
    end

    it "leaves the host's CurrentAttributes alone" do
      probe = Class.new(ActiveSupport::CurrentAttributes) { attribute :marker }
      stub_const("McpProbe", probe)
      after_call = []
      start = ActiveSupport::Notifications.subscribe("start_processing.action_controller") { |*, payload| McpProbe.marker = "set" if payload[:controller] == "ReactiveAdmin::McpController" }
      done = ActiveSupport::Notifications.subscribe("mcp_call.reactiveadmin") { after_call << McpProbe.marker }
      call_tool("list_resources", token:)
      [start, done].each { ActiveSupport::Notifications.unsubscribe(it) }

      expect(after_call).to eq(["set"])
    end

    def with_rate_limits(limits)
      original = ReactiveAdmin.config.rate_limits
      ReactiveAdmin.config.rate_limits = limits
      yield
    ensure
      ReactiveAdmin.config.rate_limits = original
    end
  end

  describe "rate limit" do
    it "has its own bucket, answering as a tool error with the wait" do
      original = ReactiveAdmin.config.rate_limits
      ReactiveAdmin.config.rate_limits = original.merge(mcp: [2, 1.minute])
      2.times { expect(call_tool("list_resources", token:)).to be_a(Hash) }
      message = call_tool("list_resources", token:)

      expect(tool_error?).to be(true)
      expect(message).to match(/Rate limited: too many tool calls. Retry in \d+ seconds/)
    ensure
      ReactiveAdmin.config.rate_limits = original
    end

    it "counts per user" do
      original = ReactiveAdmin.config.rate_limits
      ReactiveAdmin.config.rate_limits = original.merge(mcp: [1, 1.minute])
      call_tool("list_resources", token:)

      expect(call_tool("list_resources", token: editor_token)).to be_a(Hash)
    ensure
      ReactiveAdmin.config.rate_limits = original
    end
  end

  describe "audit" do
    let(:ssn) { "123-45-6789" }

    it "emits who called which tool on which resource, with how it went" do
      events = capture_events("mcp_call.reactiveadmin") do
        call_tool("list_records", {resource: "posts", filters: {title_cont: ssn}}, token: token_for(admin, client_id: "claude-code"))
      end

      expect(events.size).to eq(1)
      expect(events.first).to include(user_id: admin.id, client_id: "claude-code", tool: "list_records", resource: "posts", action: "list", status: "ok", http_status: 200)
      expect(events.first[:duration_ms]).to be_a(Integer)
    end

    it "names a run_action's action and records failures" do
      events = capture_events("mcp_call.reactiveadmin") do
        call_tool("run_action", {resource: "posts", id: first_post.id.to_s, action: "archive", kind: "member"}, token:)
        call_tool("get_record", {resource: "posts", id: "0"}, token:)
      end

      expect(events).to match([include(tool: "run_action", action: "archive", status: "error"), include(tool: "get_record", status: "error", http_status: 404)])
    end

    it "never carries argument values or record data" do
      events = capture_events("mcp_call.reactiveadmin") do
        call_tool("create_record", {resource: "posts", values: {title: ssn, author_id: alice.id.to_s}}, token:)
        call_tool("list_records", {resource: "posts", filters: {title_cont: ssn}}, token:)
        call_tool("get_record", {resource: "posts", id: first_post.id.to_s}, token:)
        call_tool("list_records", {resource: ssn}, token:)
      end

      expect(events.size).to eq(4)
      expect(events.flat_map(&:keys).uniq).to match_array(%i[user_id tool resource action status http_status duration_ms])
      expect(events.to_s).not_to include(ssn)
      expect(events.to_s).not_to include("Hello world")
      expect(events.last).not_to include(:resource)
    end

    it "leaves out the client id a host doesn't supply" do
      events = capture_events("mcp_call.reactiveadmin") { call_tool("list_resources", token:) }

      expect(events.first).not_to include(:client_id)
    end
  end
end
