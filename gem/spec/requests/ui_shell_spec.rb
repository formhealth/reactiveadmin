RSpec.describe "the client's shell at classic URLs", type: :request do
  include_context "with a blog"

  around { |example| with_ui { example.run } }

  def expect_shell(path, **headers)
    get path, headers: navigation(**headers)

    expect(response).to have_http_status(:ok), path
    expect(shell?).to be(true), path
  end

  def expect_classic(path, **headers)
    get path, headers: navigation(**headers)

    expect(shell?).to be(false), path
  end

  describe "a navigation by someone with the cookie" do
    it "gets the shell at any admin URL, signed in or not, with no authorization or lookup" do
      ["/admin", "/admin/", "/admin/dashboard", "/admin/posts", "/admin/posts?q[title_cont]=x", "/admin/posts/new", "/admin/posts/#{first_post.id}/edit",
        "/admin/groups/content", "/admin/nothing_here", "/admin/login"].each { expect_shell(it) }
    end

    it "gets it for HEAD, without a body" do
      head "/admin/posts", headers: navigation

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/html")
      expect(response.body).to be_empty
    end

    it "gets the entry, styles and preloads the manifest names, and where the client lives" do
      get "/admin/posts", headers: navigation

      html = response.body
      expect(html).to include('<script type="module" src="/reactiveadmin/assets/index-abc123.js">')
      expect(html).to include('<link rel="stylesheet" href="/reactiveadmin/assets/index-abc123.css">', '<link rel="stylesheet" href="/reactiveadmin/assets/vendor-9f.css">')
      expect(html).to include('<link rel="modulepreload" href="/reactiveadmin/assets/vendor-9f.js">')
      config = Nokogiri::HTML(html).at('meta[name="reactiveadmin-config"]')["content"]
      expect(JSON.parse(config)).to eq("admin_path" => "/admin", "mount_path" => "/api")
    end

    it "is never cached, and keeps the host's default security headers" do
      get "/admin/posts", headers: navigation

      expect(response.headers["cache-control"]).to eq("no-store")
      expect(response.headers["content-type"]).to eq("text/html; charset=utf-8")
      expect(response.headers["x-frame-options"]).to eq(ActionDispatch::Response.default_headers["X-Frame-Options"])
    end

    it "gets it with an html Accept where the browser sends no Sec-Fetch-Dest" do
      expect_shell("/admin/posts", sec_fetch_dest: nil, accept: "text/html,application/xhtml+xml")
      expect_classic("/admin/posts", sec_fetch_dest: nil, accept: "application/json")
      expect_classic("/admin/posts", sec_fetch_dest: nil, accept: "text/html", x_requested_with: "XMLHttpRequest")
    end
  end

  describe "what it leaves to classic" do
    it "answers classic without the cookie, or with another choice" do
      get "/admin/posts", headers: navigation(cookie: nil)
      expect(shell?).to be(false)

      ["reactiveadmin_ui=classic", "reactiveadmin_ui=", "reactiveadmin_ui=newer", "other=new"].each { expect_classic("/admin/posts", cookie: it) }
    end

    it "answers classic for the per-request escape hatches" do
      ["/admin/posts?classic=1", "/admin/posts?page=2&classic=1", "/admin/posts?embed=1", "/admin/posts?classic=1&embed=1"].each { expect_classic(it) }
    end

    it "serves the shell when the hatches aren't switched on" do
      ["/admin/posts?classic=0", "/admin/posts?embed=", "/admin/posts?classic[]=1"].each { expect_shell(it) }
    end

    it "answers classic for frames, fetches, scripts and other non-documents" do
      %w[iframe empty script image style].each { expect_classic("/admin/posts", sec_fetch_dest: it) }
    end

    it "answers classic for writes" do
      post "/admin/posts", headers: navigation

      expect(shell?).to be(false)
    end

    it "answers classic for downloads and other formats" do
      ["/admin/posts.csv", "/admin/posts.json", "/admin/posts/#{first_post.id}.json"].each { expect_classic(it) }
    end

    it "answers classic outside the admin namespace" do
      ["/", "/administrator", "/api/admin/_session", "/reactiveadmin/assets/index-abc123.js", "/other/admin"].each do |path|
        get path, headers: navigation

        expect(shell?).to be(false), path
      end
    end

    it "follows the configured namespace" do
      allow(ReactiveAdmin.config).to receive(:namespace).and_return(:backoffice)

      expect_shell("/backoffice/posts")
      expect_classic("/admin/posts")
    end

    it "answers classic while no client build is installed" do
      ReactiveAdmin.config.ui.client_assets = Dir.mktmpdir

      expect_classic("/admin/posts")
    end

    it "answers classic when turned off" do
      ReactiveAdmin.config.ui.enabled = false

      expect_classic("/admin/posts")
    end

    it "answers classic for a query it can't parse" do
      expect_classic("/admin/posts?a[b=1&a[]=2&a=3")
    end
  end

  describe "the built files" do
    it "are served by the gem under the prefix, hashed ones for good" do
      get "/reactiveadmin/assets/index-abc123.js"

      expect(response).to have_http_status(:ok)
      expect(response.headers["cache-control"]).to include("immutable")

      get "/reactiveadmin/manifest.json"
      expect(response.headers["cache-control"]).not_to include("immutable")
    end
  end

  describe "the classic dashboard's panel" do
    before { sign_in admin }

    it "offers the new admin to an available user, with the build's script and the default" do
      ReactiveAdmin.config.ui.default = :new
      get "/admin"

      panel = Nokogiri::HTML(response.body).at_css(".reactiveadmin-ui-toggle")
      expect(panel["data-reactiveadmin-ui"]).to eq("new")
      expect(panel.at_css("button").text).to eq("Try the new admin")
      expect(response.body).to include('<script src="/reactiveadmin/assets/uiToggle-77.js" type="module">')
    end

    it "offers the way back on a classic page viewed on request" do
      get "/admin?classic=1"

      expect(Nokogiri::HTML(response.body).at_css(".reactiveadmin-ui-toggle button").text).to eq("Return to the new admin")
    end

    it "is absent for a user who isn't available, inside frames, and without a build" do
      ReactiveAdmin.config.ui.available = ->(_user) { false }
      get "/admin"
      expect(response.body).not_to include("reactiveadmin-ui-toggle")

      ReactiveAdmin.config.ui.available = ->(_user) { true }
      get "/admin?embed=1"
      expect(response.body).not_to include("reactiveadmin-ui-toggle")

      ReactiveAdmin.config.ui.client_assets = Dir.mktmpdir
      get "/admin"
      expect(response.body).not_to include("reactiveadmin-ui-toggle")
    end

    it "does not appear in the API's rendering of the dashboard" do
      api_get("/api/admin/_pages/dashboard")

      expect(response.body).not_to include("reactiveadmin-ui-toggle")
    end
  end
end
