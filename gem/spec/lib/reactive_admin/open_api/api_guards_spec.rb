RSpec.describe ReactiveAdmin::OpenApi, "api_guards" do
  include_context "with a blog"

  let(:doc) { described_class.build(admin) }
  let(:paths) { doc["paths"] }

  def verbs(path) = paths.fetch(path, {}).keys.sort

  it "leaves out a whole reserved resource and page" do
    expect(paths.keys.grep(%r{/profiles\b|/back_office\b|_pages/back_office})).to eq([])
    expect(doc["tags"].pluck("name")).not_to include("profiles", "page:back_office")
    expect(doc.dig("components", "schemas").keys.grep(/Profile/)).to eq([])
  end

  it "leaves out reserved actions of a resource and keeps the rest" do
    expect(verbs("/api/admin/admin_users")).to eq(%w[get])
    expect(verbs("/api/admin/admin_users/new")).to eq([])
    expect(verbs("/api/admin/admin_users/{id}")).to eq(%w[get patch])
    expect(verbs("/api/admin/admin_users/{id}/impersonate")).to eq([])
    expect(verbs("/api/admin/admin_users/sweep")).to eq([])
    expect(verbs("/api/admin/admin_users/{id}/greet")).to eq(%w[post])
  end

  it "pairs a reserved form with its write" do
    expect(verbs("/api/admin/lockers/{id}/edit")).to eq([])
    expect(verbs("/api/admin/lockers/{id}")).to eq(%w[delete get])
    expect(verbs("/api/admin/lockers")).to eq(%w[get post])
  end

  it "leaves out reserved batch actions" do
    batch = paths.dig("/api/admin/admin_users/batch_action", "post")

    expect(batch["requestBody"].dig("content", "application/json", "schema", "oneOf").map { it.dig("properties", "batch_action", "const") }).to eq(%w[tidy])
    expect(batch["description"]).not_to include("promote")
  end

  it "leaves out reserved page actions" do
    expect(verbs("/api/admin/_pages/danger_zone")).to eq(%w[get])
    expect(paths.keys.grep(%r{danger_zone/(wipe|audit)})).to eq([])
  end

  it "leaves out reserved attributes from write bodies, and says so" do
    body = doc.dig("components", "schemas", "AdminUserUpdateParams")
    keys = JSON.generate(body.dig("properties", "admin_user"))

    expect(keys).to include("name", "email", "author_attributes")
    expect(keys).not_to match(/role|rating|bio/)
    expect(paths.dig("/api/admin/admin_users/{id}", "patch", "description")).to include("`role`", "`rating`", "`bio`", "403 `api_denied`")
  end

  it "names no reserved action or attribute anywhere" do
    expect(JSON.generate(paths.except("/api/admin/admin_users/{id}"))).not_to match(/impersonate|sweep|promote|wipe|Danger Zone audit/i)
  end

  it "documents api_denied among the forbidden answers" do
    expect(doc.dig("components", "responses", "Forbidden", "description")).to include("api_denied", "insufficient_scope")
  end

  it "documents a full document the same way" do
    full = described_class.build(nil, full: true)

    expect(full["paths"].keys.grep(%r{/profiles\b|/impersonate|/sweep|/back_office})).to eq([])
    expect(full["paths"]["/api/admin/admin_users"].keys).to eq(%w[get])
  end
end
