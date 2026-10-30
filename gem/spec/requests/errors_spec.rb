module ErrorsSpec
  SIGNED_OUT = {
    "manifest" => [:get, ->(_) { "/api/admin/_manifest" }],
    "session" => [:get, ->(_) { "/api/admin/_session" }],
    "meta" => [:get, ->(_) { "/api/admin/posts/_meta" }],
    "index" => [:get, ->(_) { "/api/admin/posts" }],
    "csv" => [:get, ->(_) { "/api/admin/posts.csv" }],
    "show" => [:get, ->(t) { "/api/admin/posts/#{t.first_post.id}" }],
    "new form" => [:get, ->(_) { "/api/admin/posts/new" }],
    "edit form" => [:get, ->(t) { "/api/admin/posts/#{t.first_post.id}/edit" }],
    "options" => [:get, ->(_) { "/api/admin/posts/_options?field=author&context=filter" }],
    "create" => [:post, ->(_) { "/api/admin/posts" }],
    "update" => [:patch, ->(t) { "/api/admin/posts/#{t.first_post.id}" }],
    "destroy" => [:delete, ->(t) { "/api/admin/posts/#{t.first_post.id}" }],
    "member action" => [:put, ->(t) { "/api/admin/posts/#{t.first_post.id}/publish" }],
    "collection action" => [:post, ->(_) { "/api/admin/posts/import" }],
    "batch action" => [:post, ->(_) { "/api/admin/posts/batch_action" }],
    "nested index" => [:get, ->(t) { "/api/admin/posts/#{t.first_post.id}/comments" }],
    "page" => [:get, ->(_) { "/api/admin/_pages/dashboard" }]
  }.freeze
end

RSpec.describe "errors", type: :request do
  include_context "with a blog"

  describe "401" do
    ErrorsSpec::SIGNED_OUT.each do |name, (verb, path)|
      it "answers #{name} with JSON unauthorized and never redirects to the host's sign-in" do
        api(verb, path.call(self), (verb == :get) ? nil : {})

        expect(response).to have_http_status(:unauthorized)
        expect(json).to include("code" => "unauthorized", "message" => "Authentication required")
        expect(response.location).to be_nil
      end
    end

    it "tells the client where the host would have sent the user" do
      api_get("/api/admin/posts")

      expect(json["location"]).to end_with("/login")
    end

    it "is not tricked by a stale session id" do
      sign_in admin
      admin.destroy!

      api_get("/api/admin/posts")

      expect(response).to have_http_status(:unauthorized)
    end

    it "leaves the classic admin's own redirect alone" do
      get "/admin/posts"

      expect(response).to redirect_to("/login")
    end
  end

  describe "403" do
    before { sign_in editor }

    it "answers a denied action with JSON forbidden" do
      skip "adapter allows everything" if adapter?(:default)

      api(:delete, "/api/admin/posts/#{first_post.id}")

      expect(response).to have_http_status(can_destroy_post?(editor) ? :ok : :forbidden)
      expect(json).to include("code" => "forbidden", "message" => "Not authorized") unless can_destroy_post?(editor)
    end

    it "does not leak the host's on_unauthorized_access wording or leave its flash behind" do
      skip "adapter allows everything" if adapter?(:default)

      api(:delete, "/api/admin/categories/#{news.id}")

      expect(response).to have_http_status(:forbidden)
      expect(response.body).not_to include("Access denied")
      api_get("/api/admin/_session")
      expect(response).to have_http_status(:ok)
    end

    it "answers a hidden resource's every read as forbidden" do
      skip "adapter allows everything" if adapter?(:default)

      ["", "/new", "/_meta", "/#{news.id}", "/#{news.id}/edit"].each do |suffix|
        api_get("/api/admin/categories#{suffix}")

        expect(response).to have_http_status(:forbidden), suffix
      end
    end

    it "keeps the classic admin on the host's own handler" do
      skip "adapter allows everything" if adapter?(:default)

      delete "/admin/categories/#{news.id}"

      expect(response).to have_http_status(:found)
      expect(flash[:alert]).to start_with("Access denied")
    end
  end

  describe "404" do
    before { sign_in admin }

    it "answers a missing record on every record endpoint" do
      [[:get, ""], [:get, "/edit"], [:patch, ""], [:delete, ""], [:put, "/publish"], [:post, "/archive"]].each do |verb, suffix|
        api(verb, "/api/admin/posts/0#{suffix}", (verb == :get) ? nil : {post: {title: "x"}})

        expect(response).to have_http_status(:not_found), "#{verb} #{suffix}: #{response.status}"
        expect(json).to include("code" => "not_found", "message" => "Record not found")
      end
    end

    it "answers unknown routes under the mount in JSON" do
      api_get("/api/admin/nopes")
      expect(response).to have_http_status(:not_found)
      expect(json).to include("code" => "not_found")

      api_get("/api/admin/posts/1/2/3/4")
      expect(response).to have_http_status(:not_found)
    end

    it "does not serve AA's json, xml or html formats, which would serialize whole records" do
      %w[json xml html].each do |format|
        api_get("/api/admin/posts.#{format}")

        expect(response).to have_http_status(:not_found), format
        expect(response.body).not_to include("Hello world")
      end
    end

    it "answers an unknown page in JSON" do
      api_get("/api/admin/_pages/nope")

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "unexpected errors" do
    before { sign_in admin }

    it "answers JSON with the class and action but not the exception message, and reports it" do
      allow_any_instance_of(ReactiveAdmin::IndexPayload).to receive(:as_json).and_raise(RuntimeError, "secret draft detail")
      expect(Rails.error).to receive(:report).with(an_instance_of(ReactiveAdmin::ScrubbedError), hash_including(handled: true, source: "reactiveadmin"))

      api_get("/api/admin/posts")

      expect(response).to have_http_status(:internal_server_error)
      expect(json).to eq("code" => "error", "message" => "RuntimeError while rendering posts index")
      expect(response.body).not_to include("secret")
    end

    it "keeps the exception message out of the log too" do
      allow_any_instance_of(ReactiveAdmin::ShowPayload).to receive(:as_json).and_raise(RuntimeError, "secret draft detail")
      allow(Rails.logger).to receive(:error)

      api_get("/api/admin/posts/#{first_post.id}")

      expect(Rails.logger).to have_received(:error).with(satisfy { !it.include?("secret") }).at_least(:once)
    end

    it "uses the exception's own status when Rails maps one" do
      allow_any_instance_of(ReactiveAdmin::IndexPayload).to receive(:as_json).and_raise(ActionController::BadRequest)

      api_get("/api/admin/posts")

      expect(response).to have_http_status(:bad_request)
      expect(json["code"]).to eq("error")
    end

    it "falls back to JSON when an index block raises" do
      allow_any_instance_of(ReactiveAdmin::IndexRecorder).to receive(:column).and_wrap_original do |original, *args, &block|
        raise "bad column" if args.first == "Views"

        original.call(*args, &block)
      end

      api_get("/api/admin/posts", nil, schema: "IndexResponse")

      expect(response).to have_http_status(:ok)
    end
  end

  describe "bad input" do
    before { sign_in admin }

    it "rejects a filter no declared filter explains" do
      api_get("/api/admin/posts", q: {"title_cont" => "x", "views_count_gteq" => "1", "author_name_cont" => "a"})

      expect(response).to have_http_status(:bad_request)
      expect(json).to include("code" => "invalid")
    end

    it "rejects a non-hash q" do
      api_get("/api/admin/posts?q=oops")

      expect(response).to have_http_status(:bad_request)
    end

    it "truncates absurd filter names in the message" do
      api_get("/api/admin/posts", q: {("x" * 500) => "1"})

      expect(response).to have_http_status(:bad_request)
      expect(json["message"].length).to be < 200
    end

    it "accepts the names AA's association filters search on" do
      api_get("/api/admin/posts", q: {author_id_eq: alice.id, category_id_eq: news.id, tags_id_eq: ruby.id})

      expect(response).to have_http_status(:ok)
    end
  end
end
