RSpec.describe "template forms", type: :request do
  let(:ticket) { Ticket.create!(title: "Printer") }

  before { sign_in create_admin }

  def fields = json["form"]["sections"].flat_map { it["fields"] }

  around do |example|
    ReactiveAdmin::Ladder.reset!
    example.run
  ensure
    ReactiveAdmin::Ladder.reset!
  end

  describe "an active_admin_form_for template" do
    before { api_get("/api/admin/tickets/#{ticket.id}/retitle", schema: "FormResponse") }

    it "records every input, in order" do
      expect(fields.pluck("name")).to eq %w[title note]
      expect(json["form"]["sections"].first).to include("title" => "Retitle ticket")
    end

    it "targets the form's action" do
      expect(json["action"]).to eq("method" => "put", "path" => "/api/admin/tickets/#{ticket.id}/retitle")
      expect(json["submit_label"]).to eq "Retitle"
    end

    it "is submittable and carries the record's lock" do
      expect(json).to include("submittable" => true, "lock" => {"field" => "lock_version", "value" => "0"})
    end
  end

  describe "a form without an object" do
    before { api_get("/api/admin/tickets/#{ticket.id}/plain", schema: "FormResponse") }

    it "posts top-level params, and carries the submit confirm" do
      expect(fields.pluck("param")).to eq %w[title labels[] cc[]]
      expect(json).to include("submit_label" => "Apply", "submit_confirm" => "Apply to the ticket?")
    end
  end

  describe "a form with raw inputs" do
    it "is not submittable" do
      allow_any_instance_of(ReactiveAdmin::TemplateForm::Schema).to receive(:submittable?).and_return(false)
      api_get("/api/admin/tickets/#{ticket.id}/retitle")

      expect(json).to include("submittable" => false, "unsupported_reason" => a_string_including("classic admin"))
    end
  end

  describe "a template that cannot be recorded" do
    let(:path) { "/api/admin/tickets/#{ticket.id}/broken" }

    it "answers unsupported, not 500, and decides a frame from then on" do
      api_get(path)

      expect(response).to have_http_status(:not_implemented)
      expect(json).to include("code" => "unsupported")

      api_get("/api/admin/tickets/#{ticket.id}")
      expect(by_key(json["actions"])["broken"]["view"]).to include("mode" => "frame")
    end

    it "records the degradation" do
      seen = []
      subscriber = ActiveSupport::Notifications.subscribe(ReactiveAdmin::Degradation::EVENT) { |*, payload| seen << payload[:kind] }
      api_get(path)

      expect(seen).to include("template_form_failed")
    ensure
      ActiveSupport::Notifications.unsubscribe(subscriber)
    end
  end
end
