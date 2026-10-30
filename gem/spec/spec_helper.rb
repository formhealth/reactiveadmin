RSpec.configure do |config|
  config.expect_with(:rspec) { |c| c.syntax = :expect }
  config.mock_with(:rspec) { |m| m.verify_partial_doubles = true }
  config.disable_monkey_patching!
  config.example_status_persistence_file_path = "tmp/rspec_status.txt"
  config.filter_run_when_matching :focus
  config.order = :random
  Kernel.srand config.seed
end
