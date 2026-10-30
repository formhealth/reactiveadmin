RSpec.describe ReactiveAdmin::RansackGuard do
  let(:config) { ReactiveAdmin::Registry.find("posts") }

  def violation(query) = described_class.violation(config, query)

  it "allows the predicates of declared filters" do
    expect(violation({"title_cont" => "x", "views_count_gt" => "1", "published_at_gteq" => "2026-01-01", "featured_eq" => "true"})).to be_nil
  end

  it "allows the names AA's association filters search on" do
    expect(violation({"author_id_eq" => "1", "category_id_eq" => "1", "tags_id_eq" => "1", "tags_id_in" => ["1"]})).to be_nil
  end

  it "names the first key no declared filter explains" do
    expect(violation({"title_cont" => "x", "body_cont" => "y", "views_count_gt" => "1"})).to eq("body_cont")
  end

  it "rejects association traversals that would probe other tables" do
    expect(violation({"author_email_cont" => "x"})).to eq("author_email_cont")
    expect(violation({"comments_body_cont" => "x"})).to eq("comments_body_cont")
  end

  it "rejects sorts and groupings smuggled through q" do
    expect(violation({"s" => "title asc"})).to eq("s")
    expect(violation({"g" => [{"m" => "or"}]})).to eq("g")
  end

  it "rejects a query that is not a hash" do
    expect(violation("oops")).to eq("q")
  end

  it "has nothing to allow on a resource without that attribute" do
    authors = ReactiveAdmin::Registry.find("authors")

    expect(described_class.violation(authors, {"views_count_gt" => "1"})).to eq("views_count_gt")
  end
end
