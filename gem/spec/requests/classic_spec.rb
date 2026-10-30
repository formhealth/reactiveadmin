# The gem is prepended to AA's controllers; the classic admin has to behave exactly as before.
RSpec.describe "classic admin parity", type: :request do
  include_context "with a blog"

  before { sign_in admin }

  it "renders index, show, new and edit pages as html" do
    ["/admin/posts", "/admin/posts/#{first_post.id}", "/admin/posts/new", "/admin/posts/#{first_post.id}/edit",
      "/admin/authors", "/admin/tags", "/admin/dashboard"].each do |path|
      get path

      expect(response).to have_http_status(:ok), path
      expect(response.media_type).to eq("text/html"), path
    end
  end

  it "renders the nested resource's pages under its parent" do
    comment = Comment.create!(post: first_post, body: "Hi")

    get "/admin/posts/#{first_post.id}/comments"
    expect(response).to have_http_status(:ok)

    get "/admin/posts/#{first_post.id}/comments/#{comment.id}/edit"
    expect(response).to have_http_status(:ok)
  end

  it "renders a typeahead filter declared on an association" do
    get "/admin/categories"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('name="q[posts_id_eq]"')
  end

  it "keeps AA's redirect-and-flash writes" do
    post "/admin/posts", params: {post: {title: "Classic", author_id: alice.id}}

    created = Post.find_by!(title: "Classic")
    expect(response).to redirect_to("/admin/posts/#{created.id}")
    expect(flash[:notice]).to eq("Post was successfully created.")
  end

  it "re-renders the form with errors on an invalid write" do
    post "/admin/authors", params: {author: {name: ""}}

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("can&#39;t be blank")
  end

  it "keeps custom member actions redirecting with flashes" do
    put "/admin/posts/#{second_post.id}/publish"

    expect(response).to redirect_to("/admin/posts/#{second_post.id}")
    expect(flash[:notice]).to eq("Published Bob's draft")
  end

  it "keeps AA's own 404 for a missing record" do
    get "/admin/posts/0"

    expect(response).to have_http_status(:not_found)
  end

  it "keeps AA's csv export" do
    get "/admin/posts.csv"

    expect(response.media_type).to eq("text/csv")
  end

  it "does not mark classic responses as the API's" do
    get "/admin/posts"

    expect(response.headers["Server-Timing"]).to be_nil
    expect(response.body).not_to include("data-reactiveadmin-embed")
  end
end
