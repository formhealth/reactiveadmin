RSpec.describe "client files and cookies", type: :request do
  around { |example| with_ui { example.run } }

  # Public, cacheable files must never carry a session cookie: a shared cache would hand it to other visitors.
  it "answers before the session middleware" do
    stack = Rails.application.middleware.map(&:klass)

    expect(stack.index(ReactiveAdmin::Ui::Assets::Middleware)).to be < stack.index(ActionDispatch::Cookies)
  end

  %w[/reactiveadmin/assets/index-abc123.js /reactiveadmin/manifest.json].each do |path|
    it "serves #{path} without Set-Cookie" do
      get path, headers: {"Cookie" => "_dummy_session=abc"}

      expect(response).to have_http_status(:ok)
      expect(response.headers["Set-Cookie"]).to be_nil
    end
  end

  it "keeps hashed files immutable and the manifest revalidating" do
    get "/reactiveadmin/assets/index-abc123.js"
    expect(response.headers["Cache-Control"]).to eq "public, max-age=31536000, immutable"

    get "/reactiveadmin/manifest.json"
    expect(response.headers["Cache-Control"]).to eq "no-cache"
  end

  it "doesn't escape the build directory" do
    get "/reactiveadmin/assets/..%2f..%2fGemfile"

    expect(response).to have_http_status(:not_found)
  end

  it "leaves other paths to the app" do
    get "/api/admin/_session"

    expect(response).to have_http_status(:unauthorized)
  end
end
