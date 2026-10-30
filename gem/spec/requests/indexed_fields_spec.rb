RSpec.describe "repeated fields_for groups", type: :request do
  include_context "with a blog"

  before { sign_in admin }

  let(:contacts) { {"0" => {"email" => "a@example.com", "role" => "primary"}, "1" => {"email" => "b@example.com", "role" => "backup"}, "2" => {"email" => "c@example.com", "role" => "primary"}} }

  def api_fields(path) = api_get("/api#{path}", schema: "FormResponse")["form"]["sections"].flat_map { it["fields"] || [] }

  def classic_names(path)
    get path
    Nokogiri::HTML(response.body).css("#main_content form input, #main_content form select, #main_content form textarea").filter_map { it["name"] }
      .grep(/\Aroster\[/)
  end

  def nest(flat) = Rack::Utils.parse_nested_query(flat.map { |name, value| "#{CGI.escape(name)}=#{CGI.escape(value)}" }.join("&"))

  it "names every row's fields as classic does" do
    params = api_fields("/admin/rosters/new").pluck("param").compact

    expect(params).to eq(classic_names("/admin/rosters/new"))
    expect(params).to include("roster[contacts][0][email]", "roster[contacts][2][role]", "roster[backups][1][email]")
  end

  it "keeps `name][i` hacks working" do
    expect(api_fields("/admin/rosters/new").pluck("param")).to include("roster[backups][0][email]", "roster[backups][1][email]")
  end

  it "prefills each row from its own record" do
    roster = Roster.create!(name: "Team", contacts:, backups: {"1" => {"email" => "z@example.com"}})
    fields = api_fields("/admin/rosters/#{roster.id}/edit").index_by { it["param"] }

    expect(contacts.keys.map { fields["roster[contacts][#{it}][email]"]["value"] }).to eq(%w[a@example.com b@example.com c@example.com])
    expect(fields["roster[contacts][1][role]"]).to include("value" => "backup", "control" => "select")
    expect(fields["roster[backups][1][email]"]["value"]).to eq("z@example.com")
    expect(fields).not_to include("roster[contacts][email]")
  end

  describe "submitting" do
    let(:values) do
      {"roster[name]" => "Team", "roster[backups][0][email]" => "x@example.com", "roster[backups][0][role]" => "ignored",
       **contacts.flat_map { |i, row| row.map { |key, value| ["roster[contacts][#{i}][#{key}]", value] } }.to_h}
    end

    it "stores what a classic form post stores" do
      expect(api_fields("/admin/rosters/new").pluck("param")).to include(*values.keys)
      post "/admin/rosters", params: nest(values.except("roster[backups][0][role]"))
      classic = Roster.last
      Roster.delete_all

      api(:post, "/api/admin/rosters", nest(values))

      expect(response).to have_http_status(:created)
      expect(Roster.last.attributes.slice("name", "contacts", "backups")).to eq(classic.attributes.slice("name", "contacts", "backups"))
      expect(Roster.last.contacts).to eq(contacts)
    end

    it "drops a disabled field of an indexed row" do
      api(:post, "/api/admin/rosters", nest(values))

      expect(Roster.last.backups).to eq("0" => {"email" => "x@example.com"})
    end

    it "stores a blank for a null in an indexed row, as classic's empty input posts" do
      api(:post, "/api/admin/rosters", {roster: {name: "Team", contacts: {"1" => {email: nil, role: "backup"}}}})

      expect(Roster.last.contacts).to eq("1" => {"email" => "", "role" => "backup"})
    end
  end
end
