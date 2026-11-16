RSpec.describe "a mutating GET action refuses a bad request before it runs", type: :request do
  include_context "with a blog"

  before { sign_in admin }

  let(:path) { "/api/admin/posts/#{first_post.id}/bump" }

  it "rejects an undeclared q predicate without running the action" do
    expect { api_get("#{path}?q[secret_cont]=x") }.not_to(change { first_post.reload.views_count })

    expect(response).to have_http_status(:bad_request)
  end

  it "rejects a request when the rate limit is spent without running the action" do
    allow(ReactiveAdmin::RateLimit).to receive(:retry_after).and_return(5)

    expect { api_get(path) }.not_to(change { first_post.reload.views_count })

    expect(response).to have_http_status(:too_many_requests)
  end

  it "runs the action for a valid request" do
    expect { api_get(path) }.to change { first_post.reload.views_count }.by(1)
  end
end
