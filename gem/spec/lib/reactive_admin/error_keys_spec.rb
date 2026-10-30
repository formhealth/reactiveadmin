RSpec.describe ReactiveAdmin::ErrorKeys do
  def field(name, attribute = name) = {name:, param: "override[#{attribute}]"}

  def keys(errors, *fields) = described_class.call(errors, [{kind: "inputs", fields:}])

  it "keeps keys that are already a field name" do
    expect(keys({title: ["can't be blank"]}, field("title"))).to eq("title" => ["can't be blank"])
  end

  it "maps the association and its foreign key to the field posting the foreign key" do
    result = keys({category: ["must exist"], category_id: ["has already been taken"]},
      field("category", "category_id"))

    expect(result).to eq("category" => ["must exist", "has already been taken"])
  end

  it "maps the association to a field named for the foreign key" do
    expect(keys({author: ["must exist"]}, field("author_id"))).to eq("author_id" => ["must exist"])
  end

  it "merges duplicate messages once" do
    expect(keys({author: ["must exist"], author_id: ["must exist"]}, field("author", "author_id"))).to eq("author" => ["must exist"])
  end

  it "keeps keys no field posts, and nested row keys" do
    expect(keys({"notes.body": ["is bad"], slug: ["is taken"]}, field("title"))).to eq("notes.body" => ["is bad"], "slug" => ["is taken"])
  end

  it "prefers an exact field name over an alias" do
    result = keys({author: ["a"], author_id: ["b"]}, field("author", "author_id"), field("author_id"))

    expect(result).to eq("author" => ["a"], "author_id" => ["b"])
  end
end
