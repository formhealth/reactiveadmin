RSpec.describe "MCP and the api guards", type: :request do
  include_context "with a blog"

  let!(:other) { AdminUser.create!(name: "Olive Other", email: "olive@example.com", role: "editor", author: alice) }
  let!(:locker) { Locker.create!(label: "A1") }
  let(:token) { token_for(admin) }
  let(:classic) { "http://www.example.com" }

  def tool(name, arguments = {}) = call_tool(name, arguments, token:)

  def refused(url:, containing: nil)
    expect(tool_error?).to be(true)
    expect(@result).to include("Refused by the API", "#{classic}#{url}", "Do not retry")
    expect(@result).to include(containing) if containing
  end

  def call(name, arguments = {})
    @result = tool(name, arguments)
  end

  describe "what the tools offer" do
    it "lists no reserved resource, and only the actions left open" do
      resources = tool("list_resources")["resources"].index_by { it["key"] }

      expect(resources).not_to have_key("profiles")
      expect(resources["admin_users"]["can"]).to eq(%w[index show update])
      expect(resources["lockers"]["can"]).to eq(%w[index show create destroy])
    end

    it "describes a resource without its reserved actions, batch actions or create form" do
      described = tool("describe_resource", {resource: "admin_users"})

      expect(described["can"]).not_to include("create", "destroy")
      expect(described["batch_actions"].pluck("key")).to eq(%w[tidy])
      expect(described["actions"]).to eq([])
      expect(described).not_to have_key("form")
      expect(JSON.generate(described)).not_to match(/impersonate|sweep|promote/)
    end

    it "keeps a form when only another action is reserved" do
      described = tool("describe_resource", {resource: "lockers"})

      expect(described["can"]).to eq(%w[index show create destroy])
      expect(described["form"]["fields"].pluck("key")).to eq(%w[label code])
    end

    it "shows a record without its reserved actions" do
      record = tool("get_record", {resource: "admin_users", id: other.id.to_s})

      expect(record["can"]).to eq(%w[show update])
      expect(JSON.generate(record)).not_to include("impersonate")
    end

    it "gives a form without the reserved attributes" do
      form = tool("get_form", {resource: "admin_users", id: other.id.to_s})

      expect(form["fields"].pluck("key")).to eq(%w[name email name id])
      expect(JSON.generate(form)).not_to match(/role|rating/)
    end

    it "gives a page without its reserved actions" do
      page = tool("get_page", {page: "danger_zone"})

      expect(page).not_to have_key("actions")
      expect(JSON.generate(page)).not_to match(/wipe|audit/)
    end
  end

  describe "what a dispatched call returns when it hits the guard" do
    it "refuses a reserved resource, naming the reason and the classic page" do
      call("describe_resource", {resource: "profiles"})
      refused(url: "/admin/profiles", containing: "Profiles are managed in the classic admin")

      call("list_records", {resource: "profiles"})
      refused(url: "/admin/profiles")
    end

    it "refuses a reserved form" do
      call("get_form", {resource: "lockers", id: locker.id.to_s})

      refused(url: "/admin/lockers/#{locker.id}/edit")
    end

    it "refuses a reserved page" do
      call("get_page", {page: "back_office"})

      refused(url: "/admin/back_office")
    end

    it "refuses a reserved member action, confirmed or not, and never runs it" do
      expect_any_instance_of(Admin::AdminUsersController).not_to receive(:impersonate)

      [{}, {confirm: true}, {method: "get"}].each do |extra|
        call("run_action", {resource: "admin_users", action: "impersonate", kind: "member", id: other.id.to_s, **extra})

        refused(url: "/admin/admin_users/#{other.id}")
      end
    end

    it "refuses a reserved collection action and a reserved batch action" do
      call("run_action", {resource: "admin_users", action: "sweep", kind: "collection", confirm: true})
      refused(url: "/admin/admin_users")

      call("run_action", {resource: "admin_users", action: "promote", kind: "batch", ids: [other.id.to_s]})
      refused(url: "/admin/admin_users")
    end

    it "refuses create and delete of a reserved action, and changes nothing" do
      call("create_record", {resource: "admin_users", values: {name: "New"}})
      refused(url: "/admin/admin_users")

      call("delete_record", {resource: "admin_users", id: other.id.to_s, confirm: true})
      refused(url: "/admin/admin_users")

      expect(AdminUser.where(name: "New")).to be_empty
      expect(AdminUser.exists?(other.id)).to be(true)
    end

    it "refuses a write of a reserved attribute, naming it and not its value" do
      lock = tool("get_form", {resource: "admin_users", id: other.id.to_s})["lock"]
      call("update_record", {resource: "admin_users", id: other.id.to_s, values: {role: "superadmin-s3cret"}, lock:})

      refused(url: "/admin/admin_users/#{other.id}", containing: "Reserved: role")
      expect(@result).not_to include("superadmin-s3cret")
      expect(other.reload.role).to eq("editor")
    end

    it "still serves what is not reserved" do
      lock = tool("get_form", {resource: "admin_users", id: other.id.to_s})["lock"]

      expect(tool("update_record", {resource: "admin_users", id: other.id.to_s, values: {name: "Olivia"}, lock:})).to include("ok" => true)
      expect(tool("run_action", {resource: "admin_users", action: "greet", kind: "member", id: other.id.to_s, confirm: true})).to include("ok" => true)
      expect(other.reload.name).to eq("Olivia")
    end

    it "asks for confirmation of an action that is not reserved" do
      call("run_action", {resource: "admin_users", action: "greet", kind: "member", id: other.id.to_s})

      expect(@result).to include("Ask the user to confirm")
    end
  end

  describe "ahead of the guard" do
    it "answers a write the token's scopes don't cover with the scope, not the reservation" do
      read_only = token_for(admin, scopes: ["admin:read"])
      @result = call_tool("run_action", {resource: "admin_users", action: "impersonate", kind: "member", id: other.id.to_s, confirm: true}, token: read_only)

      expect(tool_error?).to be(true)
      expect(@result).to include("admin:write").and(satisfy { !it.include?("classic") })
    end

    it "answers a token that can't read 403 insufficient_scope before any tool runs" do
      rpc("tools/call", {name: "describe_resource", arguments: {resource: "profiles"}}, token: token_for(admin, scopes: ["admin:write"]))

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body).to include("code" => "insufficient_scope")
    end

    it "answers a bad token 401" do
      rpc("tools/call", {name: "describe_resource", arguments: {resource: "profiles"}}, token: "nope")

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
