RSpec.describe ReactiveAdmin::Mcp::Output do
  let(:row) { {id: "1", label: "x" * 100} }

  it "renders compact JSON when it fits" do
    expect(described_class.render({a: 1}, limit: 100)).to eq('{"a":1}')
  end

  it "clips long strings and says how much was cut" do
    json = JSON.parse(described_class.render({note: "n" * 1_500}, limit: 5_000))

    expect(json["note"]).to end_with("... [500 more characters cut]")
    expect(json["note"].length).to be < 1_100
  end

  it "trims rows until the result fits, and says so" do
    payload = {records: Array.new(10) { row }}
    json = JSON.parse(described_class.render(payload, limit: 800, rows: :records))

    expect(json["records"].size).to be_between(1, 9)
    expect(json["truncated"]).to match(/Showing #{json["records"].size} of 10 records .*smaller per_page/)
    expect(json.to_json.bytesize).to be <= 800
  end

  it "cuts text to the room left, and says so" do
    json = JSON.parse(described_class.render({id: "1", sections: "line\n" * 900}, limit: 1_000, text: :sections))

    expect(json["sections"].bytesize).to be < 800
    expect(json["truncated"]).to match(/sections cut at \d+ bytes of 4500/)
  end

  it "doesn't clip the text it was told to fit as a whole" do
    json = JSON.parse(described_class.render({sections: "line\n" * 400}, limit: 5_000, text: :sections))

    expect(json["sections"].length).to eq(2_000)
    expect(json).not_to include("truncated")
  end

  it "hard-cuts what nothing above can trim, naming the limit" do
    result = described_class.render({a: Array.new(200) { |i| {n: i} }}, limit: 300)

    expect(result.lines.last).to eq("[truncated at 300 bytes: narrow the request]")
    expect(result.bytesize).to be < 400
  end

  it "leaves a result that fits alone even when asked to trim" do
    expect(JSON.parse(described_class.render({records: [row]}, limit: 5_000, rows: :records))).to eq("records" => [{"id" => "1", "label" => row[:label]}])
  end
end
