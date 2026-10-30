require Rails.root.join("lib/dummy_tokens")

ReactiveAdmin.configure do |config|
  config.namespace = :admin
  config.mount_path = "/api"
  config.auth = ReactiveAdmin::Auth.any(ReactiveAdmin::Auth::Session.new, ReactiveAdmin::Auth::Bearer.new { |token, _request| DummyTokens.resolve(token) })
  config.mcp.enabled = true
  # Serves a built client (`RA_OUT_DIR=... pnpm build:host`) for trying the UI switch against the dummy app.
  if ENV["REACTIVEADMIN_UI_ASSETS"]
    config.ui.available = ->(_user) { true }
    config.ui.client_assets = ENV["REACTIVEADMIN_UI_ASSETS"]
  end
end

ReactiveAdmin.api_guard(:admin_role) { |user, _request| user&.role == "admin" }

ReactiveAdmin.option_sources do
  source :authors, -> { Author.all }, label: :name, search: [:name, :email]
  source :posts, -> { Post.all }, label: :title, search: [:title]
end
