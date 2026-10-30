RSpec.describe "date input limits", type: :request do
  include_context "with a blog"

  before { sign_in admin }

  let(:fields) { api_get("/api/admin/rosters/new", schema: "FormResponse")["form"]["sections"].flat_map { it["fields"] || [] }.index_by { it["name"] } }

  it "passes `input_html: {min:, max:}` of a date picker as ISO days" do
    expect(fields["starts_on"]).to include("control" => "date", "input_html" => {"min" => "2026-01-01", "max" => "2026-12-31"})
  end

  it "reads the classic datepicker's `datepicker_options`" do
    expect(fields["signed_on"]).to include("control" => "date", "input_html" => {"min" => "2026-01-01", "max" => "2026-06-30"})
  end

  it "passes a datetime limit as an ISO time" do
    expect(fields["ends_at"]).to include("control" => "datetime", "input_html" => {"min" => "2026-03-01T09:00:00Z"})
  end

  it "leaves server-side validation to the app" do
    api(:post, "/api/admin/rosters", {roster: {name: "Team", starts_on: "2030-01-01"}})

    expect(response).to have_http_status(:created)
    expect(Roster.last.starts_on).to eq(Date.new(2030, 1, 1))
  end

  it "adds no input_html to a date without limits" do
    expect(fields_of(api_get("/api/admin/authors/new")["form"])["born_on"]).not_to have_key("input_html")
  end
end
