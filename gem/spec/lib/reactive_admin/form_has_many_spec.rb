RSpec.describe ReactiveAdmin::FormHasMany do
  describe "heading" do
    let(:single) { [{control: "typeahead", label: "Admin policy"}, {control: "hidden", label: "Id"}] }
    let(:several) { [{control: "text", label: "Body"}, {control: "boolean", label: "Approved"}] }

    def heading(options, layout, template)
      has_many = described_class.allocate
      has_many.instance_variable_set(:@klass, Comment)
      has_many.instance_variable_set(:@options, options)
      has_many.send(:heading, layout, template)
    end

    it "names a compact list for its one control, pluralized" do
      expect(heading({}, "compact", single)).to eq("Admin policies")
    end

    it "names other lists for the association's model" do
      expect(heading({}, "cards", single)).to eq("Comments")
      expect(heading({}, "compact", several)).to eq("Comments")
    end

    it "prefers the host's heading, and has none when told so" do
      expect(heading({heading: "Policies"}, "compact", single)).to eq("Policies")
      expect(heading({heading: false}, "compact", single)).to be_nil
    end
  end
end
