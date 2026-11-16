ENV["RAILS_ENV"] = "test"
ENV["AUTH_ADAPTER"] ||= "default"

require "spec_helper"
require_relative "dummy/config/environment"
require "rspec/rails"

require "reactive_admin/test_support"

Dir[File.join(__dir__, "support/**/*.rb")].each { require it }

# Rails loads routes lazily; ActiveAdmin's registrations are loaded by ReactiveAdmin.routes.
Rails.application.reload_routes_unless_loaded

ActiveRecord::Migration.suppress_messages { load File.join(__dir__, "dummy/db/schema.rb") }

RSpec.configure do |config|
  config.use_transactional_fixtures = true
  config.infer_spec_type_from_file_location!
  config.include ApiHelpers, type: :request
  config.include Builders
  config.include AdapterMatrix

  config.before(:each, :postgres) { skip "needs Postgres (set DATABASE_URL)" unless postgres? }
  config.before(:each) { Rails.cache.clear }
end
