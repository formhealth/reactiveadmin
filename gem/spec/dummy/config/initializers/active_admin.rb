require Rails.root.join("lib/custom_authorization_adapter")

ActiveAdmin.setup do |config|
  config.site_title = "Dummy Admin"
  config.comments = false
  config.comments_registration_name = "AdminComment"
  config.root_to = "dashboard#index"
  config.authentication_method = :authenticate_admin_user!
  config.current_user_method = :current_admin_user
  config.on_unauthorized_access = :handle_unauthorized_access
  config.logout_link_path = :logout_path
  config.logout_link_method = :delete
  config.batch_actions = true
  config.default_per_page = 10
  config.localize_format = :long
  config.filter_attributes = [:encrypted_password, :password]

  case ENV.fetch("AUTH_ADAPTER", "default")
  when "custom"
    config.authorization_adapter = CustomAuthorizationAdapter
  when "pundit"
    config.authorization_adapter = ActiveAdmin::PunditAdapter
    config.pundit_default_policy = "Admin::DefaultPolicy"
    config.pundit_policy_namespace = :admin
  when "default"
    config.authorization_adapter = ActiveAdmin::AuthorizationAdapter
  else
    raise "unknown AUTH_ADAPTER #{ENV["AUTH_ADAPTER"].inspect}"
  end

  config.namespace :admin do |admin|
    admin.build_menu :default do |menu|
      menu.add label: "Docs", url: "https://example.com/docs", priority: 50
    end
  end
end
