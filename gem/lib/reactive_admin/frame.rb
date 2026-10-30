module ReactiveAdmin
  # Requests the client makes to classic URLs with X-Reactiveadmin-Frame: the same action and
  # authorization as the classic admin, answered without AA's layout. Writes are answered with
  # data the client can act on: a redirect becomes JSON, anything else stays html.
  module Frame
    HEADER = "X-Reactiveadmin-Frame".freeze

    # Scripts and handlers never reach the client; the client sanitizes again. A full AA page
    # (a standard action rendered by its own Arbre view) is cut down to its main content.
    def self.sanitize(html, host: nil) = HtmlPolicy.frame_body(content(html), host:)

    def self.content(html)
      return html unless html.match?(/<body\b/i)

      doc = Nokogiri::HTML5(html)
      (doc.at_css(AA.frame_content_selector) || doc.at_css("body")).inner_html
    rescue ArgumentError
      # Too deep for the document parser: frame_body parses the page as a fragment, degrading it under its own caps.
      html
    end

    def redirect_to(options = {}, response_options = {})
      return super unless frame_request?

      location = url_for(options)
      return render_api_error(:unauthorized, "Authentication required", 401, location:) if @frame_authenticating

      notes = flash.to_hash.merge(response_options.fetch(:flash, {}).to_h.stringify_keys, response_options.slice(:notice, :alert, :error).stringify_keys)
      flash.clear
      render json: {redirect: Location.for(location, host: request.host), flash: notes.compact_blank.transform_values(&:to_s)},
        content_type: "application/json"
    end

    def rescue_with_handler(exception, **)
      return super unless frame_request? && exception.is_a?(ActionController::InvalidAuthenticityToken)

      render_api_error(:invalid_csrf, "Invalid CSRF token", 422)
      true
    end

    def render(*args, &)
      frame_request? ? super(*Layouts.replace(args, false), &) : super
    end

    private

    def frame_request?
      return @frame_request if defined?(@frame_request)

      @frame_request = request.headers[HEADER].to_s == "1" && !reactiveadmin_request?
    end

    # Classic actions answer by format, and a client's Accept must not turn them into record dumps.
    # A format in the URL (a csv export) is the client's explicit choice and passes through.
    def process_action(*)
      request.format = :html if frame_request? && params[:format].blank?
      super
      sanitize_frame_response if frame_request?
    end

    def sanitize_frame_response
      return unless response.media_type == "text/html" && response.body.present? && response.headers["Content-Disposition"].blank?

      response.body = Frame.sanitize(response.body, host: request.host)
    end

    define_method(AA.layout_hook) { frame_request? ? false : super() }
    private AA.layout_hook

    def authenticate_active_admin_user
      return super unless frame_request?

      @frame_authenticating = true
      super
      @frame_authenticating = false
    end

    def dispatch_active_admin_access_denied(exception)
      return super unless frame_request?

      render_api_error(:forbidden, "Not authorized", 403)
    end
  end

  # Swaps the layout a custom render names explicitly (`render "x", layout: "active_admin"`), which
  # takes precedence over the controller's own layout.
  module Layouts
    module_function

    def replace(args, layout)
      options = args.last
      return args unless options.is_a?(Hash) && options[:layout]

      [*args[0...-1], options.merge(layout:)]
    end
  end
end
