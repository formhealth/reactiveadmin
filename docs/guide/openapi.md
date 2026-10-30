# OpenAPI

reactiveadmin describes your admin API as an OpenAPI 3.1 document, built from your ActiveAdmin registrations. Point a docs viewer such as Scalar at it to browse every resource, filter, form and action your admin serves, and to try requests as the signed-in user.

The document is typed from declarations only. It never contains record data, option values, or anything masked, hidden or not exposed.

## Fetch the document

```text
GET /api/admin/_openapi
```

With the default `mount_path` and `namespace`, that's the URL. The response is `application/json`. It also answers `Accept: application/vnd.reactiveadmin+json`, so any client that can fetch `_manifest` can fetch this.

The endpoint works like `_manifest`:

- **Authentication** is yours: the ActiveAdmin `authentication_method` runs, and a signed-out request gets a JSON `401`.
- **The document is per user.** It lists only the resources, pages and actions that user may use, by the same rules as the manifest and the same ActiveAdmin authorization adapter. Two users with different permissions get different documents.
- **It's cached** per code version, locale and permission fingerprint, with the same key and TTL as `_meta` (`meta_cache_key`, `meta_cache_version`, `meta_cache_ttl`). A user whose permissions change without changing `meta_cache_key` sees the old document until the TTL passes.
- **It's rate limited** in the `default` bucket. See [Configuration](configuration.md).

Because the endpoint needs a session, a viewer must run in the same origin as your admin and send the cookie. Don't publish the document at a public URL. Use `rake reactiveadmin:openapi` when you need a file.

## Show it with Scalar

Serve a page from your app, at any path under the same origin. This example uses Scalar's CDN build:

```html
<div id="app"></div>
<script src="https://cdn.jsdelivr.net/npm/@scalar/api-reference"></script>
<script>
  Scalar.createApiReference("#app", {
    sources: [{ url: "/api/admin/_openapi" }],
  })
</script>
```

Scalar fetches the URL with the browser's cookie, so the document it shows is yours.

### Prefill the CSRF token

Writes need an `X-CSRF-Token` header. The document declares it as the `csrfToken` security scheme, which only write operations require. To save typing the token into the viewer, fetch it from `_session` and hand it to Scalar:

```js
const { csrf_token } = await fetch("/api/admin/_session").then((r) => r.json())

Scalar.createApiReference("#app", {
  sources: [{ url: "/api/admin/_openapi" }],
  authentication: { securitySchemes: { csrfToken: { value: csrf_token } } },
})
```

The `authentication` option names belong to Scalar and change between versions, so check its docs for yours. The token belongs to the session. A request with a missing or stale token answers `422` with code `invalid_csrf`. Reload the page to get a fresh one.

## Authentication

By default the document declares two security schemes:

| Scheme | Type | Used by |
| --- | --- | --- |
| `sessionCookie` | `apiKey` in a cookie, named after your app's session key | Every operation. |
| `csrfToken` | `apiKey` in the `X-CSRF-Token` header | Operations that aren't GET. |
| `bearerAuth` | `http` bearer | Every operation, as an alternative to the session, when `config.auth` has a bearer adapter (see [MCP](mcp.md#authentication)). A token needs no CSRF token. |

With a bearer adapter the document also lists `POST {mount}/_mcp`, which takes only the bearer token, unless `config.mcp.enabled` is off for the user.

If you authenticate another way, declare the schemes yourself. They replace the defaults. Session schemes are required together; a bearer scheme is an alternative to them:

```ruby
ReactiveAdmin.configure do |config|
  config.openapi.security_schemes = {bearer: {type: "http", scheme: "bearer"}}
end
```

An authorization adapter that defines a class method `openapi_security_scheme`, returning the same kind of hash, supplies the schemes when you configure none.

## What the document contains

- **Info and servers.** `info` is `{title: "Admin API", version: <gem version>}` merged with `config.openapi.info`. The single server is `/`, and every path includes the mount path.
- **Tags.** One tag per resource and per page, plus `meta`. The `x-tagGroups` extension groups tags by your menu groups, with anything the menu doesn't place under `Other`.
- **Operations per resource**, only for the actions the resource defines, the user may take, and no [`api` guard](dsl.md#api) refuses for the requesting channel:
  - list, with typed query parameters (below), show, the new and edit forms, create, update and delete;
  - the CSV export, if the resource offers one;
  - your member, collection and batch actions, one operation per HTTP verb;
  - `_meta`, `_options`, `_options/lookup`, `_labels` and `_value`.
- **Guards.** A resource or page an `api` guard denies is absent, and so is each denied action, batch action and form. Denied attributes are absent from write bodies, and the create and update descriptions name them. The server answers `403` `api_denied` to any of them. The document follows the channel it is for: a session's lists `:session_only` operations with `x-reactiveadmin-session-only: true`, a bearer caller's leaves them out, and `:read_only` leaves out every write. An operation a registered guard may refuse is documented as usual with `x-reactiveadmin-guard: <name>`.
- **Pages.** `GET .../_pages/{key}` and the page actions. A write to a form in a page's content is a page action. The fields of that form come with the page response, because rendering the content here would read data. A view with a GET form takes its fields as the free-form `form_fields` query parameter (`simulation[date]=2026-10-01`).
- **Metadata.** `_manifest`, `_session` and `_openapi`, and `_mcp` where bearer tokens are accepted.
- **Errors.** `401`, `403`, `404`, `409`, `422` and `429` reference the contract's error schemas.
- **Operation ids** are stable and unique: `listAuthors`, `getAuthor`, `createAuthor`, `updateAuthor`, `deleteAuthor`, `getNewAuthorForm`, `authorFeature` (a member action), `authorsStats` (a collection action).

Responses reference the generic schemas from `openapi/core.yaml`, embedded under `components`. Each resource adds typed schemas for its rows (`AuthorRow`), its list response and its write bodies (`AuthorCreateParams`, `AuthorUpdateParams`).

### The list query

- `q` carries one property for each **declared** filter predicate, such as `q[title_cont]`, typed by the filter: text, number, date range, boolean, or a choice. Any other predicate is a `400`, so the document offers none.
- `scope` is an enum of the scopes the user may see, and `order` an enum of the sortable column keys.
- `page` and `per_page` carry the default and the cap.

Choice filters and select inputs don't list their options. Their descriptions point at the `_options` endpoint, which applies the user's permissions and audit.

### Write bodies

Create and update bodies come from the same controls-only form schema the server judges writes by. The body has the form's controls under the resource's param key, nested has_many rows by index, and `lock` on update. Disabled inputs, which the server drops, and masked attributes, whose names are left out so no credential is published, aren't in the schema.

If a form can't be described (its block raised), the body is a generic object and the build reports a degradation.

## Write the document to a file

For a full document that describes the whole exposed surface, with no user and every permission, run:

```sh
bundle exec rake reactiveadmin:openapi
```

It writes YAML to `config.openapi.output` (default `openapi/admin.yaml`, under `Rails.root`). Set `OUT=path` to write elsewhere. Resources and pages still follow `config.expose`.

The output is deterministic, so two runs of the same code are byte-identical. Commit it and fail CI when it changes unexpectedly:

```sh
bundle exec rake reactiveadmin:openapi && git diff --exit-code openapi/admin.yaml
```

Set `doctor_user` before you run it. Scopes, batch actions and forms whose blocks read the current user need one to evaluate, and without one they're left out (the task warns). The user only feeds those blocks. Permission checks are skipped, so the file lists everything. Never serve it to users: it isn't filtered by permission.

## What the host configures

Nothing, to get started: the route comes with `ReactiveAdmin.routes(self)`. You can set:

- `config.openapi.info` for your title, version and description.
- `config.openapi.security_schemes` if you don't use the session cookie.
- `config.openapi.output` for the rake task's default path.
- `meta_cache_key`, so users with different permissions get different documents. The default, the user's id, is always safe.

The document is built on the first request after a deploy, and again after the TTL. It's cheap for a few resources. A large admin takes noticeably longer than `_manifest` the first time, so serve the viewer's first request from a warm cache if that matters.
