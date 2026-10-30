RSpec.describe "write safety", type: :request do
  include_context "with a blog"

  let(:ticket) { Ticket.create!(title: "Printer") }
  let(:note) { Note.create!(title: "Memo") }

  before { sign_in admin }

  def edit_lock(resource, record) = api_get("/api/admin/#{resource}/#{record.id}/edit", schema: "FormResponse")["lock"]

  def patch_ticket(title, lock: edit_lock("tickets", ticket)) = api(:patch, "/api/admin/tickets/#{ticket.id}", {ticket: {title:}, lock:}.compact)

  def patch_note(title, lock) = api(:patch, "/api/admin/notes/#{note.id}", {note: {title:}, lock:}.compact)

  def with_config(**settings)
    original = settings.keys.index_with { ReactiveAdmin.config.public_send(it) }
    settings.each { |key, value| ReactiveAdmin.config.public_send(:"#{key}=", value) }
    yield
  ensure
    original.each { |key, value| ReactiveAdmin.config.public_send(:"#{key}=", value) }
  end

  describe "submittable forms" do
    it "marks an ordinary form submittable" do
      api_get("/api/admin/notes/new", schema: "FormResponse")

      expect(json).to include("submittable" => true)
      expect(json).not_to have_key("unsupported_reason")
    end

    it "marks a form partial unsupported" do
      api_get("/api/admin/doodles/new", schema: "FormResponse")

      expect(json).to include("submittable" => false, "unsupported_reason" => ReactiveAdmin::FormSchema::UNSUPPORTED_REASON)
    end

    it "keeps a form partial that records into typed fields submittable, writes included" do
      api_get("/api/admin/sketches/new", schema: "FormResponse")
      expect(json).to include("submittable" => true)

      expect { api(:post, "/api/admin/sketches", {sketch: {title: "Alpha"}}) }.to change(Sketch, :count).by(1)
      expect(response).to have_http_status(:created)
    end

    it "marks a form with raw inputs in html unsupported" do
      api_get("/api/admin/taggings/new", schema: "FormResponse")

      expect(json).to include("submittable" => false)
    end

    it "refuses to create through an unsupported form" do
      expect { api(:post, "/api/admin/doodles", {sketch: {title: "x"}}) }.not_to change(Sketch, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(json).to include("code" => "unsupported", "message" => ReactiveAdmin::FormSchema::UNSUPPORTED_REASON)
    end

    it "refuses to update through an unsupported form" do
      sketch = Sketch.create!(title: "Hello")
      api(:patch, "/api/admin/doodles/#{sketch.id}", {sketch: {title: "Changed"}})

      expect(response).to have_http_status(:unprocessable_content)
      expect(json).to include("code" => "unsupported")
      expect(sketch.reload.title).to eq("Hello")
    end
  end

  describe "optimistic locking" do
    it "hands out lock_version for models that have one" do
      expect(edit_lock("tickets", ticket)).to eq("field" => "lock_version", "value" => "0")
    end

    it "hands out updated_at otherwise, and nothing for a new record" do
      expect(edit_lock("notes", note)).to eq("field" => "updated_at", "value" => note.updated_at.utc.iso8601(6))
      api_get("/api/admin/notes/new")
      expect(json).not_to have_key("lock")
    end

    it "applies an update that carries the current lock_version" do
      patch_ticket("Scanner")

      expect(response).to have_http_status(:ok)
      expect(ticket.reload).to have_attributes(title: "Scanner", lock_version: 1)
    end

    it "answers 409 for a stale lock_version without writing" do
      lock = edit_lock("tickets", ticket)
      ticket.update!(title: "Someone else")
      patch_ticket("Mine", lock:)

      expect(response).to have_http_status(:conflict)
      expect(json).to include("code" => "stale", "message" => "This record changed since you opened it.")
      expect(ticket.reload.title).to eq("Someone else")
    end

    it "answers 409 when the record changes between the check and the write" do
      lock = edit_lock("tickets", ticket)
      Ticket.set_callback(:update, :before, :bump_lock_elsewhere)
      Ticket.define_method(:bump_lock_elsewhere) { Ticket.where(id:).update_all("lock_version = lock_version + 1") }
      patch_ticket("Mine", lock:)

      expect(response).to have_http_status(:conflict)
      expect(json).to include("code" => "stale")
      expect(ticket.reload.title).to eq("Printer")
    ensure
      Ticket.skip_callback(:update, :before, :bump_lock_elsewhere)
    end

    it "applies an update that carries the current updated_at" do
      patch_note("Renamed", edit_lock("notes", note))

      expect(response).to have_http_status(:ok)
      expect(note.reload.title).to eq("Renamed")
    end

    it "answers 409 for a stale updated_at without writing" do
      lock = edit_lock("notes", note)
      note.touch(time: 1.minute.from_now)
      patch_note("Mine", lock)

      expect(response).to have_http_status(:conflict)
      expect(json).to include("code" => "stale")
      expect(note.reload.title).to eq("Memo")
    end

    it "treats an unparseable token as stale" do
      patch_note("Mine", {"field" => "updated_at", "value" => "yesterday"})

      expect(response).to have_http_status(:conflict)
    end

    it "refuses a lock for the wrong field" do
      patch_note("Mine", {"field" => "lock_version", "value" => "0"})

      expect(response).to have_http_status(:conflict)
    end

    it "lets the second of two operators know after the first saves" do
      first = edit_lock("notes", note)
      second = edit_lock("notes", note)
      patch_note("First", first)
      expect(response).to have_http_status(:ok)

      patch_note("Second", second)
      expect(response).to have_http_status(:conflict)
      expect(note.reload.title).to eq("First")
    end

    it "requires a lock by default" do
      patch_ticket("Scanner", lock: nil)

      expect(response).to have_http_status(:bad_request)
      expect(json).to include("code" => "invalid")
      expect(ticket.reload.title).to eq("Printer")
    end

    it "accepts a missing lock when require_lock is off, but still rejects a stale one" do
      with_config(require_lock: false) do
        patch_ticket("Scanner", lock: nil)
        expect(response).to have_http_status(:ok)

        patch_ticket("Mine", lock: {"field" => "lock_version", "value" => "0"})
        expect(response).to have_http_status(:conflict)
      end
    end

    it "does not ask creates for a lock" do
      api(:post, "/api/admin/tickets", {ticket: {title: "New"}})

      expect(response).to have_http_status(:created)
    end
  end

  describe "disabled fields" do
    it "marks the field disabled in the form" do
      api_get("/api/admin/notes/new")

      expect(fields_of(json["form"])["weight"]).to include("disabled" => true)
    end

    it "ignores a submitted value on create" do
      api(:post, "/api/admin/notes", {note: {title: "New", weight: 9}})

      expect(Note.find_by!(title: "New").weight).to eq(0)
    end

    it "ignores a submitted value on update" do
      patch_note_with = {note: {title: "Renamed", weight: 9}, lock: edit_lock("notes", note)}
      api(:patch, "/api/admin/notes/#{note.id}", patch_note_with)

      expect(note.reload).to have_attributes(title: "Renamed", weight: 0)
    end
  end

  describe "retryable errors" do
    let(:error_class) { stub_const("Retryable", Class.new(StandardError)) }

    before do
      Ticket.set_callback(:update, :before, :fail_retryably)
      Ticket.define_method(:fail_retryably) { raise Retryable, "advisory lock held" }
      ReactiveAdmin.config.retryable_errors = [error_class]
    end

    after do
      Ticket.skip_callback(:update, :before, :fail_retryably)
      ReactiveAdmin.config.retryable_errors = []
    end

    it "answers 409 retry with Retry-After instead of 500, never stale" do
      patch_ticket("Scanner")

      expect(response).to have_http_status(:conflict)
      expect(response.headers["Retry-After"]).to eq("1")
      expect(json).to include("code" => "retry")
      expect(json["message"]).not_to eq(ReactiveAdmin::FormLock::STALE_MESSAGE)
    end

    it "accepts class names for constants that reload" do
      with_config(retryable_errors: ["Retryable"]) do
        patch_ticket("Scanner")

        expect(response).to have_http_status(:conflict)
      end
    end

    it "leaves other errors alone" do
      with_config(retryable_errors: []) do
        patch_ticket("Scanner")

        expect(response).to have_http_status(:internal_server_error)
        expect(json).to include("code" => "error")
      end
    end
  end

  describe "the lock window" do
    let(:controller_class) { Admin::NotesController }

    def probing(probe)
      controller_class.define_method(:window_probe, &probe)
      controller_class.before_action(:window_probe, only: :update)
      yield
    ensure
      controller_class.skip_callback(:process_action, :before, :window_probe)
    end

    it "takes the row lock after host before_actions, inside a transaction they ran outside" do
      depth = -> { ActiveRecord::Base.connection.open_transactions }
      calls = []
      allow_any_instance_of(Note).to receive(:lock!).and_wrap_original { |m| calls << [:lock, depth.call] && m.call }
      lock = edit_lock("notes", note)
      outer = depth.call
      probing(-> { calls << [:before, depth.call] }) do
        patch_note("Renamed", lock)
      end

      expect(calls).to eq([[:before, outer], [:lock, outer + 1]])
    end

    it "answers 409 stale, not 500, when a before_action left the record dirty" do
      lock = edit_lock("notes", note)
      probing(-> { resource.title = "Dirty" }) do
        patch_note("Renamed", lock)
      end

      expect(response).to have_http_status(:conflict)
      expect(json).to include("code" => "stale")
      expect(note.reload.title).to eq("Memo")
    end

    it "answers 404 when the record is deleted before the lock is taken" do
      lock = edit_lock("notes", note)
      probing(-> { Note.where(id: resource.id).delete_all }) do
        patch_note("Renamed", lock)
      end

      expect(response).to have_http_status(:not_found)
      expect(json).to include("code" => "not_found")
    end
  end
end
