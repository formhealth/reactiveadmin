RSpec.describe "fallback ladder", type: :request do
  include_context "with a blog"

  let(:frame) { {"X-Reactiveadmin-Frame" => "1"} }

  def classic(verb, path, params: nil, headers: {}) = send(verb, path, params:, headers:)

  context "when signed in as an admin" do
    before { sign_in admin }

    describe "choosing a mode per GET action" do
      it "serves a Formtastic-only template natively as a form" do
        api_get("/api/admin/posts/#{first_post.id}/rename", schema: "FormResponse")

        expect(json).to include("resource" => "posts", "id" => first_post.id.to_s, "action" => {"method" => "post", "path" => "/api/admin/posts/#{first_post.id}/rename"})
        expect(fields_of(json["form"])["title"]).to include("control" => "text", "param" => "post[title]", "value" => "Hello world")
      end

      it "describes that view on the action: native, a dialog for a short form" do
        api_get("/api/admin/posts/#{first_post.id}")

        rename = by_key(json["actions"])["rename"]
        expect(rename["view"]).to eq("mode" => "native", "path" => "/api/admin/posts/#{first_post.id}/rename", "presentation" => "dialog")
      end

      it "describes a read-only template as a native page" do
        api_get("/api/admin/posts/_meta", schema: "ResourceMeta")

        stats = by_key(json["action_items"])["stats"]
        expect(stats["view"]).to eq("mode" => "native", "path" => "/api/admin/posts/stats", "presentation" => "page")
      end

      it "describes row items that render read-only templates the same way" do
        api_get("/api/admin/posts")

        preview = by_key(row_for(json["rows"], first_post)["actions"])["preview"]
        expect(preview["view"]).to eq("mode" => "native", "path" => "/api/admin/posts/#{first_post.id}/preview", "presentation" => "page")
      end

      it "describes a template with raw controls as a frame over the classic url" do
        api_get("/api/admin/posts/#{first_post.id}")

        audit = by_key(json["actions"])["audit"]
        expect(audit["view"]).to include("mode" => "frame", "path" => "/admin/posts/#{first_post.id}/audit")
      end

      it "answers the API path of a frame view with unsupported rather than html" do
        api_get("/api/admin/posts/#{first_post.id}/audit")

        expect(response).to have_http_status(:not_implemented)
        expect(json).to include("code" => "unsupported")
      end

      describe "a read-only template" do
        after { ReactiveAdmin::Ladder.reset! }

        it "takes a leading heading as the title" do
          api_get("/api/admin/posts/#{first_post.id}/preview", schema: "PageResponse")

          expect(json).to include("key" => "posts", "title" => "Preview of #{first_post.title}", "actions" => [], "layout" => [])
        end

        it "answers its html as typed nodes, titled by the action when there is no heading" do
          api_get("/api/admin/posts/stats", schema: "PageResponse")

          expect(json).to include("key" => "posts", "title" => "Stats", "layout" => [{"type" => "text", "text" => "Total posts: #{Post.count}"}])
        end

        it "reports no frame degradation" do
          api_get("/api/admin/posts/#{first_post.id}/preview", schema: "PageResponse")

          expect(json["degraded"].to_a.pluck("kind")).not_to include("view_frame", "page_frame")
        end

        it "walks stored markup into display nodes, never into actions" do
          first_post.update!(title: %(<b>bold</b> <a href="/admin/posts">all</a>))
          api_get("/api/admin/posts/#{first_post.id}/note", schema: "PageResponse")

          expect(json["layout"].to_json).not_to include("api_path", '"action"')
          expect(json["layout"].to_json).to include("all")
        end

        it "becomes a frame for good when the rendered html holds a control" do
          first_post.update!(title: %(<a href="/admin/posts/#{first_post.id}/archive" data-method="post">Archive</a>))
          api_get("/api/admin/posts/#{first_post.id}/note")

          expect(response).to have_http_status(:not_implemented)
          expect(ReactiveAdmin::Ladder.action(ReactiveAdmin::Registry.find("posts"), "note")).to have_attributes(mode: "frame", reason: "recording failed")
        end
      end

      it "submits a native form like any write" do
        api(:post, "/api/admin/posts/#{first_post.id}/rename", {post: {title: "Renamed"}}, schema: "ActionResult")

        expect(json).to include("ok" => true, "message" => "Renamed")
        expect(first_post.reload.title).to eq("Renamed")
      end
    end

    describe "frame requests" do
      it "return the classic page without the layout" do
        classic(:get, "/admin/posts/#{first_post.id}/preview", headers: frame)

        expect(response).to have_http_status(:ok)
        expect(response.media_type).to eq("text/html")
        expect(response.body).to include("Preview of Hello world")
        expect(response.body).not_to include("<html", "wrapper")
      end

      it "return a re-rendered fragment for a failed write" do
        classic(:patch, "/admin/authors/#{alice.id}", params: {author: {name: ""}}, headers: frame)

        expect(response).to have_http_status(:ok)
        expect(response.media_type).to eq("text/html")
        expect(response.body).to include("author[name]", "error")
        expect(alice.reload.name).to eq("Alice Author")
      end

      it "turn a redirect into a FrameRedirect with the flash" do
        classic(:post, "/admin/posts/#{first_post.id}/archive", headers: frame)

        expect(response.media_type).to eq("application/json")
        expect(json).to match_contract("FrameRedirect")
        expect(json["redirect"]).to include("resource" => "posts", "id" => first_post.id.to_s, "view" => "show")
        expect(json["flash"]).to eq("notice" => "Archived")
      end

      it "carry an alert flash in the redirect" do
        classic(:post, "/admin/posts/#{first_post.id}/flag", headers: frame)

        expect(json["flash"]).to eq("alert" => "Cannot flag this post")
      end

      it "do not touch the classic response without the header" do
        classic(:get, "/admin/authors/#{alice.id}")

        expect(response.media_type).to eq("text/html")
        expect(response.body).to include("<html")
      end
    end

    describe "iframe mode" do
      it "serves the classic page in the chrome-free embed layout" do
        classic(:get, "/admin/posts/#{first_post.id}/preview?embed=1")

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("data-reactiveadmin-embed", "Preview of Hello world")
      end
    end
  end

  context "when signed out" do
    it "answers a frame request with JSON 401 instead of a login page inside the frame" do
      classic(:get, "/admin/posts/#{first_post.id}/preview", headers: frame)

      expect(response).to have_http_status(:unauthorized)
      expect(response.media_type).to eq("application/json")
    end
  end

  describe "with forgery protection on", :csrf do
    around do |example|
      original = ActionController::Base.allow_forgery_protection
      ActionController::Base.allow_forgery_protection = true
      example.run
    ensure
      ActionController::Base.allow_forgery_protection = original
    end

    before { sign_in admin }

    it "requires the token on frame writes" do
      classic(:post, "/admin/posts/#{first_post.id}/archive", headers: frame)
      expect(first_post.reload).not_to be_archived

      classic(:post, "/admin/posts/#{first_post.id}/archive", headers: frame.merge("X-CSRF-Token" => csrf_token))
      expect(response).to have_http_status(:ok)
      expect(first_post.reload).to be_archived
    end
  end
end
