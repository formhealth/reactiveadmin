module ReactiveAdmin
  module Auth
    # Innermost on every API controller, so the guards stacked above it (rate limits, exposure, declared
    # action authorization) still run after a token authenticates. For a token request it replaces what
    # the session does: no `authentication_method`, the token's user as the current user, no CSRF.
    module Authentication
      private

      def authenticate_active_admin_user
        super unless token_request?
      end

      # For hosts whose `current_user_method` isn't defined on the controller.
      def current_active_admin_user = token_request? ? Auth.identity(request)&.user : super

      # A token isn't ambient the way a cookie is, so a forged cross-site request can't carry one.
      def verified_request? = token_request? || super

      def token_request? = reactiveadmin_request? && Auth.token_based?(request)
    end

    # Outermost: the token is checked, and the user installed, before any callback (the host's included)
    # can ask who is signed in.
    module Request
      private

      def process_action(*)
        return super unless reactiveadmin_request?

        ApiGuards::Current.channel = token_request? ? :token : :session
        unless token_request?
          return super unless token_only?

          return reject_credentials(:unauthorized, "Authentication required", Auth.challenge)
        end

        identity = Auth.identity(request)
        return reject_credentials(:unauthorized, "Invalid or expired token", Auth.challenge(error: "invalid_token")) unless identity

        scope = required_scope
        return reject_credentials(:insufficient_scope, "Token lacks the #{scope} scope", Auth.challenge(error: "insufficient_scope", scope:), 403) unless identity.allows?(scope)

        install(identity)
        super
      end

      # Only the MCP endpoint refuses sessions: its callers are agents, never a browser.
      def token_only? = false

      def required_scope
        mcp = ReactiveAdmin.config.mcp
        (request.get? || request.head?) ? mcp.read_scope : mcp.write_scope
      end

      def install(identity)
        request.session_options[:skip] = true
        user = identity.user
        method = AA.current_user_method(Registry.namespace)
        define_singleton_method(method) { user } if method
      end

      def reject_credentials(code, message, challenge, status = 401)
        response.headers["WWW-Authenticate"] = challenge
        render_api_error(code, message, status)
      end
    end
  end
end
