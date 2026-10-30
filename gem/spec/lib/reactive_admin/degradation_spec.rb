RSpec.describe ReactiveAdmin::Degradation do
  def record(kind = "k", where: "index", reason: "r") = described_class.record(kind:, where:, reason:)

  def events
    [].tap do |seen|
      subscriber = ActiveSupport::Notifications.subscribe(described_class::EVENT) { |*, payload| seen << payload }
      yield
    ensure
      ActiveSupport::Notifications.unsubscribe(subscriber)
    end
  end

  it "takes its kind as a keyword only" do
    expect { described_class.record("k", reason: "r") }.to raise_error(ArgumentError)
  end

  it "collects entries only inside a collection" do
    record

    expect(described_class.entries).to eq([])
    described_class.with_collection { record("a") }
    expect(described_class.entries).to eq([])
  end

  it "dedupes identical entries and omits a missing where" do
    entries = described_class.with_collection do
      2.times { record("a") }
      record("b", where: nil)
      described_class.entries
    end

    expect(entries).to eq([{kind: "a", where: "index", reason: "r"}, {kind: "b", reason: "r"}])
  end

  it "collapses tallies into one entry with the count" do
    entries = described_class.with_collection(action: "show") do
      3.times { described_class.tally(kind: :html_fallback, where: described_class.where("div[0]"), reason: "%d elements shown as html") }
      described_class.entries
    end

    expect(entries).to eq([{kind: "html_fallback", where: "show/div[0]", reason: "3 elements shown as html"}])
  end

  it "attaches degraded only when there is something to report" do
    described_class.with_collection do
      expect(described_class.attach({a: 1})).to eq(a: 1)
      record("a")
      expect(described_class.attach({a: 1})).to eq(a: 1, degraded: [{kind: "a", where: "index", reason: "r"}])
    end
  end

  it "keeps each request's entries apart, including across threads" do
    seen = Queue.new
    threads = %w[one two].map do |name|
      Thread.new do
        described_class.with_collection do
          record(name)
          sleep 0.01
          seen << described_class.entries.pluck(:kind)
        end
      end
    end
    threads.each(&:join)

    expect(seen.size.times.map { seen.pop }).to contain_exactly(["one"], ["two"])
  end

  it "restores the outer collection after a nested one, and after an error" do
    described_class.with_collection do
      record("outer")
      described_class.with_collection { record("inner") }
      expect { described_class.with_collection { raise "boom" } }.to raise_error("boom")

      expect(described_class.entries.pluck(:kind)).to eq(["outer"])
    end
    expect(described_class.entries).to eq([])
  end

  it "publishes degraded.reactiveadmin per unique entry with resource and action" do
    seen = events do
      described_class.with_collection(resource: "posts", action: "index") do
        2.times { record("a", where: "index/column[x]") }
        described_class.tally(kind: :html_fallback, reason: "%d x")
      end
    end

    expect(seen).to eq([{resource: "posts", action: "index", kind: "a", where: "index/column[x]"},
      {resource: "posts", action: "index", kind: "html_fallback", where: nil}])
  end

  it "still publishes outside a collection, with no resource" do
    seen = events { record("a") }

    expect(seen).to eq([{resource: nil, action: nil, kind: "a", where: "index"}])
  end
end
