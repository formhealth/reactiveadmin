Rails.application.configure do
  config.enable_reloading = false
  config.consider_all_requests_local = false
  config.action_dispatch.show_exceptions = :rescuable
  config.action_controller.allow_forgery_protection = false
  config.action_controller.perform_caching = false
  config.active_support.report_deprecations = false
  config.active_record.maintain_test_schema = false
  config.assets.compile = true
  config.assets.debug = false
end
