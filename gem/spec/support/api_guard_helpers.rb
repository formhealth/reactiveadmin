# Declares `api` guards on registered resources and pages for one example.
module ApiGuardHelpers
  def declare_guard(key, *, **)
    config = ReactiveAdmin::Registry.find(key) || ReactiveAdmin::Registry.find_page(key)
    @guard_snapshots ||= {}
    @guard_snapshots[config] = config.reactive_options[:api_guards].dup unless @guard_snapshots.key?(config)
    ReactiveAdmin::ApiGuards.declare(config, *, **)
  end

  def restore_guards
    @guard_snapshots&.each { |config, saved| saved ? config.reactive_options[:api_guards] = saved : config.reactive_options.delete(:api_guards) }
  end
end

RSpec.configure do |config|
  config.include ApiGuardHelpers
  config.after { restore_guards }
end
