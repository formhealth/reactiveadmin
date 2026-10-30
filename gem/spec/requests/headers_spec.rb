RSpec.describe "response headers and request hooks", type: :request do
  include_context "with a blog"

  before { sign_in admin }

  describe "Server-Timing" do
    it "is added to API responses with db and app durations" do
      api_get("/api/admin/posts")

      expect(response.headers["Server-Timing"]).to match(/\Adb;dur=\d+\.\d, app;dur=\d+\.\d\z/)
    end

    it "is added to API errors too" do
      api_get("/api/admin/posts/0")

      expect(response.headers["Server-Timing"]).to be_present
    end

    it "is not added outside the mount" do
      get "/admin/posts.csv"

      expect(response.headers["Server-Timing"]).to be_nil
    end
  end

  describe "background requests" do
    let(:seen) { [] }

    around do |example|
      original = ReactiveAdmin.config.on_background_request
      ReactiveAdmin.config.on_background_request = ->(controller) { seen << controller.action_name }
      example.run
    ensure
      ReactiveAdmin.config.on_background_request = original
    end

    it "calls the host hook for resource reads marked as background" do
      api_get("/api/admin/posts/_meta", headers: {"X-Reactiveadmin-Background" => "1"})
      api_get("/api/admin/posts/_options", field: "author_id_eq", context: "filter", headers: {"X-Reactiveadmin-Background" => "true"})

      expect(seen).to eq(%w[reactiveadmin_meta reactiveadmin_options])
    end

    it "calls the host hook for session and manifest revalidation" do
      api_get("/api/admin/_session", headers: {"X-Reactiveadmin-Background" => "1"})
      api_get("/api/admin/_manifest", headers: {"X-Reactiveadmin-Background" => "1"})

      expect(seen).to eq(%w[show show])
    end

    it "ignores unmarked requests" do
      api_get("/api/admin/posts/_meta")

      expect(seen).to be_empty
    end

    it "ignores the marker on record data, which is always a view" do
      header = {"X-Reactiveadmin-Background" => "1"}
      api_get("/api/admin/posts", headers: header)
      api_get("/api/admin/posts/#{first_post.id}", headers: header)
      api_get("/api/admin/posts/#{first_post.id}/edit", headers: header)
      api_get("/api/admin/posts/new", headers: header)

      expect(seen).to be_empty
    end

    it "honours the marker for _meta, _options and _labels" do
      header = {"X-Reactiveadmin-Background" => "1"}
      api_get("/api/admin/posts/_meta", headers: header)
      api_get("/api/admin/posts/_options", field: "author_id_eq", context: "filter", headers: header)
      api_get("/api/admin/posts/_labels", ids: [first_post.id.to_s], headers: header)

      expect(seen).to eq(%w[reactiveadmin_meta reactiveadmin_options reactiveadmin_labels])
    end

    it "never honours the marker on writes or exports" do
      api(:post, "/api/admin/posts/import", headers: {"X-Reactiveadmin-Background" => "1"})
      api_get("/api/admin/posts.csv", headers: {"X-Reactiveadmin-Background" => "1"})

      expect(seen).to be_empty
    end
  end

  describe "after_authorize" do
    around do |example|
      original = ReactiveAdmin.config.after_authorize
      example.run
    ensure
      ReactiveAdmin.config.after_authorize = original
    end

    it "runs after the manifest is authorized" do
      calls = []
      ReactiveAdmin.config.after_authorize = ->(controller) { calls << controller.class.name }

      api_get("/api/admin/_manifest")

      expect(calls).to eq(["ReactiveAdmin::ManifestController"])
    end
  end

  describe "meta cache" do
    let(:computed) { [] }

    around do |example|
      keys = ReactiveAdmin.config.meta_cache_key
      version = ReactiveAdmin.config.meta_cache_version
      example.run
    ensure
      ReactiveAdmin.config.meta_cache_key = keys
      ReactiveAdmin.config.meta_cache_version = version
    end

    before do
      calls = computed
      allow_any_instance_of(ReactiveAdmin::ResourceSummary).to receive(:as_json).and_wrap_original do |original, *args|
        calls << true
        original.call(*args)
      end
    end

    it "computes once per user by default" do
      other = create_admin(email: "second@example.com", name: "Second")

      2.times { api_get("/api/admin/posts/_meta") }
      sign_in other
      api_get("/api/admin/posts/_meta")

      expect(computed.size).to eq(2)
    end

    it "shares a payload between users with an equal meta_cache_key" do
      ReactiveAdmin.config.meta_cache_key = ->(user) { user.role }
      other = create_admin(email: "second@example.com", name: "Second")

      api_get("/api/admin/posts/_meta")
      sign_in other
      api_get("/api/admin/posts/_meta")
      sign_in editor
      api_get("/api/admin/posts/_meta")

      expect(computed.size).to eq(2)
    end

    it "recomputes when meta_cache_version changes" do
      version = "v1"
      ReactiveAdmin.config.meta_cache_version = -> { version }

      api_get("/api/admin/posts/_meta")
      api_get("/api/admin/posts/_meta")
      version = "v2"
      api_get("/api/admin/posts/_meta")

      expect(computed.size).to eq(2)
    end
  end
end
