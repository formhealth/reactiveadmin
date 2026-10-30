RSpec.describe "ransack guard on custom actions", type: :request do
  let!(:ticket) { Ticket.create!(title: "Printer jam") }
  let(:stats) { "/api/admin/posts/stats" }
  let(:lookup) { "/api/admin/tickets/#{ticket.id}/lookup" }

  before do
    ReactiveAdmin::RansackGuard.learned.clear
    Rails.cache.clear
    ReactiveAdmin::Ladder.reset!
    sign_in create_admin
  end

  it "rejects an undeclared q on a custom action" do
    api_get(stats, q: {body_cont: "x"})

    expect(response).to have_http_status(:bad_request)
    expect(json).to include("message" => "Unsupported filter: body_cont")
  end

  it "lets a custom action have the declared filters' q" do
    api_get(stats, q: {title_cont: "x"})

    expect(response).not_to have_http_status(:bad_request)
  end

  it "leaves an action the resource declares as owning q alone" do
    api_get("/api/admin/tickets/#{ticket.id}/find", q: {term: "printer"})

    expect(response).to have_http_status(:ok)
    expect(json).to eq("term" => "printer")
  end

  it "leaves an action the host config lists alone" do
    ReactiveAdmin.config.ransack_unguarded_actions = {posts: [:stats]}
    api_get(stats, q: {body_cont: "x"})

    expect(response).not_to have_http_status(:bad_request)
  ensure
    ReactiveAdmin.config.ransack_unguarded_actions = {}
  end

  describe "a search form the templates record" do
    it "rejects the submit while no recorded form posts q to the action" do
      api(:post, lookup, {q: {term: "Printer"}})

      expect(response).to have_http_status(:bad_request)
    end

    it "accepts it once rendering the form has recorded q fields posting there" do
      api_get(lookup, schema: "FormResponse")
      api(:post, lookup, {q: {term: "Printer"}}, schema: "FormResponse")

      expect(response).to have_http_status(:ok)
    end

    it "agrees across processes through the shared cache" do
      api_get(lookup, schema: "FormResponse")
      ReactiveAdmin::RansackGuard.learned.clear
      api(:post, lookup, {q: {term: "Printer"}}, schema: "FormResponse")

      expect(response).to have_http_status(:ok)
    end

    it "still guards the other actions of the resource" do
      api_get(lookup, schema: "FormResponse")
      api_get("/api/admin/tickets", q: {title_cont: "x", body_cont: "y"})

      expect(response).to have_http_status(:bad_request)
    end
  end
end
