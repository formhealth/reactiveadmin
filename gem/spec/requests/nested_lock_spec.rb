RSpec.describe "lock over nested has_many rows", type: :request do
  include_context "with a blog"

  let!(:comment) { Comment.create!(post: first_post, body: "first") }
  let(:path) { "/api/admin/posts/#{first_post.id}" }
  let(:lock) { api_get("#{path}/edit", schema: "FormResponse")["lock"] }

  before { sign_in admin }

  def update(lock) = api(:patch, path, {post: {title: "Renamed"}, lock:})

  it "digests the nested rows into the updated_at token" do
    expect(lock).to include("field" => "updated_at", "value" => match(/\A\d{4}-.*Z~\h{16}\z/))
  end

  it "accepts an unchanged token" do
    update(lock)

    expect(response).to have_http_status(:ok)
  end

  it "refuses a token when another editor added a nested row" do
    token = lock
    Comment.create!(post: first_post, body: "second")
    update(token)

    expect(response).to have_http_status(:conflict)
    expect(first_post.reload.title).not_to eq "Renamed"
  end

  it "refuses a token when another editor changed a nested row" do
    token = lock
    comment.update_columns(updated_at: 1.hour.from_now)
    update(token)

    expect(response).to have_http_status(:conflict)
  end

  it "refuses a token without the digest" do
    update(lock.merge("value" => lock["value"].split("~").first))

    expect(response).to have_http_status(:conflict)
  end

  it "keeps the plain timestamp for a form without has_many sections" do
    api_get("/api/admin/authors/#{alice.id}/edit")

    expect(json["lock"]["value"]).not_to include("~")
  end
end
