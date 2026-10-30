RSpec.describe "write audit and error scrubbing", type: :request do
  include_context "with a blog"

  let(:events) { [] }
  let(:ssn) { "123-45-6789" }

  before do
    %w[write write_rejected].each { |name| ActiveSupport::Notifications.subscribe("#{name}.reactiveadmin") { |*, payload| events << [name, payload] } }
    sign_in admin
  end

  after { ActiveSupport::Notifications.unsubscribe(/reactiveadmin\z/) }

  def post_body(**attrs) = {post: {title: "T", author_id: alice.id}.merge(attrs)}

  def rejected = events.select { it.first == "write_rejected" }.map(&:last)

  def written = events.select { it.first == "write" }.map(&:last)

  describe "accepted writes" do
    it "emits who wrote what, without values" do
      api(:post, "/api/admin/posts", post_body(title: ssn))

      expect(response).to have_http_status(:created)
      expect(written).to eq([{resource: "posts", action: "create", id: json["id"], user_id: admin.id}])
      expect(events.to_s).not_to include(ssn)
      expect(rejected).to be_empty
    end

    it "covers updates" do
      api(:patch, "/api/admin/posts/#{first_post.id}", post_body(title: "New").merge(lock: lock_of(first_post)))

      expect(written).to eq([{resource: "posts", action: "update", id: first_post.id.to_s, user_id: admin.id}])
    end

    it "covers destroys, whose record is gone by the time the event fires" do
      skip "adapter disallows destroy" unless can_destroy_post?(admin)

      api(:delete, "/api/admin/posts/#{second_post.id}")

      expect(written).to eq([{resource: "posts", action: "destroy", id: second_post.id.to_s, user_id: admin.id}])
    end

    it "stays quiet for reads" do
      api_get("/api/admin/posts")

      expect(events).to be_empty
    end
  end

  describe "rejected writes" do
    it "records an invalid write as invalid" do
      api(:post, "/api/admin/posts", post_body(title: ""))

      expect(response).to have_http_status(:unprocessable_content)
      expect(rejected).to eq([{resource: "posts", action: "create", id: nil, user_id: admin.id, code: "invalid"}])
      expect(written).to be_empty
    end

    it "records a stale write as stale" do
      lock = lock_of(first_post)
      first_post.touch(time: 1.minute.from_now)
      api(:patch, "/api/admin/posts/#{first_post.id}", post_body(title: "Mine").merge(lock:))

      expect(response).to have_http_status(:conflict)
      expect(rejected).to eq([{resource: "posts", action: "update", id: first_post.id.to_s, user_id: admin.id, code: "stale"}])
    end

    it "records a forbidden write as forbidden" do
      skip "adapter allows everything" if adapter?(:default)
      sign_in editor
      events.clear

      api(:delete, "/api/admin/categories/#{news.id}")

      expect(response).to have_http_status(:forbidden)
      expect(rejected).to eq([{resource: "categories", action: "destroy", id: news.id.to_s, user_id: editor.id, code: "forbidden"}])
    end

    it "records a write the form can't carry as unsupported" do
      api(:post, "/api/admin/doodles", {sketch: {title: "x"}})

      expect(response).to have_http_status(:unprocessable_content)
      expect(rejected).to eq([{resource: "doodles", action: "create", id: nil, user_id: admin.id, code: "unsupported"}])
    end

    it "records a write to a missing record as not found" do
      api(:patch, "/api/admin/posts/0", post_body)

      expect(rejected.pluck(:code)).to eq(["not_found"])
    end

    it "records any code a controller renders, such as a host's rate limit" do
      controller = Struct.new(:request, :action_name, :params, :controller_path, :active_admin_config)
        .new(ActionDispatch::Request.new("REQUEST_METHOD" => "POST"), "create", {}, "admin/posts", nil)
      allow(ReactiveAdmin).to receive(:current_user).and_return(admin)

      ReactiveAdmin::WriteAudit.rejected(controller, :rate_limited)

      expect(rejected).to eq([{resource: "admin/posts", action: "create", id: nil, user_id: admin.id, code: "rate_limited"}])
    end

    it "records a crashed write and keeps its message out of everything" do
      allow_any_instance_of(Post).to receive(:save).and_raise(RuntimeError, "boom #{ssn}")

      api(:post, "/api/admin/posts", post_body)

      expect(response).to have_http_status(:internal_server_error)
      expect(rejected).to eq([{resource: "posts", action: "create", id: nil, user_id: admin.id, code: "error"}])
      expect(events.to_s + response.body).not_to include(ssn)
    end

    it "leaves out a client-supplied id that isn't plainly an id" do
      api(:patch, "/api/admin/posts/#{ssn}%20ssn", post_body)

      expect(rejected.pluck(:id)).to eq([nil])
    end

    it "leaves unauthenticated writes to the host's own logs" do
      reset!
      events.clear

      api(:post, "/api/admin/posts", post_body)

      expect(response).to have_http_status(:unauthorized)
      expect(events).to be_empty
    end
  end

  describe "error reporting" do
    let(:reported) { [] }
    let(:log) { StringIO.new }

    around do |example|
      original = ReactiveAdmin.config.error_reporter
      logger = Rails.logger
      ReactiveAdmin.config.error_reporter = ->(error, context) { reported << [error, context] }
      Rails.logger = ActiveSupport::Logger.new(log)
      example.run
    ensure
      Rails.logger = logger
      ReactiveAdmin.config.error_reporter = original
    end

    it "hands the reporter a scrubbed error, never the original message" do
      allow_any_instance_of(ReactiveAdmin::IndexPayload).to receive(:as_json).and_raise(ArgumentError, "bad value #{ssn}")

      api_get("/api/admin/posts")

      error, context = reported.first
      expect(error).to be_a(ReactiveAdmin::ScrubbedError)
      expect(error.message).to eq("ArgumentError in posts#index")
      expect(error.backtrace).not_to be_empty
      expect(error.cause).to be_nil
      expect(context).to eq(resource: "posts", action: "index", request_id: response.headers["X-Request-Id"], error_class: "ArgumentError")
      expect([error.message, error.inspect, error.full_message, context.to_s, response.body, log.string].join).not_to include(ssn)
    end

    it "reaches Rails.error subscribers by default without the message" do
      ReactiveAdmin.config.error_reporter = ReactiveAdmin::Configuration.new.error_reporter
      seen = []
      subscriber = Class.new { define_method(:report) { |error, **opts| seen << [error, opts] } }.new
      Rails.error.subscribe(subscriber)
      allow_any_instance_of(ReactiveAdmin::ShowPayload).to receive(:as_json).and_raise(RuntimeError, "ssn #{ssn}")

      api_get("/api/admin/posts/#{first_post.id}")

      error, opts = seen.first
      expect(error.message).to eq("RuntimeError in posts#show")
      expect(opts).to include(handled: true, source: "reactiveadmin", context: hash_including(resource: "posts", action: "show"))
      expect(seen.to_s + log.string).not_to include(ssn)
    ensure
      Rails.error.unsubscribe(subscriber)
    end

    it "survives a reporter that raises" do
      ReactiveAdmin.config.error_reporter = ->(*) { raise "reporter down #{ssn}" }
      allow_any_instance_of(ReactiveAdmin::IndexPayload).to receive(:as_json).and_raise(RuntimeError, "x")

      api_get("/api/admin/posts")

      expect(response).to have_http_status(:internal_server_error)
      expect(log.string).not_to include(ssn)
    end
  end
end
