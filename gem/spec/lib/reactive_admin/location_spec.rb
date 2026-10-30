RSpec.describe ReactiveAdmin::Location do
  def locate(url) = described_class.for(url, host: "www.example.com")

  it "resolves a show page to a resource reference" do
    expect(locate("http://www.example.com/admin/posts/4")).to eq(url: "/admin/posts/4", resource: "posts", id: "4", view: "show")
  end

  it "resolves index, new and edit pages" do
    expect(locate("/admin/posts")).to eq(url: "/admin/posts", resource: "posts", view: "index")
    expect(locate("/admin/posts/new")).to include(view: "new")
    expect(locate("/admin/posts/4/edit")).to include(view: "edit", id: "4")
  end

  it "keeps the query in the url" do
    expect(locate("/admin/posts?scope=draft")).to include(url: "/admin/posts?scope=draft", resource: "posts")
  end

  it "resolves nested resources" do
    expect(locate("/admin/posts/1/comments/9")).to include(resource: "comments", id: "9", view: "show")
  end

  it "keeps the path of routes that are not resource pages" do
    expect(locate("/admin/posts/4/publish")).to eq(url: "/admin/posts/4/publish")
    expect(locate("/admin/dashboard")).to eq(url: "/admin/dashboard")
    expect(locate("/somewhere")).to eq(url: "/somewhere")
  end

  it "leaves other hosts untouched" do
    expect(locate("https://other.test/admin/posts/4")).to eq(url: "https://other.test/admin/posts/4")
  end

  it "survives malformed urls" do
    expect(locate("http://bad host/")).to eq(url: "http://bad host/")
  end
end
