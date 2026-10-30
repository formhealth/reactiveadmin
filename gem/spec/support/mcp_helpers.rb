module McpHelpers
  def mcp_path = "/api/admin/_mcp"

  def json_headers = ApiHelpers::JSON_HEADERS

  def token_for(user, **) = DummyTokens.issue(user, **)

  def bearer(token) = {"Authorization" => "Bearer #{token}"}

  def rpc(method, params = nil, token:, id: 1, headers: {})
    body = {jsonrpc: "2.0", method:, id:, params:}.compact
    post mcp_path, params: body.to_json, headers: {"CONTENT_TYPE" => "application/json", "ACCEPT" => "application/json, text/event-stream"}.merge(bearer(token)).merge(headers)
    response.parsed_body if response.media_type == "application/json"
  end

  # The tool's result: parsed JSON for a success, the message for an error.
  def call_tool(name, arguments = {}, token:)
    reply = rpc("tools/call", {name:, arguments:}, token:)
    result = reply.fetch("result")
    text = result["content"].first["text"]
    @tool_error = result["isError"]
    @tool_error ? text : JSON.parse(text)
  end

  def tool_error? = @tool_error

  def capture_events(name)
    events = []
    subscriber = ActiveSupport::Notifications.subscribe(name) { |*, payload| events << payload }
    yield
    events
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end
end

RSpec.configure do |config|
  config.include McpHelpers, type: :request
  config.before { DummyTokens::STORE.clear }
end
