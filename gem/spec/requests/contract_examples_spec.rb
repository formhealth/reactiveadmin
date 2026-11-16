require "reactive_admin/rspec"

RSpec.describe "ReactiveAdmin::RSpec.contract_examples", type: :request do
  include_context "with a blog"
  before { sign_in admin }

  ReactiveAdmin::RSpec.contract_examples(self)
end

RSpec.describe "ReactiveAdmin::RSpec.contract_examples failures" do
  def run_examples(&setup)
    group = RSpec::Core::ExampleGroup.describe("inner", type: :request) do
      include_context "with a blog"
      before { sign_in admin }
      before(&setup)
      ReactiveAdmin::RSpec.contract_examples(self)
    end
    group.run(RSpec::Core::NullReporter)
    group.examples.map { it.execution_result.status }
  end

  it "fails a registration that answers 500 with a well-formed error" do
    statuses = run_examples { allow_any_instance_of(ReactiveAdmin::IndexPayload).to receive(:as_json).and_raise("boom") }

    expect(statuses).to include(:failed)
  end

  it "passes when every registration answers as the contract says" do
    expect(run_examples {}.uniq).to eq([:passed])
  end
end
