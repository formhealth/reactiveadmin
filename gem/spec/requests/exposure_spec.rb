RSpec.describe "exposure", type: :request do
  include_context "with a blog"

  let(:config) { ReactiveAdmin.config }
  let(:manifest) { api_get("/api/admin/_manifest", schema: "Manifest") }

  def menu_ids(items) = items.flat_map { [it["id"], *menu_ids(it["children"])] }

  around do |example|
    ReactiveAdmin::MenuOverlay.reset!
    config.expose = :listed
    example.run
  ensure
    config.expose = :all
    config.exposed_resources = []
    ReactiveAdmin::Registry.resources.each { it.reactive_options.delete(:expose) }
    ReactiveAdmin::Registry.find("tags").reactive_options.delete(:menu)
    ReactiveAdmin::MenuOverlay.reset!
  end

  before { sign_in admin }

  context "with posts listed in the menu overlay" do
    before { ReactiveAdmin.menu { group("Content") { resources :posts } } }

    it "serves a listed resource" do
      api_get("/api/admin/posts", schema: "IndexResponse")
      expect(response).to have_http_status(:ok)

      api_get("/api/admin/posts/_meta")
      expect(response).to have_http_status(:ok)
    end

    it "answers 404 not_found on every endpoint of an unlisted resource" do
      id = news.id
      [
        [:get, "/api/admin/categories"], [:get, "/api/admin/categories/#{id}"], [:get, "/api/admin/categories/new"],
        [:get, "/api/admin/categories/#{id}/edit"], [:get, "/api/admin/categories/_meta"],
        [:get, "/api/admin/categories/_options"], [:get, "/api/admin/categories/#{id}/_value"], [:get, "/api/admin/categories.csv"],
        [:post, "/api/admin/categories"], [:put, "/api/admin/categories/#{id}"], [:delete, "/api/admin/categories/#{id}"],
        [:post, "/api/admin/categories/batch_action"]
      ].each do |verb, path|
        api(verb, path, ((verb == :get) ? nil : {category: {name: "X"}}))
        expect(response).to have_http_status(:not_found), "#{verb} #{path}"
        expect(json).to include("code" => "not_found")
      end
      expect(Category.exists?(id)).to be(true)
      expect(Category.where(name: "X")).to be_empty
    end

    it "answers 404 on an unlisted resource's custom actions" do
      ReactiveAdmin::MenuOverlay.reset!
      ReactiveAdmin.menu { group("Content") { resources :categories } }

      api(:put, "/api/admin/posts/#{second_post.id}/publish")
      expect(response).to have_http_status(:not_found)
      expect(second_post.reload).not_to be_published
    end

    it "does not report what the API denies whole or action by action as permitted but not exposed" do
      locker = ReactiveAdmin::Registry.find("lockers")
      before = locker.reactive_options.deep_dup
      ReactiveAdmin::ReactiveDSL.new(locker).api(:deny, only: %w[index show new create edit update destroy])

      keys = ReactiveAdmin::Exposure.audit(user: admin).find { it[:kind] == :exposure_permitted_not_exposed }[:keys].split(", ")

      expect(keys).to include("categories")
      expect(keys).not_to include("profiles", "lockers", "back_office")
    ensure
      locker.reactive_options.replace(before)
    end

    it "serves the root page without a listing" do
      api_get("/api/admin/_pages/dashboard")

      expect(response).to have_http_status(:ok)
    end

    it "answers 404 on an unlisted page, at both of its paths" do
      allow(ReactiveAdmin::Registry.namespace).to receive(:root_to).and_return("posts#index")
      api_get("/api/admin/_pages/dashboard")
      expect(response).to have_http_status(:not_found)

      api_get("/api/admin/dashboard")
      expect(response).to have_http_status(:not_found)

      api(:post, "/api/admin/dashboard/recalc")
      expect(response).to have_http_status(:not_found)
    end

    it "answers 401 to signed-out clients before it says anything about exposure" do
      reset!
      api_get("/api/admin/categories")

      expect(response).to have_http_status(:unauthorized)
    end

    it "leaves the manifest and menu with the listed resources only" do
      expect(manifest["resources"].pluck("key")).to eq(%w[posts])
      expect(menu_ids(manifest["menu"])).to include("posts")
      expect(menu_ids(manifest["menu"])).not_to include("categories", "tags", "authors")
    end

    it "does not touch the classic admin" do
      get "/admin/categories"
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/html")
    end

    it "does not reference an unexposed record from a cell" do
      api_get("/api/admin/posts")

      refs = json["rows"].flat_map { |row| row["cells"].values.filter_map { it["ref"] if it.is_a?(Hash) } }
      expect(refs.pluck("resource").uniq - %w[posts]).to be_empty
    end
  end

  describe "listing resources and pages" do
    it "serves a resource named in exposed_resources" do
      config.exposed_resources = %w[tags]

      api_get("/api/admin/tags")
      expect(response).to have_http_status(:ok)
      expect(manifest["resources"].pluck("key")).to eq(%w[tags])
    end

    it "serves a resource marked `reactive { expose true }`" do
      ReactiveAdmin::Registry.find("authors").reactive_options[:expose] = true

      api_get("/api/admin/authors")
      expect(response).to have_http_status(:ok)
    end

    it "denies a resource marked `reactive { expose false }` even when listed" do
      ReactiveAdmin.menu { resources :posts }
      ReactiveAdmin::Registry.find("posts").reactive_options[:expose] = false

      api_get("/api/admin/posts")
      expect(response).to have_http_status(:not_found)
    end

    it "serves a page placed in the overlay" do
      allow(ReactiveAdmin::Registry.namespace).to receive(:root_to).and_return("posts#index")
      ReactiveAdmin.menu { page :dashboard }

      api_get("/api/admin/_pages/dashboard", schema: "PageResponse")
      expect(response).to have_http_status(:ok)
      expect(menu_ids(manifest["menu"])).to include("dashboard")
    end

    it "serves a resource placed through `reactive { menu path: }`" do
      ReactiveAdmin::Registry.find("tags").reactive_options[:menu] = {path: ["Content"]}

      api_get("/api/admin/tags")
      expect(response).to have_http_status(:ok)
    end
  end

  describe "nested-only resources" do
    let!(:comment) { Comment.create!(post: first_post, body: "Nice post") }

    it "are served when listed and their parent is exposed" do
      ReactiveAdmin.menu { group("Content") { resources :posts } }
      config.exposed_resources = %w[comments]

      api_get("/api/admin/posts/#{first_post.id}/comments", schema: "IndexResponse")
      expect(response).to have_http_status(:ok)
      api_get("/api/admin/posts/#{first_post.id}/comments/#{comment.id}")
      expect(response).to have_http_status(:ok)
      api_get("/api/admin/comments/_meta")
      expect(response).to have_http_status(:ok)
    end

    it "are not served unless listed, whatever their parent" do
      ReactiveAdmin.menu { group("Content") { resources :posts } }

      api_get("/api/admin/posts/#{first_post.id}/comments")
      expect(response).to have_http_status(:not_found)
    end

    it "are not served when their parent is not exposed" do
      config.exposed_resources = %w[comments]

      api_get("/api/admin/posts/#{first_post.id}/comments")
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "the default mode" do
    it "serves everything the policy permits" do
      config.expose = :all

      api_get("/api/admin/categories")
      expect(response).to have_http_status(:ok)
      expect(manifest["resources"].pluck("key")).to include("categories", "posts", "tags")
    end
  end
end
