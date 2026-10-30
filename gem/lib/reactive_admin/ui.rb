module ReactiveAdmin
  # Serves the React client at the classic admin's own URLs. The browser's `reactiveadmin_ui=new` cookie picks it
  # (`Ui::Shell` answers navigations with the client's page) and the client decides everything else: it sends the
  # browser back to classic when the user can't use it or it has no screen for the URL. The server only says, in
  # `_session`, whether the user may switch and which UI the host would default them to.
  module Ui
    autoload :Assets, "reactive_admin/ui/assets"
    autoload :ClientBuild, "reactive_admin/ui/client_build"
    autoload :Helper, "reactive_admin/ui/helper"
    autoload :Shell, "reactive_admin/ui/shell"

    MODES = %w[classic new].freeze
    COOKIE = "reactiveadmin_ui".freeze

    module_function

    def settings = ReactiveAdmin.config.ui

    # The host's callable runs on every `_session`, so a failure there means "not available".
    def available?(user)
      !user.nil? && !!settings.available.call(user)
    rescue => e
      Rails.logger.warn("[reactiveadmin] ui.available raised #{e.class}; treated as unavailable")
      false
    end

    def default_mode(user)
      mode = settings.default
      mode = mode.call(user) if mode.respond_to?(:call)
      MODES.include?(mode.to_s) ? mode.to_s : "classic"
    rescue => e
      Rails.logger.warn("[reactiveadmin] ui.default raised #{e.class}; using classic")
      "classic"
    end

    def payload(user) = {available: available?(user), default: default_mode(user)}
  end
end
