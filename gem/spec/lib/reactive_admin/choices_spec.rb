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

  describe ".cache_key" do
    it "varies by user, even for users whose fingerprints match" do
      original = ReactiveAdmin.config.meta_cache_key
      ReactiveAdmin.config.meta_cache_key = ->(user) { user.role }
      config = ReactiveAdmin::Registry.find("posts")
      other = create_editor(author: bob, email: "other-editor@example.com")
      sample = ->(user) { ReactiveAdmin::Doctor::Sample.new(config, user).view }
      key = ->(user) { described_class.cache_key(config, "filter", "category", sample.call(user)) }

      expect(ReactiveAdmin.user_fingerprint(sample.call(editor).controller)).to eq(ReactiveAdmin.user_fingerprint(sample.call(other).controller))
      expect(key.call(editor)).not_to eq(key.call(other))
    ensure
      ReactiveAdmin.config.meta_cache_key = original
    end
  end

  describe ".column" do
    def values_for(user, relation = Post.all, column = "views_count")
      view.controller.define_singleton_method(:current_admin_user) { user }
      described_class.column(relation, column, view).list([], 10)[:options].pluck(:value)
    end

    it "offers the distinct values of a plain column" do
      expect(values_for(admin)).to eq(%w[0 3 1200])
    end

    it "offers only the values of rows the user may read" do
      expect(values_for(editor)).to eq(Post.all.select { can_see_post?(editor, it) }.map(&:views_count).uniq.sort.map(&:to_s))
    end

    it "keeps the order of a bounded relation so the limit picks the same rows" do
      expect(values_for(admin, Post.order(:views_count).limit(1))).to eq(%w[0])
      expect(values_for(admin, Post.order(views_count: :desc).limit(1).offset(1))).to eq(%w[3])
    end

    it "keeps the order of a bounded relation with a composite key" do
      StockLevel.create!(warehouse: "A", sku: "z", quantity: 1)
      StockLevel.create!(warehouse: "A", sku: "a", quantity: 9)

      expect(values_for(admin, StockLevel.order(sku: :desc).limit(1), "quantity")).to eq(%w[1])
    end

    it "keeps the order of a bounded distinct relation" do
      expect(values_for(admin, Post.distinct.select(:id, :views_count).order(:views_count).limit(1))).to eq(%w[0])
    end

    it "keeps the order of a bounded distinct relation with a composite key" do
      StockLevel.create!(warehouse: "A", sku: "z", quantity: 1)
      StockLevel.create!(warehouse: "A", sku: "a", quantity: 9)

      expect(values_for(admin, StockLevel.distinct.select(:warehouse, :sku, :quantity).order(:sku).limit(1), "quantity")).to eq(%w[9])
    end

    it "keeps the joins an unbounded composite-key relation needs" do
      stock = Class.new(StockLevel) do
        self.table_name = "stock_levels"
        has_many :matches, class_name: "Post", primary_key: :warehouse, foreign_key: :title
        def self.name = "StockLevel"
      end
      StockLevel.create!(warehouse: "Hello world", sku: "a", quantity: 4)
      StockLevel.create!(warehouse: "Nope", sku: "b", quantity: 5)
      relation = stock.includes(:matches).where(posts: {title: "Hello world"})

      expect(values_for(admin, relation, "quantity")).to eq(%w[4])
    end

    it "keeps a bounded distinct relation's rows when its projection omits the column" do
      relation = Post.distinct.select(:id, :title).order(:title).limit(1)

      expect(values_for(admin, relation)).to eq([Post.order(:title).first.views_count.to_s])
    end

    it "keeps a bounded distinct composite-key relation's rows when its projection omits the column" do
      StockLevel.create!(warehouse: "A", sku: "z", quantity: 1)
      StockLevel.create!(warehouse: "A", sku: "a", quantity: 9)

      expect(values_for(admin, StockLevel.distinct.select(:warehouse, :sku).order(:sku).limit(1), "quantity")).to eq(%w[9])
    end

    it "offers nothing for a bounded distinct relation that projects neither the column nor its key" do
      relation = Post.where(id: Post.order(:title).first.id).select(:title).distinct.order(:title).limit(1)

      expect(values_for(admin, relation)).to eq([])
    end

    it "offers nothing for a bounded distinct composite-key relation missing part of its key" do
      StockLevel.create!(warehouse: "A", sku: "a", quantity: 9)

      expect(values_for(admin, StockLevel.where(sku: "a").distinct.select(:sku).order(:sku).limit(1), "quantity")).to eq([])
    end

    it "recognizes qualified projections of the key" do
      ["posts.id", '"posts"."id"', Post.arel_table[:id]].each do |key|
        relation = Post.distinct.select(key, :title).order(:title).limit(1)

        expect(values_for(admin, relation)).to eq([Post.order(:title).first.views_count.to_s])
      end
    end

    it "recognizes a qualified projection of the column" do
      relation = Post.distinct.select('"posts"."views_count"', "posts.title").order(:title).limit(1)

      expect(values_for(admin, relation)).to eq([Post.order(:title).first.views_count.to_s])
    end

    it "recognizes the columns of a comma-separated string projection" do
      relation = Post.distinct.select("posts.id, posts.title").order(:title).limit(1)

      expect(values_for(admin, relation)).to eq([Post.order(:title).first.views_count.to_s])
    end

    it "offers nothing when the key only appears inside an expression" do
      [
        ["COALESCE(NULL, posts.id, NULL) AS chosen_id", :title],
        ["COALESCE(NULL, posts.id, NULL) AS chosen_id, title"],
        ["title AS id", :title],
        ["posts.id AS views_count, posts.title"],
        ["'prefix,id,suffix' AS note", :title],
        ["'it''s,id,here' AS note", :title],
        ['"a,id" AS note', :title]
      ].each do |select|
        expect(values_for(admin, Post.distinct.select(*select).order(:title).limit(1))).to eq([])
      end
    end

    it "keeps the alias a bounded relation orders by" do
      relation = Post.select("posts.*, LENGTH(title) AS title_length").order("title_length DESC").limit(1)

      expect(values_for(admin, relation)).to eq([Post.all.max_by { it.title.length }.views_count.to_s])
    end

    it "recognizes a wildcard beside expressions in one string, so the column isn't projected twice" do
      relation = Post.select("posts.*, LENGTH(title) AS title_length").order("title_length DESC").limit(1)

      expect(described_class.projecting?(relation, "views_count")).to be true
      expect(described_class.projecting?(Post.select("COALESCE(NULL, posts.*) AS x, title"), "views_count")).to be false
    end

    it "offers nothing when an expression's alias shadows the key" do
      relation = Post.distinct.select("posts.author_id AS id", :id, :title).order(:title).limit(1)

      expect(values_for(admin, relation)).to eq([])
    end

    it "adds the column to a bounded projection that omits it, keeping the ordering alias" do
      relation = Post.select(:id, "LENGTH(title) AS title_length").order("title_length DESC").limit(1)

      expect(values_for(admin, relation)).to eq([Post.all.max_by { it.title.length }.views_count.to_s])
    end

    context "with single-table inheritance" do
      let(:vehicle) { Class.new(ApplicationRecord) { self.table_name = "vehicles" } }
      let(:car) { Class.new(vehicle) { def self.name = "Car" } }
      let(:bike) { Class.new(vehicle) { def self.name = "Bike" } }

      before do
        ActiveRecord::Base.connection.create_table(:vehicles, force: true) do |t|
          t.string :type
          t.integer :wheels
        end
        stub_const("Vehicle", vehicle)
        stub_const("Car", car)
        stub_const("Bike", bike)
        Car.create!(wheels: 4)
        Bike.create!(wheels: 2)
      end

      after { ActiveRecord::Base.connection.drop_table(:vehicles, if_exists: true) }

      it "reads a subtype's column through a derived table without the type column" do
        expect(values_for(admin, Car.all, "wheels")).to eq(%w[4])
      end

      it "rejoins a bounded distinct subtype relation that omits the type column" do
        relation = Car.distinct.select(:id).order(:id).limit(1)

        expect(values_for(admin, relation, "wheels")).to eq(%w[4])
      end
    end

    it "does not take another table's key for its own" do
      relation = Post.joins(:author).distinct.select("authors.id", :title).order(:title).limit(1)

      expect(values_for(admin, relation)).to eq([])
    end

    it "searches only the option column" do
      user = admin
      view.controller.define_singleton_method(:current_admin_user) { user }
      options = ->(column, term) { described_class.column(Post.all, column, view).search(term, 10)[:options].pluck(:value) }

      expect(options.call("views_count", "1200")).to eq(%w[1200])
      expect(options.call("views_count", "5")).to eq([])
      expect(options.call("title", "123")).to eq([])
      expect(options.call("title", Post.first.title[0, 3])).to include(Post.first.title)
    end

    it "replaces a projection on the relation" do
      expect(values_for(admin, Post.select(:id, :title))).to eq(%w[0 3 1200])
    end
  end
end
