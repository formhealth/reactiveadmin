RSpec.describe "_labels", type: :request do
  include_context "with a blog"

  let(:path) { "/api/admin/posts/_labels" }
  let(:posts) { [first_post, second_post, third_post] }

  def fetch(ids, **opts) = api_get(path, {ids:}, schema: "LabelsResponse", **opts)

  def labelled = json["labels"].pluck("id")

  context "when signed in as an admin" do
    before { sign_in admin }

    it "returns only resource, id and display name" do
      fetch([first_post.id.to_s])

      expect(json["labels"].size).to eq(1)
      expect(json["labels"].first.keys).to eq(%w[resource id display_name])
      expect(json["labels"].first).to include("resource" => "posts", "id" => first_post.id.to_s)
      expect(json["labels"].first["display_name"]).to be_present
    end

    it "accepts comma-separated ids and skips unknown ones" do
      fetch("#{first_post.id},0,#{second_post.id}")

      expect(labelled).to eq([first_post.id.to_s, second_post.id.to_s])
    end

    it "requires ids" do
      api_get(path)

      expect(response).to have_http_status(:bad_request)
    end

    it "caps the lookup at 20 ids" do
      fetch(posts.map { it.id.to_s } + (1..40).map { "9#{it}000" })

      expect(response).to have_http_status(:ok)
      expect(labelled.size).to be <= ReactiveAdmin::LabelsPayload::MAX_IDS
      expect(labelled).to match_array(posts.map { it.id.to_s })

      ids = Array.new(25) { create_post(author: alice).id.to_s }
      fetch(ids)

      expect(labelled).to eq(ids.first(ReactiveAdmin::LabelsPayload::MAX_IDS))
    end

    it "is metadata: the background header is honoured" do
      calls = []
      ReactiveAdmin.config.on_background_request = ->(controller) { calls << controller.action_name }
      fetch([first_post.id.to_s], headers: {"X-Reactiveadmin-Background" => "1"})

      expect(calls).to eq(["reactiveadmin_labels"])
    ensure
      ReactiveAdmin.config.on_background_request = nil
    end
  end

  context "when signed in as an editor" do
    before { sign_in editor }

    it "leaves out records the adapter refuses to show" do
      fetch(posts.map { it.id.to_s })

      expect(response).to have_http_status(:ok)
      expect(labelled).to match_array(posts.select { can_see_post?(editor, it) }.map { it.id.to_s })
    end
  end

  context "with the resource not exposed" do
    around do |example|
      ReactiveAdmin.config.expose = :listed
      example.run
    ensure
      ReactiveAdmin.config.expose = :all
    end

    before { sign_in admin }

    it "answers 404 like every other endpoint" do
      api_get("/api/admin/categories/_labels", ids: [news.id.to_s])

      expect(response).to have_http_status(:not_found)
    end
  end

  it "requires a signed-in user" do
    api_get(path, ids: ["1"])

    expect(response).to have_http_status(:unauthorized)
  end
end
