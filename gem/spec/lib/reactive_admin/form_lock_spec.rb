RSpec.describe ReactiveAdmin::FormLock do
  let(:ticket) { Ticket.create!(title: "Printer") }
  let(:note) { Note.create!(title: "Memo") }

  describe ".for" do
    it "uses lock_version when the model has one" do
      expect(described_class.for(ticket).as_json).to eq(field: "lock_version", value: "0")
    end

    it "falls back to updated_at with microseconds" do
      expect(described_class.for(note).as_json).to eq(field: "updated_at", value: note.updated_at.utc.iso8601(6))
    end

    it "is nil for a record that isn't saved" do
      expect(described_class.for(Note.new)).to be_nil
    end
  end

  describe "#matches?" do
    it "accepts the token it handed out, as an object or a bare value" do
      lock = described_class.for(note)

      expect(lock.matches?(lock.as_json.stringify_keys)).to be(true)
      expect(lock.matches?(ActionController::Parameters.new(lock.as_json))).to be(true)
      expect(lock.matches?(lock.value)).to be(true)
    end

    it "rejects another value, another field and garbage" do
      lock = described_class.for(note)

      expect(lock.matches?("value" => (note.updated_at + 1).utc.iso8601(6))).to be(false)
      expect(lock.matches?("field" => "lock_version", "value" => lock.value)).to be(false)
      expect(lock.matches?("not a time")).to be(false)
    end

    it "compares lock_version exactly" do
      lock = described_class.for(ticket)
      ticket.update!(title: "Scanner")

      expect(lock.matches?("0")).to be(false)
      expect(described_class.for(ticket).matches?("1")).to be(true)
    end
  end
end
