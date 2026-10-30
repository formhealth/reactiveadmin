RSpec.describe "json values", type: :request do
  include_context "with a blog"
  include ActiveSupport::Testing::TimeHelpers

  let(:context_value) { {"theme" => "dark", "api_token" => "tok-secret-123", "nested" => {"list" => [1, {"deep" => "x"}]}} }
  let!(:comment) { Comment.create!(post: first_post, body: "Nice post", context: context_value) }
  let(:comments_path) { "/api/admin/posts/#{first_post.id}/comments" }
  let(:value_path) { "#{comments_path}/#{comment.id}/_value" }

  def cell = row_for(json["rows"], comment)["cells"]["context"]

  def link = api_get(comments_path, schema: "IndexResponse") && cell["expand_path"]

  def row_value(label: "Context")
    api_get("#{comments_path}/#{comment.id}", schema: "ShowResponse")
    nodes_of(json["layout"], "attributes_table").flat_map { it["rows"] }.find { it["label"] == label }["value"].first
  end

  def queries
    count = 0
    counter = ->(*, payload) { count += 1 unless %w[SCHEMA TRANSACTION].include?(payload[:name]) || payload[:cached] }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { yield }
    count
  end

  def audited
    events = []
    ActiveSupport::Notifications.subscribed(->(*, payload) { events << payload }, "value_viewed.reactiveadmin") { yield }
    events
  end

  context "when signed in as an admin" do
    before do
      ReactiveAdmin.config.masked_attributes = [:api_token]
      sign_in admin
    end

    after { ReactiveAdmin.config.masked_attributes = [] }

    describe "index" do
      it "summarizes the value and points to the endpoint" do
        api_get(comments_path, schema: "IndexResponse")

        expect(cell).to match(
          "type" => "json",
          "summary" => {"kind" => "object", "keys" => %w[theme api_token nested], "size" => context_value.to_json.bytesize},
          "expand_path" => start_with("#{value_path}?field=context&token=")
        )
        expect(response.body).not_to include("tok-secret-123", "dark")
      end

      it "caps the keys of objects and gives arrays none" do
        comment.update!(context: (1..30).to_h { ["k#{it}", it] })
        api_get(comments_path)
        expect(cell["summary"]["keys"].size).to eq(20)

        comment.update!(context: [1, 2])
        api_get(comments_path)
        expect(cell["summary"]).to include("kind" => "array", "keys" => [])
      end

      it "leaves an empty value empty" do
        comment.update!(context: nil)
        api_get(comments_path)

        expect(cell).to eq("type" => "empty")
      end
    end

    describe "show" do
      it "sends a small value inline" do
        comment.update!(context: {"theme" => "dark"})

        expect(row_value).to eq("type" => "json", "value" => {"theme" => "dark"})
      end

      it "summarizes a value over the limit" do
        ReactiveAdmin.config.inline_json_limit = 10
        comment.update!(context: {"theme" => "dark", "layout" => "wide"})

        expect(row_value).to match("type" => "json", "summary" => {"kind" => "object", "keys" => %w[theme layout], "size" => comment.context.to_json.bytesize},
          "expand_path" => start_with("#{value_path}?field=context&token="))
      ensure
        ReactiveAdmin.config.inline_json_limit = 2048
      end

      it "summarizes a small value that holds a masked key, however deep" do
        comment.update!(context: {"a" => [{"api_token" => "tok-secret-123"}]})

        expect(row_value).to include("summary", "expand_path")
        expect(response.body).not_to include("tok-secret-123")
      end

      it "treats an unrelated record's attribute as plain text" do
        api_get("/api/admin/posts/#{first_post.id}", schema: "ShowResponse")

        metadata = nodes_of(json["layout"], "attributes_table").flat_map { it["rows"] }.find { it["label"] == "Metadata" }["value"].first
        expect(metadata).to eq("type" => "json", "value" => {"seo" => {"slug" => "hello"}})
      end
    end

    describe "_value" do
      it "returns the full value with masked keys replaced" do
        api_get(link, schema: "ValueResponse")

        expect(json["value"]).to eq(context_value.merge("api_token" => "[masked]"))
        expect(response.body).not_to include("tok-secret-123")
      end

      it "is never cached" do
        api_get(link)

        expect(response.headers["Cache-Control"]).to include("no-store")
      end

      it "digs into the value by path" do
        api_get(link, path: "nested.list.1.deep")
        expect(json["value"]).to eq("x")

        api_get(link, path: "nested.list")
        expect(json["value"]).to eq([1, {"deep" => "x"}])
      end

      it "masks a path that lands on a masked key" do
        api_get(link, path: "api_token")

        expect(json["value"]).to eq("[masked]")
      end

      it "answers 404 for an unknown path" do
        url = link
        ["nope", "theme.deeper", "nested.list.9", "nested.list.x", Array.new(40, "a").join(".")].each do |path|
          api_get(url, path:)

          expect(response).to have_http_status(:not_found), path
        end
      end

      it "answers 404 for an attribute a page rendered but that is neither json nor text" do
        api_get(value_path, field: "approved", token: value_token(comment, "approved", user: admin, via: "index"))

        expect(response).to have_http_status(:not_found)
      end

      it "answers 404 when the page the token came from is no longer served" do
        url = link
        allow(ReactiveAdmin::Registry).to receive(:actions).and_return([:show])

        api_get(url)

        expect(response).to have_http_status(:not_found)
      end

      it "answers 403 without a token, or with one that was not issued for this user, record, field or time" do
        good = value_token(comment, "context", user: admin)
        other = Comment.create!(post: first_post, body: "Other", context: context_value)
        bad = {
          "none" => nil, "empty" => "", "forged" => "#{good}x", "garbage" => "abc--def",
          "other field" => value_token(comment, "body", user: admin), "other record" => value_token(other, "context", user: admin),
          "other user" => value_token(comment, "context", user: editor), "tampered" => good.sub(/.\z/) { |c| (c == "A") ? "B" : "A" }
        }

        bad.each do |name, token|
          events = audited { api_get(value_path, field: "context", token:) }

          expect(response).to have_http_status(:forbidden), name
          expect(json).to include("code" => "forbidden")
          expect(events).to be_empty
        end
      end

      it "answers 403 once the token has expired" do
        url = link

        travel_to(ReactiveAdmin.config.value_token_ttl.from_now + 1.second) { api_get(url) }

        expect(response).to have_http_status(:forbidden)
      end

      it "re-renders the pages to find the allowlist in legacy mode, without a token" do
        ReactiveAdmin.config.value_token = false

        api_get(value_path, field: "context")
        expect(response).to have_http_status(:ok)

        [[value_path, "approved"], [value_path, "nope"], [value_path, ""], [value_path, "destroy"], [value_path, "post"]].each do |path, field|
          api_get(path, field:)

          expect(response).to have_http_status(:not_found), "#{path} #{field}"
        end
      ensure
        ReactiveAdmin.config.value_token = true
      end

      it "answers 404 for a missing record" do
        api_get("#{comments_path}/0/_value", field: "context")

        expect(response).to have_http_status(:not_found)
      end

      it "audits the view without the value" do
        url = link
        events = audited { api_get(url, path: "theme") }

        expect(events).to eq([{resource: "comments", id: comment.id.to_s, field: "context", user_id: admin.id}])
      end

      it "does not audit a refused read" do
        expect(audited { api_get(value_path, field: "body") }).to be_empty
      end

      it "is a real view even when the client claims background" do
        calls = 0
        ReactiveAdmin.config.on_background_request = ->(_controller) { calls += 1 }
        api_get(link, nil, headers: {"X-Reactiveadmin-Background" => "1"})

        expect(response).to have_http_status(:ok)
        expect(calls).to eq(0)
      ensure
        ReactiveAdmin.config.on_background_request = nil
      end

      it "stays within a small query budget" do
        url = link
        api_get(url)

        expect(queries { api_get(url) }).to be <= 3
      end
    end
  end

  context "when signed in as an editor" do
    let(:path) { ->(post) { "/api/admin/posts/#{post.id}/_value" } }

    before do
      second_post.update!(metadata: {"a" => 1})
      sign_in editor
    end

    it "reads a value only of a record the adapter lets the editor see" do
      [first_post, second_post].each do |post|
        events = audited { api_get(path.call(post), field: "metadata", token: value_token(post, "metadata", user: editor)) }

        expect(response).to have_http_status(can_see_post?(editor, post) ? :ok : :forbidden), "post #{post.id}"
        expect(events.size).to eq(can_see_post?(editor, post) ? 1 : 0)
      end
    end
  end

  context "when signed out" do
    it "answers 401" do
      api_get(value_path, field: "context")

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
