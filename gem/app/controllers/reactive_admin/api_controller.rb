module ReactiveAdmin
  # Base of the shell endpoints. Subclasses ActiveAdmin's controller base, so authentication,
  # the authorization adapter and the host's callbacks for AA controllers apply as for any AA page.
  class ApiController < AA.base_controller
    include Auth::Authentication
    include ApiErrors
    include BackgroundRequests
    include Auth::Request

    private

    # The namespace's root page stands in for AA's per-controller config: its authorization
    # decides who may open the admin at all.
    def active_admin_config = @active_admin_config ||= root_page

    def active_admin_namespace = Registry.namespace

    def root_page
      pages = Registry.pages
      root = AA.root_page_key(active_admin_namespace)
      pages.find { it.controller.controller_path.split("/").last == root } || pages.first
    end

    def authorize_root!
      authorize!(AA::Auth::READ, active_admin_config) if active_admin_config
      ReactiveAdmin.config.after_authorize&.call(self)
    end
  end
end
