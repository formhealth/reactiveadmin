RSpec.describe ReactiveAdmin::TemplateContent do
  include_context "with a blog"

  let(:posts) { ReactiveAdmin::Registry.find("posts") }

  def sample(action, id: nil)
    ReactiveAdmin::Doctor::Sample.new(posts, admin).call(action, path_params: id ? {id: id.to_s} : {})
  end

  after { ReactiveAdmin::Ladder.reset! }

  it "walks a read-only template into nodes with its heading as the title" do
    status, payload = sample("preview", id: first_post.id)

    expect(status).to eq(200)
    expect(payload).to include("key" => "posts", "title" => "Preview of #{first_post.title}", "layout" => [], "actions" => [])
  end

  it "keeps the rest of the content as nodes" do
    _, payload = sample("stats")

    expect(payload["layout"]).to eq([{"type" => "text", "text" => "Total posts: #{Post.count}"}])
  end

  it "walks links in stored markup as display links, never as actions" do
    first_post.update!(title: %(<a href="/admin/posts" data-x="1">all</a>))
    _, payload = sample("note", id: first_post.id)

    expect(payload["layout"].to_json).to include('"type":"link"')
    expect(payload["layout"].to_json).not_to include('"action"')
  end

  %w[<form><input></form> <button>Go</button> <a\ data-method="post"\ href="/x">x</a> <script>x()</script>].each do |markup|
    it "refuses rendered html holding #{markup}" do
      first_post.update!(title: markup)
      status, payload = sample("note", id: first_post.id)

      expect(status).to eq(501)
      expect(payload).to include("code" => "unsupported")
    end
  end

  it "is decided as a frame afterwards" do
    first_post.update!(title: "<button>Go</button>")
    sample("note", id: first_post.id)

    expect(ReactiveAdmin::Ladder.action(posts, "note")).to have_attributes(mode: "frame", reason: "recording failed", read_only: false)
  end

  it "leaves a template with raw controls to the frame" do
    expect(ReactiveAdmin::Ladder.action(posts, "audit")).to have_attributes(mode: "frame", reason: "no Formtastic form", read_only: false)
    expect(ReactiveAdmin::Ladder.action(posts, "preview")).to have_attributes(mode: "native", reason: "read-only markup", read_only: true, presentation: "page")
  end
end
