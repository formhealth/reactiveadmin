RSpec.describe "client error reports", type: :request do
  include_context "with a blog"
  include McpHelpers
  include ActiveSupport::Testing::TimeHelpers

  let(:path) { "/api/admin/_client_errors" }
  let(:report) do
    {error_name: "TypeError", boundary: "route", components: %w[Pill ResourceShow], route: "/:resource/:id/edit", resource: "posts",
     client_version: "0.1.0", request_id: "req-1"}
  end
  let(:reported) { [] }

  # 204 has no body for the helper's JSON contract check, which still applies to every error.
  def post_report(body = report, headers: {})
    post path, params: body.to_json, headers: ApiHelpers::JSON_HEADERS.merge(headers)
    check_contract(nil) unless response.status == 204
  end

  def with_reporter
    original = ReactiveAdmin.config.error_reporter
    ReactiveAdmin.config.error_reporter = ->(error, context) { reported << [error, context] }
    yield
  ensure
    ReactiveAdmin.config.error_reporter = original
  end

  around { |example| with_reporter { example.run } }

  around do |example|
    original = ReactiveAdmin.config.rate_limits
    ReactiveAdmin.config.rate_limits = false
    example.run
  ensure
    ReactiveAdmin.config.rate_limits = original
  end

  describe "as a signed-in user" do
    before { sign_in editor }

    it "answers 404 and reports nothing when the host turns client errors off" do
      ReactiveAdmin.config.ui.client_errors = false
      post_report

      expect(response).to have_http_status(:not_found)
      expect(reported).to be_empty
      expect(api_get("/api/admin/_session")["ui"]).to include("client_errors" => false)
    ensure
      ReactiveAdmin.config.ui.client_errors = true
    end

    it "hands a scrubbed error to the reporter and answers 204" do
      post_report

      expect(response).to have_http_status(:no_content)
      error, context = reported.sole
      expect(error).to be_a(ReactiveAdmin::ClientError)
      expect(error.original_class).to eq("TypeError")
      expect(error.message).to eq("TypeError in the client at /:resource/:id/edit")
      expect(error.backtrace).to eq(["in Pill", "in ResourceShow"])
      expect(context).to include(resource: "posts", action: "client", boundary: "route", route: "/:resource/:id/edit", client_version: "0.1.0",
        client_request_id: "req-1", error_class: "TypeError", request_id: a_string_matching(/\S/))
    end

    it "takes the report the contract describes" do
      expect(report.deep_stringify_keys).to match_contract("ClientErrorReport")
    end

    it "still hands the report to the reporter when a subscriber raises, and publishes it when the reporter does" do
      subscriber = ActiveSupport::Notifications.subscribe("client_error.reactiveadmin") { raise "counter store down" }
      post_report
      ActiveSupport::Notifications.unsubscribe(subscriber)
      expect(response).to have_http_status(:no_content)
      expect(reported.size).to eq(1)

      ReactiveAdmin.config.error_reporter = ->(*) { raise "reporter down" }
      events = capture_events("client_error.reactiveadmin") { post_report(report.merge(boundary: "app")) }
      expect(response).to have_http_status(:no_content)
      expect(events.size).to eq(1)
    end

    it "publishes client_error.reactiveadmin with names and the user's id, nothing else" do
      events = capture_events("client_error.reactiveadmin") { post_report }

      expect(events.sole).to eq(report.except(:error_name, :request_id).merge(error_class: "TypeError", client_request_id: "req-1", user_id: editor.id, request_id: events.sole[:request_id]))
    end

    it "keeps only fields shaped like names, so text and values can't ride along" do
      post_report({error_name: "TypeError", boundary: "route", components: ["Pill", "Cannot read x of jane@example.com", "Ok2", {a: 1}],
                   route: "/authors/42/edit?name=Jane", resource: "jane-smith", client_version: "1.0 beta", request_id: "a b c"})

      error, context = reported.sole
      expect(error.components).to eq(%w[Pill Ok2])
      expect(context.keys).not_to include(:route, :resource, :client_version, :client_request_id)
      expect(error.message).to eq("TypeError in the client at an unknown route")
    end

    it "drops a route that holds a literal or an id instead of a pattern" do
      ["/authors/42", "/authors/42/edit", "/:resource/42", "/groups/people/staff", "/:resource/:id/edit/:a/:b/:c/:d/:e/:f/:g"].each do |route|
        reported.clear
        post_report(report.merge(route:))
        expect(reported.sole.first.route).to be_nil, route
      end
      %w[/ /* /:resource /groups/* /:resource/new /:resource/:id/actions/:key].each do |route|
        reported.clear
        post_report(report.merge(route:))
        expect(reported.sole.first.route).to eq(route)
      end
    end

    it "drops a resource the user's app doesn't serve, including text that merely looks like a key" do
      post_report(report.merge(resource: "patients"))

      expect(reported.sole.first.resource).to be_nil
    end

    it "drops a resource the user may not read" do
      post_report(report.merge(resource: "categories"))

      expect(reported.sole.first.resource).to eq(can_read_categories?(editor) ? "categories" : nil)
    end

    it "authorizes only the registrations the report names" do
      asked = []
      allow_any_instance_of(ReactiveAdmin::Authorizer).to receive(:authorized?).and_wrap_original { |m, *args, **opts| (asked << opts[:config]) && m.call(*args, **opts) }

      post_report(report.merge(resource: "posts"))
      expect(asked.map { ReactiveAdmin::Registry.route_key(it) }).to eq(["posts"])

      asked.clear
      post_report(report.except(:resource))
      expect(asked).to be_empty
    end

    it "accepts a page key as the resource" do
      post_report(report.merge(resource: "dashboard"))

      expect(reported.sole.first.resource).to eq("dashboard")
    end

    it "refuses a report that names no error" do
      post_report(report.merge(error_name: "something went wrong for jane@example.com"))

      expect(response).to have_http_status(:bad_request)
      expect(json).to include("code" => "invalid")
      expect(reported).to be_empty
    end

    it "caps the component list" do
      post_report(report.merge(components: Array.new(50) { "C#{it}" }))

      expect(reported.sole.first.components.size).to eq(20)
    end

    it "survives a reporter that raises" do
      ReactiveAdmin.config.error_reporter = ->(*) { raise "reporter down" }

      post_report

      expect(response).to have_http_status(:no_content)
    end

    it "leaves no write audit trail: a report isn't a write" do
      events = capture_events("write.reactiveadmin") { post_report }

      expect(events).to be_empty
    end
  end

  describe "authentication" do
    it "needs a session" do
      post_report

      expect(response).to have_http_status(:unauthorized)
      expect(reported).to be_empty
    end

    it "refuses a bearer token: reports come from the browser" do
      post_report(headers: bearer(token_for(admin)))

      expect(response).to have_http_status(:forbidden)
      expect(reported).to be_empty
    end
  end

  describe "with forgery protection on", :csrf do
    around do |example|
      original = ActionController::Base.allow_forgery_protection
      ActionController::Base.allow_forgery_protection = true
      example.run
    ensure
      ActionController::Base.allow_forgery_protection = original
    end

    before { sign_in editor }

    it "needs the session's CSRF token, as any write does" do
      post_report

      expect(response).to have_http_status(:unprocessable_content)
      expect(reported).to be_empty

      post_report(headers: {"X-CSRF-Token" => csrf_token})

      expect(response).to have_http_status(:no_content)
    end
  end

  describe "rate limit" do
    around do |example|
      original = ReactiveAdmin.config.rate_limits
      ReactiveAdmin.config.rate_limits = {client_error: [2, 1.minute], default: nil}
      example.run
    ensure
      ReactiveAdmin.config.rate_limits = original
    end

    it "answers 429 with Retry-After once the client_error budget is spent, per user" do
      sign_in editor
      2.times do
        post_report
        expect(response).to have_http_status(:no_content)
      end
      post_report

      expect(response).to have_http_status(:too_many_requests)
      expect(json).to include("code" => "rate_limited")
      expect(response.headers["Retry-After"].to_i).to be_between(1, 60)
      expect(reported.size).to eq(2)

      sign_in admin
      post_report
      expect(response).to have_http_status(:no_content)
    end

    it "throttles before authorizing, so a flood doesn't reach the host's checks" do
      authorized = 0
      original = ReactiveAdmin.config.after_authorize
      ReactiveAdmin.config.after_authorize = ->(_) { authorized += 1 }
      sign_in editor
      3.times { post_report }

      expect(response).to have_http_status(:too_many_requests)
      expect(authorized).to eq(2)
    ensure
      ReactiveAdmin.config.after_authorize = original
    end

    it "draws on its own bucket" do
      sign_in editor
      3.times { post_report }

      api_get("/api/admin/posts")

      expect(response).to have_http_status(:ok)
    end
  end
end
