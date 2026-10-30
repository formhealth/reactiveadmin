RSpec.describe "api guards", type: :request do
  include_context "with a blog"

  let(:events) { [] }
  let(:secret) { "superadmin-s3cret" }
  let!(:other) { AdminUser.create!(name: "Olive Other", email: "olive@example.com", role: "editor", author: alice) }
  let!(:profile) { Profile.create!(author: alice, bio: "Hi") }
  let!(:locker) { Locker.create!(label: "A1") }

  before do
    ActiveSupport::Notifications.subscribe("write_rejected.reactiveadmin") { |*, payload| events << payload }
    sign_in admin
  end

  after { ActiveSupport::Notifications.unsubscribe(/reactiveadmin\z/) }

  def refused(url: nil, message: nil)
    expect(response).to have_http_status(:forbidden)
    expect(json).to match_contract("Error").and include("code" => "api_denied")
    expect(json["classic_url"]).to eq(url) if url
    expect(json["message"]).to eq(message) if message
  end

  describe "actions" do
    it "refuses a member action that a GET could run, and points at the same classic page" do
      api_get("/api/admin/admin_users/#{other.id}/impersonate")

      refused(url: "/admin/admin_users/#{other.id}/impersonate", message: ReactiveAdmin::ApiGuards::ACTION_MESSAGE)
    end

    it "refuses a member action that writes, and points at the record's classic page" do
      api(:post, "/api/admin/admin_users/#{other.id}/impersonate")

      refused(url: "/admin/admin_users/#{other.id}")
      expect(events).to eq([{resource: "admin_users", action: "impersonate", id: other.id.to_s, user_id: admin.id, code: "api_denied", guard: "deny"}])
    end

    it "serves the member actions it was not told about" do
      api(:post, "/api/admin/admin_users/#{other.id}/greet")

      expect(response).to have_http_status(:ok)
      expect(json).to include("ok" => true, "message" => "Hello")
    end

    it "refuses a collection action" do
      api(:post, "/api/admin/admin_users/sweep")

      refused(url: "/admin/admin_users")
    end

    it "refuses create, and the form that submits it" do
      api(:post, "/api/admin/admin_users", {admin_user: {name: "New"}})
      refused(url: "/admin/admin_users")
      api_get("/api/admin/admin_users/new")
      refused(url: "/admin/admin_users/new")

      expect(AdminUser.where(name: "New")).to be_empty
    end

    it "refuses destroy" do
      api(:delete, "/api/admin/admin_users/#{other.id}")

      refused(url: "/admin/admin_users/#{other.id}")
      expect(AdminUser.exists?(other.id)).to be(true)
    end

    it "refuses an edit form and its update together, and serves what it was not told about" do
      api_get("/api/admin/lockers/#{locker.id}/edit")
      refused(url: "/admin/lockers/#{locker.id}/edit")
      api(:patch, "/api/admin/lockers/#{locker.id}", {locker: {label: "B2"}})
      refused(url: "/admin/lockers/#{locker.id}")
      expect(locker.reload.label).to eq("A1")

      api(:post, "/api/admin/lockers", {locker: {label: "C3"}})
      expect(response).to have_http_status(:created)
      api_get("/api/admin/lockers/new")
      expect(response).to have_http_status(:ok)
    end

    it "refuses the batch action it names, and runs the others" do
      api(:post, "/api/admin/admin_users/batch_action", {batch_action: "promote", collection_selection: [other.id]})
      refused(url: "/admin/admin_users")

      api(:post, "/api/admin/admin_users/batch_action", {batch_action: "tidy", collection_selection: [other.id]})
      expect(response).to have_http_status(:ok)
      expect(json["message"]).to eq("Tidied 1")
    end

    it "refuses a page action, and serves the page itself" do
      api(:post, "/api/admin/danger_zone/wipe")
      refused(url: "/admin/danger_zone")
      api_get("/api/admin/danger_zone/audit")
      refused(url: "/admin/danger_zone/audit")

      api_get("/api/admin/_pages/danger_zone")
      expect(response).to have_http_status(:ok)
    end

    it "refuses the options of a form it refuses" do
      api_get("/api/admin/lockers/_options", context: "form", id: locker.id, field: "label")

      refused
    end
  end

  describe "a whole resource" do
    let(:reason) { "Profiles are managed in the classic admin" }

    it "refuses every endpoint it has, with the reason" do
      {
        "/api/admin/profiles" => "/admin/profiles",
        "/api/admin/profiles.csv" => "/admin/profiles",
        "/api/admin/profiles/#{profile.id}" => "/admin/profiles/#{profile.id}",
        "/api/admin/profiles/new" => "/admin/profiles/new",
        "/api/admin/profiles/#{profile.id}/edit" => "/admin/profiles/#{profile.id}/edit",
        "/api/admin/profiles/_meta" => "/admin/profiles",
        "/api/admin/profiles/_labels?ids=#{profile.id}" => "/admin/profiles",
        "/api/admin/profiles/_options?context=filter&field=bio" => "/admin/profiles",
        "/api/admin/profiles/#{profile.id}/_value?field=bio" => "/admin/profiles/#{profile.id}"
      }.each do |path, classic|
        api_get(path)

        refused(url: classic, message: reason)
      end
    end

    it "refuses every write" do
      api(:post, "/api/admin/profiles", {profile: {bio: "x"}})
      refused(message: reason)
      api(:patch, "/api/admin/profiles/#{profile.id}", {profile: {bio: "x"}})
      refused(message: reason)
      api(:delete, "/api/admin/profiles/#{profile.id}")
      refused(message: reason)

      expect(profile.reload.bio).to eq("Hi")
    end

    it "is left out of the manifest" do
      keys = api_get("/api/admin/_manifest")["resources"].pluck("key")

      expect(keys).to include("authors")
      expect(keys).not_to include("profiles")
    end

    it "refuses a whole page" do
      api_get("/api/admin/_pages/back_office")

      refused(url: "/admin/back_office")
    end

    it "does not link records of it from other resources" do
      expect(ReactiveAdmin::Registry.for_class(Profile)).to be_nil
    end
  end

  describe "attributes" do
    def update(attrs) = api(:patch, "/api/admin/admin_users/#{other.id}", {admin_user: attrs, lock: lock_of(other)})

    it "refuses a write that includes one, naming it and never its value" do
      update(name: "Renamed", role: secret)

      refused(url: "/admin/admin_users/#{other.id}", message: "Roles and ratings are changed in the classic admin")
      expect(json["attributes"]).to eq(["role"])
      expect(response.body).not_to include(secret)
      expect(other.reload).to have_attributes(name: "Olive Other", role: "editor")
    end

    it "refuses one at any nesting" do
      update(author_attributes: {id: alice.id, rating: 5})
      expect(json["attributes"]).to eq(["rating"])

      update(author_attributes: {id: alice.id, profile_attributes: {bio: secret}})
      expect(json["attributes"]).to eq(["bio"])
      expect(alice.reload.rating).to eq(4.5)
    end

    it "lists every attribute the write includes, once" do
      update(role: "admin", author_attributes: {rating: 1, profile_attributes: {bio: "x"}})

      expect(json["attributes"]).to eq(%w[bio rating role])
    end

    it "refuses it even where the form doesn't map it" do
      api(:patch, "/api/admin/admin_users/#{other.id}?admin_user[role]=admin", {admin_user: {name: "Q"}, lock: lock_of(other)})

      expect(json["attributes"]).to eq(["role"])
    end

    it "accepts the writes that leave them alone" do
      update(name: "Renamed", author_attributes: {id: alice.id, name: "Alice B"})

      expect(response).to have_http_status(:ok)
      expect(other.reload.name).to eq("Renamed")
      expect(alice.reload.name).to eq("Alice B")
    end

    it "leaves reading them as it was, and shows their inputs read-only with a classic link" do
      form = api_get("/api/admin/admin_users/#{other.id}/edit", schema: "FormResponse")
      fields = fields_of(form["form"])

      expect(fields["role"]).to include("value" => "editor", "disabled" => true, "api_denied" => true, "classic_url" => "/admin/admin_users/#{other.id}/edit")
      expect(fields["rating"]).to include("api_denied" => true)
      expect(fields["name"]).not_to include("api_denied")
      expect(api_get("/api/admin/admin_users/#{other.id}")["layout"].to_s).to include("editor")
    end

    it "is not fooled by an attribute that is only a blank key" do
      update(name: "Renamed", role: "")

      refused
    end
  end

  describe "audit" do
    it "emits the write rejection with ids only, whatever the verb" do
      api(:patch, "/api/admin/admin_users/#{other.id}", {admin_user: {role: secret}, lock: lock_of(other)})
      api_get("/api/admin/profiles")

      expect(events).to eq([
        {resource: "admin_users", action: "update", id: other.id.to_s, user_id: admin.id, code: "api_denied", guard: "deny"},
        {resource: "profiles", action: "index", id: nil, user_id: admin.id, code: "api_denied", guard: "deny"}
      ])
      expect(events.to_s).not_to include(secret)
    end

    it "stays quiet for a request that was refused before it was authenticated" do
      reset!
      api_get("/api/admin/profiles")

      expect(response).to have_http_status(:unauthorized)
      expect(events).to be_empty
    end
  end

  describe "ways around it" do
    it "is not reached through a method override" do
      post "/api/admin/admin_users/#{other.id}", params: {_method: "delete"}

      expect(AdminUser.exists?(other.id)).to be(true)
      expect(response).to have_http_status(:forbidden)
      expect(json["code"]).to eq("api_denied")
    end

    it "is not reached by naming another format" do
      %w[json xml].each do |format|
        api_get("/api/admin/admin_users/#{other.id}/impersonate.#{format}")
        expect(response).to have_http_status(:not_found)
        api_get("/api/admin/profiles.#{format}")
        expect(response).to have_http_status(:not_found)
      end
      api_get("/api/admin/admin_users/#{other.id}/impersonate.reactiveadmin")

      refused
    end

    it "is enforced on a classic URL asked for in the API's media type" do
      get "/admin/profiles", headers: {"ACCEPT" => "application/vnd.reactiveadmin+json"}
      refused(url: "/admin/profiles")

      get "/admin/admin_users/#{other.id}/impersonate", headers: {"ACCEPT" => "application/vnd.reactiveadmin+json"}
      refused(url: "/admin/admin_users/#{other.id}/impersonate")
    end

    it "is enforced on a bearer-style request without a session cookie" do
      reset!
      allow_any_instance_of(ApplicationController).to receive(:current_admin_user).and_return(admin)

      api(:post, "/api/admin/admin_users/#{other.id}/impersonate")

      refused
    end

    it "is enforced when the host skips authentication" do
      allow_any_instance_of(Admin::AdminUsersController).to receive(:authenticate_active_admin_user)
      allow_any_instance_of(Admin::AdminUsersController).to receive(:current_admin_user).and_return(admin)

      api(:post, "/api/admin/admin_users/#{other.id}/impersonate")

      refused
    end

    it "is enforced before the action's own callbacks do any work" do
      ran = false
      allow_any_instance_of(Admin::AdminUsersController).to receive(:impersonate) { ran = true }

      api(:post, "/api/admin/admin_users/#{other.id}/impersonate")

      expect(ran).to be(false)
    end
  end

  describe "the classic admin" do
    it "serves every page and action it was refused on the API" do
      ["/admin/profiles", "/admin/profiles/#{profile.id}", "/admin/admin_users/new", "/admin/lockers/#{locker.id}/edit", "/admin/back_office"].each do |path|
        get path

        expect(response).to have_http_status(:ok), path
        expect(response.media_type).to eq("text/html"), path
      end
    end

    it "runs the actions" do
      post "/admin/admin_users/#{other.id}/impersonate"
      expect(response).to redirect_to("/admin/admin_users/#{other.id}")
      expect(flash[:notice]).to eq("Impersonating")

      post "/admin/danger_zone/wipe"
      expect(flash[:notice]).to eq("Wiped")

      post "/admin/admin_users/batch_action", params: {batch_action: "promote", collection_selection: [other.id]}
      expect(flash[:notice]).to eq("Promoted 1")
    end

    it "writes the attributes, creates and destroys" do
      patch "/admin/admin_users/#{other.id}", params: {admin_user: {role: "admin"}}
      expect(other.reload.role).to eq("admin")

      post "/admin/admin_users", params: {admin_user: {name: "Classic", role: "admin"}}
      expect(AdminUser.find_by(name: "Classic")).to be_present

      delete "/admin/admin_users/#{other.id}"
      expect(AdminUser.exists?(other.id)).to be(false)
    end
  end

  describe "metadata" do
    it "marks the actions, with a classic link and nothing that runs" do
      shown = api_get("/api/admin/admin_users/#{other.id}")
      impersonate = by_key(shown["actions"])["impersonate"]

      expect(impersonate).to include("api_denied" => true, "classic_url" => "/admin/admin_users/#{other.id}", "supported" => false)
      expect(impersonate.keys).not_to include("api_path", "form_path", "view")
      expect(by_key(shown["actions"])["destroy"]).to include("api_denied" => true)
      expect(by_key(shown["actions"])["edit"]).not_to include("api_denied")
    end

    it "marks batch actions" do
      batch = by_key(api_get("/api/admin/admin_users/_meta")["batch_actions"])

      expect(batch["promote"]).to include("api_denied" => true, "classic_url" => "/admin/admin_users")
      expect(batch["tidy"]).not_to include("api_denied")
    end

    it "marks a partly denied resource in the manifest" do
      resource = by_key(api_get("/api/admin/_manifest")["resources"])["admin_users"]

      expect(resource["api_denied"]).to eq(
        "actions" => %w[new create destroy impersonate sweep promote],
        "attributes" => %w[role rating bio],
        "classic_url" => "/admin/admin_users"
      )
      expect(by_key(api_get("/api/admin/_manifest")["resources"])["authors"]).not_to include("api_denied")
    end

    it "marks a page's actions" do
      page = api_get("/api/admin/_pages/danger_zone")

      expect(by_key(page["actions"])["audit"]).to include("api_denied" => true, "classic_url" => "/admin/danger_zone/audit")
    end

    it "marks a denied resource's menu entry as a classic link" do
      menu = api_get("/api/admin/_manifest")["menu"]
      nodes = ->(list) { list.flat_map { [it, *nodes.call(it["children"])] } }

      expect(nodes.call(menu).select { it["api_denied"] }).to all(include("kind" => "link"))
    end
  end

  describe ReactiveAdmin::ApiGuards do
    let(:config) { Struct.new(:reactive_options, :resource_class).new({}, Post) }

    def declare(guard = nil, **) = described_class.declare(config, guard, **)

    def denial(*names, **) = described_class.denial(config, names, **)

    it "denies everything for false, with no names" do
      declare false

      expect(described_class.whole?(config)).to be(true)
      expect(described_class.message(denial("anything"))).to eq(described_class::ACTION_MESSAGE)
    end

    it "pairs the form with its write, in only and in except" do
      declare :deny, only: [:new, :update]

      expect(%w[new create edit update].map { denial(it).present? }).to all(be(true))
      expect(denial("destroy")).to be_nil

      other = Struct.new(:reactive_options, :resource_class).new({}, Post)
      described_class.declare(other, :deny, except: [:edit])
      expect(%w[edit update].map { described_class.denial(other, [it]) }).to all(be_nil)
      expect(described_class.denial(other, %w[new])).to be_present
    end

    it "matches a batch action by its key or as all of them" do
      declare :deny, only: [:promote]

      expect(denial("batch_action", "promote")).to be_present
      expect(denial("batch_action", "tidy")).to be_nil
      expect(denial("batch_action")).to be_nil
    end

    it "uses each declaration's reason and falls back to the guard's message" do
      declare :deny, only: [:archive], reason: "No"
      declare :read_only

      expect(described_class.message(denial("archive"))).to eq("No")
      expect(described_class.message(denial("destroy"))).to eq(described_class::MESSAGES[:read_only])
    end

    it "watches an association's foreign key, ids and nested attributes under its name" do
      declaration = declare :deny, attributes: [:author, :tags]

      expect(described_class.watched(config, declaration)).to include("author_id" => "author", "author_attributes" => "author", "tag_ids" => "tags", "tags_attributes" => "tags")
    end

    it "reads a batch action's inputs, which travel as JSON" do
      expect(described_class.keys_in({"batch_action_inputs" => {"role" => "x"}.to_json}).to_a).to include("role")
    end

    it "refuses a declaration that makes no sense, at boot" do
      expect { declare }.to raise_error(ArgumentError, /needs a guard/)
      expect { declare :deny, only: [:a], except: [:b] }.to raise_error(ArgumentError, /don't combine/)
      expect { declare :read_only, attributes: [:a] }.to raise_error(ArgumentError, /no attributes/)
      expect { declare :no_such_guard }.to raise_error(ArgumentError, /no guard by that name.*ReactiveAdmin\.api_guard\(:no_such_guard\)/)
    end

    it "reports the typo of an action name" do
      locker = ReactiveAdmin::Registry.find("lockers")
      before = locker.reactive_options.deep_dup
      ReactiveAdmin::ReactiveDSL.new(locker).api(:deny, only: :destory)

      expect(described_class.audit).to eq([{kind: :api_guard_unknown_action, resource: "lockers", action: "destory", reason: "api :deny names destory, which matches no action of this resource"}])
    ensure
      locker.reactive_options.replace(before)
    end
  end

  describe "the doctor" do
    let(:report) { ReactiveAdmin::Doctor.run(user: admin) }

    it "lists the declarations as accepted decisions, not findings" do
      declared = report[:api_guards].group_by { it[:key] }

      expect(declared["profiles"]).to contain_exactly(include(kind: "resource", guard: "deny", whole: true, reason: "Profiles are managed in the classic admin"))
      expect(declared["admin_users"]).to contain_exactly(
        include(guard: "deny", whole: false, only: %w[create destroy impersonate sweep promote]),
        include(guard: "deny", attributes: %w[role rating bio])
      )
      expect(declared["back_office"]).to contain_exactly(include(kind: "page", whole: true))
      expect(report[:resources].pluck(:key)).not_to include("profiles")
      expect(report[:failures] || report[:summary][:failures]).to be_zero
      expect(report[:diagnostics].pluck(:kind)).not_to include("api_guard_unknown_action")
    end

    it "prints them in their own section" do
      text = ReactiveAdmin::Doctor::Table.new(report).to_s

      expect(text).to include("API guards (accepted)", "resource profiles: deny all (Profiles are managed in the classic admin)",
        "resource admin_users: deny only create, destroy, impersonate, sweep, promote", "resource admin_users: deny attributes role, rating, bio")
    end

    it "lists explicit menu overlay links as accepted decisions" do
      ReactiveAdmin.menu { group("Tools") { link("Reports", url: "/admin/reports") && link("Dynamic", url: -> { "/x" }) } }
      text = ReactiveAdmin::Doctor::Table.new(report).to_s

      expect(report[:menu_links]).to eq([{id: "tools/reports", path: %w[Tools Reports], url: "/admin/reports"}, {id: "tools/dynamic", path: %w[Tools Dynamic], url: nil}])
      expect(text).to include("Menu links (accepted)", "Tools > Reports: /admin/reports", "Tools > Dynamic: computed")
    ensure
      ReactiveAdmin::MenuOverlay.reset!
    end

    it "counts a resource or page as accepted when nothing of it is left to serve, however it was denied" do
      locker = ReactiveAdmin::Registry.find("lockers")
      before = locker.reactive_options.deep_dup
      denied = ->(key) { ReactiveAdmin::ApiGuards.fully_denied?([*ReactiveAdmin::Registry.resources, *ReactiveAdmin::Registry.pages].find { ReactiveAdmin::Exposure.key(it) == key }) }

      expect(%w[profiles back_office].map(&denied)).to eq([true, true])
      expect(%w[lockers danger_zone admin_users].map(&denied)).to eq([false, false, false])
      ReactiveAdmin::ReactiveDSL.new(locker).api(:deny, only: %w[index show new create edit update destroy])
      expect(denied.call("lockers")).to be(true)
    ensure
      locker.reactive_options.replace(before)
    end

    it "does not count them as legacy" do
      items = ReactiveAdmin::LegacyInventory.new(user: admin).run

      expect(items.select { it.key.match?(/admin_users|profiles|lockers|danger_zone|back_office/) && it.category.in?(%w[action_unsupported menu_link not_exposed view_unsupported]) }).to be_empty
    end
  end
end
