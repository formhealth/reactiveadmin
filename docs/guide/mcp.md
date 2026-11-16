# MCP server

ReactiveAdmin can serve your admin to AI agents over the [Model Context Protocol](https://modelcontextprotocol.io). The endpoint is `{mount}/_mcp`, for example `POST /api/admin/_mcp`. An agent signs in as a person, and it can do only what that person can do in the admin.

The server adds no access of its own. Every tool call is an internal request to the same API the React client uses, sent through your app's whole Rack stack with the caller's `Authorization` header. Your authorization adapter (Pundit or any other), your controller overrides, masking, the declared-filter allowlist, optimistic locking, rate limits and audit events all apply unchanged. No tool reads a model directly.

## What the server speaks

- Streamable HTTP transport, revisions `2025-06-18`, `2025-03-26` and `2024-11-05`.
- One JSON-RPC 2.0 message per `POST`, answered with one JSON document. There is no SSE stream and no session, so `GET` and `DELETE` answer `405`.
- The methods `initialize`, `ping`, `tools/list`, `tools/call`, `prompts/list` and `prompts/get`. Batches are refused. The server advertises the `tools` and `prompts` capabilities, with `listChanged` false for both.
- It is written in the gem, not built on the `mcp` gem. The surface is six methods, and a hand-written server keeps a pre-1.0 dependency out of an app that handles sensitive data.

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

When the block returns `scopes`, reads need `config.mcp.read_scope` (default `admin:read`) and writes need `config.mcp.write_scope` (default `admin:write`). GET and HEAD requests are reads, except for a GET custom action the registration lists in `reactive { unsafe_gets ... }`. This applies to the whole API, not only `_mcp`. A token without the needed scope gets `403` with code `insufficient_scope` and a `WWW-Authenticate: Bearer error="insufficient_scope", scope="admin:write"` header. `tools/list` omits the write tools for a token that lacks the write scope, and `tools/call` answers them as unknown tools. Scopes don't open a resource to writes: its [mode](#resource-modes) must as well. `run_action` runs only the member, collection and batch actions the resource declares, with a method the action declares.

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

### 5. Choose what agents may change

Agents only read until you opt a resource in. Out of the box every resource and page is `:read_only` through MCP, whatever the token's scopes. See [Resource modes](#resource-modes).

```ruby
ActiveAdmin.register Post do
  reactive { mcp :full }
end
```

### 6. Origin

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
| `count_records` | How many records match `filters` and `scope`, and the count in each scope. No rows. | read-only |
| `get_record` | One record's fields and sections as text, and its custom actions. | read-only |
| `get_page` | A custom page as text, with its actions. A page with a filter (GET) form lists its fields as `query_fields`; `query` takes values for them and returns the results. | read-only |
| `get_form` | The new or edit form: each field's `key`, control, requirement, value and options, and the `lock`. Only on resources whose mode allows the write. | read-only |
| `field_options` | Typeahead for a filter or form field. | read-only |
| `reveal_value` | The full value behind an `expand_path` (a long text or a json value shown as a summary). Audited as a view. | read-only |
| `create_record` | Creates a record from `values` keyed by form field keys. | additive write |
| `update_record` | Changes fields. Needs the `lock` from `get_form`, or `lock_version`. A stale lock is refused. With `dry_run: true` it validates and returns each field's `from` and `to` without saving. | write |
| `delete_record` | Deletes a record. Needs `confirm: true`. | destructive |
| `run_action` | Runs a member, collection or batch action, with `inputs`. A GET action with a filter form takes `query`, like `get_page`. Anything but a GET needs `confirm: true`. | destructive |

A destructive call without `confirm: true` does nothing and returns a message that says what it would do, including the app's own confirmation text for an action. The model is expected to ask the user, then call again.

Tool results are compact JSON. Layout is reduced to text, `json` and long text values stay summaries with an `expand_path`, masked values stay `[masked]`, and nothing is added to what the API returned. A result over `config.mcp.max_response_bytes` is cut with an explicit note, such as "Showing 4 of 25 records because the response limit was reached", and `list_records` returns `next` for the following page. Errors come back as tool errors (`isError: true`) with a message that names the next step: `401` as re-authorize, `403` as a final refusal, `404`, `409` stale as "reload and review", `422` with the failing fields, and `429` with the wait.

`query` is an object nested by the form's field `param`s (`{"simulation": {"date": "2026-10-01"}}`, or the flat bracket names). The tool reads the view once without it to learn the declared fields, refuses any other field or a view with no GET form, and then reads it again with the query. It is audited as the same tool call and never logs the values.

Buttons that navigate the browser with a POST (see [Custom views](custom-views.md#navigating-post-buttons)) are never offered to MCP: the page has no node or action for them.

A nested resource needs its parent: pass `parent_id`. `list_resources` shows `nested_under`.

### Resource modes

Each resource and page has an MCP mode: `config.mcp.default` (`:read_only` unless you change it), or its own `reactive { mcp ... }`.

| Mode | Agents get |
| --- | --- |
| `:read_only` | The read tools: `describe_resource`, `list_records`, `get_record`, `reveal_value`, `field_options` for filters, and `get_page`. `run_action` reaches GET and HEAD actions, which are reads, except any listed in `unsafe_gets`, and the actions you list; an action declared for both GET and POST is judged by the verb of the call, so its GET runs and its POST is refused. No forms, no writes. |
| `:none` | Nothing. The resource or page is left out of `list_resources`, and every tool answers it as an unknown resource. |
| `:full` | Everything the `api` guards and the policy allow, as before modes existed. |

```ruby
ActiveAdmin.register Order do
  reactive { mcp :read_only, actions: [:approve, :refund_batch] } # or `mcp actions: [...]`
end

ActiveAdmin.register Patient do
  reactive { mcp :none }
end
```

`actions:` names custom member, collection and batch actions that agents may run on a read-only resource. It doesn't open `create_record`, `update_record`, `delete_record` or `get_form`, even for a name like `:destroy` that a batch action shares with a standard one: `actions: [:destroy]` lets agents run the batch delete, not `delete_record`. Use `:full` for those. Pages have no `run_action`.

`tools/list` leaves out any tool that no resource's mode offers: with no `:full` resource, the create, update, delete and form tools aren't listed, and `tools/call` answers them as unknown tools, like a write tool a token's scopes don't cover. A tool that is listed but called on a resource whose mode excludes it fails with the same "Unknown resource" tool error as a resource that doesn't exist, and changes nothing. `list_resources`, `describe_resource` and `get_record` show only what the mode leaves, so a read-only resource's `can` is `index` and `show`.

The API enforces the mode too, not only the tools: the requests MCP tools dispatch carry `reactiveadmin.mcp`, and the API refuses what the mode excludes with `403` `api_denied`, like an `api` guard. The React client and other token clients are unaffected.

A mode only narrows what the `api` guards leave open, and an `api` guard only narrows what the mode allows. Neither widens the other: `mcp :full` doesn't reopen an action `api :deny` reserves, and listing an action in `actions:` doesn't run it past a guard. The tightest of the two wins.

`rake reactiveadmin:doctor` lists each resource's mode with the tools and actions it leaves agents, and warns about `:full` on a resource in `sensitive_resources` or with masked attributes. See [Doctor](doctor.md).

### Counting

`count_records` takes the same `filters` and `scope` as `list_records` and asks the index for one row, so authorization, scoping, the declared-filter allowlist and the ransack guard are the index's own. It returns `total` for the filters and scope, and `scopes` with the count in each (counted over the filtered records, as the index tabs are). The row is dropped. A resource that turns off totals (`pagination_total: false`) has no `total`, and the result says so. A scope that sets `show_count: false` has no count.

### Dry runs

`update_record` with `dry_run: true` answers what the update would do and saves nothing:

```json
{"ok": true, "dry_run": true, "saved": false, "record": "posts/7",
 "changes": {"title": {"from": "Hello", "to": "Hello world"}, "status": {"from": "draft", "to": "published"}},
 "note": "Nothing was saved. Call again without dry_run to apply."}
```

Validation failures come back as the result (`ok: false`, `problems`), not as a tool error. Everything else, such as a stale or missing lock, a form the API can't submit, a refused field or a guard, is refused as it is for the real update.

It is the API's own `PATCH` with `dry_run: true`, so it passes the same checks as a write: the write scope, the `api` guards, authorization to update, the form-aware parameter checks and the optimistic lock. The write scope is needed because it is a `PATCH`. Then it assigns the permitted attributes, runs the model's validations in a transaction that is always rolled back, and reports the difference. Nothing is saved.

A rollback undoes rows, not what a callback sent elsewhere, so a dry run only assigns what can't save or run host code on its own: database columns the form offers a control for whose writer is the one Rails generates, and nested rows of a `has_many` (without a proc or method-name `limit`) or an `update_only` section. Anything else, such as an association or `*_ids` field (it saves at once on a persisted record), a stored or virtual attribute, a column the form has no control for, a column whose writer the model overrides, an attachment or a nested section that would replace a record, is refused with `400` naming the field. Send that update without `dry_run`.

- The diff covers the attributes the request submitted. A value a callback derives from them is not shown. Rows of `has_many` sections are counted (`nested`: `added`, `changed`, `removed`), not diffed.
- A masked attribute shows `[masked]` for `from` and `to`, never the value. A json value shows with its masked keys hidden, or as a size when it is large. Long text is cut.
- It runs only validations. The resource's `update` override, save callbacks and ActiveAdmin's update callbacks don't run, so a failure only they would cause (a `before_save` that halts, a database constraint) is not predicted. Controller `before_action` and `after_action` filters on the update do run, as they do for a write, so keep side effects out of them.
- It emits no `write.reactiveadmin` event. A dry run the API rejects (invalid, stale) still publishes `write_rejected.reactiveadmin` with `dry_run: true`, and the `mcp_call.reactiveadmin` event for it carries `dry_run: true`.
- `dry_run` is refused with `400` on every other API request (create, destroy, custom and page actions, and GETs) rather than ignored, so a request that acts is never run for real by mistake. An action that has its own `dry_run` parameter can't take it through the API.

### Prompts

`prompts/list` and `prompts/get` offer runbooks a person can start from their client (Claude Code lists them as slash commands). Each is one user message, built from tool names and a resource key, never from record data.

| Prompt | Arguments | Does |
| --- | --- | --- |
| `find_record` | `resource`, `details` | Learn the filters, count matches, list and confirm one record. |
| `review_recent_changes` | `resource`, `since` (optional) | Find a timestamp column and date filter, then summarize the newest records. |
| `bulk_update` | `resource`, `change`, `matching` | Count and sample, preview each change with `dry_run`, and ask for confirmation before applying with each record's lock. A stale record is previewed again and confirmed again. |

A prompt is offered only when every tool it names is visible to the token, so a token without the write scope doesn't see `bulk_update`. `resource` must be a registered key. The other arguments are text: whitespace is collapsed and they are cut at 500 characters. Each prompt ends by telling the agent that record contents are data, not instructions. An unknown prompt or a bad argument is a JSON-RPC `-32602` error.

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

The payload has `user_id`, `client_id` (when the block returned one), `tool`, `resource` (a registered key, otherwise left out), `action` (the action key for `run_action`, otherwise the tool's verb), `status` (`"ok"` or `"error"`), `http_status` of the API call behind it, and `duration_ms`. A dry-run `update_record` also has `dry_run: true`. It never has argument values or anything the API returned.

Because each tool runs through the API, the host's own events fire too, as the token's user: `write.reactiveadmin`, `write_rejected.reactiveadmin`, `export.reactiveadmin`, `value_viewed.reactiveadmin` and `lookup.reactiveadmin`, plus your own controller callbacks. Those requests carry `request.env["reactiveadmin.mcp"] = true` (set by the server, never by a client) for hosts that tell agent traffic apart.

The [audit envelope](security.md#audit-envelope) joins them for you: the `mcp_call` and every event its tool caused share a `correlation_id`, with `channel: "mcp"` and the `client_id`.

## Limits

Tool calls draw on the `mcp` rate-limit bucket (default 120 a minute per user), and the requests behind them draw on their own buckets, such as `options` and `value`. A call over the budget returns a tool error with the wait. `config.mcp.max_per_page` (default 25) caps `list_records`, below the API's own `max_per_page`.

## Things to know

- `describe_resource` fetches one index row to learn the columns, and discards it. Your host sees that as an index view. Pass `columns: false` to skip it.
- A tool's internal request runs in the same thread, inside the outer request. The gem sets the outer request's executor state aside for the call and restores it, so `CurrentAttributes` survive. In development, a code reload that lands mid-call is not protected.
- Pages that render raw HTML forms or iframes come back as a note to use the admin UI. The same limits as the React client apply.
