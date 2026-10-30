require "rake"

RSpec.describe "rake reactiveadmin:openapi" do
  include_context "with a blog"

  let(:task) { Rake::Task["reactiveadmin:openapi"] }
  let(:out) { Rails.root.join("tmp/openapi_task_spec/admin.yaml") }

  before do
    Rails.application.load_tasks unless Rake::Task.task_defined?("reactiveadmin:openapi")
    task.reenable
    allow(ReactiveAdmin.config).to receive(:doctor_user).and_return(-> { admin })
  end

  after { FileUtils.rm_rf(out.dirname) }

  def run(output)
    ENV["OUT"] = output
    expect { task.invoke }.to output(/wrote /).to_stdout
  ensure
    ENV.delete("OUT")
  end

  it "warns when there is no doctor_user to evaluate user-dependent blocks for" do
    allow(ReactiveAdmin.config).to receive(:doctor_user).and_return(nil)
    ENV["OUT"] = "tmp/openapi_task_spec/admin.yaml"

    expect { task.invoke }.to output(/doctor_user is not set/).to_stderr.and output(/wrote /).to_stdout
  ensure
    ENV.delete("OUT")
  end

  it "writes the full exposed surface as YAML to OUT" do
    run("tmp/openapi_task_spec/admin.yaml")
    document = YAML.safe_load_file(out)

    expect(document["openapi"]).to eq("3.1.0")
    expect(document["paths"]).to have_key("/api/admin/categories")
    expect(document["paths"]["/api/admin/posts/{id}"]).to have_key("delete")
    expect(JSONSchemer.openapi(document).validate.to_a).to eq([])
  end

  it "is stable between runs, so a host can diff it in CI" do
    run("tmp/openapi_task_spec/admin.yaml")
    first = File.read(out)
    task.reenable
    run("tmp/openapi_task_spec/admin.yaml")

    expect(File.read(out)).to eq(first)
  end

  it "writes to config.openapi.output without OUT" do
    settings = ReactiveAdmin.config.openapi
    old = settings.output
    settings.output = "tmp/openapi_task_spec/configured.yaml"
    expect { task.invoke }.to output(/configured\.yaml/).to_stdout

    expect(File).to exist(Rails.root.join("tmp/openapi_task_spec/configured.yaml"))
  ensure
    settings.output = old
  end
end
