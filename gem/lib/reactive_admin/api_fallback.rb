module ReactiveAdmin
  # GET actions that render an HTML template (or only answer html) have nothing to say to the API.
  # Without this they surface as 406 "unexpected error" reports; the contract says `unsupported`.
  # Prepended after ApiErrors so it sees the exception first.
  module ApiFallback
    UNSUPPORTED = [ActionController::UnknownFormat, ActionView::MissingTemplate].freeze

    def rescue_with_handler(exception, **)
      return super unless reactiveadmin_request? && request.get? && UNSUPPORTED.any? { exception.is_a?(it) }

      render_api_error(:unsupported, "Render in the classic admin", 501)
      true
    end
  end
end
