RSpec.describe ReactiveAdmin::Doctor, "samples" do
  include_context "with a blog"

  def resource(key) = described_class.run(user: admin)[:resources].find { it[:key] == key }

  it "keeps a sampled form that can't be submitted apart from one that can" do
    expect(resource("doodles")[:form]).to include(submittable: false)
    expect(resource("notes")[:form]).not_to have_key(:submittable)
  end

  it "reports a show with no record as skipped, not as a render with nothing on it" do
    Note.delete_all
    expect(resource("notes")[:show]).to eq(skipped: "no record to show")

    Note.create!(title: "Alpha")
    expect(resource("notes")[:show]).to include(typed: be_positive, rows: 1)
  end

  it "marks the degraded events its samples publish as synthetic" do
    seen = []
    subscriber = ActiveSupport::Notifications.subscribe(ReactiveAdmin::Degradation::EVENT) { |*, payload| seen << payload }
    described_class.run(user: admin)

    expect(seen).not_to be_empty
    expect(seen).to all(include(synthetic: true))
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end

  describe "tallying a sample" do
    it "counts values that failed to render apart from typed ones" do
      tally = ReactiveAdmin::Doctor::Tally.nodes([{"type" => "text", "text" => "a"}, {"type" => "error", "label" => "Couldn't display this value"}, {"type" => "html"}, {"type" => "iframe", "src" => "/x"}])

      expect(tally).to eq(typed: 1, html: 1, errors: 1, frames: 1)
    end
  end
end
