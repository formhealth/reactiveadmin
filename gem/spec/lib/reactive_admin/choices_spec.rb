RSpec.describe ReactiveAdmin::Choices do
  include_context "with a blog"

  let(:view) { ApplicationController.new.view_context.tap { it.extend(ActiveAdmin::ViewHelpers) } }

  describe "cursors" do
    it "round-trips offsets" do
      expect(described_class.decode_cursor(described_class.encode_cursor(40))).to eq(40)
    end

    it "treats garbage and negatives as the start" do
      expect(described_class.decode_cursor(nil)).to eq(0)
      expect(described_class.decode_cursor(Base64.urlsafe_encode64("-5"))).to eq(0)
      expect(described_class.decode_cursor(Base64.urlsafe_encode64("abc"))).to eq(0)
    end

    it "rejects an undecodable cursor as a bad request" do
      expect { described_class.decode_cursor("!!!") }.to raise_error(ReactiveAdmin::ApiErrors::BadRequest, "Invalid cursor")
    end
  end

  describe "Pairs" do
    let(:pairs) { described_class::Pairs.new([["Alpha", "a"], ["Beta Gamma", "b"], ["Delta", "d"]]) }

    it "lists everything when small, selection only when truncated" do
      expect(pairs.list([], 10)).to eq(options: [{label: "Alpha", value: "a"}, {label: "Beta Gamma", value: "b"}, {label: "Delta", value: "d"}], truncated: false)
      expect(pairs.list(["d"], 2)).to eq(options: [{label: "Delta", value: "d"}], truncated: true)
    end

    it "matches every token against label or value, case-insensitively" do
      expect(pairs.search("gam BET", 10)[:options].pluck(:value)).to eq(%w[b])
      expect(pairs.search("A", 10)[:options].pluck(:value)).to eq(%w[a b d])
    end

    it "pages with cursors" do
      first = pairs.search("", 2)
      second = pairs.search("", 2, first[:next_cursor])

      expect(first).to include(truncated: true)
      expect(first[:options].size).to eq(2)
      expect(second).to include(options: [{label: "Delta", value: "d"}], truncated: false)
      expect(second).not_to have_key(:next_cursor)
    end

    it "looks values up" do
      expect(pairs.lookup(%w[a d]).pluck(:label)).to eq(%w[Alpha Delta])
      expect(pairs.lookup(%w[zzz])).to eq([])
    end

    context "with hints" do
      let(:pairs) { described_class::Pairs.new([["Alpha", "a", "first letter"], ["Beta", "b"]]) }

      it "serves a hint where an entry has one" do
        expect(pairs.list([], 10)[:options]).to eq([{label: "Alpha", value: "a", hint: "first letter"}, {label: "Beta", value: "b"}])
        expect(pairs.lookup(%w[a]).first).to include(hint: "first letter")
      end

      it "searches the hint too" do
        expect(pairs.search("first", 10)[:options].pluck(:value)).to eq(%w[a])
      end

      it "leaves the hint out of the classic admin's pairs" do
        expect(pairs.pairs).to eq([%w[Alpha a], %w[Beta b]])
      end
    end

    it "unescapes html entities in labels" do
      expect(described_class.option("A &amp; B", 1)).to eq(label: "A & B", value: "1")
    end
  end

  describe ".for" do
    it "builds pairs from hashes, arrays and scalars" do
      expect(described_class.for({"A" => 1}, view).pairs).to eq([["A", 1]])
      expect(described_class.for([["A", 1], "b"], view).pairs).to eq([["A", 1], ["b", "b"]])
    end

    it "reads a hint from a third element or a hash entry" do
      entries = described_class.for([["A", 1, "one"], {label: "B", value: 2, hint: "two"}, {label: "C"}, "d"], view).entries

      expect(entries).to eq([["A", 1, "one"], ["B", 2, "two"], ["C", "C"], ["d", "d"]])
    end

    it "evaluates procs in the view" do
      expect(described_class.for(-> { [["x", 1]] }, view).pairs).to eq([["x", 1]])
    end

    it "keeps relations lazy as Records" do
      expect(described_class.for(Author.all, view)).to be_a(described_class::Records)
      expect(described_class.for(Author, view)).to be_a(described_class::Records)
    end

    it "caches non-relation lists under the given key" do
      calls = 0
      collection = -> { (calls += 1) && [["x", 1]] }

      2.times { described_class.for(collection, view, cache: "k") }

      expect(calls).to eq(1)
    end

    it "does not cache when options_cache_ttl is zero" do
      original = ReactiveAdmin.config.options_cache_ttl
      ReactiveAdmin.config.options_cache_ttl = 0
      calls = 0
      collection = -> { (calls += 1) && [["x", 1]] }

      2.times { described_class.for(collection, view, cache: "k2") }

      expect(calls).to eq(2)
    ensure
      ReactiveAdmin.config.options_cache_ttl = original
    end
  end

  describe "Records" do
    let(:records) { described_class.for(Author.all, view) }

    it "lists alphabetically and reports truncation" do
      expect(records.list([], 10)[:options].pluck(:label)).to eq(["Alice Author", "Bob Builder"])
      expect(records.list([bob.id.to_s], 1)).to eq(options: [{label: "Bob Builder", value: bob.id.to_s}], truncated: true)
    end

    it "looks up by value column" do
      expect(records.lookup([alice.id.to_s]).pluck(:label)).to eq(["Alice Author"])
      expect(records.lookup([])).to eq([])
    end

    it "offers the whole list as pairs for the classic admin" do
      expect(records.pairs).to eq([["Alice Author", alice.id], ["Bob Builder", bob.id]])
    end
  end

  describe ".source" do
    it "resolves a registered source and refines it with scope:" do
      source = described_class.source(:authors, view, scope: ->(relation) { relation.where(name: "Bob Builder") })

      expect(source.pairs).to eq([["Bob Builder", bob.id]])
    end

    it "fails loudly for an unknown source" do
      expect { described_class.source(:nope, view) }.to raise_error(KeyError, /unknown option source :nope/)
    end
  end

  describe ".column" do
    it "offers the distinct values of a plain column" do
      expect(described_class.column(Post, "views_count", view).list([], 10)[:options].pluck(:value)).to eq(%w[0 3 1200])
    end
  end
end
