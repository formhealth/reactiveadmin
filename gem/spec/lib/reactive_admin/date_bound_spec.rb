RSpec.describe ReactiveAdmin::DateBound do
  include ActiveSupport::Testing::TimeHelpers

  around { |example| travel_to(Time.utc(2026, 10, 16, 12)) { example.run } }

  def day(value) = described_class.call(value, "date")

  def instant(value) = described_class.call(value, "datetime")

  it "takes a Date, a Time and an ISO string" do
    expect(day(Date.new(2026, 1, 2))).to eq("2026-01-02")
    expect(day(Time.utc(2026, 1, 2, 23))).to eq("2026-01-02")
    expect(day("2026-01-02")).to eq("2026-01-02")
    expect(instant(Time.utc(2026, 1, 2, 9))).to eq("2026-01-02T09:00:00Z")
    expect(instant("2026-01-02")).to eq("2026-01-02T00:00:00Z")
  end

  it "counts a number as days from today, as the classic datepicker does" do
    expect(day(0)).to eq("2026-10-16")
    expect(day(-3)).to eq("2026-10-13")
    expect(day(7)).to eq("2026-10-23")
  end

  it "reads relative strings" do
    expect(day("+1m +7d")).to eq("2026-11-23")
    expect(day("-1y")).to eq("2025-10-16")
    expect(day("+2w")).to eq("2026-10-30")
    expect(day("+1M")).to eq("2026-11-16")
  end

  it "ignores what it can't read" do
    expect([day("soon"), day(nil), day(""), day(Object.new), day("2026-13-45")]).to all(be_nil)
  end
end
