RSpec.describe "lookup audit and form-context permissions", type: :request do
  include_context "with a blog"

  let(:events) { [] }
  let(:options_path) { "/api/admin/posts/_options" }
  let(:adapter) { ReactiveAdmin::AA.authorization_adapter(ReactiveAdmin::Registry.namespace) }

  def lookups = events.map(&:last)

  def authors_config = ReactiveAdmin::AA.resource_for(ReactiveAdmin::Registry.namespace, Author)

  def deny(*actions)
    allow_any_instance_of(adapter).to receive(:authorized?).and_wrap_original do |original, action, subject = nil|
      actions.exclude?(action) && original.call(action, subject)
    end
  end

  before do
    ActiveSupport::Notifications.subscribe("lookup.reactiveadmin") { |*, payload| events << ["lookup", payload] }
    ReactiveAdmin.config.sensitive_resources = %w[authors]
    sign_in admin
  end

  after do
    ActiveSupport::Notifications.unsubscribe("lookup.reactiveadmin")
    ReactiveAdmin.config.sensitive_resources = []
  end

  describe "sensitive resources" do
    it "audits a typeahead search without the term or the names" do
      api_get(options_path, field: "author_id_eq", context: "filter", term: "Alice")

      expect(lookups).to eq([{resource: "posts", field: "author_id_eq", kind: :search, target: "authors", result_count: 1, user_id: admin.id}])
      expect(events.to_s).not_to include("Alice")
    end

    it "audits resolving selected values as a lookup" do
      api_get(options_path, field: "author_id_eq", context: "filter", value: "#{alice.id},#{bob.id}")

      expect(lookups).to match([include(kind: :lookup, result_count: 2)])
      expect(events.to_s).not_to include("Bob")
    end

    it "audits the batched lookup once per sensitive field" do
      api_get("#{options_path}/lookup", fields: {author_id_eq: bob.id.to_s, category: news.id.to_s}, context: "filter")

      expect(lookups).to eq([{resource: "posts", field: "author_id_eq", kind: :lookup, target: "authors", result_count: 1, user_id: admin.id}])
    end

    it "audits _labels once per request, whatever the number of records" do
      api_get("/api/admin/authors/_labels", ids: [alice.id, bob.id].join(","))

      expect(json["labels"].size).to eq(2)
      expect(lookups).to eq([{resource: "authors", field: nil, kind: :labels, target: "authors", result_count: 2, user_id: admin.id}])
      expect(events.to_s).not_to include("Alice")
    end

    it "stays a background request" do
      calls = []
      ReactiveAdmin.config.on_background_request = ->(controller) { calls << controller.action_name }
      api_get(options_path, {field: "author_id_eq", context: "filter"}, headers: {"X-Reactiveadmin-Background" => "1"})

      expect(calls).to eq(["reactiveadmin_options"])
      expect(lookups.size).to eq(1)
    ensure
      ReactiveAdmin.config.on_background_request = nil
    end

    it "honours a resource's own `sensitive false`" do
      authors_config.reactive_options[:sensitive] = false
      api_get(options_path, field: "author_id_eq", context: "filter")

      expect(lookups).to be_empty
    ensure
      authors_config.reactive_options.delete(:sensitive)
    end

    it "honours a resource's own `sensitive true`" do
      ReactiveAdmin.config.sensitive_resources = []
      authors_config.reactive_options[:sensitive] = true
      api_get(options_path, field: "author_id_eq", context: "filter")

      expect(lookups.size).to eq(1)
    ensure
      authors_config.reactive_options.delete(:sensitive)
    end
  end

  describe "other resources" do
    it "are not audited" do
      api_get(options_path, field: "category", context: "filter", term: "News")
      api_get(options_path, field: "status", context: "filter")
      api_get("/api/admin/posts/_labels", ids: first_post.id.to_s)

      expect(lookups).to be_empty
    end

    it "are not audited without sensitive_resources" do
      ReactiveAdmin.config.sensitive_resources = []
      api_get(options_path, field: "author_id_eq", context: "filter")

      expect(lookups).to be_empty
    end
  end

  describe "context=form" do
    it "is a 403 without NEW for a new record" do
      deny :new
      api_get(options_path, field: "author", context: "form")
      expect(response).to have_http_status(:forbidden)

      api_get("#{options_path}/lookup", fields: {author: alice.id.to_s}, context: "form")
      expect(response).to have_http_status(:forbidden)
      expect(lookups).to be_empty
    end

    it "is a 403 without EDIT for an existing one" do
      deny :edit
      api_get(options_path, field: "author", context: "form", id: first_post.id)
      expect(response).to have_http_status(:forbidden)

      api_get("#{options_path}/lookup", fields: {author: alice.id.to_s}, context: "form", id: first_post.id)
      expect(response).to have_http_status(:forbidden)
    end

    it "leaves filter choices to READ" do
      deny :new, :create, :edit, :update, :destroy
      api_get(options_path, field: "author_id_eq", context: "filter")

      expect(response).to have_http_status(:ok)
    end

    it "serves form choices when new and edit are allowed" do
      api_get(options_path, field: "author", context: "form")
      expect(response).to have_http_status(:ok)

      api_get(options_path, field: "author", context: "form", id: first_post.id)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "page forms" do
    let(:path) { "/api/admin/_pages/broadcasts" }

    it "need the permission of the action the form posts to" do
      deny :announce
      api_get(path, context: "page_form", form: 0, field: "region")

      expect(response).to have_http_status(:forbidden)
    end

    it "are served when the action is permitted" do
      api_get(path, context: "page_form", form: 0, field: "region")

      expect(response).to have_http_status(:ok)
    end
  end
end
