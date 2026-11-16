module ReactiveAdmin
  # `{mount}/_client_errors`: the React client reports a crash its error boundary caught (see ClientError).
  # Sessions only: the reports come from a browser, and a token has no reason to send them.
  class ClientErrorsController < ApiController
    wrap_parameters false
    before_action :require_enabled
    # Throttled first, so a flood never reaches the host's authorization checks.
    before_action :throttle
    before_action :authorize_root!
    before_action :require_session

    def create
      error = ClientError.from_params(params, authorizer: Authorizer.for(self)) or return render_api_error(:invalid, "error_name is required", 400)

      ClientError.report(error, request_id: request.request_id, user_id: ReactiveAdmin.current_user(self).id)
      head :no_content
    end

    private

    def audit_writes? = false

    def require_enabled
      render_api_error(:not_found, "Not found", 404) unless Ui.settings.client_errors
    end

    def require_session
      render_api_error(:forbidden, "Client errors are reported from a session", 403) if token_request?
    end

    def throttle
      seconds = RateLimit.retry_after(:client_error, ReactiveAdmin.current_user(self)&.id) or return

      response.headers["Retry-After"] = seconds.to_s
      render_api_error(:rate_limited, "Too many requests; try again in #{seconds} seconds", 429)
    end
  end
end
