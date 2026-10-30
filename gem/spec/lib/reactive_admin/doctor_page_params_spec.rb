RSpec.describe ReactiveAdmin::Doctor, "page params" do
  include_context "with a blog"

  let(:post) { Post.first }
  let(:report) { described_class.run(user: admin) }
  let(:row) { report[:pages].find { it[:key] == "post_previews" } }

  after { ReactiveAdmin.config.doctor_page_params = nil }

  it "renders a page that reads required params with the host's params" do
    ReactiveAdmin.config.doctor_page_params = ->(key) { {post_id: post.id} if key == "post_previews" }

    expect(row).to include(mode: "native", nodes: {typed: 1, html: 0})
    expect(row).not_to include(:failure)
  end

  it "keeps the fallback when the host gives no params for the page" do
    ReactiveAdmin.config.doctor_page_params = ->(_) {}

    expect(row[:mode]).to eq("iframe")
  end

  it "renders without params when unset" do
    expect(row[:mode]).to eq("iframe")
  end
end
