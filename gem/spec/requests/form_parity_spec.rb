# The API form exposes the controls classic renders, under the same param names.
RSpec.describe "form field parity with classic", type: :request do
  include_context "with a blog"

  # `article[title]`, `article[tags][]` and `article[born_on(1i)]` all name the attribute once.
  def classic_attrs(path, param_key)
    get path
    expect(response).to have_http_status(:ok)
    Nokogiri::HTML(response.body).css("#main_content form input, #main_content form select, #main_content form textarea")
      .filter_map { it["name"].to_s[/\A#{Regexp.escape(param_key)}\[(\w+?)(?:\(\di\))?\]/, 1] }.uniq.sort
  end

  def api_sections(path) = api_get("/api#{path}", schema: "FormResponse")["form"]["sections"]

  def api_attrs(sections, param_key)
    sections.flat_map { |section| section["fields"]&.pluck("param") || [section["param"]] }
      .filter_map { it.to_s[/\A#{Regexp.escape(param_key)}\[(\w+)\]/, 1] }.uniq.sort
  end

  def expect_same_fields(path, param_key)
    classic = classic_attrs(path, param_key)
    api = api_attrs(api_sections(path), param_key)
    expect([classic - api, api - classic]).to eq([[], []])
  end

  describe "inputs chosen by the signed-in user" do
    it "records the branch classic renders for an admin" do
      sign_in admin

      expect_same_fields("/admin/articles/new", "article")
      attrs = api_attrs(api_sections("/admin/articles/new"), "article")
      expect(attrs).to include("views_count")
      expect(attrs).not_to include("featured")
    end

    it "records the other branch for an editor" do
      sign_in editor

      expect_same_fields("/admin/articles/new", "article")
      attrs = api_attrs(api_sections("/admin/articles/new"), "article")
      expect(attrs).to include("featured")
      expect(attrs).not_to include("views_count")
    end
  end

  describe "a hidden association input" do
    before { sign_in admin }

    it "posts under the association name, as Formtastic's hidden input does" do
      field = fields_of({"sections" => api_sections("/admin/articles/new")})["author"]

      expect(field).to include("control" => "hidden", "param" => "article[author]")
    end
  end

  describe "has_many with heading: true" do
    before { sign_in admin }

    it "has a string or null title on every section, like classic's empty heading" do
      sections = api_sections("/admin/articles/new")

      expect(sections.pluck("title")).to all(satisfy { it.nil? || it.is_a?(String) })
      expect(sections.last).to include("kind" => "has_many", "name" => "comments")
      expect(sections.last["title"]).to be_nil
    end
  end

  describe "a form partial" do
    before { sign_in admin }

    it "exposes the inputs the partial renders" do
      expect_same_fields("/admin/sketches/new", "sketch")
      fields = fields_of({"sections" => api_sections("/admin/sketches/new")})

      expect(fields["title"]).to include("control" => "select", "param" => "sketch[title]")
      expect(fields["title"]["options"].pluck("value")).to eq(%w[Alpha Beta])
      expect(fields["weight"]).to include("control" => "number", "param" => "sketch[weight]")
    end

    it "keeps the html around the inputs" do
      html = api_sections("/admin/sketches/new").flat_map { it["fields"] }.select { it["control"] == "html" }

      expect(html.pluck("value").join).to include("Sketches are shared drafts.")
    end

    it "carries the record's values on edit" do
      sketch = Sketch.create!(title: "Alpha")
      api_get("/api/admin/sketches/#{sketch.id}/edit", schema: "FormResponse")

      expect(fields_of(json["form"])["title"]["value"]).to eq("Alpha")
    end
  end
end
