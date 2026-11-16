require "reactive_admin/rspec"

RSpec.describe "ReactiveAdmin::RSpec.contract_examples", type: :request do
  include_context "with a blog"
  before { sign_in admin }

  ReactiveAdmin::RSpec.contract_examples(self)
end
