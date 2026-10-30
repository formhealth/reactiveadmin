RSpec.describe ReactiveAdmin::RateLimit do
  around do |example|
    old = ReactiveAdmin.config.rate_limits
    ReactiveAdmin.config.rate_limits = {options: [2, 10.seconds], default: [1, 1.minute], open: nil}
    example.run
  ensure
    ReactiveAdmin.config.rate_limits = old
  end

  before { Rails.cache.clear }

  def hit(bucket, user = 1, now: 1_000) = described_class.retry_after(bucket, user, now:)

  it "returns the seconds left in the window once over budget" do
    expect([hit(:options), hit(:options)]).to all(be_nil)
    expect(hit(:options, now: 1_003)).to eq(7)
  end

  it "starts over in the next window" do
    3.times { hit(:options) }

    expect(hit(:options, now: 1_010)).to be_nil
  end

  it "keys by user and bucket" do
    3.times { hit(:options) }

    expect(hit(:options, 2)).to be_nil
    expect(hit(:value)).to be_nil
    expect(hit(:value)).to eq(20)
  end

  it "leaves a bucket set to nil unlimited, even with a default" do
    expect(Array.new(5) { hit(:open) }).to all(be_nil)
  end

  it "does nothing without a user or when off" do
    expect(Array.new(5) { hit(:options, nil) }).to all(be_nil)

    ReactiveAdmin.config.rate_limits = false
    expect(Rails.logger).not_to receive(:warn)
    expect(Array.new(5) { hit(:options) }).to all(be_nil)
  end
end
