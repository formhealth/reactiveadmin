module ReactiveAdmin
  class Engine < ::Rails::Engine
    initializer "reactiveadmin.mime" do
      Mime::Type.register "application/vnd.reactiveadmin+json", :reactiveadmin unless Mime[:reactiveadmin]
    end

    initializer "reactiveadmin.server_timing" do |app|
      app.middleware.insert_after ActionDispatch::RequestId, ServerTiming
    end

    initializer "reactiveadmin.token_requests" do |app|
      app.middleware.insert_after ServerTiming, Auth::TokenRequests
    end

    initializer "reactiveadmin.provenance" do
      ActiveSupport.on_load(:action_view) { prepend Provenance::Helpers }
    end

    # Innermost, so the host's own middleware (CSP headers, host authorization) wraps the shell as it does any page.
    initializer "reactiveadmin.ui_shell" do |app|
      app.middleware.use Ui::Shell
    end

    initializer "reactiveadmin.ui_helper" do
      ActiveSupport.on_load(:action_view) { include Ui::Helper }
    end

    # The overlay is redefined by the host's app/admin files on every AA (re)load.
    initializer "reactiveadmin.menu_overlay" do
      AA.on_before_load { MenuOverlay.reset! }
    end

    # Prepended so custom controller overrides that call super still reach us.
    config.to_prepare do
      Typeahead.install
      AA.prepend_display_helper(CompositeKeys::DisplayName)
      AA.prepend_csv_builder(Masking::Csv, CsvInjection)
      AA.prepend_tag(Provenance::Tags)
      AA.extend_page(dsl: ResourceDSL, config: ResourceOptions)
      AA.prepend_controller_extensions(
        page: [Auth::Authentication, ApiErrors, Exposure::Guard, ApiGuards::Guard, PageControllerExtension, RateLimit::Guard, BackgroundRequests, ApiFallback, ApiGuards::Backstop, Auth::Request],
        # Exposure and ApiGuards sit inside ControllerExtension so they answer before declared-action authorization.
        resource: [Auth::Authentication, ApiErrors, Exposure::Guard, ApiGuards::Guard, ControllerExtension, RateLimit::Guard, QueryGuard::Guard, RansackGuard, BackgroundRequests, ApiFallback, ApiGuards::Backstop, Auth::Request]
      )
    end
  end
end
