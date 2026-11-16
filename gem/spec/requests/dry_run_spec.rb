RSpec.describe "update dry run", type: :request do
  include_context "with a blog"

  let(:events) { [] }
  let(:csrf) { {"X-CSRF-Token" => csrf_token} }

  before do
    %w[write write_rejected].each { |name| ActiveSupport::Notifications.subscribe("#{name}.reactiveadmin") { |*, payload| events << [name, payload] } }
    sign_in admin
  end

  after { ActiveSupport::Notifications.unsubscribe(/reactiveadmin\z/) }

  def dry_update(record, attrs, path: "posts", key: :post, lock: lock_of(record), schema: "DryRunResult", **extra)
    api(:patch, "/api/admin/#{path}/#{record.id}", {key => attrs, :lock => lock, :dry_run => true}.merge(extra), headers: csrf, schema:)
  end

  it "returns each changed field's from and to and saves nothing" do
    dry_update(first_post, {title: "Retitled", featured: first_post.featured})

    expect(response).to have_http_status(:ok)
    expect(json).to eq("ok" => true, "dry_run" => true, "changes" => {"title" => {"from" => "Hello world", "to" => "Retitled"}})
    expect(first_post.reload.title).to eq("Hello world")
  end

  it "refuses association ids rather than assigning them, which saves at once and runs callbacks" do
    rails = Tag.create!(name: "rails")
    statements = []
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") { |*, payload| statements << payload[:sql] }

    expect { dry_update(first_post, {tag_ids: [rails.id.to_s]}) }.not_to change(Tagging, :count)

    ActiveSupport::Notifications.unsubscribe(subscriber)
    expect(response).to have_http_status(:bad_request)
    expect(json["message"]).to include("tag_ids")
    expect(statements.grep(/\A\s*(INSERT|UPDATE|DELETE)/i)).to be_empty
  end

  it "previews a has_one section that updates in place" do
    alice.create_profile!(bio: "Hi")
    dry_update(alice, {profile_attributes: {id: alice.profile.id, bio: "Hello"}}, path: "authors", key: :author)

    expect(response).to have_http_status(:ok)
    expect(json["nested"]).to eq("profile" => {"added" => 0, "removed" => 0, "changed" => 1})
    expect(alice.profile.reload.bio).to eq("Hi")
  end

  it "counts nested rows without diffing them" do
    rows = {comments_attributes: {"0" => {body: "A new one"}}}
    expect { dry_update(first_post, rows) }.not_to change(Comment, :count)

    expect(json["nested"]).to eq("comments" => {"added" => 1, "removed" => 0, "changed" => 0})
  end

  it "previews nested rows sent as an array" do
    expect { dry_update(first_post, {comments_attributes: [{body: "A new one"}]}) }.not_to change(Comment, :count)

    expect(response).to have_http_status(:ok)
    expect(json["nested"]).to eq("comments" => {"added" => 1, "removed" => 0, "changed" => 0})
  end

  it "shows a multiparameter date as a change to its attribute" do
    dry_update(first_post, {"published_at(1i)" => "2031", "published_at(2i)" => "1", "published_at(3i)" => "2", "published_at(4i)" => "3", "published_at(5i)" => "4"})

    expect(response).to have_http_status(:ok)
    expect(json["changes"]["published_at"]["to"]).to start_with("2031-01-02")
  end

  it "refuses a permitted column the form has no control for, rather than reading back its stored value" do
    allow_any_instance_of(ReactiveAdmin::FormSchema).to receive(:sections).and_wrap_original { |m| m.call.map { it.merge(fields: it[:fields].to_a.reject { |f| f[:name] == "body" }) } }

    dry_update(first_post, {body: "Peeking"})

    expect(response).to have_http_status(:bad_request)
    expect(json["message"]).to include("body", "form doesn't offer")
  end

  it "masks a password control's change, since the form withholds its stored value" do
    allow_any_instance_of(ReactiveAdmin::FormSchema).to receive(:sections).and_wrap_original { |m| m.call.map { |s| s.merge(fields: s[:fields].to_a.map { (it[:name] == "title") ? it.merge(control: "password") : it }) } }

    dry_update(first_post, {title: "New secret"})

    expect(json["changes"]).to eq("title" => {"from" => "[masked]", "to" => "[masked]"})
    expect(response.body).not_to include("Hello world", "New secret")
  end

  it "masks a field the form masks, since the stored value is hidden from the form" do
    allow_any_instance_of(ReactiveAdmin::FormSchema).to receive(:sections).and_wrap_original { |m| m.call.map { |s| s.merge(fields: s[:fields].to_a.map { (it[:name] == "title") ? it.merge(masked: true) : it }) } }

    dry_update(first_post, {title: "New secret"})

    expect(json["changes"]).to eq("title" => {"from" => "[masked]", "to" => "[masked]"})
    expect(response.body).not_to include("Hello world", "New secret")
  end

  it "refuses a column whose reader the host overrides, since it could show something other than the stored value" do
    allow_any_instance_of(Post).to receive(:title).and_return("computed")

    dry_update(first_post, {title: "Retitled"})

    expect(response).to have_http_status(:bad_request)
    expect(json["message"]).to include("title")
    expect(response.body).not_to include("computed", "Hello world")
  end

  it "summarizes a JSON value the form wouldn't inline, however small" do
    allow(ReactiveAdmin.config).to receive(:inline_json_limit).and_return(10)
    first_post.update!(metadata: {"token" => "stored-secret-value"})

    dry_update(first_post, {metadata: {"token" => "new"}})

    expect(json["changes"]["metadata"]["from"]).to match(/\A\[hash, \d+ bytes\]\z/)
    expect(response.body).not_to include("stored-secret-value")
  end

  it "answers a validation failure as the usual 422 and saves nothing" do
    dry_update(first_post, {title: ""})

    expect(response).to have_http_status(:unprocessable_content)
    expect(json["errors"]).to include("title")
    expect(first_post.reload.title).to eq("Hello world")
  end

  it "applies the same lock check" do
    lock = lock_of(first_post)
    first_post.touch(time: 1.minute.from_now)
    dry_update(first_post, {title: "Mine"}, lock:)

    expect(response).to have_http_status(:conflict)
  end

  it "applies the same masking: a secret's change is shown as masked, never its value" do
    news.update!(api_token: "tok-secret-123")
    dry_update(news, {name: "Headlines", api_token: "tok-new-456"}, path: "categories", key: :category)

    expect(json["changes"]).to eq("name" => {"from" => news.name, "to" => "Headlines"}, "api_token" => {"from" => "[masked]", "to" => "[masked]"})
    expect(response.body).not_to include("tok-secret-123", "tok-new-456")
    expect(news.reload.api_token).to eq("tok-secret-123")
  end

  it "keeps a secret submitted blank as unchanged" do
    news.update!(api_token: "tok-secret-123")
    dry_update(news, {api_token: ""}, path: "categories", key: :category)

    expect(json["changes"]).to eq({})
  end

  it "emits no write event, and marks a rejected dry run" do
    dry_update(first_post, {title: "Retitled"})
    expect(events).to be_empty

    dry_update(first_post, {title: ""})
    expect(events.map(&:first)).to eq(%w[write_rejected])
    expect(events.first.last).to include(code: "invalid", dry_run: true)
  end

  it "is a plain write when dry_run is false" do
    api(:patch, "/api/admin/posts/#{first_post.id}", {post: {title: "Real"}, lock: lock_of(first_post), dry_run: false}, headers: csrf)

    expect(first_post.reload.title).to eq("Real")
    expect(events.map(&:first)).to eq(%w[write])
    expect(events.first.last).not_to include(:dry_run)
  end

  it "refuses dry_run on a create or a destroy rather than writing" do
    expect { api(:post, "/api/admin/posts", {post: {title: "T", author_id: alice.id}, dry_run: true}, headers: csrf) }.not_to change(Post, :count)
    expect(response).to have_http_status(:bad_request)

    expect { api(:delete, "/api/admin/posts/#{second_post.id}", {dry_run: true}, headers: csrf) }.not_to change(Post, :count)
    expect(response).to have_http_status(:bad_request)
  end

  it "refuses dry_run on a GET custom action that writes, and on a page action" do
    expect { api_get("/api/admin/posts/#{first_post.id}/bump", dry_run: true) }.not_to change { first_post.reload.views_count }
    expect(response).to have_http_status(:bad_request)

    api(:post, "/api/admin/dashboard/recalc", {dry_run: true}, headers: csrf)
    expect(response).to have_http_status(:bad_request)
  end

  it "refuses dry_run on a plain GET read" do
    api_get("/api/admin/posts", dry_run: true)

    expect(response).to have_http_status(:bad_request)
  end

  it "never saves" do
    allow_any_instance_of(Post).to receive(:save).and_raise("saved")

    dry_update(first_post, {title: "Retitled"})

    expect(response).to have_http_status(:ok)
  end
end

RSpec.describe ReactiveAdmin::DryRun do
  def refused?(klass, attributes)
    described_class.allocate.send(:refuse_unpreviewable, klass, attributes)
    false
  rescue ReactiveAdmin::ApiErrors::BadRequest
    true
  end

  it "refuses what saves at once or runs host code" do
    expect(refused?(Post, {"tag_ids" => [1]})).to be true
    expect(refused?(Post, {"tags" => []})).to be true
    expect(refused?(Post, {"unheard_of" => "x"})).to be true
    expect(refused?(Post, {"taggings_attributes" => {"0" => {"tag_id" => 1}}})).to be true
    expect(refused?(Post, {"comments_attributes" => {"0" => {"post_ids" => [1]}}})).to be true
  end

  it "refuses a column whose writer the host defined, since it could notify or call out" do
    host_post = Class.new(Post) do
      def title=(value)
        super
      end
    end

    expect(refused?(host_post, {"title" => "x"})).to be true
    expect(refused?(host_post, {"body" => "x"})).to be false
  end

  it "refuses a nested section whose writer the host defined" do
    host_post = Class.new(Post) do
      def comments_attributes=(rows)
        super
      end
    end

    expect(refused?(host_post, {"comments_attributes" => [{"body" => "x"}]})).to be true
  end

  it "treats a column ending in _attributes as a plain column, not a section" do
    ActiveRecord::Base.connection.create_table(:widgets) { it.json :custom_attributes }
    stub_const("Widget", Class.new(ActiveRecord::Base) { self.table_name = "widgets" })

    expect(refused?(Widget, {"custom_attributes" => {"a" => 1}})).to be false
    expect(refused?(Widget, {"unheard_of_attributes" => {"a" => 1}})).to be true
  ensure
    ActiveRecord::Base.connection.drop_table(:widgets, if_exists: true)
  end

  it "keeps the fields of a singular section sent without an id" do
    expect(refused?(Author, {"profile_attributes" => {"bio" => "x"}})).to be false
    expect(refused?(Author, {"profile_attributes" => {"unheard_of" => "x"}})).to be true
  end

  it "checks array-form rows" do
    expect(refused?(Post, {"comments_attributes" => [{"body" => "x"}]})).to be false
    expect(refused?(Post, {"comments_attributes" => [{"post_ids" => [1]}]})).to be true
  end

  it "refuses a has_one section that would replace its record" do
    allow(Author).to receive(:nested_attributes_options).and_return(profile: {update_only: false})

    expect(refused?(Author, {"profile_attributes" => {"bio" => "x"}})).to be true
  end

  it "refuses a has_many whose additions are hooked" do
    allow(Post.reflect_on_association(:comments)).to receive(:options).and_return({after_add: :notify})

    expect(refused?(Post, {"comments_attributes" => {"0" => {"body" => "x"}}})).to be true
  end

  it "refuses a nested section whose reject_if is host code, but allows :all_blank" do
    allow(Post).to receive(:nested_attributes_options).and_return(comments: {reject_if: proc { true }})
    expect(refused?(Post, {"comments_attributes" => [{"body" => "x"}]})).to be true

    allow(Post).to receive(:nested_attributes_options).and_return(comments: {reject_if: ActiveRecord::NestedAttributes::ClassMethods::REJECT_ALL_BLANK_PROC})
    expect(refused?(Post, {"comments_attributes" => [{"body" => "x"}]})).to be false
  end

  it "refuses a has_many whose limit is a proc or method name, which Rails evaluates on assignment" do
    [proc { 5 }, :max_rows, 5, nil].each do |limit|
      allow(Post).to receive(:nested_attributes_options).and_return(comments: {limit:})

      expect(refused?(Post, {"comments_attributes" => [{"body" => "x"}]})).to be(limit.is_a?(Proc) || limit.is_a?(Symbol))
    end
  end

  it "refuses a nested section whose rows could be an STI subclass with its own writers" do
    allow(Comment).to receive(:inheritance_column).and_return("body")

    expect(refused?(Post, {"comments_attributes" => [{"body" => "x"}]})).to be true
  end

  it "accepts attributes, multiparameter dates and nested rows" do
    expect(refused?(Post, {"title" => "x", "published_at(1i)" => "2026", "comments_attributes" => {"0" => {"body" => "x", "_destroy" => "0"}}})).to be false
    expect(refused?(Author, {"profile_attributes" => {"id" => 1, "bio" => "x"}})).to be false
  end
end
