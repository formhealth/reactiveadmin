require "active_admin"

module ReactiveAdmin
  # The one boundary between this gem and ActiveAdmin's internals: AA constants, private controller
  # and view methods, inherited_resources ivars, Arbre and Formtastic classes. Everything else calls
  # intention-revealing methods here (`AA.scopes(config)`, `AA.resource_ivar(controller)`), so an AA
  # upgrade is a new implementation module, not a hunt through the gem. `aa_boundary_spec` fails when
  # an AA constant appears elsewhere in `lib` or `app`.
  #
  # `V3` implements AA 3.5; `V4` documents what changes for AA 4. The module is picked by
  # `ActiveAdmin::VERSION` when this file loads.
  #
  # Kept outside the boundary on purpose, because hosts and AA itself define them:
  # - the read-only resource and page config API (`resource_class`, `resource_name`, `param_key`,
  #   `route_*_path`, `belongs_to_config`, `member_actions`, ...), the same names in AA 4;
  # - names of AA hooks our prepended modules override (`authenticate_active_admin_user`,
  #   `dispatch_active_admin_access_denied`, `find_resource`, `process_action`, `format_attribute`, ...),
  #   listed per version in `AA::V4`;
  # - the host DSL (`ActiveAdmin.register`, `reactive do ... end`).
  module AA
    autoload :V3, "reactive_admin/aa/v3"
    autoload :V4, "reactive_admin/aa/v4"

    class << self
      def version = Gem::Version.new(::ActiveAdmin::VERSION)

      def v4? = version.segments.first >= 4

      def implementation = v4? ? V4 : V3
    end

    AccessDenied = ::ActiveAdmin::AccessDenied

    # Authorization action symbols; the same in AA 3 and 4.
    module Auth
      READ = ::ActiveAdmin::Auth::READ
      NEW = ::ActiveAdmin::Auth::NEW
      CREATE = ::ActiveAdmin::Auth::CREATE
      EDIT = ::ActiveAdmin::Auth::EDIT
      UPDATE = ::ActiveAdmin::Auth::UPDATE
      DESTROY = ::ActiveAdmin::Auth::DESTROY
    end

    extend implementation
  end
end
