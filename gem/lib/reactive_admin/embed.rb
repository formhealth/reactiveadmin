module ReactiveAdmin
  # `?embed=1` on a classic URL: the same page without AA's chrome, plus a bridge that tells the
  # embedding window about size, navigation and flashes. Meant for iframes on the same origin.
  module Embed
    LAYOUT = "reactive_admin/embed".freeze
    CHROME = "#{AA.chrome_selectors} {display: none !important}".freeze
    BRIDGE = File.expand_path("../../app/assets/reactive_admin/bridge.js", __dir__)

    def self.bridge_js
      return File.read(BRIDGE) if Rails.application.config.enable_reloading

      @bridge_js ||= File.read(BRIDGE)
    end

    # Standard AA actions build the whole document themselves, so the chrome can only be hidden
    # and the bridge appended; custom actions get the embed layout instead.
    def self.inject(html, nonce: nil)
      return html if html.include?("data-reactiveadmin-embed") || !html.match?(/<\/body>/i)

      attribute = %( nonce="#{ERB::Util.h(nonce)}") if nonce
      html.sub(/<body\b([^>]*)>/i) { "<body#{$1} data-reactiveadmin-embed>" }
        .sub(/<\/head>/i) { "<style>#{CHROME}</style></head>" }
        .sub(/<\/body>/i) { "<script#{attribute}>#{bridge_js}</script></body>" }
    end

    # A redirect keeps the request inside the embed.
    def self.carry(url, request)
      uri = URI.parse(url.to_s)
      return url if uri.host.present? && uri.host != request.host

      uri.query = Rack::Utils.parse_query(uri.query.to_s).merge("embed" => "1").to_query
      uri.to_s
    rescue URI::InvalidURIError
      url
    end

    def redirect_to(options = {}, response_options = {})
      return super unless embed_request?

      super(Embed.carry(url_for(options), request), response_options)
    end

    def render(*args, &)
      embed_request? ? super(*Layouts.replace(args, LAYOUT), &) : super
    end

    private

    def embed_request?
      return @embed_request if defined?(@embed_request)

      @embed_request = params[:embed] == "1" && !reactiveadmin_request? && !frame_request?
    end

    def process_action(*)
      super
      finish_embed if embed_request?
    end

    def finish_embed
      response.headers["X-Frame-Options"] = "SAMEORIGIN"
      return unless response.media_type == "text/html" && response.body.present? && response.headers["Content-Disposition"].blank?

      response.body = Embed.inject(response.body, nonce: request.content_security_policy_nonce)
    end

    define_method(AA.layout_hook) do
      layout = super()
      (embed_request? && layout) ? LAYOUT : layout
    end
    private AA.layout_hook
  end
end
