# MCP server

reactiveadmin can serve your admin to AI agents over the [Model Context Protocol](https://modelcontextprotocol.io). The endpoint is `{mount}/_mcp`, for example `POST /api/admin/_mcp`. An agent signs in as a person, and it can do only what that person can do in the admin.

The server adds no access of its own. Every tool call is an internal request to the same API the React client uses, sent through your app's whole Rack stack with the caller's `Authorization` header. Your authorization adapter (Pundit or any other), your controller overrides, masking, the declared-filter allowlist, optimistic locking, rate limits and audit events all apply unchanged. No tool reads a model directly.

## What the server speaks

- Streamable HTTP transport, revisions `2025-06-18`, `2025-03-26` and `2024-11-05`.
- One JSON-RPC 2.0 message per `POST`, answered with one JSON document. There is no SSE stream and no session, so `GET` and `DELETE` answer `405`.
- The methods `initialize`, `ping`, `tools/list` and `tools/call`. Batches are refused.
- It is written in the gem, not built on the `mcp` gem. The surface is four methods, and a hand-written server keeps a pre-1.0 dependency out of an app that handles sensitive data.

## Host setup

You provide the OAuth authorization server. The gem validates tokens through a block you write and tells MCP clients where to sign in. It never issues tokens.

### 1. Authenticate bearer tokens

Accept both the session (for the React client) and bearer tokens (for agents):

```ruby
# config/initializers/reactiveadmin.rb
ReactiveAdmin.configure do |config|
  config.auth = ReactiveAdmin::Auth.any(
    ReactiveAdmin::Auth::Session.new,
    ReactiveAdmin::Auth::Bearer.new do |token, request|
      grant = AccessGrant.active.find_by_token(token) # your OAuth provider's lookup
      next unless grant

      {user: grant.user, scopes: grant.scopes, client_id: grant.client_id}
    end
  )
end
```

The block gets the token and the request. It returns:

- `nil`, for a token that is invalid, expired or revoked. The request answers `401`.
- A user, for a token that carries no scopes. The user must respond to `id`.
- `{user:, scopes:, client_id:}`. `scopes` is an array or a space-separated string, and `client_id` is the OAuth client, for the audit trail. Both are optional.

A request under the API mount with an `Authorization: Bearer` header is authenticated by the token alone. It never falls back to cookies, which are dropped before your app sees them, and it skips CSRF. Every other request is a session request, and a bearer header on a classic route such as `/admin/...` is ignored, so a token can't reach what an `api` guard keeps off the API. See [Security](security.md#bearer-tokens).

The token's user becomes the current user, so your `current_user_method` and your authorization adapter see them as they would for a session. ActiveAdmin's `authentication_method` is skipped for these requests. Authentication callbacks you added yourself to a base controller still run, so make any that read the session (Devise's `authenticate_*!`, for one) skip requests with a bearer header, or they will reject the token's user.

The block runs on every request, so a revoked token stops working at once. Keep it to one indexed lookup.

### 2. Require scopes

When the block returns `scopes`, reads need `config.mcp.read_scope` (default `admin:read`) and writes need `config.mcp.write_scope` (default `admin:write`). This applies to the whole API, not only `_mcp`. A token without the needed scope gets `403` with code `insufficient_scope` and a `WWW-Authenticate: Bearer error="insufficient_scope", scope="admin:write"` header. `tools/list` omits the write tools for a token that lacks the write scope.

Grant both scopes for an agent that edits, because a write tool also reads the form first. A token whose block returns a bare user has no scope claim, so no scope is required of it. Set `read_scope` or `write_scope` to `nil` to stop requiring one.

### 3. Publish protected resource metadata

MCP clients find your authorization server from [RFC 9728](https://datatracker.ietf.org/doc/html/rfc9728) metadata. Serve it from your app and tell the gem where it is. A `401` from the API then carries the URL, which starts the client's sign-in:

```ruby
ReactiveAdmin.configure do |config|
  config.mcp.resource_metadata_url = "https://admin.example.com/.well-known/oauth-protected-resource"
end
```

```ruby
# config/routes.rb
get "/.well-known/oauth-protected-resource", to: ->(_env) {
  body = {
    resource: "https://admin.example.com/api/admin/_mcp",
    authorization_servers: ["https://auth.example.com"],
    scopes_supported: %w[admin:read admin:write],
    bearer_methods_supported: ["header"]
  }
  [200, {"Content-Type" => "application/json"}, [body.to_json]]
}
```

Your authorization server must support OAuth 2.1 with PKCE and, for clients that register themselves, dynamic client registration or client ID metadata documents. Set the token's audience to the `resource` URL and have the block check it.

### 4. Turn it on

```ruby
ReactiveAdmin.configure do |config|
  config.mcp.enabled = ->(user) { FeatureFlag.enabled?("admin-mcp", user, default: false) }
end
```

`enabled` is `true`, `false`, or a callable that gets the authenticated user. When it is `false` for everyone, or the callable returns false for this user, the endpoint answers `404`. A plain `false` answers before authentication, so a disabled deployment reveals nothing.

### 5. Origin

A browser that calls `_mcp` sends an `Origin` header. The endpoint refuses any origin that is not this site's own or in `config.mcp.allowed_origins`, with `403`, which blocks DNS-rebinding attacks. Requests with no `Origin`, such as Claude Code and other non-browser clients, pass. Keep your `config.hosts` list tight as well.

## Connect Claude Code

```sh
claude mcp add --transport http admin https://admin.example.com/api/admin/_mcp
```

Claude Code finds your authorization server from the `401` challenge. Run `/mcp` in a session to sign in. To use a token you issued yourself, pass it as a header:

```sh
claude mcp add --transport http admin https://admin.example.com/api/admin/_mcp \
  --header "Authorization: Bearer $ADMIN_TOKEN"
```

## Tools

The tools are generic: a dozen that take a resource key, not one per operation. Call `list_resources` first.

| Tool | Does | Hints |
| --- | --- | --- |
| `list_resources` | Resources and pages the user may open, with what they can do and their menu descriptions. | read-only |
| `describe_resource` | Columns, filters and the exact params for each, scopes, sorting, batch and collection actions, and the create form. | read-only |
| `list_records` | Records as typed values. `filters` takes declared filter params, plus `scope`, `order`, `page` and `per_page`. | read-only |
| `get_record` | One record's fields and sections as text, and its custom actions. | read-only |
| `get_page` | A custom page as text, with its actions. A page with a filter (GET) form lists its fields as `query_fields`; `query` takes values for them and returns the results. | read-only |
| `get_form` | The new or edit form: each field's `key`, control, requirement, value and options, and the `lock`. | read-only |
| `field_options` | Typeahead for a filter or form field. | read-only |
| `reveal_value` | The full value behind an `expand_path` (a long text or a json value shown as a summary). Audited as a view. | read-only |
| `create_record` | Creates a record from `values` keyed by form field keys. | additive write |
| `update_record` | Changes fields. Needs the `lock` from `get_form`, or `lock_version`. A stale lock is refused. | write |
| `delete_record` | Deletes a record. Needs `confirm: true`. | destructive |
| `run_action` | Runs a member, collection or batch action, with `inputs`. A GET action with a filter form takes `query`, like `get_page`. Anything but a GET needs `confirm: true`. | destructive |

A destructive call without `confirm: true` does nothing and returns a message that says what it would do, including the app's own confirmation text for an action. The model is expected to ask the user, then call again.

Tool results are compact JSON. Layout is reduced to text, `json` and long text values stay summaries with an `expand_path`, masked values stay `[masked]`, and nothing is added to what the API returned. A result over `config.mcp.max_response_bytes` is cut with an explicit note, such as "Showing 4 of 25 records because the response limit was reached", and `list_records` returns `next` for the following page. Errors come back as tool errors (`isError: true`) with a message that names the next step: `401` as re-authorize, `403` as a final refusal, `404`, `409` stale as "reload and review", `422` with the failing fields, and `429` with the wait.

`query` is an object nested by the form's field `param`s (`{"simulation": {"date": "2026-10-01"}}`, or the flat bracket names). The tool reads the view once without it to learn the declared fields, refuses any other field or a view with no GET form, and then reads it again with the query. It is audited as the same tool call and never logs the values.

Buttons that navigate the browser with a POST (see [Custom views](custom-views.md#navigating-post-buttons)) are never offered to MCP: the page has no node or action for them.

A nested resource needs its parent: pass `parent_id`. `list_resources` shows `nested_under`.

### API guards

MCP requests authenticate with a token, so the [`api` guards](security.md#api-guards) judge them as tokens. Anything a static guard refuses (`:deny`, `:read_only`, and `:session_only`, which lets only a signed-in session through) is not offered. `list_resources` leaves out denied resources and pages and the actions a resource keeps from `can`, `describe_resource` and `get_record` list no denied action or batch action, and `get_form` has no denied field. Under `:read_only`, an agent sees a resource it can only read.

A guard you registered decides per request, so what it covers is offered with a note: `describe_resource`, `get_record` and `get_form` mark the action or field "may be refused (superadmin_session)", and list the actions in `guarded`.

A call that reaches a denied action anyway is refused by the API, before the action or any of your callbacks run, and comes back as a final tool error that names the guard, the reason and the classic page to use:

> Refused by the API: Roles are changed in the classic admin. Reserved: role. Do not retry or work around it; tell the user to use the classic admin at https://admin.example.com/admin/users/7.

The lead is "Read-only through the API" for `:read_only`, "Not available to API tokens" for `:session_only`, and "Refused by the API guard superadmin_session" for a registered guard.

`run_action` doesn't ask for confirmation of a denied action, because it can't run. The order of refusals is the API's: no valid token is `401`, a missing scope is `403` `insufficient_scope`, then `api_denied`.

## Audit

Every tool call publishes `mcp_call.reactiveadmin`. Subscribe to it for your audit trail:

```ruby
ActiveSupport::Notifications.subscribe("mcp_call.reactiveadmin") do |*, payload|
  AuditLog.record(:mcp_call, **payload)
end
```

The payload has `user_id`, `client_id` (when the block returned one), `tool`, `resource` (a registered key, otherwise left out), `action` (the action key for `run_action`, otherwise the tool's verb), `status` (`"ok"` or `"error"`), `http_status` of the API call behind it, and `duration_ms`. It never has argument values or anything the API returned.

Because each tool runs through the API, the host's own events fire too, as the token's user: `write.reactiveadmin`, `write_rejected.reactiveadmin`, `export.reactiveadmin`, `value_viewed.reactiveadmin` and `lookup.reactiveadmin`, plus your own controller callbacks. Those requests carry `request.env["reactiveadmin.mcp"] = true` (set by the server, never by a client) for hosts that tell agent traffic apart.

## Limits

Tool calls draw on the `mcp` rate-limit bucket (default 120 a minute per user), and the requests behind them draw on their own buckets, such as `options` and `value`. A call over the budget returns a tool error with the wait. `config.mcp.max_per_page` (default 25) caps `list_records`, below the API's own `max_per_page`.

## Things to know

- `describe_resource` fetches one index row to learn the columns, and discards it. Your host sees that as an index view. Pass `columns: false` to skip it.
- A tool's internal request runs in the same thread, inside the outer request. The gem sets the outer request's executor state aside for the call and restores it, so `CurrentAttributes` survive. In development, a code reload that lands mid-call is not protected.
- Pages that render raw HTML forms or iframes come back as a note to use the admin UI. The same limits as the React client apply.
