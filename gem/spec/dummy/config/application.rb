require_relative "boot"

require "rails"
require "active_record/railtie"
require "action_controller/railtie"
require "action_view/railtie"
require "sprockets/railtie"

Bundler.require(*Rails.groups)

module Dummy
  class Application < Rails::Application
    config.root = File.expand_path("..", __dir__)
    FileUtils.mkdir_p([root.join("log"), root.join("tmp")])

    config.load_defaults 8.1
    config.eager_load = false
    config.secret_key_base = "reactiveadmin-dummy"
    config.active_support.deprecation = :stderr
    config.logger = ActiveSupport::Logger.new(root.join("log/test.log"))
    config.cache_store = :memory_store
    config.hosts.clear
    config.active_record.encryption.primary_key = "dummy-primary-key"
    config.active_record.encryption.deterministic_key = "dummy-deterministic-key"
    config.active_record.encryption.key_derivation_salt = "dummy-derivation-salt"

    # ActiveAdmin registrations are loaded by ActiveAdmin, not by Zeitwerk.
    initializer "dummy.ignore_admin_dir", before: :setup_main_autoloader do
      Rails.autoloaders.main.ignore(root.join("app/admin"))
    end
  end
end
