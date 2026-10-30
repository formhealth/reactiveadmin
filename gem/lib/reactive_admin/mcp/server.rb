module ReactiveAdmin
  module Mcp
    # JSON-RPC 2.0 over one POST per message (the Streamable HTTP transport without SSE or sessions):
    # initialize, ping, tools/list and tools/call. `handle` returns [http_status, body], body nil for 202.
    class Server
      NAME = "reactiveadmin".freeze
      INSTRUCTIONS = <<~TEXT.squish.freeze
        Operate the admin through these tools. Start with list_resources, then describe_resource to learn a resource's
        filters and fields. Results are what this user may see and do; a refusal is final, so report it rather than
        working around it. Writes and actions change real records: use get_form for current values and the lock,
        and confirm with the user before delete_record or run_action. Avoid reading more records than the task needs.
      TEXT

      class Rpc < StandardError
        attr_reader :code

        def initialize(code, message)
          super(message)
          @code = code
        end

        def to_error = {code:, message:}
      end

      def initialize(controller)
        @request = controller.request
        @controller = controller
        @identity = Auth.identity(@request)
      end

      def handle(raw)
        message = JSON.parse(raw)
        return invalid("Batch requests are not supported", -32600) unless message.is_a?(Hash) && message["jsonrpc"] == "2.0"
        return [202, nil] unless message.key?("method")

        reply(message)
      rescue JSON::ParserError
        [400, envelope(nil, error: {code: -32700, message: "Parse error"})]
      end

      private

      def reply(message)
        id = message["id"]
        result = dispatch(message["method"].to_s, message["params"].is_a?(Hash) ? message["params"] : {})
        return [202, nil] unless message.key?("id")

        [200, envelope(id, result:)]
      rescue Rpc => e
        message.key?("id") ? [200, envelope(id, error: e.to_error)] : [202, nil]
      end

      def dispatch(method, params)
        case method
        when "initialize" then initialize_result(params)
        when "ping" then {}
        when "tools/list" then {tools: Tools.visible(@identity).map(&:definition)}
        when "tools/call" then call_tool(params)
        when %r{\Anotifications/} then nil
        else raise Rpc.new(-32601, "Method not found")
        end
      end

      def initialize_result(params)
        asked = params["protocolVersion"].to_s
        {
          protocolVersion: PROTOCOL_VERSIONS.include?(asked) ? asked : PROTOCOL_VERSIONS.first,
          capabilities: {tools: {listChanged: false}},
          serverInfo: {name: NAME, version: VERSION},
          instructions: ReactiveAdmin.config.mcp.instructions || INSTRUCTIONS
        }
      end

      def call_tool(params)
        tool = Tools.find(params["name"]) or raise Rpc.new(-32602, "Unknown tool: #{params["name"].to_s.first(60)}")
        args = params.fetch("arguments", {})
        api = Api.new(@request)
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        text, error = run(tool, args, api)
        audit(tool, args, api, error:, started:)
        {content: [{type: "text", text:}], isError: error}
      end

      def run(tool, args, api)
        if (seconds = RateLimit.retry_after(:mcp, @identity.user.id))
          api.last_status = 429
          return ["Rate limited: too many tool calls. Retry in #{seconds} seconds.", true]
        end

        [Tools.call(tool, args, Tools::Context.new(api)), false]
      rescue ToolError => e
        api.last_status ||= e.status
        [e.message, true]
      rescue => e
        ScrubbedError.report(e, resource: tool.name, action: "mcp", request_id: @request.request_id)
        ["The tool failed unexpectedly (#{e.class}). Nothing more can be done from here; tell the user.", true]
      end

      # Who called what and how it went, never the arguments or anything the API returned.
      def audit(tool, args, api, error:, started:)
        ActiveSupport::Notifications.instrument("mcp_call.reactiveadmin", {
          user_id: @identity.user.id, client_id: @identity.client_id, tool: tool.name, resource: known_key(args), action: action_of(tool, args),
          status: error ? "error" : "ok", http_status: api.last_status, duration_ms: ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
        }.compact)
      rescue => e
        Rails.logger.error("[reactiveadmin] mcp audit failed: #{e.class}")
      end

      # Only keys the registry knows: a client-supplied string is never logged.
      def known_key(args)
        key = args["resource"] || args["page"]
        key if key.is_a?(String) && (Registry.find(key) || Registry.find_page(key))
      end

      def action_of(tool, args)
        action = args["action"]
        (tool.name == "run_action" && action.is_a?(String) && Tools::ACTION_NAME.match?(action)) ? action.first(64) : tool.name.split("_").first
      end

      def invalid(message, code) = [400, envelope(nil, error: {code:, message:})]

      def envelope(id, **body) = {jsonrpc: "2.0", id:, **body}
    end
  end
end
