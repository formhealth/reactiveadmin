RSpec.describe "forms in register_page content", type: :request do
  include_context "with a blog"

  before { sign_in admin }

  def forms(layout = json["layout"]) = nodes_of(layout, "form").pluck("form")

  describe "a page of Formtastic forms" do
    before { api_get("/api/admin/_pages/broadcasts", schema: "PageResponse") }

    it "renders each form as a native form node inside its panel, and the page as native" do
      expect(json["view"]).to include("mode" => "native", "presentation" => "page")
      expect(nodes_of(json["layout"], "frame")).to be_empty
      expect(json["layout"].map { it.values_at("type", "title") }).to eq([["panel", "Announce"], ["panel", "Quick note"]])
      expect(forms.pluck("resource")).to eq(%w[broadcasts broadcasts])
    end

    it "describes the partial's form: action, fields, params, submit button and its confirm" do
      form = forms.first

      expect(form).to include("action" => {"method" => "post", "path" => "/api/admin/broadcasts/announce"}, "submittable" => true,
        "submit_label" => "Send announcement", "submit_confirm" => "Send to everyone?")
      fields = fields_of(form["form"])
      expect(fields.slice("subject", "urgent", "audience", "tags", "region").transform_values { it.values_at("control", "param") }).to eq(
        "subject" => %w[text broadcast[subject]], "urgent" => %w[boolean broadcast[urgent]], "audience" => %w[radio broadcast[audience]],
        "tags" => %w[checkboxes broadcast[tags][]], "region" => %w[typeahead broadcast[region]]
      )
      expect(fields["subject"]).to include("required" => true)
      expect(fields["body"]).to include("control" => "textarea")
      expect(form["form"]["sections"].flat_map { it["fields"] }.find { it["control"] == "html" }["value"]).to include("Goes to every reader.")
    end

    it "describes an Arbre active_admin_form_for the same way" do
      form = forms.last

      expect(form).to include("action" => {"method" => "post", "path" => "/api/admin/broadcasts/note"}, "submit_label" => "Save note", "submit_confirm" => "Post this note?")
      expect(fields_of(form["form"])["note"]).to include("param" => "quick[note]", "hint" => "Seen by everyone")
    end

    it "carries no markup for the forms and keeps the classic page unchanged" do
      expect(response.body).not_to include("reactiveadmin-node", "<form")

      get "/admin/broadcasts"
      expect(response.body).to include('action="/admin/broadcasts/announce"', 'data-confirm="Send to everyone?"')
    end
  end

  describe "submitting a form of the page" do
    let(:path) { "/api/admin/broadcasts/announce" }

    it "gives the action what a browser's post of the form would" do
      api(:post, path, {broadcast: {subject: "Hi", body: nil, urgent: nil, audience: nil, tags: nil, region: nil}}, schema: "ActionResult")

      expect(response).to have_http_status(:ok)
      posted = JSON.parse(json["message"])
      expect(posted).to include("subject" => "Hi", "body" => "", "region" => "")
      expect(posted).not_to have_key("audience")
    end

    it "keeps lists and chosen values as sent" do
      api(:post, path, {broadcast: {subject: "Hi", audience: "staff", tags: ["news"], urgent: true}})

      expect(JSON.parse(json["message"])).to include("audience" => "staff", "tags" => ["news"], "urgent" => true)
    end

    it "answers the action's alert as an invalid response" do
      api(:post, path, {broadcast: {subject: ""}})

      expect(response).to have_http_status(:unprocessable_content)
      expect(json).to include("code" => "invalid", "base" => ["Subject can't be blank"])
    end

    it "answers a post without the form's param as a bad request" do
      api(:post, path, {})

      expect(response).to have_http_status(:bad_request)
    end

    it "runs the action when the content can't be rendered to learn the form" do
      allow(ReactiveAdmin::PagePayload).to receive(:new).and_raise(RuntimeError)

      api(:post, path, {broadcast: {subject: "Hi"}})

      expect(response).to have_http_status(:ok)
    end

    it "is a 401 when signed out" do
      delete "/logout"
      api(:post, path, {broadcast: {subject: "Hi"}})

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "options too long to inline" do
    let(:path) { "/api/admin/_pages/broadcasts" }

    it "are searched through the page that holds the form" do
      api_get("/api/admin/_pages/broadcasts")
      field = fields_of(forms.first["form"])["region"]
      expect(field).to include("control" => "typeahead", "options_path" => "#{path}?context=page_form&field=region&form=0")

      api_get(path, context: "page_form", form: 0, field: "region", term: "Region 14", schema: "OptionsResponse")

      expect(json["options"].pluck("label")).to include("Region 14", "Region 140")
      expect(json["options"].pluck("label")).not_to include("Region 15")
    end

    it "answers 404 for a field or form the page doesn't have" do
      api_get(path, context: "page_form", form: 0, field: "nope")
      expect(response).to have_http_status(:not_found)

      api_get(path, context: "page_form", form: -1, field: "region")
      expect(response).to have_http_status(:not_found)

      api_get(path, context: "page_form", form: 5, field: "region")
      expect(response).to have_http_status(:not_found)
    end

    it "shares the options budget" do
      allow(ReactiveAdmin::RateLimit).to receive(:retry_after).with(:options, anything).and_return(7)

      api_get(path, context: "page_form", form: 0, field: "region")

      expect(response).to have_http_status(:too_many_requests)
      expect(response.headers["Retry-After"]).to eq "7"
    end
  end

  describe "forms that can't be native" do
    before { api_get("/api/admin/_pages/legacy_forms", schema: "PageResponse") }

    # The literal `<form>` in the partial is no frame: markup the form helpers didn't build can't be told from stored text.
    it "stay frames: an off-site action, a GET form and a route outside the admin" do
      expect(forms).to be_empty
      frames = nodes_of(json["layout"], "frame")
      expect(frames.size).to eq 3
      expect(frames.map { it["src"] }.uniq).to eq(["/admin/legacy_forms"])
      expect(json["view"]).to include("mode" => "frame")
    end
  end

  describe "a form that raises while recording" do
    it "renders as a frame, and the page says why" do
      allow_any_instance_of(ReactiveAdmin::TemplateForm::Recorder).to receive(:inputs).and_raise(RuntimeError)

      api_get("/api/admin/_pages/broadcasts")

      expect(forms).to be_empty
      expect(nodes_of(json["layout"], "frame").size).to eq 2
      expect(json["degraded"].pluck("kind")).to include("page_form_failed")
    end
  end

  describe "the frame override" do
    it "keeps the forms as frames when the page is forced to one" do
      allow(ReactiveAdmin::Ladder).to receive(:override).and_call_original
      allow(ReactiveAdmin::Ladder).to receive(:override).with(anything, "*").and_return({mode: "frame"})

      api_get("/api/admin/_pages/broadcasts")

      expect(forms).to be_empty
      expect(nodes_of(json["layout"], "frame").size).to eq 1
    end
  end
end
