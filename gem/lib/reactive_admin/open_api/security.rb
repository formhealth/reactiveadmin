module ReactiveAdmin
  module OpenApi
    # The credentials the API takes. By default the host's ActiveAdmin session cookie, plus the CSRF token
    # writes must carry, and a bearer token where `config.auth` has a bearer adapter. Other authentication
    # is declared with `config.openapi.security_schemes`, or by an authorization adapter that defines
    # `openapi_security_scheme`.
    module Security
      SESSION = "sessionCookie".freeze
      CSRF = "csrfToken".freeze
      BEARER = "bearerAuth".freeze

      module_function

      def schemes
        configured = ReactiveAdmin.config.openapi.security_schemes || adapter_schemes || defaults
        configured.to_h { |name, scheme| [name.to_s, scheme.deep_stringify_keys] }
      end

      # A token is an alternative to the session, never an addition: it carries no cookie and no CSRF token.
      def requirement(write:)
        all = schemes
        names = write ? all.keys : all.keys - [CSRF]
        tokens, session = names.partition { token?(all[it]) }
        [session.presence&.to_h { [it, []] }, *tokens.map { {it => []} }].compact
      end

      # For the endpoints only tokens may call (MCP).
      def token_requirement = schemes.select { |_, scheme| token?(scheme) }.keys.map { {it => []} }

      def token?(scheme) = %w[oauth2 openIdConnect].include?(scheme["type"]) || (scheme["type"] == "http" && scheme["scheme"].to_s.casecmp?("bearer"))

      def defaults
        session = Auth.token_only? ? {} : session_schemes
        Auth.bearer? ? session.merge(BEARER => Core.document.dig("components", "securitySchemes", BEARER).symbolize_keys) : session
      end

      def session_schemes
        {
          SESSION => {type: "apiKey", in: "cookie", name: session_key,
                      description: "The signed-in ActiveAdmin session. Sign in to the admin in the same browser; requests carry the cookie."},
          CSRF => {type: "apiKey", in: "header", name: "X-CSRF-Token",
                   description: "Required on every write (anything but GET). Read it from `csrf_token` in `GET #{Paths.api("/#{ReactiveAdmin.config.namespace}/_session")}`; a missing or stale token answers 422 `invalid_csrf`."}
        }
      end

      def adapter_schemes
        adapter = AA.authorization_adapter(Registry.namespace)
        adapter.openapi_security_scheme if adapter.respond_to?(:openapi_security_scheme)
      end

      # The host's cookie name, when the session store says it.
      def session_key = Rails.application.config.session_options[:key].presence || "_session_id"
    end
  end
end
