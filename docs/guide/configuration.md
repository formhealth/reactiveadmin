# Configuration

Set options in an initializer with `ReactiveAdmin.configure`:

```ruby
ReactiveAdmin.configure do |config|
  config.mount_path = "/api"
  config.doctor_user = -> { User.find_by!(email: "ops@example.com") }
end
```

Every option has a default, so you only set the ones you need. The table lists each option. Lambdas receive the controller unless noted otherwise.

## Options

| Option | Default | Purpose |
| --- | --- | --- |
| `namespace` | `:admin` | The ActiveAdmin namespace to serve. The API exposes that namespace's resources and pages. |
| `mount_path` | `"/api"` | The URL prefix for the API. The API lives at `<mount_path>/<namespace>`. |
| `current_user` | `nil` | `->(controller) { user }`. Returns the signed-in user. When unset, the gem calls the namespace's `current_user_method`. |
| `meta_cache_key` | `->(user) { user.try(:id) }` | `->(user) { value }`. Returns a JSON-able value that changes whenever the user's permissions or roles change. Users with equal keys share a cached `_meta` payload. |
| `meta_cache_version` | `nil` | A value, or `-> { value }`, that changes on every deploy of admin code. When unset, the gem reads `GIT_SHA`, `GIT_COMMIT`, `SOURCE_VERSION`, or `REVISION` from the environment. If none is set, it uses a per-process ID. In development, it changes on every reload. |
| `meta_cache_ttl` | `5.minutes` | How long the cache keeps a `_meta` payload. |
| `options_cache_ttl` | `60` | Seconds to keep a non-relation option list, such as a literal array or a computed collection. `0` disables the cache. |
| `inline_options_limit` | `100` | The largest option list the payload inlines. Larger lists switch to typeahead search through `_options`. Requests for `_options` also cap `limit` at 100. |
| `scope_options_by_policy` | `true` | Limits typeahead options to the rows the user may read, using the target model's ActiveAdmin read scope. Set `policy: false` on a source to opt out for that source. |
| `authorize_custom_actions` | `true` | Controls how custom member, collection, and batch actions are authorized. `true` checks every custom action up front through the adapter. `:match_active_admin` checks only what ActiveAdmin checks itself, which is when the action body loads `resource` or `collection`. Other values raise `ArgumentError`. |
| `expose` | `:all` | Which resources and pages the API serves. `:all` serves everything the policy permits. `:listed` serves only what you name: resources and pages placed in `ReactiveAdmin.menu`, keys in `exposed_resources`, and anything marked `reactive { expose true }`. Everything else answers `404` `not_found`. Other values raise `ArgumentError`. See [Security](security.md#exposure). |
| `exposed_resources` | `[]` | Route keys of resources, and keys of pages, to serve under `expose = :listed`. Use it for nested-only and hidden resources that no menu places. |
| `max_per_page` | `100` | Largest page the API serves. Larger `per_page` values are clamped. See [Security](security.md#page-size-sorting-exports-and-rate-limits). |
| `max_export_rows` | `10_000` | Largest CSV export. A bigger one answers `422` before streaming. `nil` removes the limit. |
| `rate_limits` | `{options: [30, 10.seconds], lookup: [120, 1.minute], export: [5, 1.minute], value: [60, 1.minute], mcp: [120, 1.minute], default: nil}` | Requests per user in a window, as `[count, period]`, by bucket. `options` covers `_options` (search and value labels), `lookup` covers `_options/lookup`, `export` covers CSV, `value` covers `_value`, `mcp` covers MCP tool calls (see [MCP](mcp.md)), and `default` covers every other API request. `nil` for a bucket means unlimited, and `false` turns limiting off. Counts live in `Rails.cache`; a store that can't count (the null store) leaves requests unlimited. |
| `auth` | `nil` | How API requests authenticate. `nil` is the session. `ReactiveAdmin::Auth.any(ReactiveAdmin::Auth::Session.new, ReactiveAdmin::Auth::Bearer.new { \|token, request\| user })` accepts both. See [MCP](mcp.md#authentication). |
| `mcp.enabled` | `false` | Turns on `{mount}/_mcp`. `true`, `false`, or `->(user) { boolean }` to decide per user. Disabled answers `404`. |
| `mcp.read_scope`, `mcp.write_scope` | `"admin:read"`, `"admin:write"` | Scopes a bearer token needs for reads and for writes, when its resolver returns `scopes:`. `nil` stops requiring one. |
| `mcp.resource_metadata_url` | `nil` | URL of your OAuth protected resource metadata (RFC 9728), sent in `WWW-Authenticate` on `401`. |
| `mcp.allowed_origins` | `[]` | Browser origins besides this site's own that may call `_mcp`. Requests with no `Origin` header always pass. |
| `mcp.max_response_bytes`, `mcp.max_per_page` | `20_000`, `25` | Cap on one tool result, and on `per_page` for `list_records`. |
| `mcp.instructions` | built in | Text `initialize` hands the agent. |
| `api_guards` | `{}` | Guards by name for `api :name` in a registration: `->(user, request) { boolean }`, true to allow. Register with `ReactiveAdmin.api_guard(:name) { ... }` before the admin files load. See [DSL](dsl.md#custom-guards). |
| `sensitive_resources` | `[]` | Route keys of resources whose display names are sensitive (for example `authors`). Typeahead searches, option lookups and `_labels` that return their records publish `lookup.reactiveadmin` (resource, field, kind, target, result count, user; never the term or names), while staying background requests. `reactive { sensitive true }` or `sensitive false` sets it per resource. See [Security](security.md#lookup-audit). |
| `after_authorize` | `nil` | `->(controller) { ... }`. Runs after the manifest passes authorization. Use it when your base controller has its own verification callbacks, such as `skip_authorization` under Pundit. |
| `on_background_request` | `nil` | `->(controller) { ... }`. Runs for metadata GETs (`_manifest`, `_session`, `_meta`, `_options`, `_labels`) that carry `X-Reactiveadmin-Background`; record data is never background. Use it to skip view audits or session extension. Lookups of sensitive data are still audited through `lookup.reactiveadmin`. See [Security](security.md). |
| `implicit_defaults` | `:secure` | Which columns a resource's index and show sections show when they have no block. `:secure` shows json, jsonb and hstore columns as a summary and text columns truncated (the full value is an audited `_value` call), and leaves out binary columns, encrypted attributes, `filter_attributes` and masked attributes, reporting each as `implicit_column_hidden` in `degraded` (except attributes you masked explicitly, which are a decision). `:all` is ActiveAdmin's behavior. Other values raise `ArgumentError`. Explicit blocks are never filtered, and the default form isn't filtered either. See [Security](security.md#implicit-defaults). |
| `inline_json_limit` | `2048` | Largest json value, in bytes of JSON, that a show page or an edit form sends inline. Larger values, values with a masked key at any depth, and every index cell are sent as a `summary` (kind, up to 20 top-level keys, size) plus an `expand_path` to the audited `_value` endpoint. |
| `inline_text_limit` | `2048` | Largest text column, in bytes, that a show page sends whole for a resource without a `show` block under `implicit_defaults = :secure`. Longer text, and every index cell over 120 characters, is sent as a 120-character preview with `truncated: true` plus an `expand_path` to the audited `_value` endpoint. |
| `value_token` | `true` | `_value` answers only for the signed `token` in an `expand_path`, issued for the same user, record and field, instead of rendering index, show and the edit form to rebuild its allowlist. `false` restores that rendering and tokenless links. See [Security](security.md#json-values). |
| `value_token_ttl` | `15.minutes` | How long an `expand_path` token stays valid. A page left open longer needs a reload before its JSON can be expanded. |
| `strict_defaults` | `false` | `true` serves no columns or layout for a section without a block, and reports `implicit_view_blocked` in `degraded`. |
| `masked_attributes` | `[]` | Attribute names (symbols or regular expressions) whose values are masked everywhere in the API, on top of `reactive { mask }`. See [Security](security.md#masking). |
| `mask_filter_parameters` | `true` | Also masks attributes that match Rails' `filter_parameters`. Turn it off where that list names fields operators need to see, and list the secrets in `masked_attributes` instead. |
| `mask_csv` | `true` | Masks the same attributes in CSV exports, classic and API alike. Masked values export as `[MASKED]`. |
| `html_trusted_hosts` | `[]` | Hosts, as an array or a callable that returns one, whose images and embedded documents html may load besides this site; the manifest lists them as `site.trusted_media_hosts`. Other external media becomes a link. See [Security](security.md#html-policy). |
| `require_lock` | `true` | Updates must send back the `lock` token from the form. `false` accepts updates without one, still rejecting a stale token. Use `false` only for clients that predate locking. See [Security](security.md#optimistic-locking). |
| `retryable_errors` | `[]` | Error classes, or their names, that answer `409` `retry` (with `Retry-After`) and a "try again" message instead of `500`. Use them for host concurrency guards. |
| `error_reporter` | Calls `Rails.error.report` | `->(error, context) { ... }`. Receives each unexpected error as a `ScrubbedError`, which carries the class, backtrace, resource, action, and request ID, but never the original message. |
| `doctor_user` | `nil` | `-> { user }`. The user `rake reactiveadmin:doctor` samples as. Without it, the doctor reads code only and doesn't run requests. |
| `doctor_page_params` | `nil` | `->(page_key) { {post_id: 1} or nil }`. Query params the doctor renders a page with, for pages that read required params. `nil` renders the page without any. See [Doctor](doctor.md#pages-that-need-params). |
| `ui.available` | nobody | `->(user) { boolean }`. Who may use the new admin at the classic URLs and switch between the two. Reported in `_session`, where the client reads it. Runs on every `_session` request, so keep it cheap: read the user's flags or attributes, with no database queries. See [Roll out the new admin](rollout.md). |
| `ui.default` | `:classic` | `:classic`, `:new`, or `->(user) { mode }`. The UI to start an available user in, until they choose. Reported in `_session`. |
| `ui.enabled` | `true` | `false` takes the middleware that serves the client's shell out of the request path. |
| `ui.client_assets` | `public/reactiveadmin` | The directory of the built client (`rake reactiveadmin:client:build`). A path, or a callable that returns one. |
| `ui.asset_prefix` | `"/reactiveadmin"` | The URL prefix of the built files: a path the gem serves when nothing else does, or an absolute URL for a CDN. |
| `openapi.info` | `{}` | OpenAPI `info` overrides, merged over the default `title: "Admin API"` and the gem's `version`. |
| `openapi.output` | `"openapi/admin.yaml"` | Where `rake reactiveadmin:openapi` writes, relative to `Rails.root`. `OUT=` overrides it. |
| `openapi.security_schemes` | `nil` | OpenAPI security schemes by name, replacing the session cookie and CSRF token defaults. Use it for a bearer scheme. See [OpenAPI](openapi.md#authentication). |

## Settings from ActiveAdmin

The gem reads these settings from your ActiveAdmin configuration. Change them in `config/initializers/active_admin.rb`, not in `ReactiveAdmin.configure`:

- `site_title`, `site_title_link`, `site_title_image`, `favicon`, and `footer`
- `logout_link_path` and `logout_link_method`
- `default_per_page` and `max_per_page`
- `localize_format`, which selects the date and time formats
- `current_user_method` and `authentication_method`
- `authorization_adapter`
- `download_links`, which sets the default export formats

## Registering option sources and menus

Two other entry points live in the host app, not in the configuration block:

- `ReactiveAdmin.option_sources` registers named lists for typeahead inputs. See [DSL](dsl.md#option-sources).
- `ReactiveAdmin.menu` places resources and pages in the menu. See [DSL](dsl.md#menu-overlay).

Invalid values fail when you assign them. For example, `authorize_custom_actions` raises `ArgumentError` for any value other than `true` or `:match_active_admin`.
