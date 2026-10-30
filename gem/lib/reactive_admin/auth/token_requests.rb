module ReactiveAdmin
  module Auth
    # A bearer request to the API carries no session: its cookies are dropped before the host's session
    # and authentication middleware or callbacks can read them, so the token is the only credential.
    class TokenRequests
      def initialize(app) = @app = app

      def call(env)
        request = ActionDispatch::Request.new(env)
        env.delete("HTTP_COOKIE") if Auth.token_based?(request)
        @app.call(env)
      end
    end
  end
end
