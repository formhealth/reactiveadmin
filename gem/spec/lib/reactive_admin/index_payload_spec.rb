RSpec.describe ReactiveAdmin::IndexPayload do
  include_context "with a blog"

  def declared(key) = described_class.new(ReactiveAdmin::Doctor::Sample.new(ReactiveAdmin::Registry.find(key), admin).controller).declared_columns

  it "lists an index block's columns with the attribute each shows, without reading rows" do
    queries = []
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") { |*, payload| queries << payload[:sql] unless payload[:name] == "SCHEMA" }
    columns = declared("posts")
    ActiveSupport::Notifications.unsubscribe(subscriber)

    expect(columns.map { |column, attribute| [column[:key], attribute] }).to include(["id", "id"], ["title", "title"], ["status", nil], ["published_at", "published_at"])
    expect(columns.find { |column, _| column[:key] == "views" }.first).to include(sortable: true, sort_key: "views_count")
    expect(queries.grep(/FROM "posts"/)).to eq([])
  end

  it "falls back to the secure default columns without a block" do
    attributes = declared("scans").map(&:last)

    expect(attributes).to include("title")
    expect(attributes).not_to include("image")
  end
end
