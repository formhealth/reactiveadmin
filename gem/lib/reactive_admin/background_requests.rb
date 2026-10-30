module ReactiveAdmin
  # Metadata the client revalidates on its own (_manifest, _meta, _session, _options, _labels) may
  # carry X-Reactiveadmin-Background so a host can keep it out of its access audit and stop it
  # extending an idle session.
  #
  # The header is the client's claim, so the route decides what may be background: record data
  # (show, index, edit, new, _value, pages, actions) is always a view whatever the header says.
  module BackgroundRequests
    HEADER = "X-Reactiveadmin-Background".freeze
    METADATA_ACTIONS = %w[reactiveadmin_meta reactiveadmin_options reactiveadmin_lookup reactiveadmin_labels].freeze
    METADATA_CONTROLLERS = %w[reactive_admin/manifest reactive_admin/session].freeze

    # Rack env key only server code can set (a client header arrives as HTTP_*): the doctor's samples.
    INTERNAL_ENV = "reactiveadmin.internal".freeze

    def self.background?(request)
      request.env.key?(INTERNAL_ENV) ||
        (request.get? && request.headers[HEADER].to_s.in?(%w[1 true]) && metadata?(request.path_parameters))
    end

    def self.metadata?(params) = METADATA_ACTIONS.include?(params[:action]) || METADATA_CONTROLLERS.include?(params[:controller])

    private

    # Before callbacks, so the hook can mark the request before the host's own callbacks decide
    # whether to refresh the session or track a view.
    def process_action(*)
      hook = ReactiveAdmin.config.on_background_request
      hook.call(self) if hook && BackgroundRequests.background?(request)
      super
    end
  end
end
