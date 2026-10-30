module ReactiveAdmin
  module Mcp
    # Calls the admin API through the host's whole Rack stack, as the caller: same Authorization header,
    # so its authentication, authorization, masking, audit events and rate limits apply to every tool.
    class Api
      Result = Data.define(:status, :body, :headers) do
        def ok? = status.between?(200, 299)
      end

      FORWARDED = %w[REMOTE_ADDR HTTP_USER_AGENT HTTP_X_FORWARDED_FOR HTTP_X_FORWARDED_PROTO HTTP_X_REAL_IP].freeze
      # Set by the server only (a client's header arrives as HTTP_*), for hosts that tell MCP traffic apart.
      ENV_KEY = "reactiveadmin.mcp".freeze

      # Status of the most recent call, for the audit event.
      attr_accessor :last_status

      def initialize(request) = @request = request

      def get!(path, query = {}) = call!("GET", path, query:)

      def call!(verb, path, query: {}, body: nil)
        result = call(verb, path, query:, body:)
        raise error_for(result) unless result.ok?

        result.body
      end

      def call(verb, path, query: {}, body: nil)
        status, headers, chunks = isolated { Rails.application.call(env_for(verb, path, query, body)).then { read(it) } }
        self.last_status = status
        Result.new(status:, body: parse(chunks), headers:)
      end

      private

      def env_for(verb, path, query, body)
        uri = query.compact_blank.empty? ? path : "#{path}?#{query.compact.to_query}"
        env = Rack::MockRequest.env_for(uri, :method => verb, :input => body&.to_json, "CONTENT_TYPE" => ("application/json" if body), "HTTP_ACCEPT" => "application/json")
        env.merge!(@request.env.slice(*FORWARDED))
        env.merge!("HTTP_HOST" => @request.host_with_port, "SERVER_NAME" => @request.host, "SERVER_PORT" => @request.port.to_s,
          "rack.url_scheme" => @request.scheme, "SCRIPT_NAME" => @request.script_name, "HTTP_X_REQUEST_ID" => @request.request_id, "HTTP_AUTHORIZATION" => @request.authorization, ENV_KEY => true)
        env["HTTPS"] = "on" if @request.ssl?
        env.compact
      end

      def read(response)
        status, headers, body = response
        chunks = +""
        body.each { chunks << it }
        [status, headers, chunks]
      ensure
        body.close if body.respond_to?(:close)
      end

      def parse(chunks)
        JSON.parse(chunks) if chunks.start_with?("{", "[")
      rescue JSON::ParserError
        nil
      end

      # Rails' executor middleware starts a fresh execution with `reset: true`, completing the one this
      # request is running in, which would clear the host's CurrentAttributes mid-request. Set the outer
      # execution aside for the nested call and put everything back after.
      def isolated
        state = ActiveSupport::IsolatedExecutionState
        keys = [Rails.application.executor, Rails.application.reloader].filter_map { it.active_key if it.respond_to?(:active_key) }
        outer = keys.index_with { state.delete(it) }.compact
        current = ActiveSupport::CurrentAttributes.descendants.to_h { [it, it.instance.attributes] }
        yield
      ensure
        outer&.each { |key, execution| state[key] = execution }
        current&.each { |klass, attributes| klass.instance.attributes = attributes }
      end

      def error_for(result)
        body = result.body.is_a?(Hash) ? result.body : {}
        ToolError.new(message_for(result.status, body, result.headers), status: result.status, code: body["code"])
      end

      def message_for(status, body, headers)
        code = body["code"]
        case status
        when 401 then "Authentication failed: the token was rejected or has expired. Ask the user to re-authorize."
        when 403 then forbidden_message(code, body)
        when 404 then "Not found: #{body["message"]}. The resource, record or action doesn't exist, or the user can't see it."
        when 409 then (code == "retry") ? "Busy: nothing was changed. Retry the same call." : "Stale: the record changed since it was loaded. Call get_form again, review the current values and retry with the new lock."
        when 422 then validation_message(body)
        when 429 then "Rate limited. Retry in #{headers["Retry-After"] || "a few"} seconds."
        when 400 then "Bad request: #{body["message"]}"
        when 501 then body["message"].to_s
        else "The admin API failed (HTTP #{status}#{" #{code}" if code})."
        end
      end

      def forbidden_message(code, body)
        case code
        when "insufficient_scope" then "#{body["message"]}. Ask the user to grant it."
        when "api_denied" then api_denied_message(body)
        else "Not authorized: the user's account may not do this. Do not retry; tell the user."
        end
      end

      DENIALS = {"read_only" => "Read-only through the API", "session_only" => "Not available to API tokens"}.freeze

      # Final, like any refusal: it names the classic page so the user can do it themselves.
      def api_denied_message(body)
        reason = body["message"].to_s.delete_suffix(".") unless ApiGuards::MESSAGES.value?(body["message"])
        attributes = " Reserved: #{body["attributes"].join(", ")}." if body["attributes"].present?
        path = body["classic_url"].to_s
        url = " at #{@request.base_url}#{path}" if path.start_with?("/")
        "#{denial(body["guard"])}#{": #{reason}" if reason.present?}.#{attributes} Do not retry or work around it; tell the user to use the classic admin#{url}."
      end

      def denial(guard) = DENIALS.fetch(guard.to_s) { ApiGuards::STATIC.include?(guard.to_s.to_sym) ? "Refused by the API" : "Refused by the API guard #{guard}" }

      def validation_message(body)
        problems = body.fetch("errors", {}).map { |field, messages| "#{field} #{Array(messages).join(", ")}" } + Array(body["base"])
        "Validation failed: #{problems.presence&.join("; ") || body["message"]}"
      end
    end
  end
end
