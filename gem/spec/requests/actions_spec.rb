RSpec.describe "member, collection and batch actions", type: :request do
  include_context "with a blog"

  let(:batch_path) { "/api/admin/posts/batch_action" }

  def batch(key, ids, inputs = nil)
    body = {batch_action: key, collection_selection: ids.map { it.id.to_s }}
    body[:batch_action_inputs] = inputs if inputs
    api(:post, batch_path, body, schema: "ActionResult")
  end

  context "when signed in as an admin" do
    before { sign_in admin }

    describe "member actions" do
      it "runs a PUT action and reports its flash and redirect" do
        api(:put, "/api/admin/posts/#{second_post.id}/publish", schema: "ActionResult")

        expect(response).to have_http_status(:ok)
        expect(json).to include("ok" => true, "message" => "Published Bob's draft")
        expect(json["location"]).to include("resource" => "posts", "id" => second_post.id.to_s, "view" => "show")
        expect(second_post.reload).to be_published
      end

      it "runs a POST action" do
        api(:post, "/api/admin/posts/#{first_post.id}/archive", schema: "ActionResult")

        expect(json).to include("ok" => true, "message" => "Archived")
        expect(first_post.reload).to be_archived
      end

      it "runs actions of other resources" do
        api(:post, "/api/admin/authors/#{alice.id}/ping", schema: "ActionResult")

        expect(json).to include("ok" => true, "message" => "Pinged Alice Author")
      end

      it "turns an alert flash into a 422 with the message in base" do
        api(:post, "/api/admin/posts/#{first_post.id}/flag")

        expect(response).to have_http_status(:unprocessable_content)
        expect(json).to include("code" => "invalid", "errors" => {}, "base" => ["Cannot flag this post"])
        expect(json["location"]).to include("resource" => "posts", "id" => first_post.id.to_s)
      end

      it "is a 404 for a missing record" do
        api(:post, "/api/admin/posts/0/archive")

        expect(response).to have_http_status(:not_found)
      end

      it "never answers a GET template action with an html page or an empty body" do
        api_get("/api/admin/posts/#{first_post.id}/preview")

        expect(response).to have_http_status(:ok).or have_http_status(:not_implemented)
        expect(json).to be_present
      end
    end

    describe "collection actions" do
      it "runs a POST action" do
        api(:post, "/api/admin/posts/import", schema: "ActionResult")

        expect(json).to include("ok" => true, "message" => "Imported")
        expect(json["location"]).to include("resource" => "posts", "view" => "index")
      end

      it "leaves `q` of a custom action to the host when the host lists it" do
        ReactiveAdmin.config.ransack_unguarded_actions = {posts: [:import]}
        api(:post, "/api/admin/posts/import", {q: {body_cont: "x"}}, schema: "ActionResult")

        expect(json).to include("ok" => true, "message" => "Imported")
      ensure
        ReactiveAdmin.config.ransack_unguarded_actions = {}
      end

      it "rejects an undeclared `q` on a custom action" do
        api(:post, "/api/admin/posts/import", {q: {body_cont: "x"}})

        expect(response).to have_http_status(:bad_request)
      end

      it "never answers a GET template action with an empty body" do
        api_get("/api/admin/posts/stats")

        expect(response).to have_http_status(:ok).or have_http_status(:not_implemented)
        expect(json).to be_present
      end
    end

    describe "batch actions" do
      it "rejects an undeclared filter selecting the collection" do
        api(:post, batch_path, {batch_action: "feature", collection_selection: [], q: {body_cont: "x"}})

        expect(response).to have_http_status(:bad_request)
        expect(json).to include("message" => "Unsupported filter: body_cont")
      end

      it "runs a batch action with its form inputs" do
        batch("set_status", [first_post, second_post], {status: "archived", note: "cleanup"})

        expect(response).to have_http_status(:ok)
        expect(json).to include("ok" => true, "message" => "Updated 2 posts to archived")
        expect([first_post, second_post].map { it.reload.status }).to eq(%w[archived archived])
      end

      it "runs a batch action without inputs" do
        batch("feature", [second_post])

        expect(json).to include("ok" => true, "message" => "Featured 1 posts")
        expect(second_post.reload.featured).to be(true)
      end

      it "runs AA's built-in destroy only where the adapter allows it" do
        batch("destroy", [second_post])

        expect(Post.exists?(second_post.id)).to eq(!can_destroy_post?(admin))
        expect(response).to have_http_status(can_destroy_post?(admin) ? :ok : :forbidden)
      end

      it "answers JSON for a batch action that does not exist" do
        api(:post, batch_path, {batch_action: "nope", collection_selection: [first_post.id.to_s]})

        expect(response.media_type).to eq("application/json")
        expect(response.status).to be >= 400
      end
    end
  end

  context "when signed in as an editor" do
    before { sign_in editor }

    it "refuses a member action on another author's post under scoping adapters" do
      api(:put, "/api/admin/posts/#{second_post.id}/publish")

      expect(response).to have_http_status(can_see_post?(editor, second_post) ? :ok : :forbidden)
      expect(second_post.reload.published?).to eq(can_see_post?(editor, second_post))
    end

    it "runs a member action on its own post" do
      api(:put, "/api/admin/posts/#{third_post.id}/publish")

      expect(response).to have_http_status(:ok)
    end

    it "authorizes a collection action whose body never loads anything" do
      api(:post, "/api/admin/posts/import")

      expect(response).to have_http_status(can_import_posts?(editor) ? :ok : :forbidden)
    end

    it "marks the action item disabled with a reason when denied" do
      item = by_key(api_get("/api/admin/posts/_meta")["action_items"])["import"]

      expect(item["enabled"]).to eq(can_import_posts?(editor))
      expect(item["disabled_reason"]).to be_present unless can_import_posts?(editor)
    end

    it "limits a batch action to the posts the editor can see" do
      batch("set_status", [first_post, second_post], {status: "archived"})

      if can_see_post?(editor, second_post)
        expect(response).to have_http_status(:ok)
      else
        expect(response).to have_http_status(:not_found)
        expect(second_post.reload).to be_draft
      end
    end

    it "applies the adapter to AA's destroy batch action" do
      batch("destroy", [first_post])

      expect(response).to have_http_status(can_destroy_post?(editor) ? :ok : :forbidden)
    end
  end

  context "with authorize_custom_actions set to :match_active_admin" do
    around do |example|
      original = ReactiveAdmin.config.authorize_custom_actions
      ReactiveAdmin.config.authorize_custom_actions = :match_active_admin
      example.run
    ensure
      ReactiveAdmin.config.authorize_custom_actions = original
    end

    before { sign_in editor }

    it "leaves authorization to AA, which skips actions that never load a record" do
      api(:post, "/api/admin/posts/import")

      expect(response).to have_http_status(:ok)
    end

    it "still authorizes actions that load the record" do
      api(:put, "/api/admin/posts/#{second_post.id}/publish")

      expect(response).to have_http_status(can_see_post?(editor, second_post) ? :ok : :forbidden)
    end
  end

  context "when signed out" do
    it "answers 401 to batch actions" do
      batch("feature", [first_post])

      expect(response).to have_http_status(:unauthorized)
    end

    it "answers 401 to member and collection actions" do
      api(:put, "/api/admin/posts/#{first_post.id}/publish")
      expect(response).to have_http_status(:unauthorized)

      api(:post, "/api/admin/posts/import")
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
