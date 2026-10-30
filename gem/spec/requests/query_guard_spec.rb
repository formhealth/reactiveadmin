require "csv"

RSpec.describe "query guard", type: :request do
  include_context "with a blog"

  def list(params = nil, path = "/api/admin/posts") = api_get(path, params)

  def with_config(**settings)
    old = settings.keys.to_h { [it, ReactiveAdmin.config.public_send(it)] }
    settings.each { |key, value| ReactiveAdmin.config.public_send(:"#{key}=", value) }
    yield
  ensure
    old.each { |key, value| ReactiveAdmin.config.public_send(:"#{key}=", value) }
  end

  before { sign_in admin }

  describe "per_page" do
    it "clamps a request for more than the cap" do
      list(per_page: 50_000)

      expect(response).to have_http_status(:ok)
      expect(json["meta"]["per_page"]).to eq(100)
    end

    it "clamps to the configured cap" do
      with_config(max_per_page: 2) { list(per_page: 50) }

      expect(json["meta"]["per_page"]).to eq(2)
      expect(json["rows"].size).to eq(2)
    end

    it "honours a size within the cap" do
      list(per_page: 25)

      expect(json["meta"]["per_page"]).to eq(25)
    end

    it "uses the default for anything that isn't a positive integer" do
      ["abc", "0", "-5", "1e3", "", "0x10", "2.5"].each do |value|
        list(per_page: value)

        expect(json["meta"]["per_page"]).to eq(10), "per_page=#{value.inspect}"
      end
    end

    it "caps the page of a resource that declares per_page sizes above the host cap" do
      with_config(max_per_page: 5) do
        list({per_page: 15}, "/api/admin/tags")

        expect(json["meta"]["per_page"]).to eq(15)
      end
    end
  end

  describe "order" do
    it "sorts by a displayed sortable column" do
      list(order: "title_asc")

      expect(response).to have_http_status(:ok)
    end

    it "sorts by the sort_key of a column" do
      list(order: "views_count_desc")

      expect(response).to have_http_status(:ok)
    end

    it "rejects a real column the index doesn't show, naming only the key" do
      list(order: "body_asc")

      expect(response).to have_http_status(:bad_request)
      expect(json).to include("code" => "invalid", "message" => "Unsupported sort: body")
    end

    it "rejects a column that doesn't exist instead of failing in SQL" do
      list(order: "nope_desc")

      expect(response).to have_http_status(:bad_request)
      expect(json["message"]).to eq("Unsupported sort: nope")
    end

    it "rejects an order that isn't a column and direction" do
      list(order: "title; drop table posts")

      expect(response).to have_http_status(:bad_request)
      expect(json["code"]).to eq("invalid")
    end

    it "rejects the sort key of a column that isn't sortable" do
      list(order: "link_asc")

      expect(response).to have_http_status(:bad_request)
    end

    it "keeps the default order without a param" do
      list

      expect(response).to have_http_status(:ok)
      expect(json["meta"]["order"]).to eq("id_desc")
    end

    context "with a custom order_by clause" do
      let(:notes) { "/api/admin/notes" }

      before do
        Note.create!(title: "Longer title", body: "x")
        Note.create!(title: "Hi", body: "y")
      end

      it "sorts by the clause of a displayed column" do
        list({order: "title_length_asc"}, notes)

        expect(response).to have_http_status(:ok)
        expect(json["rows"].map { it["cells"]["title"]["text"] }).to eq(["Hi", "Longer title"])
      end

      it "still rejects hidden columns" do
        list({order: "body_asc"}, notes)

        expect(response).to have_http_status(:bad_request)
      end

      it "always allows the resource's default order, shown or not" do
        list({order: "id_desc"}, notes)

        expect(response).to have_http_status(:ok)
      end

      it "doesn't extend the default order to its other direction" do
        list({order: "id_asc"}, notes)

        expect(response).to have_http_status(:bad_request)
      end
    end
  end

  describe "exports" do
    def table = CSV.parse(response.body.delete_prefix("﻿"), headers: true)

    def export(params = nil) = api_get("/api/admin/posts.csv", params)

    it "rejects a hidden sort column" do
      export(order: "body_asc")

      expect(response).to have_http_status(:bad_request)
      expect(json).to include("code" => "invalid", "message" => "Unsupported sort: body")
    end

    it "refuses more rows than the limit, before streaming" do
      with_config(max_export_rows: 2) { export }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.media_type).to eq("application/json")
      expect(json).to include("code" => "invalid", "message" => "Narrow your filters to export fewer than 2 rows")
    end

    it "exports exactly the limit" do
      with_config(max_export_rows: 3) { export }

      expect(response).to have_http_status(:ok)
      expect(table.size).to eq(3)
    end

    it "counts the filtered rows, so narrowing works" do
      with_config(max_export_rows: 2) { export(q: {author_id_eq: alice.id}, scope: "published") }

      expect(response).to have_http_status(:ok)
      expect(table["Title"]).to eq(["Hello world"])
    end

    it "has no limit when turned off" do
      with_config(max_export_rows: nil) { export }

      expect(table.size).to eq(3)
    end

    describe "audit event" do
      let(:events) { [] }

      before { @subscriber = ActiveSupport::Notifications.subscribe("export.reactiveadmin") { |*, payload| events << payload } }

      after { ActiveSupport::Notifications.unsubscribe(@subscriber) }

      it "reports who exported what, with filter keys but never values" do
        export(q: {author_id_eq: alice.id, title_cont: "Hello"}, scope: "published")

        expect(events).to contain_exactly(resource: "posts", user_id: admin.id, filters: %w[author_id_eq title_cont], scope: "published", row_count: 1)
        expect(events.to_s).not_to include("Hello")
      end

      it "stays silent for a refused export" do
        with_config(max_export_rows: 1) { export }

        expect(events).to be_empty
      end
    end
  end
end
