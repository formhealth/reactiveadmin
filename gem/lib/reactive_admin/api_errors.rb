module ReactiveAdmin
  # JSON error responses for reactiveadmin requests; falls through to AA's behaviour otherwise.
  # Implemented as method overrides rather than callbacks/rescue_from: those are copied per
  # subclass, so registering them after AA built its controllers would miss them.
  module ApiErrors
    include WriteAudit

    # Raise for bad client input that should answer 400 `invalid` with this message (kept free of sensitive data).
    BadRequest = Class.new(StandardError)

    def rescue_with_handler(exception, **)
      return super unless reactiveadmin_request?

      case exception
      when ActiveRecord::RecordNotFound then render_api_error(:not_found, "Record not found", 404)
      when ActionController::InvalidAuthenticityToken then render_api_error(:invalid_csrf, "Invalid CSRF token", 422)
      when ActiveRecord::StaleObjectError then render_api_error(:stale, FormLock::STALE_MESSAGE, 409)
      when ->(e) { retryable_error?(e) } then render_retry
      when ActionController::ParameterMissing then render_api_error(:invalid, "Missing parameter: #{exception.param}", 400)
      when BadRequest then render_api_error(:invalid, exception.message, 400)
      when AA::AccessDenied, ->(e) { defined?(::Pundit::NotAuthorizedError) && e.is_a?(::Pundit::NotAuthorizedError) }
        render_api_error(:forbidden, "Not authorized", 403)
      else return super || render_unexpected_error(exception)
      end
      true
    end

    # Public like Rails' own: responders call it on the controller. A redirect while authenticating
    # is the host sending the user to sign in.
    def redirect_to(options = {}, response_options = {})
      return super unless reactiveadmin_request?

      location = url_for(options)
      if @reactiveadmin_authenticating
        render_api_error(:unauthorized, "Authentication required", 401, location:)
      else
        render_redirect_result(location, response_options)
      end
    end

    private

    # 409 rather than 503: the server is healthy and the write lost a race with another operation, so
    # the client must tell it apart from a stale lock (`stale`) and from an outage.
    def render_retry
      response.headers["Retry-After"] = "1"
      render_api_error(:retry, "Couldn't save right now — another operation was in progress. Try again.", 409)
    end

    def retryable_error?(exception)
      classes = ReactiveAdmin.config.retryable_errors.filter_map { it.is_a?(Module) ? it : it.to_s.safe_constantize }
      [exception, exception.cause].compact.any? { |error| classes.any? { error.is_a?(it) } }
    end

    # Memoized because writes switch the request format to html, so AA's responders behave
    # as they do in the classic admin.
    def reactiveadmin_request?
      return @reactiveadmin_request if defined?(@reactiveadmin_request)

      @reactiveadmin_request = request.format.symbol == :reactiveadmin || reactiveadmin_export?
    end

    # The one API response that isn't JSON: AA's streamed CSV, served under the mount.
    def reactiveadmin_export?
      request.format.csv? && request.path.start_with?("#{ReactiveAdmin.config.mount_path}/")
    end

    # Last resort so API clients never get an html error page. The exception message is left out
    # of both the response and the log: it may carry sensitive data.
    def render_unexpected_error(exception)
      return false unless exception.is_a?(StandardError)

      Rails.logger.error("[reactiveadmin] #{exception.class} at #{exception.backtrace&.first} in #{controller_path}##{action_name}")
      ScrubbedError.report(exception, resource: resource_key_for_errors, action: action_name, request_id: request.request_id)
      status = ActionDispatch::ExceptionWrapper.status_code_for_exception(exception.class.name)
      render_api_error(:error, "#{exception.class} while rendering #{resource_key_for_errors} #{action_name}", status)
      true
    end

    def resource_key_for_errors = WriteAudit.resource_key(self)

    def render_api_error(code, message, status, location: nil, **extra)
      WriteAudit.rejected(self, code, guard: extra[:guard]) unless @reactiveadmin_write_rejected
      @reactiveadmin_write_rejected = true
      render json: {code:, message:, location:, **extra}.compact, status:, content_type: "application/json"
    end

    def render_redirect_result(location, _response_options)
      render_api_error(:error, "Unexpected redirect", 500, location:)
    end

    # AA's hook for denied authorization: answer before the host's `on_unauthorized_access`,
    # which redirects.
    def dispatch_active_admin_access_denied(exception)
      return super unless reactiveadmin_request?

      render_api_error(:forbidden, "Not authorized", 403)
    end

    # Left true when authentication fails by raising, so the host's handler (a redirect to sign in)
    # is answered as 401.
    def authenticate_active_admin_user
      return super unless reactiveadmin_request?

      @reactiveadmin_authenticating = true
      super
      @reactiveadmin_authenticating = false
    end

    # Exports keep AA's check that the format is one of the resource's download links.
    AA.format_guard_names.each do |name|
      define_method(name) { super() if !reactiveadmin_request? || reactiveadmin_export? }
      private name
    end
  end
end
