module ReactiveAdmin
  # What an error reporter sees of a crash in the React client. The client sends names only (the error's
  # class, the components it unwound through, a route pattern, a resource key); each field is kept only
  # if it is shaped like one of those, so error text, a URL's ids and record values can't ride along.
  class ClientError < StandardError
    EVENT = "client_error.reactiveadmin".freeze
    NAME = /\A[A-Za-z_$][\w$]{0,63}\z/
    BOUNDARY = /\A(?:app|route|frame|iframe|node:\w{1,40})\z/
    VERSION = /\A[\w.+-]{1,32}\z/
    REQUEST_ID = WriteAudit::ID_FORMAT
    ROUTE_LITERALS = %w[groups new edit actions *].freeze
    ROUTE_PARAM = /\A:\w{1,32}\z/
    MAX_COMPONENTS = 20
    MAX_ROUTE_SEGMENTS = 8

    attr_reader :original_class, :boundary, :components, :route, :resource, :client_version, :client_request_id

    # Nil without a usable error name: there is nothing to report. `authorizer` limits the resource to what its user may read.
    def self.from_params(params, authorizer:)
      name = text(params[:error_name], NAME) or return

      new(name, boundary: text(params[:boundary], BOUNDARY), components: components_of(params[:components]), route: route_of(params[:route]),
        resource: resource_of(params[:resource], authorizer), client_version: text(params[:client_version], VERSION), client_request_id: text(params[:request_id], REQUEST_ID))
    end

    # Never raises: the client has already survived the crash, so a failing reporter mustn't turn the report into a 500.
    # The event and the reporter are tried apart, so one failing (a subscriber's counter store, say) can't drop the other.
    def self.report(error, request_id:, user_id:)
      payload = error.to_h.merge(request_id:, user_id:)
      deliver("event") { ActiveSupport::Notifications.instrument(EVENT, payload) }
      deliver("error_reporter") { ReactiveAdmin.config.error_reporter.call(error, payload.except(:components, :user_id).merge(action: "client")) }
    end

    def self.deliver(via)
      yield
    rescue => e
      Rails.logger.error("[reactiveadmin] client error #{via} failed: #{e.class}")
    end

    def self.text(value, format) = (value if value.is_a?(String) && value.match?(format))

    def self.components_of(value) = Array.wrap(value).filter_map { text(it, NAME) }.first(MAX_COMPONENTS)

    def self.route_of(value)
      return unless value.is_a?(String)

      segments = value.delete_prefix("/").split("/", -1)
      value if segments.size <= MAX_ROUTE_SEGMENTS && segments.all? { it.empty? || it.in?(ROUTE_LITERALS) || it.match?(ROUTE_PARAM) }
    end

    def self.resource_of(value, authorizer)
      named = [*Registry.resources, *Registry.pages].select { (AA.page?(it) ? it.underscored_resource_name : Registry.route_key(it)) == value }
      value if named.any? { Exposure.allowed?(it) && Exposure.permitted?(authorizer, it) }
    end

    def initialize(name, boundary: nil, components: [], route: nil, resource: nil, client_version: nil, client_request_id: nil)
      @original_class = name
      @boundary = boundary
      @components = components
      @route = route
      @resource = resource
      @client_version = client_version
      @client_request_id = client_request_id
      super("#{name} in the client at #{route || "an unknown route"}")
      set_backtrace(components.map { "in #{it}" })
    end

    def to_h = {resource:, boundary:, route:, components:, client_version:, client_request_id:, error_class: original_class}.compact
  end
end
