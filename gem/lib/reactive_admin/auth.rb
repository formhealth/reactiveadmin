module ReactiveAdmin
  # How API requests prove who they are. The default is the session: ActiveAdmin's own
  # `authentication_method` runs and writes need a CSRF token. A bearer adapter authenticates a token
  # instead, for clients that have no cookie (the MCP endpoint, scripts):
  #
  #   config.auth = ReactiveAdmin::Auth.any(
  #     ReactiveAdmin::Auth::Session.new,
  #     ReactiveAdmin::Auth::Bearer.new { |token, request| AdminToken.find_by_token(token)&.user }
  #   )
  #
  # A request under the API mount with an `Authorization: Bearer` header is answered by the bearer adapter
  # alone and never falls back to cookies (they are dropped before the host sees them); every other request
  # is a session request. Token requests skip CSRF, which only exists to protect cookies.
  #
  # Bearer tokens never authenticate outside the mount. The classic admin runs actions `api` guards keep
  # off the API, in any format, so a token accepted there would bypass it.
  #
  # An adapter is any object with `claims?(request)`, `token_based?` and, when token based,
  # `authenticate(request)` returning an Identity or nil.
  module Auth
    autoload :Authentication, "reactive_admin/auth/guard"
    autoload :Request, "reactive_admin/auth/guard"
    autoload :TokenRequests, "reactive_admin/auth/token_requests"

    IDENTITY_ENV = "reactiveadmin.auth.identity".freeze

    # `scopes` nil means the token carries no scope claim, so no scope is required of it.
    Identity = Data.define(:user, :scopes, :client_id) do
      def allows?(scope) = scope.blank? || scopes.nil? || scopes.include?(scope)
    end

    class Session
      def claims?(_request) = true

      def token_based? = false
    end

    # The block gets the token and the request and returns a user, `{user:, scopes:, client_id:}`, or nil
    # for an invalid token. `scopes` is an array or a space-separated string.
    class Bearer
      SCHEME = /\ABearer(?:\s|\z)/i
      TOKEN = /\ABearer\s+(\S+)\z/i

      def initialize(&resolver)
        raise ArgumentError, "Bearer needs a block" unless resolver

        @resolver = resolver
      end

      def claims?(request) = SCHEME.match?(request.authorization.to_s)

      def token_based? = true

      def authenticate(request)
        token = TOKEN.match(request.authorization.to_s)&.[](1) or return
        identity(@resolver.call(token, request))
      rescue => e
        Rails.logger.warn("[reactiveadmin] bearer authentication failed: #{e.class}")
        nil
      end

      private

      def identity(result)
        result = {user: result} unless result.is_a?(Hash)
        user = result[:user] or return
        Identity.new(user:, scopes: scopes_of(result[:scopes]), client_id: result[:client_id]&.to_s)
      end

      def scopes_of(scopes)
        return if scopes.nil?

        Array(scopes.is_a?(String) ? scopes.split : scopes).map(&:to_s)
      end
    end

    # Token adapters claim their requests; everything else belongs to the first session-style adapter.
    class Composite
      def initialize(*adapters)
        raise ArgumentError, "Auth.any needs at least one adapter" if adapters.empty?

        @adapters = adapters
      end

      attr_reader :adapters

      def adapter_for(request)
        @adapters.find { it.token_based? && it.claims?(request) } || @adapters.find { !it.token_based? } || @adapters.first
      end
    end

    SESSION = Session.new

    module_function

    def any(*adapters) = Composite.new(*adapters)

    def session = SESSION

    # Under the namespace of the mount, the only place a token can authenticate.
    def api_path?(request)
      config = ReactiveAdmin.config
      request.path.start_with?("#{File.join(config.mount_path, config.namespace.to_s)}/")
    end

    def adapter_for(request)
      return SESSION unless api_path?(request)

      auth = ReactiveAdmin.config.auth || SESSION
      auth.respond_to?(:adapter_for) ? auth.adapter_for(request) : auth
    end

    def adapters = Array(ReactiveAdmin.config.auth&.then { it.respond_to?(:adapters) ? it.adapters : it })

    def bearer? = adapters.any?(&:token_based?)

    def token_only? = adapters.any? && adapters.all?(&:token_based?)

    def token_based?(request) = adapter_for(request).token_based?

    # Memoized per request: the host's block may query.
    def identity(request)
      return request.env[IDENTITY_ENV] if request.env.key?(IDENTITY_ENV)

      adapter = adapter_for(request)
      request.env[IDENTITY_ENV] = (adapter.authenticate(request) if adapter.token_based?)
    end

    def challenge(error: nil, scope: nil)
      url = ReactiveAdmin.config.mcp.resource_metadata_url
      params = {error:, scope:, resource_metadata: url}.compact.map { |key, value| %(#{key}="#{value}") }
      ["Bearer", params.join(", ")].compact_blank.join(" ")
    end
  end
end
