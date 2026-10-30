RSpec.describe ReactiveAdmin::OpenApi::ResourceDoc do
  include_context "with a blog"

  def build(key, user: admin)
    context = ReactiveAdmin::OpenApi::Context.new(user, controller: nil, full: false)
    described_class.new(context, context.resources.find { it[:key] == key }).call
  end

  def routes(doc) = doc[:paths].flat_map { |path, item| item.keys.map { "#{it.upcase} #{path}" } }

  it "returns the resource's tag, paths, generated schemas and shared parameters" do
    doc = build("posts")

    expect(doc[:tag]).to include(name: "posts", "x-displayName": "Posts")
    expect(doc[:schemas].keys).to include("PostsIndexResponse", "PostRow", "PostCreateParams", "PostUpdateParams")
    expect(doc[:parameters].keys).to include("GetOptionsField", "GetOptionsContext")
    expect(routes(doc)).to include("GET /api/admin/posts", "POST /api/admin/posts", "PATCH /api/admin/posts/{id}", "GET /api/admin/posts/_meta")
  end

  it "documents only the actions the resource defines" do
    allow(ReactiveAdmin::Registry).to receive(:actions).and_call_original
    allow(ReactiveAdmin::Registry).to receive(:actions).with(ReactiveAdmin::Registry.find("notes")).and_return(%i[index show])
    paths = routes(build("notes"))

    expect(paths).to include("GET /api/admin/notes", "GET /api/admin/notes/{id}")
    expect(paths).not_to include("POST /api/admin/notes", "DELETE /api/admin/notes/{id}", "GET /api/admin/notes/new")
    expect(build("notes")[:schemas].keys).not_to include("NoteCreateParams")
  end

  it "leaves out writes the user's permissions refuse" do
    expect(routes(build("posts")).include?("DELETE /api/admin/posts/{id}")).to eq(can_destroy_post?(admin))
  end

  it "nests the paths of a resource under its required parent" do
    doc = build("comments")

    expect(routes(doc)).to include("GET /api/admin/posts/{post_id}/comments", "POST /api/admin/posts/{post_id}/comments", "GET /api/admin/comments/_meta")
    expect(routes(doc)).to include("GET /api/admin/posts/{post_id}/comments/_options")
    expect(routes(doc)).not_to include("GET /api/admin/comments/_labels")
  end

  it "falls back to generic schemas, with a degradation, when what a resource declares fails" do
    allow(ReactiveAdmin::ResourceMeta).to receive(:new).and_raise(RuntimeError, "private detail")
    allow(ReactiveAdmin::Degradation).to receive(:record)
    doc = build("posts")

    expect(routes(doc)).to include("GET /api/admin/posts")
    expect(ReactiveAdmin::Degradation).to have_received(:record).with(hash_including(kind: :openapi_degraded, reason: a_string_matching(/\A(?!.*private detail)/))).at_least(:once)
  end

  it "gives member and collection actions the ids the verb and kind imply" do
    ids = build("posts")[:paths].values.flat_map(&:values).pluck(:operationId)

    expect(ids).to include("postPublish", "postRenameGet", "postRenamePost", "postsStats", "postsImport")
  end

  it "drops a resource's batch endpoint when it declares none" do
    expect(build("tags")[:paths]).not_to have_key("/api/admin/tags/batch_action") if ReactiveAdmin::AA.batch_actions(ReactiveAdmin::Registry.find("tags")).none?
    expect(build("posts")[:paths]).to have_key("/api/admin/posts/batch_action")
  end
end
