RSpec::Matchers.define_negated_matcher :not_include, :include

RSpec.describe "api guard kinds", type: :request do
  include_context "with a blog"

  let(:events) { [] }
  let(:token) { token_for(admin) }
  let(:post_path) { "/api/admin/posts/#{first_post.id}" }

  before do
    ActiveSupport::Notifications.subscribe("write_rejected.reactiveadmin") { |*, payload| events << payload }
    sign_in admin
  end

  after { ActiveSupport::Notifications.unsubscribe(/reactiveadmin\z/) }

  def refused(guard:, message: nil)
    expect(response).to have_http_status(:forbidden)
    expect(json).to match_contract("Error").and include("code" => "api_denied", "guard" => guard)
    expect(json["message"]).to eq(message) if message
  end

  def as_token(verb, path, body = nil) = api(verb, path, body, headers: bearer(token))

  def token_get(path, **) = api_get(path, headers: bearer(token), **)

  def actions_of(path, **opts) = by_key(opts[:token] ? token_get(path)["actions"] : api_get(path)["actions"])

  def operations(document) = document["paths"].flat_map { |path, item| item.keys.map { |verb| [verb, path] } }

  describe ":read_only" do
    before { declare_guard("posts", :read_only) }

    it "serves reads and refuses every write, with the guard's own message" do
      api_get("/api/admin/posts")
      expect(response).to have_http_status(:ok)
      api_get(post_path)
      expect(response).to have_http_status(:ok)

      api(:post, "/api/admin/posts", {post: {title: "x"}})
      refused(guard: "read_only", message: ReactiveAdmin::ApiGuards::MESSAGES[:read_only])
      api(:delete, post_path)
      refused(guard: "read_only")
      api(:post, "#{post_path}/archive")
      refused(guard: "read_only")
      api(:post, "/api/admin/posts/import")
      refused(guard: "read_only")
      api(:post, "/api/admin/posts/batch_action", {batch_action: "feature", collection_selection: [first_post.id]})
      refused(guard: "read_only")
      expect(first_post.reload.status).to eq("published")
      expect(Post.exists?(first_post.id)).to be(true)
    end

    it "serves a GET action" do
      api_get("/api/admin/posts/stats")

      expect(json["code"]).not_to eq("api_denied")
    end

    it "closes the form of a write it refuses, and the options of that form" do
      api_get("/api/admin/posts/new")
      refused(guard: "read_only")
      api_get("#{post_path}/edit")
      refused(guard: "read_only")
      api_get("/api/admin/posts/_options", context: "form", id: first_post.id, field: "author")
      refused(guard: "read_only")
    end

    it "refuses a write sent by method override" do
      post post_path, params: {_method: "delete"}

      expect(response).to have_http_status(:forbidden)
      expect(Post.exists?(first_post.id)).to be(true)
    end

    it "marks every write as a link to the classic admin" do
      actions = actions_of(post_path)

      expect(actions.values_at("archive", "publish", "edit", "destroy").compact).to all(include("api_denied" => true, "supported" => false))
      expect(by_key(api_get("/api/admin/posts/_meta")["batch_actions"]).values).to all(include("api_denied" => true))
      items = by_key(api_get("/api/admin/posts/_meta")["action_items"])
      expect(items["import"]).to include("api_denied" => true)
      expect(items["stats"]).not_to include("api_denied")
    end

    it "lists what it denies in the manifest summary" do
      summary = by_key(api_get("/api/admin/_manifest")["resources"])["posts"]["api_denied"]

      expect(summary["actions"]).to include("new", "create", "edit", "update", "destroy", "archive", "import", "feature", "set_status", "batch_action")
      expect(summary["actions"]).not_to include("index", "show", "stats", "preview")
    end

    it "documents only the reads" do
      paths = ReactiveAdmin::OpenApi.build(admin)["paths"].select { |path, _| path.start_with?("/api/admin/posts") && path.exclude?("/_") && path.exclude?("comments") }

      expect(paths.values.flat_map(&:keys).uniq).to eq(%w[get])
      expect(paths.keys).to include("/api/admin/posts", "/api/admin/posts/{id}", "/api/admin/posts/stats")
      expect(paths.keys).not_to include("/api/admin/posts/new", "/api/admin/posts/{id}/archive", "/api/admin/posts/import", "/api/admin/posts/batch_action")
    end

    it "applies to a page's actions too" do
      declare_guard("dashboard", :read_only)

      api(:post, "/api/admin/dashboard/recalc")
      refused(guard: "read_only")
      api_get("/api/admin/_pages/dashboard")
      expect(response).to have_http_status(:ok)
    end

    it "keeps MCP to reads" do
      result = call_tool("describe_resource", {resource: "posts"}, token:)

      expect(result["can"]).to eq(%w[index show])
      expect(result["batch_actions"]).to eq([])
      expect(result["actions"].pluck("key")).to eq(%w[stats])
      expect(call_tool("get_record", {resource: "posts", id: first_post.id.to_s}, token:)["can"]).to eq(%w[show])
      call_tool("run_action", {resource: "posts", action: "archive", kind: "member", id: first_post.id.to_s, confirm: true}, token:)
      expect(tool_error?).to be(true)
    end
  end

  describe ":session_only" do
    before { declare_guard("posts", :session_only, only: [:archive, :destroy], reason: "Archive from the admin") }

    it "lets a session run the action and refuses a token, before the action runs" do
      api(:post, "#{post_path}/archive")
      expect(response).to have_http_status(:ok)
      expect(first_post.reload.status).to eq("archived")

      expect_any_instance_of(Admin::PostsController).not_to receive(:archive)
      as_token(:post, "#{post_path}/archive")
      refused(guard: "session_only", message: "Archive from the admin")
      expect(json["classic_url"]).to eq("/admin/posts/#{first_post.id}")
      as_token(:delete, post_path)
      refused(guard: "session_only")
      expect(events.last).to include(code: "api_denied", guard: "session_only", action: "destroy")
    end

    it "leaves everything else to a token" do
      as_token(:post, "#{post_path}/flag")

      expect(response).to have_http_status(:unprocessable_content).or have_http_status(:ok)
      expect(json["code"]).not_to eq("api_denied")
    end

    it "is the session's metadata for a session, and a link to the classic admin for a token" do
      expect(actions_of(post_path)["archive"]).to include("api_path").and(not_include("api_denied"))

      archive = actions_of(post_path, token: true)["archive"]
      expect(archive).to include("api_denied" => true, "supported" => false, "disabled_reason" => "Archive from the admin")
      expect(archive.keys).not_to include("api_path")
    end

    it "shows a token the denial in the manifest, and a session nothing" do
      session = by_key(api_get("/api/admin/_manifest")["resources"])["posts"]
      expect(session).not_to include("api_denied")

      denied = by_key(token_get("/api/admin/_manifest")["resources"])["posts"]["api_denied"]
      expect(denied["actions"]).to eq(%w[destroy archive])
    end

    it "is not shared between a session and a token through the meta cache" do
      expect(token_get("/api/admin/posts/_meta")["api_denied"]).to include("actions" => %w[destroy archive])
      expect(api_get("/api/admin/posts/_meta")).not_to include("api_denied")
      expect(token_get("/api/admin/posts/_meta")["api_denied"]).to be_present
    end

    it "documents the operation for a session, annotated, and leaves it out for a token" do
      session = ReactiveAdmin::OpenApi.build(admin)
      token_doc = ReactiveAdmin::OpenApi.build(admin, channel: :token)

      expect(session.dig("paths", "/api/admin/posts/{id}/archive", "post")).to include("x-reactiveadmin-session-only" => true)
      expect(session.dig("paths", "/api/admin/posts/{id}", "get")).not_to include("x-reactiveadmin-session-only")
      expect(operations(token_doc)).not_to include(["post", "/api/admin/posts/{id}/archive"])
      expect(operations(token_doc)).to include(["get", "/api/admin/posts/{id}"])
    end

    it "keeps the denied action out of MCP, and refuses it there" do
      expect(call_tool("get_record", {resource: "posts", id: first_post.id.to_s}, token:)).not_to include("archive")
      expect(call_tool("describe_resource", {resource: "posts"}, token:)["can"]).not_to include("destroy")
      call_tool("run_action", {resource: "posts", action: "archive", kind: "member", id: first_post.id.to_s, confirm: true}, token:)

      expect(tool_error?).to be(true)
      expect(@tool_error).to be(true)
    end

    it "judges attributes by channel too" do
      declare_guard("posts", :session_only, attributes: [:featured])

      api(:patch, post_path, {post: {featured: false}, lock: lock_of(first_post)})
      expect(response).to have_http_status(:ok)

      as_token(:patch, post_path, {post: {featured: true}, lock: lock_of(first_post)})
      refused(guard: "session_only")
      expect(json["attributes"]).to eq(["featured"])
      expect(json["message"]).to eq("A signed-in admin session can change: featured")
    end

    it "is refused for a token over a whole resource" do
      declare_guard("tags", :session_only)

      token_get("/api/admin/tags")
      refused(guard: "session_only")
      expect(by_key(token_get("/api/admin/_manifest")["resources"])).not_to have_key("tags")
      expect(by_key(api_get("/api/admin/_manifest")["resources"])).to have_key("tags")
      api_get("/api/admin/tags")
      expect(response).to have_http_status(:ok)
    end
  end

  describe "a registered guard" do
    let(:other_post) { second_post }

    before { declare_guard("posts", :admin_role, only: :archive, reason: "Admins archive") }

    it "lets a request through when it returns true, and refuses when it returns false" do
      api(:post, "#{post_path}/archive")
      expect(response).to have_http_status(:ok)

      reset!
      sign_in editor
      api(:post, "/api/admin/posts/#{other_post.id}/archive")
      refused(guard: "admin_role", message: "Admins archive")
      expect(other_post.reload.status).to eq("draft")
      expect(events.last).to include(code: "api_denied", guard: "admin_role")
    end

    it "gets the user and the request" do
      seen = []
      ReactiveAdmin.api_guard(:spy) { |user, request| seen << [user.id, request.path] && true }
      declare_guard("posts", :spy, only: :flag)

      api(:post, "#{post_path}/flag")

      expect(seen).to eq([[admin.id, "#{post_path}/flag"]])
    ensure
      ReactiveAdmin.api_guards.delete(:spy)
    end

    it "keeps the metadata and annotates it, for a session and a token alike" do
      expect(actions_of(post_path)["archive"]).to include("api_guard" => "admin_role", "api_path" => "#{post_path}/archive").and(not_include("api_denied"))
      expect(actions_of(post_path, token: true)["archive"]).to include("api_guard" => "admin_role")
      expect(by_key(api_get("/api/admin/_manifest")["resources"])["posts"]["api_denied"]).to eq("guards" => {"archive" => "admin_role"}, "classic_url" => "/admin/posts")
    end

    it "annotates the operation and still documents it" do
      operation = ReactiveAdmin::OpenApi.build(admin).dig("paths", "/api/admin/posts/{id}/archive", "post")

      expect(operation).to include("x-reactiveadmin-guard" => "admin_role")
      expect(operation).not_to include("x-reactiveadmin-session-only")
    end

    it "tells MCP the action may be refused, and refuses it for the wrong user" do
      record = call_tool("get_record", {resource: "posts", id: first_post.id.to_s}, token:)

      expect(record["actions"].find { it["key"] == "archive" }).to include("note" => "may be refused (admin_role)")
      expect(record["guarded"]).to eq("archive" => "may be refused (admin_role)")

      call_tool("run_action", {resource: "posts", action: "archive", kind: "member", id: first_post.id.to_s, confirm: true}, token: token_for(editor))
      expect(tool_error?).to be(true)
      expect(@tool_error).to be(true)
    end

    it "words a refusal for the agent with the guard's name and reason" do
      result = call_tool("run_action", {resource: "posts", action: "archive", kind: "member", id: first_post.id.to_s, confirm: true}, token: token_for(editor))

      expect(tool_error?).to be(true)
      expect(result).to include("Refused by the API guard admin_role: Admins archive", "Do not retry", "/admin/posts/#{first_post.id}")
    end

    it "refuses, and says nothing of the error, when it raises" do
      ReactiveAdmin.api_guard(:boom) { |_user, _request| raise "secret-detail" }
      declare_guard("posts", :boom, only: :flag)

      api(:post, "#{post_path}/flag")

      refused(guard: "boom")
      expect(response.body).not_to include("secret-detail")
    ensure
      ReactiveAdmin.api_guards.delete(:boom)
    end

    it "refuses when its registration has gone" do
      ReactiveAdmin.api_guard(:gone) { |_user, _request| true }
      declare_guard("posts", :gone, only: :flag)
      ReactiveAdmin.api_guards.delete(:gone)

      api(:post, "#{post_path}/flag")

      refused(guard: "gone")
    end

    it "guards attributes, by who writes them" do
      declare_guard("posts", :admin_role, attributes: [:title], reason: "Admins retitle")

      api(:patch, post_path, {post: {title: "Retitled"}, lock: lock_of(first_post)})
      expect(response).to have_http_status(:ok)

      reset!
      sign_in editor
      api(:patch, post_path, {post: {title: "Again"}, lock: lock_of(first_post)})
      refused(guard: "admin_role", message: "Admins retitle")
      expect(json["attributes"]).to eq(["title"])
      expect(first_post.reload.title).to eq("Retitled")
    end

    it "is registered under a name, a block and a symbol" do
      expect { ReactiveAdmin.api_guard(:nope) }.to raise_error(ArgumentError, /needs a block/)
      expect { ReactiveAdmin.api_guard(:deny) { true } }.to raise_error(ArgumentError, /built in/)

      ReactiveAdmin.api_guards["lambda"] = ->(_user, _request) { true }
      expect(ReactiveAdmin::ApiGuards.registered(:lambda)).to be_present
    ensure
      ReactiveAdmin.api_guards.delete("lambda")
    end

    it "fails loudly at declaration when the name is unknown" do
      config = ReactiveAdmin::Registry.find("tags")

      expect { ReactiveAdmin::ReactiveDSL.new(config).api(:superadmin_session, only: :update) }
        .to raise_error(ArgumentError, /:superadmin_session: no guard by that name.*ReactiveAdmin\.api_guard/)
      expect(ReactiveAdmin::ApiGuards.declarations(config)).to eq([])
    end
  end

  describe "except:" do
    before { declare_guard("posts", :deny, except: [:index, :show]) }

    it "denies every other action and keeps the ones it names" do
      api_get("/api/admin/posts")
      expect(response).to have_http_status(:ok)
      api_get(post_path)
      expect(response).to have_http_status(:ok)
      api_get("/api/admin/posts/_meta")
      expect(response).to have_http_status(:ok)

      api(:post, "#{post_path}/archive")
      refused(guard: "deny")
      api(:patch, post_path, {post: {title: "x"}})
      refused(guard: "deny")
      api_get("/api/admin/posts/new")
      refused(guard: "deny")
      api(:post, "/api/admin/posts/batch_action", {batch_action: "feature", collection_selection: [first_post.id]})
      refused(guard: "deny")
    end

    it "keeps both halves of a pair it names" do
      declare_guard("tags", :deny, except: [:show, :edit])

      tag = ruby
      api_get("/api/admin/tags/#{tag.id}/edit")
      expect(response).to have_http_status(:ok)
      api(:patch, "/api/admin/tags/#{tag.id}", {tag: {name: "rubies"}, lock: lock_of(tag)})
      expect(response).to have_http_status(:ok)
      api_get("/api/admin/tags/new")
      refused(guard: "deny")
    end
  end

  describe "stacking" do
    it "refuses when any guard does, and names the first that does" do
      declare_guard("posts", :admin_role, only: :archive)
      declare_guard("posts", :deny, only: :archive, reason: "No archiving")

      api(:post, "#{post_path}/archive")

      refused(guard: "deny", message: "No archiving")
      expect(first_post.reload.status).to eq("published")
    end

    it "lets a request through only when every guard allows it" do
      declare_guard("posts", :admin_role, only: :archive)
      declare_guard("posts", :session_only, only: :archive)

      api(:post, "#{post_path}/archive")
      expect(response).to have_http_status(:ok)

      as_token(:post, "#{post_path}/flag")
      expect(json["code"]).not_to eq("api_denied")
    end

    it "merges the attributes of several guards in one refusal" do
      declare_guard("posts", :deny, attributes: [:title])
      declare_guard("posts", :session_only, attributes: [:body])

      as_token(:patch, post_path, {post: {title: "x", body: "y"}, lock: "z"})

      refused(guard: "deny")
      expect(json["attributes"]).to eq(%w[body title])
    end

    it "scopes attributes to the writes named" do
      declare_guard("posts", :deny, attributes: [:title], only: :update)

      api(:post, "/api/admin/posts", {post: {title: "Created", author_id: alice.id}})
      expect(response).to have_http_status(:created)
      api(:patch, post_path, {post: {title: "Retitled"}, lock: lock_of(first_post)})
      refused(guard: "deny")

      fields = fields_of(api_get("#{post_path}/edit")["form"])
      expect(fields["title"]).to include("api_denied" => true, "disabled" => true)
      expect(fields_of(api_get("/api/admin/posts/new")["form"])["title"]).not_to include("api_denied")
    end
  end

  describe "a page" do
    it "is denied whole for `api false`, in every channel" do
      declare_guard("dashboard", false, reason: "Closed")

      api_get("/api/admin/_pages/dashboard")
      refused(guard: "deny", message: "Closed")
      token_get("/api/admin/_pages/dashboard")
      refused(guard: "deny")
      expect(ReactiveAdmin::OpenApi.build(admin)["paths"].keys.grep(/dashboard/)).to eq([])
    end

    it "is kept from MCP's list of pages" do
      declare_guard("dashboard", false)

      expect(call_tool("list_resources", {}, token:)["pages"].pluck("page")).not_to include("dashboard")
    end
  end

  describe "the classic admin" do
    it "is untouched by any guard" do
      declare_guard("posts", :read_only)
      declare_guard("posts", :admin_role)

      post "/admin/posts/#{first_post.id}/archive"

      expect(response).to redirect_to("/admin/posts/#{first_post.id}")
      expect(first_post.reload.status).to eq("archived")
    end
  end
end
