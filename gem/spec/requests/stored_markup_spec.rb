RSpec.describe "stored markup in a show row", type: :request do
  let(:forged) do
    '<a href="/admin/articles/1" data-method="delete" data-confirm="Totally safe">Read more</a>' \
    '<form class="button_to" method="post" action="/admin/articles/1/publish"><input type="submit" value="Click to continue"></form>'
  end
  let(:article) { Article.create!(title: forged, author: Author.create!(name: "Ann", email: "ann@example.com")) }

  before { sign_in create_admin }

  def rows = nodes_of(json["layout"], "attributes_table").flat_map { it["rows"] }.to_h { [it["label"], it["value"]] }

  it "turns the DSL's control into an action and the stored markup into none" do
    api_get("/api/admin/articles/#{article.id}")

    expect(rows["Control"].pluck("type")).to eq(%w[action])
    expect(rows["Control"].first["action"]).to include("kind" => "destroy", "method" => "delete", "confirm" => "Remove it?")
    expect(rows["Stored"].to_json).not_to match(/Totally safe|Click to continue|"type":"(action|iframe)"/)
  end
end
