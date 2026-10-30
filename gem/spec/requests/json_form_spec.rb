RSpec.describe "json controls in forms", type: :request do
  include_context "with a blog"

  let(:secret_metadata) { {"seo" => {"slug" => "hello"}, "api_token" => "tok-1", "nested" => [{"api_token" => "tok-2", "keep" => 1}]} }
  let(:edit_path) { "/api/admin/posts/#{first_post.id}/edit" }
  let(:value_path) { "/api/admin/posts/#{first_post.id}/_value" }

  def field = fields_of(json["form"])["metadata"]

  def update(attrs)
    api(:patch, "/api/admin/posts/#{first_post.id}", {post: attrs, lock: lock_of(first_post)})
  end

  def audited
    events = []
    ActiveSupport::Notifications.subscribed(->(*, payload) { events << payload }, "value_viewed.reactiveadmin") { yield }
    events
  end

  before do
    ReactiveAdmin.config.masked_attributes = [:api_token]
    sign_in admin
  end

  after do
    ReactiveAdmin.config.masked_attributes = []
    ReactiveAdmin.config.inline_json_limit = 2048
  end

  describe "edit" do
    it "sends a small value inline" do
      api_get(edit_path, schema: "FormResponse")

      expect(field).to include("value" => {"seo" => {"slug" => "hello"}})
      expect(field).not_to include("summary", "expand_path")
    end

    it "summarizes a value over the limit and points to the audited endpoint" do
      ReactiveAdmin.config.inline_json_limit = 10
      api_get(edit_path, schema: "FormResponse")

      expect(field).to include("value" => nil, "summary" => {"kind" => "object", "keys" => %w[seo], "size" => first_post.metadata.to_json.bytesize},
        "expand_path" => start_with("#{value_path}?field=metadata&token="))
      expect(response.body).not_to include("hello")
    end

    it "summarizes a small value with a masked key at any depth" do
      first_post.update!(metadata: secret_metadata)
      api_get(edit_path, schema: "FormResponse")

      expect(field).to include("value" => nil, "summary" => include("keys" => %w[seo api_token nested]),
        "expand_path" => start_with("#{value_path}?field=metadata&token="))
      expect(response.body).not_to include("tok-1", "tok-2", "hello")
    end
  end

  describe "_value" do
    it "serves a form field that no page renders, audited and masked" do
      news.update!(settings: {"a" => 1, "api_token" => "tok-3"})

      api_get("/api/admin/categories/#{news.id}/edit")
      url = fields_of(json["form"])["settings"]["expand_path"]
      events = audited { api_get(url, schema: "ValueResponse") }

      expect(json["value"]).to eq("a" => 1, "api_token" => "[masked]")
      expect(events).to eq([{resource: "categories", id: news.id.to_s, field: "settings", user_id: admin.id}])
    end

    it "checks the update permission on every request, whatever the token says" do
      news.update!(settings: {"a" => 1, "api_token" => "tok-3"})
      api_get("/api/admin/categories/#{news.id}/edit")
      url = fields_of(json["form"])["settings"]["expand_path"]
      allow_any_instance_of(ReactiveAdmin::Authorizer).to receive(:authorized?).and_wrap_original do |original, action, *args, **options|
        (action == ActiveAdmin::Auth::UPDATE) ? false : original.call(action, *args, **options)
      end

      events = audited { api_get(url) }

      expect(response).to have_http_status(:not_found)
      expect(events).to be_empty
    end

    it "answers 404 for a form field that is not json" do
      api_get("/api/admin/categories/#{news.id}/_value", field: "name", token: value_token(news, "name", user: admin, via: "form"))

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "update" do
    before { first_post.update!(metadata: secret_metadata) }

    it "keeps the value when the summarized field is omitted" do
      update(title: "Renamed")

      expect(first_post.reload).to have_attributes(title: "Renamed", metadata: secret_metadata)
    end

    it "keeps the value when the summarized field comes back null or empty" do
      [nil, ""].each do |blank|
        update(title: "Again", metadata: blank)

        expect(first_post.reload.metadata).to eq(secret_metadata)
      end
    end

    it "still lets a loaded value be emptied with {}" do
      update(metadata: {})

      expect(first_post.reload.metadata).to eq({})
    end

    it "restores masked placeholders and applies the edit, as a structure" do
      api_get(edit_path)
      api_get(fields_of(json["form"])["metadata"]["expand_path"])
      loaded = json["value"]
      expect(loaded).to include("api_token" => "[masked]")

      update(metadata: loaded.merge("seo" => {"slug" => "edited"}))

      expect(first_post.reload.metadata).to eq(secret_metadata.merge("seo" => {"slug" => "edited"}))
    end

    it "restores masked placeholders submitted as JSON text where the host permits a scalar" do
      ReactiveAdmin.config.inline_json_limit = 10
      memo = Memo.create!(title: "m", payload: {"api_token" => "tok-4", "a" => 1})
      api_get("/api/admin/memos/#{memo.id}/edit", schema: "FormResponse")
      expect(fields_of(json["form"])["payload"]).to include("value" => nil, "summary" => include("kind" => "object"))

      api_get(fields_of(json["form"])["payload"]["expand_path"])
      api(:patch, "/api/admin/memos/#{memo.id}", {memo: {payload: json["value"].merge("b" => 2).to_json}, lock: lock_of(memo)})

      expect(memo.reload.payload).to eq({"api_token" => "tok-4", "a" => 1, "b" => 2}.to_json)
    end

    it "replaces a masked key given a new value, and never writes the literal" do
      update(metadata: {"api_token" => "fresh", "extra" => {"api_token" => "[masked]"}})

      expect(first_post.reload.metadata).to eq("api_token" => "fresh", "extra" => {})
      expect(first_post.metadata.to_json).not_to include("[masked]")
    end
  end

  describe "ParamNormalizer" do
    it "leaves an omitted summarized field out" do
      sections = [{kind: "inputs", fields: [{param: "post[metadata]", control: "json", summary: {}}]}]
      params = ActionController::Parameters.new(post: {title: "x"})

      ReactiveAdmin::ParamNormalizer.call(params, sections)

      expect(params[:post].to_unsafe_h).to eq("title" => "x")
    end
  end
end
