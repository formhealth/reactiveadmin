RSpec.describe ReactiveAdmin::Permissions do
  let(:config) { ReactiveAdmin::Registry.find("notes") }
  let(:asked) { [] }
  let(:authorizer) do
    log = asked
    Class.new { define_method(:authorized?) { |action, *, **| log << action } }.new
  end

  it "asks what classic AA asks for its New and Edit buttons" do
    described_class.new(config, authorizer).resource
    described_class.new(config, authorizer).record(Note.new)

    expect(asked).to include(ActiveAdmin::Auth::NEW, ActiveAdmin::Auth::EDIT)
    expect(asked).not_to include(ActiveAdmin::Auth::CREATE, ActiveAdmin::Auth::UPDATE)
  end
end
