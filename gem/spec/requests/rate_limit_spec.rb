RSpec.describe "rate limits", type: :request do
  include_context "with a blog"
  include ActiveSupport::Testing::TimeHelpers

  let(:limits) { {options: [2, 10.seconds], lookup: [5, 1.minute], export: [1, 1.minute], value: [1, 1.minute], default: nil} }
  let!(:comment) { Comment.create!(post: first_post, body: "Nice post", context: {"a" => 1}) }

  def options = api_get("/api/admin/posts/_options", field: "author_id_eq", context: "filter")

  def export = api_get("/api/admin/posts.csv")

  def value = api_get("/api/admin/posts/#{first_post.id}/comments/#{comment.id}/_value", field: "context", token: value_token(comment, "context", user: admin))

  def with_limits(value)
    old = ReactiveAdmin.config.rate_limits
    ReactiveAdmin.config.rate_limits = value
    yield
  ensure
    ReactiveAdmin.config.rate_limits = old
  end

  around { |example| with_limits(limits) { example.run } }

  before { sign_in admin }

  it "answers 429 with Retry-After once a bucket's budget is spent" do
    2.times do
      options

      expect(response).to have_http_status(:ok)
    end
    options

    expect(response).to have_http_status(:too_many_requests)
    expect(json).to include("code" => "rate_limited")
    expect(response.headers["Retry-After"].to_i).to be_between(1, 10)
  end

  it "keeps buckets independent" do
    3.times { options }
    expect(response).to have_http_status(:too_many_requests)

    export
    expect(response).to have_http_status(:ok)
    value
    expect(response).to have_http_status(:ok)
    api_get("/api/admin/posts")
    expect(response).to have_http_status(:ok)
  end

  it "limits exports and values by their own budgets" do
    export
    expect(response).to have_http_status(:ok)
    export
    expect(response).to have_http_status(:too_many_requests)
    expect(response.media_type).to eq("application/json")
    expect(response.headers["Retry-After"].to_i).to be_between(1, 60)

    value
    expect(response).to have_http_status(:ok)
    value
    expect(response).to have_http_status(:too_many_requests)
  end

  def lookup = api_get("/api/admin/posts/_options/lookup", fields: {author_id_eq: first_post.author_id.to_s}, context: "filter")

  it "gives lookups a bucket apart from search" do
    3.times { options }
    expect(response).to have_http_status(:too_many_requests)

    3.times { lookup }
    expect(response).to have_http_status(:ok)
  end

  it "answers 429 once the lookup budget is spent" do
    6.times { lookup }

    expect(response).to have_http_status(:too_many_requests)
  end

  it "budgets each user separately" do
    3.times { options }
    expect(response).to have_http_status(:too_many_requests)

    sign_in editor
    options
    expect(response).to have_http_status(:ok)
  end

  it "resets when the window passes" do
    window_start = Time.at(Time.now.to_i / 10 * 10)
    travel_to(window_start) { 3.times { options } }
    expect(response).to have_http_status(:too_many_requests)

    travel_to(window_start + 10) { options }
    expect(response).to have_http_status(:ok)
  end

  context "with a default bucket" do
    let(:limits) { {options: [1, 10.seconds], default: [2, 1.minute]} }

    it "covers every bucket that has no budget of its own" do
      2.times { api_get("/api/admin/posts") }
      expect(response).to have_http_status(:ok)

      api_get("/api/admin/posts")
      expect(response).to have_http_status(:too_many_requests)
    end
  end

  context "with pages" do
    let(:limits) { {options: [1, 10.seconds], default: [2, 1.minute]} }

    it "spends the default budget on page reads and page actions" do
      api_get("/api/admin/_pages/dashboard")
      api(:post, "/api/admin/dashboard/recalc")
      expect(response).to have_http_status(:ok)

      api_get("/api/admin/dashboard")
      expect(response).to have_http_status(:too_many_requests)
      expect(json).to include("code" => "rate_limited")
    end

    it "gives a page form's options the options bucket" do
      2.times { api_get("/api/admin/dashboard", context: "page_form", form: "0", field: "x") }

      expect(response).to have_http_status(:too_many_requests)
      api_get("/api/admin/dashboard")
      expect(response).to have_http_status(:ok)
    end
  end

  context "when turned off" do
    let(:limits) { false }

    it "never limits" do
      5.times { options }

      expect(response).to have_http_status(:ok)
    end
  end

  context "when the cache can't count" do
    it "leaves requests unlimited" do
      allow(Rails.cache).to receive(:increment).and_return(nil)
      5.times { options }

      expect(response).to have_http_status(:ok)
    end

    it "leaves requests unlimited when the cache raises" do
      allow(Rails.cache).to receive(:increment).and_raise(Errno::ECONNREFUSED)
      5.times { options }

      expect(response).to have_http_status(:ok)
    end
  end

  context "with a request the server marks internal (the doctor's samples)" do
    def internal_options(headers: {}, env: {ReactiveAdmin::BackgroundRequests::INTERNAL_ENV => true})
      get "/api/admin/posts/_options", params: {field: "author_id_eq", context: "filter"},
        headers: ApiHelpers::JSON_HEADERS.merge(headers), env:
    end

    it "is never limited and spends no budget" do
      expect(Rails.cache).not_to receive(:increment)
      5.times { internal_options }

      expect(response).to have_http_status(:ok)
    end

    it "is limited again once the marker is absent" do
      3.times { internal_options }
      expect(response).to have_http_status(:ok)

      3.times { options }
      expect(response).to have_http_status(:too_many_requests)
    end

    it "isn't exempted by a client header that looks like the marker" do
      3.times { options }

      internal_options(headers: {"X-Reactiveadmin-Internal" => "1"}, env: {})
      expect(response).to have_http_status(:too_many_requests)
    end
  end

  it "doesn't budget unauthenticated requests" do
    reset!
    3.times { options }

    expect(response).to have_http_status(:unauthorized)
  end
end
