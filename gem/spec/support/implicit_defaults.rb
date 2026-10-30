RSpec.configure do |config|
  config.around(:each, :all_defaults) do |example|
    ReactiveAdmin.config.implicit_defaults = :all
    example.run
  ensure
    ReactiveAdmin.config.implicit_defaults = :secure
  end
end
