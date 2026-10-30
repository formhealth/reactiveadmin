# Security

reactiveadmin adds an API on top of your ActiveAdmin resources. It keeps ActiveAdmin's authentication, authorization, and write path, and it adds guards of its own. This page describes what the gem enforces, what your app must still do, and how to handle sensitive data, such as PII or PHI.

## Authentication

The API runs your ActiveAdmin `authentication_method` before every action. A request that fails authentication gets a JSON response, not a redirect:

```json
{ "code": "unauthorized", "message": "Authentication required", "location": "/admin/login" }
```

The `location` is the URL your authentication method redirects to. The client uses it to send the operator to sign in. The status is `401`.

## Authorization

Every endpoint checks ActiveAdmin's authorization adapter, the same one that guards the classic pages. The default adapter and `ActiveAdmin::PunditAdapter` both work.

- **The manifest** requires read permission on the namespace's root page. The `after_authorize` hook runs after that check.
- **Index, show, and forms** require the matching read, update, or create permission on the resource.
- **Custom member, collection, and batch actions** are authorized before the action runs. `authorize_custom_actions` controls how strictly. The default, `true`, checks each action through the adapter. `:match_active_admin` checks only what ActiveAdmin checks itself.
- **Each row and record** carries a `permissions` object, so the client can hide controls the user can't use. The server still checks every request, so the object is for display only.
- **Form choices** (`_options` and `_options/lookup` with `context=form`) need what the form itself needs: create permission when there is no `id`, update permission when there is one. A page form's choices need the permission of the action the form posts to. `context=filter` needs only read. Without them the answer is `403`, as for `new` and `edit`.
- **Typeahead options** are limited to the rows the user may read, when `scope_options_by_policy` is on. Sources can opt out with `policy: false`. Use that only for lists that hold no restricted data.

A denied request returns `403` with code `forbidden` and the message "Not authorized". Authorization runs through the adapter, so custom adapters and Pundit policies apply without changes.

### The `after_authorize` hook

Some base controllers verify authorization in their callbacks. Under Pundit, for example, a `verify_authorized` callback fails unless something marks the request as authorized. Set `after_authorize` to do that once the manifest passes:

```ruby
config.after_authorize = ->(controller) { controller.skip_authorization }
```

## Exposure

Authorization decides who may read a resource. Exposure decides whether the API serves it at all. With `config.expose = :listed`, the API serves only the resources and pages you name, so a new or forgotten resource stays classic-only until someone lists it. Set it for any app that holds sensitive data:

```ruby
ReactiveAdmin.configure do |config|
  config.expose = :listed
  config.exposed_resources = ["author_contracts"] # nested-only or hidden keys
end
```

A resource or page is exposed when it:

- is placed in `ReactiveAdmin.menu` (or `reactive { menu path: [...] }`),
- has its key in `config.exposed_resources`, or
- declares `reactive { expose true }`.

The namespace's root page is always exposed, so the shell can load. A nested-only resource, one whose `belongs_to` is required, also needs its parent to be exposed. `reactive { expose false }` denies a resource even when something lists it.

Everything else answers `404` with code `not_found` on every endpoint: index, show, forms, writes, actions, `_meta`, `_options`, `_value`, CSV and `_pages`. The check runs after authentication and before authorization, so a signed-out client still gets `401`, and a signed-in one learns nothing about what exists. The manifest, the menu, and record references leave out unexposed resources. The classic admin is unaffected.

`rake reactiveadmin:doctor` reports `exposure_permitted_not_exposed` (what the policy permits for the doctor user but you haven't exposed) and `exposure_unknown_key` (a listed key that matches nothing).

## API guards

Authorization says who may act. Some actions must not run through the API at all, whoever the user is, or only for some callers: granting superadmin, changing roles, impersonating another user. Declare an `api` guard and the server refuses them on every API request, so they stay out of reach of the React client and of anything else that dispatches through the API, such as an MCP server. The classic admin is unaffected.

```ruby
ActiveAdmin.register AdminUser do
  permit_params :name, :email, :role, :superadmin

  api :deny, only: [:impersonate, :destroy], reason: "Impersonation happens in the classic admin"
  api :deny, attributes: [:role, :superadmin], reason: "Roles are changed in the classic admin"
  api :session_only, only: [:update]

  member_action :impersonate, method: :post do
    # ...
  end
end
```

With this, `POST /api/admin/admin_users/7/impersonate` and `DELETE /api/admin/admin_users/7` return `403`, so does any write that includes `role` or `superadmin`, and so does an update that authenticates with a token instead of a session. The same requests to `/admin/admin_users/...` work as before. See [DSL](dsl.md#api) for the guards (`:deny`, `:read_only`, `:session_only`, and your own) and their options.

What the server does:

- **It decides by the controller and action that will run**, not by what the manifest advertises. The check runs for every API request: the mount path, a classic URL requested with the `application/vnd.reactiveadmin+json` media type, a session cookie, a bearer token. It runs after authentication, so a signed-out client still gets `401`, and next to [exposure](#exposure), before authorization and before any callback or action of yours acts. A second check immediately before the action runs covers a controller that skips authentication. A guard you registered runs here, with the user and the request.
- **It answers `403` with code `api_denied`**, a `message` (your `reason:`, or the guard's default), the `guard` that refused (`deny`, `read_only`, `session_only` or your name), and `classic_url`, the classic page of the same request: the page itself for a GET, else the record's or the resource's page. A refused write that includes guarded attributes also lists their names in `attributes`, never their values.
- **It fails closed.** Guards stack and any refusal wins. A registered guard that returns false, raises (the error stays out of the response and the log) or has been removed refuses. An unknown guard name stops the boot.
- **It closes the side doors.** Batch actions are matched by name, so `POST .../batch_action` with `batch_action=promote` is refused. `?_method=delete` and other method overrides land on the action that would run, and are refused. A format suffix other than the API's own (`.json`, `.xml`) is a `404`. Form choices of a refused form are refused. Forms in a page's content that post to a refused action are refused when their choices load and when they submit. A resource denied whole also drops out of the manifest, the typed cross-links, and the menu, where it stays as a link to its classic page.
- **It tells each caller the truth.** `:session_only` is the one guard that depends on how the request authenticated, which the server knows from the request itself. The metadata caches are kept apart by it, so a token never reads what a session was shown.
- **It publishes `write_rejected.reactiveadmin`** with `code: "api_denied"` and the `guard`, for every verb, because a GET can act too. The event carries the resource, action, record id and user id, never params or values.

Reading is unchanged for attribute guards: a guarded attribute still shows in index, show and forms, read-only, with a link to the classic admin. Use `mask` to keep a value out of the API.

Things to know:

- Attributes are matched by key name at any depth of the request's params, so `author_attributes[profile_attributes][role]` is caught, and so is a `role` inside a JSON column. For an association, its foreign key, its ids and its `_attributes` count as the attribute. Only unsafe verbs count: GET requests may carry a `role` filter.
- `api` guards don't protect classic URLs. The classic admin keeps answering in any format ActiveAdmin allows, with whatever authentication the host accepts there. The gem never authenticates a bearer token on a classic route, so a token can't reach them; a host that adds its own token authentication to classic routes reopens the gap.
- `:session_only` trusts the host's bearer adapter to tell tokens from sessions. A custom guard that checks `request` headers does too.
- A name that matches no action guards nothing. `rake reactiveadmin:doctor` lists every declaration as an accepted decision, and reports a name that matches no action as `api_guard_unknown_action`.

## Format lockdown

The API mount answers only in its own format, plus CSV exports on index. Requests for other formats return `404` with code `not_found`:

- `GET /api/admin/authors/:id.json` and `.xml` return `404`. They would serialize whole records.
- `GET /api/admin/authors.csv` returns the CSV export, which honors your `csv do` block and the current filters and scopes.

A request for an unknown path under the mount also returns `404` JSON, not the host's HTML error page.

## Filters and search

The API honors only the Ransack predicates that a declared filter can produce. A `q[...]` key that no filter explains returns `400` with code `invalid` and a message that names the key:

```json
{ "code": "invalid", "message": "Unsupported filter: npi_null" }
```

This keeps `q` from probing columns the page never shows. Classic pages aren't affected by this guard.

Typeahead searches cover only the source's `search` columns. The search matches the start of words, and pasting an id returns that record. Choose the `label` of an option source with care, because anyone who can read the source can see its labels.

## Page size, sorting, exports and rate limits

ActiveAdmin accepts any `per_page` and sorts by any column. The API bounds both, and budgets the endpoints that are cheap to call and costly to serve.

- **`per_page`** is clamped, not rejected, to `max_per_page` (default `100`). A resource's own `max_per_page` still applies, and the sizes it offers (`per_page: [25, 250]`) raise the cap for it. A value that isn't a positive integer uses the resource's default page size. A resource with pagination turned off keeps its own `max_per_page`.
- **`order`** must name a column the index shows and marks sortable (by its `sort_key`, so `order_by` clauses work), or be the resource's default `sort_order`. Anything else returns `400` with code `invalid` and the message `Unsupported sort: <key>`. Sorting by a hidden column would reveal how its values compare, so the allowlist applies to exports too. The message carries the key only.
- **Exports** stop at `max_export_rows` (default `10_000`). A larger export returns `422` with code `invalid` and "Narrow your filters to export fewer than N rows". The check is a `LIMIT n+1` count before streaming. Set it to `nil` to remove the limit.
- **Rate limits** give each user a budget per bucket and window, counted on `Rails.cache`. Over budget returns `429` with code `rate_limited` and a `Retry-After` header in seconds. The buckets are `options` (typeahead search), `lookup` (labels for selected values, batched per form), `export`, `value` (full json values), and `default` (every other API request):

```ruby
config.rate_limits = {options: [30, 10.seconds], lookup: [120, 1.minute], export: [5, 1.minute], value: [60, 1.minute], default: nil}
```

  A bucket set to `nil` is unlimited. `config.rate_limits = false` turns limiting off. Budgets key on the user id, never the IP address. They need a cache store shared by your processes. A null store, or a cache error, leaves requests unlimited.

Each export emits `export.reactiveadmin` with `resource`, `user_id`, `filters` (the `q` keys, never the values), `scope` and `row_count`. Subscribe to it for your audit trail, as with `value_viewed.reactiveadmin`:

```ruby
ActiveSupport::Notifications.subscribe("export.reactiveadmin") do |*, payload|
  Audit.record("export", payload)
end
```

## Actions and buttons

The header lists a member or collection action only when one of these is true:

- An action item or a link in the content references it.
- You expose it with `expose` in the `reactive` block.

An `if:` lambda that raises hides the action. A button the host meant to withhold stays hidden. See [DSL](dsl.md#expose).

## Background requests

Clients mark metadata requests that they make without the operator asking for a page. They send the header `X-Reactiveadmin-Background: 1`.

The route decides what can be background, not the header. Only these GET endpoints honor it: `_manifest`, `_session`, `{resource}/_meta`, `{resource}/_options` (and its `lookup`), and `{resource}/_labels`. They carry no record data beyond display names. For everything else the header is ignored, so these are always views:

- `show`, `index`, `new`, and `edit`
- `_value`
- pages and actions
- CSV exports and all writes

The gem exposes the decision in two ways:

- `config.on_background_request` runs for background requests before your own callbacks. Use it to skip view audits, or to stop background traffic from extending an idle session.
- `ReactiveAdmin.background_request?(request)` returns `true` for those requests. Call it from your own callbacks, such as the one that records page views or refreshes the session. It is `false` for record data whatever the header says, so a `curl` that sets the header still produces an audit event and extends the session.

Lookups that return sensitive names are background for sessions and page views, but they are still audited; see [Lookup audit](#lookup-audit).

The header can still be set by hand, but the only requests it can hide are metadata ones. Per-record reads cannot skip your audit, and `rate_limits[:default]` bounds how fast anyone can scrape them. Set a default budget in your host.

The standalone client does not prefetch records. Opening a record always sends a fresh request, even when the cache holds the record, so every open is audited. The command palette's recent records ask `GET /admin/{resource}/_labels?ids=` for display names only. Each record needs READ, as in `show`; ids that are missing or refused are omitted, and at most 20 ids are looked up. `rake reactiveadmin:doctor` marks its samples as internal, so hosts keep them out of the audit too.

## Sessions and CSRF

The API uses the session cookie, so the client and the API must share an origin. In development, the Vite proxy handles that. In production, serve the client from the same host as the admin.

Writes need a CSRF token:

1. The client calls `GET /api/admin/_session`. The response includes the current user and a `csrf_token`.
2. Each write sends the token in the `X-CSRF-Token` header.
3. A missing or stale token returns `422` with code `invalid_csrf`. The client fetches a new token and retries once.

Frame writes follow the same rule. The client moves the form's CSRF field into the header.

### Bearer tokens

A host that sets `config.auth` can accept bearer tokens on the same API, for agents and scripts (see [MCP](mcp.md#authentication)). A request under the API mount (`{mount_path}/{namespace}/`) with an `Authorization: Bearer` header is authenticated by the token alone. Anywhere else, including classic routes such as `/admin/...` in any format, the header is ignored and the session decides:

- The session and its cookies are never consulted, and the cookies are dropped before the host sees them. A bad token is `401`, even when the request also carries a valid session.
- CSRF is skipped for these requests only. A browser can't attach an `Authorization` header to a cross-site request, so there is nothing to forge.
- The token's user is the current user for the authorization adapter and for host code, so a Pundit policy sees the same user it would for a session.
- A resolver that returns `scopes:` limits the token: reads need `mcp.read_scope`, writes need `mcp.write_scope`. A missing scope is `403` with code `insufficient_scope`.

## Writes

Writes run through ActiveAdmin's own controller, as HTML. Validations, callbacks, `controller do` overrides, and flashes all run as they do in the classic admin. The gem then translates the result into JSON:

- A redirect becomes a `200` or `201` response with `ok`, `id`, `message`, and `location`.
- A validation failure becomes a `422` with code `invalid`, and field errors under `errors`.

Every successful write and every rejected write from a signed-in user publishes an event. See [Write audit](#write-audit).

## Optimistic locking

Two operators can open the same record and save changes that overwrite each other. The gem guards updates with a lock token that the form response carries:

```json
"lock": { "field": "lock_version", "value": "3" }
```

Send the object back unchanged as the top-level `lock` in the update body:

```json
{ "author": { "email": "ada@example.com" }, "lock": { "field": "lock_version", "value": "3" } }
```

The gem picks the field. It uses `lock_version` when the model has Rails' optimistic locking, and `updated_at` otherwise. An `updated_at` token doesn't move when only nested rows change, so prefer `lock_version` for models with `has_many` forms. Create requests don't need a token.

- **Missing token.** With `config.require_lock = true` (the default), an update without `lock` returns `400` with code `invalid`. Reload the form and try again.
- **Stale token.** A token that no longer matches returns `409` with code `stale` and the message "This record changed since you opened it."
- **Row lock.** For `updated_at`, the gem holds a row lock from the check until the write commits (host before_actions run before it), so a concurrent update can't slip between them.

Set `require_lock = false` only for clients that predate locking. Those clients still get `409` for a stale token.

## Retryable errors

Some host errors mean "try again", such as a busy advisory lock. Declare them, and the API answers `409` with code `retry` and a `Retry-After: 1` header instead of a `500`. The code differs from `stale` because nothing changed under the user: clients resend the same write, and only a `stale` response means "review the changes":

```ruby
ReactiveAdmin.configure do |config|
  config.retryable_errors = ["Billing::LockBusy"]
end
```

Accept classes or class names. Names suit constants that reload in development. The gem checks the error and its cause, so a wrapped error still counts.

## Forms that can't be submitted

A form the API can't post faithfully is marked `submittable: false` in its `FormResponse`, with an `unsupported_reason`. A form is not submittable when:

- an html section holds raw inputs (`input`, `select`, `textarea`, or a submit button), because the sanitizer would drop them,
- an input has no typed control and renders as html,
- a form block, a section, or a `form partial:` raises.

Clients should disable Save for these forms. A write to one returns `422` with code `unsupported`. The exception is a form partial, or a record that a custom `new` built: their writes go through unless the form holds raw inputs.

## Frames and embeds

Frame responses are sanitized twice. The server removes `<script>` elements, `on*` attributes, `javascript:` URLs, and `srcdoc`. The client then runs the result through DOMPurify. The embed response sends `X-Frame-Options: SAMEORIGIN`, so only same-origin pages can frame it.

### Typed nodes and where markup comes from

Two rules keep text a user wrote (for example Markdown a host renders unfiltered) from becoming a dangerous typed node.

**Markers.** When the gem puts a JSON value into a show row, it keeps the node in a table that lives for that request and writes only a random id into the markup. The walker resolves ids from that table, and drops anything else (a `data-node` attribute, a guessed id) with a `forged_node_marker` degradation. Only `json`, `text`, `empty`, and `form` nodes can use this channel.

**Provenance.** The walker does interpret markup: `<a data-method>`, a one-button `<form>`, and an `<iframe>` in rendered HTML can all turn into typed nodes. Which ones it trusts depends on who wrote them.

- While the gem renders a request, `link_to`, `button_to`, and the form helpers (`form_for`, `form_with`, `form_tag`, Formtastic) stamp the anchor or form they return with a random per-request secret (`data-reactiveadmin-origin`). The stamp never leaves the server: sanitizers strip it, and the secret dies with the request. Output outside a render of the gem is never stamped, so classic pages are unchanged.
- Only a stamped control becomes an `action` node, and only a stamped form becomes a `frame`. A `data-method` link or a one-button form that came from a string value (`raw(markdown)`, `simple_format(record.notes)`, `html_safe` on stored data) has no stamp. A link with a non-GET `data-method` becomes plain text. A `data-confirm` link becomes an ordinary link, and its confirm text is dropped. A form becomes sanitized html with its inputs removed. Stored `data-method` links inside a stamped form's frame lose the attribute.
- Markup you write by hand in a template (a literal `<a data-method="delete">` or `<form>` in ERB) can't be told from stored text, so it gets no stamp either. Build controls with the helpers.
- A stamped POST control to a route of this host outside the admin and the API mount becomes a `navigate` action: the client submits a real form to it in the top window with the session's CSRF token. The server allows only this origin over http(s), a plain path, and a session request; a bearer token never gets one. The client checks the target again: http(s), same origin, not under `/admin` or `/api`, no dot segments, and no `javascript:` or `data:`.
- An `<iframe>` in markup becomes an `iframe` node only when its path is under `/admin/`, has no dot segments, and routes to a registered, exposed resource or page. Any other same-site path (an upload, a blob) becomes a link. Iframes the gem adds itself, for pages that run their own JS, always use the page's own classic URL.

This is defense in depth. Hosts should still render untrusted text through a filter: use Redcarpet's `filter_html: true` and `safe_links_only: true`, or `sanitize`.

**Client.** The client checks targets again before it renders them. An iframe `src` must be same-origin, an `/admin/` path, and is always loaded with `?embed=1`; so must a page the framed content asks to navigate to. A link is an admin path on this origin, or an http(s), `mailto`, or `tel` URL the server marked `external`. An action's API, form, and view paths must be same-origin. Anything else renders as plain text or not at all.

Iframes carry `sandbox="allow-same-origin allow-scripts allow-forms allow-modals allow-downloads allow-popups allow-popups-to-escape-sandbox"`. Classic pages need their own JS, session cookie, `data-confirm` dialogs, CSV downloads, and `target=_blank` links to Sidekiq and other tools, which is why popups may leave the sandbox. The sandbox omits `allow-top-navigation`, so a framed page can't navigate the app away. It isn't isolation, though: same-origin scripts can lift it. The `/admin/` path rule is the boundary.

## HTML policy

The server applies one sanitizer policy to all HTML it renders. Two rules apply, one for content and one for frames.

For `html` nodes in content:

- It removes `<script>` and `<style>`, and every tag or attribute outside the allowlist. Allowed URL schemes are `http`, `https`, `mailto`, and `tel`.
- It keeps images and documents that load from this site, as typed `image` and `document` nodes where it can (see below). A relative URL, the request's host, and any host in `html_trusted_hosts` count as this site. A `data:` URI is kept for images only.
- It replaces external images, documents, and embedded pages with a link that opens in a new tab. The link is labeled `External image`, `External document`, or `External page`. The gem records an `external_media_blocked` degradation.

For `frame` nodes, which allow forms:

- It removes `<script>`, `<base>`, `<meta http-equiv>`, `on*` attributes, `srcdoc`, and `javascript:`, `vbscript:`, and `data:` URLs in links and form actions.
- It points form actions at other sites to `#`, and removes off-site iframes, embeds, and objects. Links to other sites stay, with `rel="noopener noreferrer"`. The gem records a `frame_offsite_target` degradation.

List the hosts your content loads from. Use only hosts you control:

```ruby
ReactiveAdmin.configure do |config|
  config.html_trusted_hosts = ["documents.example.com"] # or a lambda that returns an array
end
```

The client builds its DOMPurify configuration from `rake reactiveadmin:html_policy`, so the two lists stay in step. Hosts are per deployment, so the client also reads them at runtime from the manifest (`site.trusted_media_hosts`) and the snapshot ships with none.

### Images and documents

Images and PDFs from this site or a trusted host become typed `image` and `document` nodes instead of raw HTML. An `<img>` becomes an `image` node with a lightbox. An `<embed>` or `<object>` that declares `application/pdf`, or an `<iframe>` whose path ends in `.pdf`, becomes a `document` node that the client shows in the browser's own PDF viewer.  Media inside a `<details>` stays typed inside its `disclosure` node.

- A same-site PDF must also end in `.pdf`, so a same-site HTML page can't render in the viewer. A trusted host may serve a declared PDF from an extensionless URL, such as a signed CDN link.
- Only http(s) URLs on this site or a trusted host become nodes. Never `data:` (it stays inside `html` for images only), `javascript:`, protocol-relative URLs, or URLs with credentials. The client checks each `src` again against the manifest's list.
- The browser loads the file straight from its host. The gem never proxies it and the client never fetches it through `fetch`, so sensitive documents travel from the CDN to the browser only, as they do in classic admin.
- Every request carries `referrerpolicy="no-referrer"`, so the admin URL (which names records) doesn't reach the CDN. For defense in depth, the host can also send `Referrer-Policy: same-origin` with the app shell.
- Signed URLs expire. An image that fails to load shows a notice with a link instead of a broken image. Reloading the page issues fresh URLs.

### Content-Security-Policy

The standalone app sets no CSP of its own. Whatever serves the app's HTML must allow the trusted hosts, or the browser refuses them even though the client accepts them. For a host `cdn.example.com`:

```
img-src 'self' data: https://cdn.example.com;
frame-src 'self' https://cdn.example.com;
object-src 'none';
```

`frame-src` covers the PDF viewer. Add `object-src https://cdn.example.com` only if your markup uses `<object>` outside the typed nodes. Keep the list in step with `html_trusted_hosts`: a host in one and not the other shows a blocked preview. Without a CSP the browser applies no restriction, and the client's own checks still limit loads to this site and the manifest's hosts.

## Degraded responses

When the gem falls back instead of failing, it says so. Index, show, form, and page responses list each fallback in `degraded`:

```json
"degraded": [
  { "kind": "implicit_column_hidden", "where": "index", "reason": "encrypted column hidden by secure defaults: secret" }
]
```

Each entry has a `kind`, a structural `where`, and a `reason`. The reason names an exception class or a rule, never a record value or an exception message.

- The `X-Reactiveadmin-Degraded` header carries the count on index, show, form, and page responses.
- Each entry publishes a `degraded.reactiveadmin` notification with `resource`, `action`, `kind`, and `where`. Send it to your metrics:

```ruby
ActiveSupport::Notifications.subscribe("degraded.reactiveadmin") do |*, payload|
  Metrics.increment("reactiveadmin.degraded", tags: payload.slice(:resource, :kind))
end
```

## Masking

Credentials and secrets never go over the API. The gem masks their values in index cells, show rows, and form fields. An attribute counts as masked when it matches one of these:

- `config.masked_attributes`, for names that apply across the app. Use symbols or regular expressions.
- `reactive { mask }`, for one resource.
- `config.mask_filter_parameters`, which is on by default and masks attributes that match Rails' `filter_parameters`.

```ruby
ReactiveAdmin.configure do |config|
  config.masked_attributes = [:api_key, /_token\z/]
  config.mask_filter_parameters = false # if filter_parameters also lists fields operators need, such as email
end
```

```ruby
ActiveAdmin.register Integration do
  reactive do
    mask :client_secret
  end
end
```

Masking works like this:

- A present value shows as a `masked` node. An empty value stays empty, so an operator can see that no secret is set.
- A form field for a masked attribute carries `masked: true` and no value. A blank submit keeps the stored value. To clear a secret, use a custom action or the classic admin.
- JSON values replace masked keys with `[masked]` in `_value` responses, and a value with a masked key is never sent inline.
- CSV exports mask attributes by default (`config.mask_csv`, on by default): each present value is written as `[MASKED]`.
- API CSV exports prefix any cell whose text starts with `=`, `+`, `-`, `@`, tab or CR with `'`, so spreadsheets don't run it as a formula. Classic exports keep AA's behavior.

Masking covers attribute values only. A column or row that a block computes is your code's responsibility.

## Implicit defaults

A resource without an `index` or `show` block shows default columns. With `config.implicit_defaults = :secure` (the default), the gem shows these columns safely:

- `json`, `jsonb` and `hstore` columns follow the [JSON values](#json-values) rule: a summary and an audited `expand_path`, with a small value inline on show.
- `text` columns are truncated. An index cell, and a show row longer than `inline_text_limit`, carries the first 120 characters (cut on the server) with `truncated: true` and an `expand_path` to the audited `_value` endpoint. Text of 120 characters or fewer is sent whole, and so is text up to `inline_text_limit` on show.

It leaves out these columns:

- `binary` columns, which have no meaningful display,
- encrypted attributes,
- attributes in `filter_attributes`, and
- masked attributes, which are credentials and secrets.

Each omitted column appears in `degraded` as `implicit_column_hidden`; a shown column is not degraded, and neither is an attribute you masked on purpose with `mask` or `config.masked_attributes`. Set `config.implicit_defaults = :all` to get ActiveAdmin's behavior instead (full text and every column).

A truncated text node looks like this:

```json
{
  "type": "text",
  "text": "Draft notes ...",
  "truncated": true,
  "expand_path": "/api/admin/notes/42/_value?field=body&token=eyJfcmFpbHMi..."
}
```

`_value` answers a text column with `{ "value": "<full text>" }` under the same token, `read` permission and audit as json. It serves only plain `text` columns, never with a `path`.

Two limits apply:

- An explicit block is never filtered. Declare an `index` and a `show` block for every resource that holds sensitive data.
- The default form isn't filtered. It shows the inputs ActiveAdmin's default form shows, so declare a `form` block as well.

Set `config.strict_defaults = true` to serve no columns or layout for a section without a block. The response records `implicit_view_blocked` in `degraded`. `rake reactiveadmin:doctor` lists the hidden columns for each resource.

## JSON values

A json or jsonb attribute can hold large or sensitive data, so the API summarizes it. An index cell always carries a summary. A show row carries the full value only when it is within `inline_json_limit` and has no masked key:

```json
{
  "type": "json",
  "summary": { "kind": "object", "keys": ["bio", "links"], "size": 5120 },
  "expand_path": "/api/admin/authors/42/_value?field=profile_data&token=eyJfcmFpbHMi..."
}
```

The summary lists the kind (`object` or `array`), up to 20 top-level key names, and the size in bytes. It never includes the values.

An edit form's json control follows the same rule: a stored value over the limit, or with a masked key at any depth, comes as `value: null` plus `summary` and `expand_path`. The editor loads it through `expand_path` on an explicit click, which is an audited view. On save:

- A summarized field that is omitted, `null` or `""` keeps the stored value. Send `{}` or `[]` to empty it.
- `[masked]` placeholders in a submitted value take back the stored value of the same key (matched by path), and a placeholder with nothing stored is dropped. The literal is never written.

To fetch the full value, call `expand_path` as given. Add `path` to read one nested key, such as `path=allergies.0`:

- The `token` in `expand_path` is a signed, short-lived proof (`value_token_ttl`, 15 minutes by default) that index, show or the edit form rendered this field of this record for this user. `_value` checks the proof instead of rendering those pages again. A missing, forged, expired or other-user (or other record or field) token answers `403 forbidden`. Reload the page for a fresh link.
- It authorizes `read` on the record, as show does. For a token from the edit form it also requires the `update` permission, and it requires the page that issued the token to still be served. Both are checked on every request.
- It answers `404` for an attribute that is neither json nor a plain text column, and for masked attributes.
- It replaces masked keys with `[masked]`.
- It sends `Cache-Control: no-store`.
- It publishes `value_viewed.reactiveadmin` with `resource`, `id`, `field`, and `user_id`. Because it is a real view, `on_background_request` never applies to it.

Set `config.value_token = false` to go back to the unsigned `_value`: it then renders index, show and the edit form again on each call to learn what the field may expose, and answers `404` for an attribute none of them show.

Send the event to your audit trail without the value:

```ruby
ActiveSupport::Notifications.subscribe("value_viewed.reactiveadmin") do |*, payload|
  AuditLog.record(:sensitive_view, **payload.slice(:resource, :id, :field, :user_id))
end
```

## Write audit

The gem publishes two events for writes from a signed-in user:

- `write.reactiveadmin` after a write succeeds and its transaction commits.
- `write_rejected.reactiveadmin` when the API rejects a write, with the `code` of the error.

Both carry `resource`, `action`, `id`, and `user_id`. A rejection also carries the `code`, including `api_denied`, with the `guard`, for what an `api` guard refused (see [API guards](#api-guards)). The `id` is included only when it is a plain identifier. The events never carry params or values.

## Lookup audit

A typeahead search, an option lookup, or `_labels` can return an author's name, and none of them is a page view. When the records returned belong to a sensitive resource, each request publishes one `lookup.reactiveadmin` event after it is answered:

| Key | Value |
| --- | --- |
| `resource` | The resource whose endpoint was called. |
| `field` | The input searched or resolved. `nil` for `_labels`. |
| `kind` | `:search` (term or listing), `:lookup` (selected values resolved, by `_options` or `_options/lookup`), or `:labels`. |
| `target` | The sensitive resource whose records were returned. |
| `result_count` | How many options or labels were returned. |
| `user_id` | The signed-in user. |

The event never carries the search term or a returned name. It is one event per request, and one per sensitive field for the batched `_options/lookup`, never one per result. The rate limits on `_options` and `_options/lookup` bound the volume. A failing subscriber is logged and never turns the lookup into a `500`.

Mark a resource as sensitive with `config.sensitive_resources = %w[authors]` (route keys), or in its own file with `reactive { sensitive true }`. `sensitive false` opts a resource out of the list. Choose resources whose display name is a person's name or otherwise identifies an author. A resource that only points at an author (a todo, a fee) isn't sensitive itself; its author typeahead is audited through the authors target. Staff names usually aren't sensitive.

Subscribe in the host:

```ruby
ActiveSupport::Notifications.subscribe("lookup.reactiveadmin") do |*, payload|
  Analytics.track(user_id: payload[:user_id], event: "Admin Lookup", properties: payload.slice(:resource, :field, :kind, :target, :result_count))
end
```

## Error codes

| Code | Status | Meaning |
| --- | --- | --- |
| `unauthorized` | 401 | Not signed in. `location` holds the sign-in URL. |
| `forbidden` | 403 | The policy denies the request. |
| `not_found` | 404 | No such record, or the resource isn't exposed. |
| `invalid` | 400 or 422 | Bad input or failed validation. A 400 also covers a missing `lock`. |
| `invalid_csrf` | 422 | Missing or stale CSRF token. |
| `unsupported` | 422 or 501 | A write to a form that can't be submitted returns 422. A GET view that no mode can render returns 501. |
| `stale` | 409 | The record changed since the form loaded. |
| `api_denied` | 403 | An `api` guard refused the action, resource, page or attribute. Carries `guard`, `classic_url`, and `attributes` for a write. Never retry it. |
| `retry` | 409 | A host error declared in `retryable_errors`. Carries `Retry-After: 1`. Resend the same write. |
| `rate_limited` | Planned | The contract defines the code, but no code returns it yet. |
| `error` | Usually 500 | An unexpected error. The message names the exception class and the resource, never the exception message. |

## Logging and errors

The gem keeps record data out of its own logs and responses:

- **Warnings** name the resource, the section, and the exception class. They include the first backtrace frame, not the exception message.
- **Unexpected errors** return an error status, `500` by default, with the exception class and the resource. The gem logs the class and the first backtrace frame.
- **Error reports** go to `config.error_reporter` as a `ScrubbedError`. It carries the original class, the backtrace, and the resource, action, and request ID. It never carries the original message. The default reporter calls `Rails.error.report`.
- **Doctor output** names resources, sources, and counts. It never prints record data or exception messages.
- **Server-Timing** headers carry only the database and application durations.

Two things remain your responsibility:

- Request logs record the query string, so `q[...]` values and the `term` parameter appear in them. Add any parameter that can carry sensitive data to `filter_parameter_logging`, in your app's initializer. Include the predicate keys, such as `name_cont`, if they can hold sensitive data.
- Errors raised inside your own code can carry sensitive data in their messages. The gem drops the message from its own reports, but it doesn't control what your code puts in an exception before the gem sees it.

The gem sends no analytics and no client-side error reports.

## The UI switch

`config.ui` ([Roll out the new admin](rollout.md)) lets a page load at a classic URL answer with the client's shell. What it exposes:

- **No new data path.** The shell is a static page, the same for everyone, and the middleware that serves it knows nothing of users, resources or authorization. Every record still comes through the API, with its authorization, exposure, `api` guards and audit.
- **A preference, not a credential.** The `reactiveadmin_ui` cookie holds `new` or `classic`, readable by scripts, with `SameSite=Lax`. Setting it by hand only chooses which UI renders. `ui.available` gates the interface; a user who isn't available is sent back to classic by the client, and the API doesn't depend on it.
- **Failure means classic.** `ui.available` defaults to nobody, and a callable that raises counts as unavailable. Without a client build, the middleware does nothing.
- **Public assets, uncached shell.** The built files are public and hold no secrets. The shell is `Cache-Control: no-store` and carries your app's default response headers and CSP nonce.

## Planned

These aren't in the gem yet:

- Rate limits on the API. The contract already defines the `rate_limited` code.

## Checklist

Before you expose a resource that holds sensitive data:

- [ ] `config.expose = :listed`, and the resource is placed in the menu, listed in `exposed_resources`, or marked `expose true` on purpose.
- [ ] The `index`, `show`, and `form` blocks declare only the fields the API needs.
- [ ] `masked_attributes` or `reactive { mask }` covers every credential and secret.
- [ ] `implicit_defaults` is `:secure`, and `strict_defaults` is on if a section must never show defaults.
- [ ] `require_lock` is `true` unless a client predates locking.
- [ ] `html_trusted_hosts` lists only hosts you control.
- [ ] Option sources declare `search:` columns and a safe `label`.
- [ ] Actions and attributes that grant privileges or act as another user are behind an `api` guard (`:deny`, or `:session_only` where the React client may use them), and your own code doesn't authenticate bearer tokens on classic routes (the gem doesn't).
- [ ] Custom actions have an authorization rule, and `authorize_custom_actions` is `true`.
- [ ] Your error reporter and log filters cover the sensitive data that can reach them.
- [ ] `filter_parameter_logging` covers the sensitive parameters that can reach the API.
- [ ] Your audit trail subscribes to `value_viewed.reactiveadmin` and `write.reactiveadmin`, and to `write_rejected.reactiveadmin` if you audit rejections.
- [ ] `sensitive_resources` names every resource whose display name identifies an author, and your audit subscribes to `lookup.reactiveadmin`.
- [ ] Background requests are handled in `on_background_request`, if your audit needs it.
