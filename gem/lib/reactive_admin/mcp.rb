module ReactiveAdmin
  # A Model Context Protocol server (Streamable HTTP, stateless JSON responses) over the admin API.
  #
  # It is hand-rolled rather than built on the `mcp` gem: the surface is four methods
  # (initialize, ping, tools/list, tools/call), every response is a single JSON document, and the
  # tool list depends on the caller's token, which a hand-rolled server makes trivial. That avoids a
  # pre-1.0 runtime dependency (and its json-schema dependency) in a gem that guards sensitive data.
  #
  # Tools never touch models. Each one dispatches an internal request through the host's Rack stack
  # to the same API routes the React client uses, with the caller's Authorization header, so the
  # controllers' authorization, masking, audit events and rate limits all apply unchanged.
  module Mcp
    autoload :Server, "reactive_admin/mcp/server"
    autoload :Api, "reactive_admin/mcp/api"
    autoload :Tools, "reactive_admin/mcp/tools"
    autoload :Output, "reactive_admin/mcp/output"
    autoload :Layout, "reactive_admin/mcp/layout"
    autoload :Shapes, "reactive_admin/mcp/shapes"

    PROTOCOL_VERSIONS = %w[2025-06-18 2025-03-26 2024-11-05].freeze
    # What a client that sends no MCP-Protocol-Version header is assumed to speak (per the spec).
    DEFAULT_PROTOCOL_VERSION = "2025-03-26".freeze

    # A tool failure the agent can act on. `message` is shown to the model, so it names the next step and
    # never carries record data.
    class ToolError < StandardError
      attr_reader :status, :code

      def initialize(message, status: nil, code: nil)
        super(message)
        @status = status
        @code = code
      end
    end

    module_function

    def protocol_version_supported?(request)
      version = request.headers["MCP-Protocol-Version"]
      version.blank? || PROTOCOL_VERSIONS.include?(version)
    end

    # The origin of a browser request, which an MCP endpoint must check against DNS rebinding.
    def origin_allowed?(request)
      origin = request.headers["Origin"]
      return true if origin.blank?

      [request.base_url, *Array(ReactiveAdmin.config.mcp.allowed_origins)].any? { it.to_s.chomp("/").casecmp?(origin) }
    end
  end
end
