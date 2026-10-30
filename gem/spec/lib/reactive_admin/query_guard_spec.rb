RSpec.describe ReactiveAdmin::QueryGuard do
  let(:config) { Struct.new(:paginate, :max_per_page, :sort_order, :order_clause).new(true, 10_000, "id_desc", ActiveAdmin::OrderClause) }

  describe ".per_page_cap" do
    it "is the host cap" do
      expect(described_class.per_page_cap(config)).to eq(100)
    end

    it "grows to the sizes the resource offers" do
      expect(described_class.per_page_cap(config, [25, 250])).to eq(250)
    end

    it "never exceeds the resource's own max_per_page" do
      config.max_per_page = 50

      expect(described_class.per_page_cap(config, [25, 250])).to eq(50)
    end

    it "keeps the resource's max_per_page when pagination is off" do
      config.paginate = false

      expect(described_class.per_page_cap(config)).to eq(10_000)
    end
  end

  describe ".per_page" do
    it "clamps to the cap" do
      expect(described_class.per_page(config, "50000", 30)).to eq(100)
    end

    it "falls back for anything but a positive integer" do
      expect(%w[abc 0 -1 1.5 0x10] << nil << "").to all(satisfy { described_class.per_page(config, it, 30) == 30 })
    end

    it "clamps the fallback too" do
      expect(described_class.per_page(config, nil, 500)).to eq(100)
    end
  end

  describe ".order_violation" do
    def violation(order, keys = %w[title]) = described_class.order_violation(config, order, keys)

    it "accepts offered keys in both directions and the default order" do
      expect([violation("title_asc"), violation("title_desc"), violation("id_desc"), violation(nil)]).to all(be_nil)
    end

    it "names only the key of anything else" do
      expect(violation("body_asc")).to eq("body")
      expect(violation("id_asc")).to eq("id")
    end

    it "accepts qualified keys and names them whole" do
      expect(violation("posts.title_asc", %w[posts.title])).to be_nil
      expect(violation("posts.body_asc", %w[posts.title])).to eq("posts.body")
    end

    it "bounds the length of an echoed key" do
      expect(violation("#{"x" * 500}!").size).to eq(described_class::MAX_KEY_LENGTH)
    end
  end
end
