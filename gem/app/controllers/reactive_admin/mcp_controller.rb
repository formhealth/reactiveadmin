module ReactiveAdmin
  # `{mount}/_mcp`: the MCP endpoint (see Mcp). Bearer tokens only; a session cookie is never accepted
  # here, so a page the operator has open can't be made to drive it.
  class McpController < ApiController
    wrap_parameters false
    rescue_from ActionDispatch::Http::Parameters::ParseError, with: :parse_error
    before_action :authorize_root!
    before_action :ensure_enabled

    def create
      status, body = Mcp::Server.new(self).handle(request.raw_post)
      response.cache_control[:no_store] = true
      body ? render(json: body, status:, content_type: "application/json") : head(status)
    end

    # No server-initiated stream (GET) and no sessions to end (DELETE).
    def unsupported
      response.headers["Allow"] = "POST"
      head :method_not_allowed
    end

    private

    def token_only? = true

    def audit_writes? = false

    # Every message is a POST, but the tool behind it is what reads or writes, and its request is held to its own scope.
    def required_scope = ReactiveAdmin.config.mcp.read_scope

    # Before authentication: a disabled or foreign-origin request learns nothing about the app.
    def process_action(*)
      return reject(:not_found, "Not found", 404) unless ReactiveAdmin.config.mcp.possibly_enabled?
      return reject(:forbidden, "Origin not allowed", 403) unless Mcp.origin_allowed?(request)
      return reject(:invalid, "Unsupported MCP-Protocol-Version", 400) unless Mcp.protocol_version_supported?(request)

      super
    end

    def ensure_enabled
      reject(:not_found, "Not found", 404) unless ReactiveAdmin.config.mcp.enabled_for?(ReactiveAdmin.current_user(self))
    end

    def reject(code, message, status) = render(json: {code:, message:}, status:, content_type: "application/json")

    def parse_error = render(json: {jsonrpc: "2.0", id: nil, error: {code: -32700, message: "Parse error"}}, status: :bad_request, content_type: "application/json")
  end
end
