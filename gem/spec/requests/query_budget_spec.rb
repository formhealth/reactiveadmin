RSpec.describe "query budgets", type: :request do
  include_context "with a blog"

  def queries
    count = 0
    counter = ->(*, payload) { count += 1 unless %w[SCHEMA TRANSACTION].include?(payload[:name]) || payload[:cached] }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { yield }
    count
  end

  before { sign_in admin }

  describe "update" do
    let(:path) { "/api/admin/posts/#{first_post.id}" }

    def update(title) = api(:patch, path, {post: {title:}, lock: lock_of(first_post)})

    it "judges the write without building the form's options" do
      update("Warm up")
      lock = lock_of(first_post)
      count = queries { api(:patch, path, {post: {title: "Renamed"}, lock:}) }

      expect(response).to have_http_status(:ok)
      expect(count).to be <= (adapter?(:pundit) ? 11 : 10)
    end
  end

  describe "_meta" do
    it "stays within a small budget once the static part is cached" do
      api_get("/api/admin/posts/_meta")
      count = queries { api_get("/api/admin/posts/_meta") }

      expect(response).to have_http_status(:ok)
      expect(count).to be <= 3
    end
  end

  describe "show" do
    it "is bounded" do
      path = "/api/admin/posts/#{first_post.id}"
      api_get(path)
      count = queries { api_get(path) }

      expect(response).to have_http_status(:ok)
      expect(count).to be <= 7
    end
  end

  describe "_value" do
    let!(:comment) { Comment.create!(post: first_post, body: "Nice post", context: {"theme" => "dark", "api_token" => "t"}) }

    it "answers from the token without rendering the pages" do
      api_get("/api/admin/posts/#{first_post.id}/comments", schema: "IndexResponse")
      url = row_for(json["rows"], comment)["cells"]["context"]["expand_path"]
      api_get(url)

      %w[IndexPayload ShowPayload FormPayload FormSchema].each { expect(ReactiveAdmin.const_get(it)).not_to receive(:new) }
      count = queries { api_get(url) }

      expect(response).to have_http_status(:ok)
      expect(count).to be <= 3
    end
  end
end
