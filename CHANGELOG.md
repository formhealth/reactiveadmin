# Changelog

All notable changes to this project are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project aims to follow [Semantic Versioning](https://semver.org/) from 1.0.

## 0.2.1

### Changed

- **Custom actions in the contract.** `core.yaml` declares GET member actions (`runMemberActionGet`, answering `ActionGetResponse`: a form, page content, options or a redirect's result), lets action writes answer `ActionWriteResponse` (a result or a re-rendered form), and declares their `501 unsupported`. The OpenAPI document gives member, collection and page actions the same responses.

### Fixed

- The client's files (`ui.asset_prefix`) are answered by a Rack middleware placed before the cookie and session middleware. They were served from the router, behind the session, so a host whose stack loads the session sent `Set-Cookie` on public, immutable responses, which a CDN could cache and hand to other visitors. Files that aren't hashed now say `Cache-Control: no-cache` themselves instead of relying on later middleware.

## 0.2.0

### Added

- **MCP agent workflow tools.** `count_records` returns the total and per-scope counts for filters and a scope, through the index's own guards, with no rows. `update_record` takes `dry_run: true` and returns each field's `from` and `to` without saving; it is the API's `PATCH ... dry_run`, validated inside a rolled-back transaction, with masked values hidden and no `write` audit event. It previews only plain attributes the form offers a control for, and in-memory nested rows, and `dry_run` is refused anywhere but update. `prompts/list` and `prompts/get` serve three runbooks (`find_record`, `review_recent_changes`, `bulk_update`), offered only when the token can use the tools they name, and `initialize` advertises the `prompts` capability.
- A project website on GitHub Pages (`apps/site`, VitePress): a landing page, the guides and the changelog, plus a demo of the React admin that runs on mock data (`pnpm --filter standalone build:demo`).
- The crawl runs against a host app: `--base-url` takes a host's admin URL, `--auth` names a login hook, and the `reactiveadmin-crawl` bin runs it from a checkout. Docs warn that crawling real data creates audit reads and recommend a dedicated user.
- Performance budgets for the crawl (`--budget=p95=1500`, `--budget=index.max=4000`, `--budget-file`): the run exits non-zero and the report lists the screens over the limit.
- `--parity` compares each index's first page (row count and record ids, never values) with classic ActiveAdmin. Table rows, cards and grid items carry `data-row-id`.
- Keyboard navigation on index pages: `j`/`k` or the arrow keys move a visible row cursor in the table, card and grid views, `Enter` opens the row, `x` selects it when the resource has batch actions, and `/` focuses the filters. Press `?` for a dialog listing the shortcuts on the current screen.
- The gem ships a prebuilt React client (`gem/vendor/client`, built by `rake package`), so installing it from RubyGems needs no repository checkout and no Node.js. It is stamped with the gem version and manifest `schema_version`, and served only while they match. Builds refer to their own files relatively, so the packaged client works under any `ui.asset_prefix` or CDN, and `RA_ASSET_PREFIX` is gone. `config.ui.client_assets` and a host's own build (`rake reactiveadmin:client:build`) both win over it.
- A `packaged gem` CI job that builds the gem, installs it from a local index and smoke-tests the manifest and the client page.
- A `release` workflow: pushing a `v<version>` tag builds the gem with the client, smoke-tests it, publishes it to RubyGems with trusted publishing after maintainer approval, and creates a GitHub release from the CHANGELOG. The gem now includes the README, LICENSE and CHANGELOG, and lists Form Health as its author.
- `rails generate reactiveadmin:install`, which asks how to start (guided by default: `config.expose = :listed` with a generated `app/admin/menu.rb` listing every registration to prune, and an initializer annotated with `TODO(setup)` notes; quick: `expose :all`; strict: only what's listed, plus the dashboard and anything marked `reactive { expose true }`), which attributes to mask (proposed from `db/schema.rb`), whether to turn on MCP, and who may switch to the new admin, adding the switch to the dashboard. Every answer is also a flag (`--preset`, `--mask`, `--mcp`, `--ui`, `--yes`). It mounts the routes, serves ActiveAdmin's namespace, boots the app to check the setup, and changes nothing when run again.
- Typed react-query hooks per resource (`useListAuthors`) generated from a host's own `rake reactiveadmin:openapi` document with `reactiveadmin-gen`, through the client's `apiFetch`, optionally split by tag. CI generates and typechecks them against the dummy app.
- Rollout telemetry: the client reports caught crashes, names only, to `POST {mount}/admin/_client_errors` (a `client_error.reactiveadmin` event and `config.error_reporter`, in the `client_error` rate-limit bucket), which `config.ui.client_errors = false` turns off, and `rake reactiveadmin:readiness` combines each resource's doctor mode with recent `degraded` and client error counts (`config.event_counts`) as a checklist for leaving classic.
- `rake reactiveadmin:fixtures` records scrubbed JSON fixtures of the manifest, meta, index, show and form payloads from a running app, and `fixtureHandlers` turns them into MSW handlers for Storybook.
- A statement that the client needs React 19.2 or later. A React 18 install fails because React Router 8 and the client use React 19 APIs.
- A unified audit envelope: every audit event is also published as `audit.reactiveadmin` with one schema (kind, user, resource, action, record ids, channel, client id, request id, correlation id, outcome, time, details), and `ReactiveAdmin.on_audit { |event| ... }` subscribes to it. The existing events are unchanged.
- MCP writes carry the tool call's `correlation_id`, `channel: "mcp"` and the token's `client_id` in the envelope.
- Batch-action write events carry the selected ids as `record_ids`.
- `config.audit_views` (default `false`) publishes a `view` envelope for API show and edit reads.
- Switching between the classic and new admin publishes a `ui_switch` envelope.
- Panels' `header_action` (the method form) records as typed `header_actions`, kept through form content and MCP.
- Grid, blog and block index views show a selection checkbox per record when the resource has batch actions.
- `ReactiveAdmin::RSpec.contract_examples` (`require "reactive_admin/rspec"`) runs each registration's meta, index and show against the contract in a host's own suite.

### Changed

- The minimum Rails version is now 8.1.
- The middleware serves the client's page only once `config.ui.available` names who may use it. Until then, upgrading changes nothing, even though a client is now installed.

### Security

These close gaps in the API and change what some clients get. Review them before you upgrade.

- **Disabled nested fields.** A write drops the params of a has_many row's disabled fields, as it already did for top-level fields. A row is held to the saved row its `id` names, or to a new row's fields, whatever index the client sent it at.
- **Mutating GET actions.** GET and HEAD actions stay reads. Declare a GET action that changes data with `reactive { unsafe_gets :name }`: it then needs the write scope, is write-audited, is refused by `api :read_only`, and needs MCP confirmation in `run_action`.
- **MCP is read-only by default (behavior change).** Each resource and page has an MCP mode: `config.mcp.default` (new, `:read_only`) or `reactive { mcp :full | :read_only | :none }`, with `mcp actions: [...]` to let agents run named custom or batch actions on a read-only resource. Agents lose `create_record`, `update_record`, `delete_record`, `get_form` and every `run_action` but GET and HEAD actions not listed in `unsafe_gets` on any resource that doesn't opt in, whatever the token's scopes; add `mcp :full` where agents must write, or set `config.mcp.default = :full` for the old behavior. `:none` leaves a resource out of MCP. `tools/list` hides tools no resource offers, a tool called on a resource whose mode excludes it fails as an unknown resource, and the API refuses MCP-dispatched requests the mode excludes. A mode never widens an `api` guard. `rake reactiveadmin:doctor` adds an "MCP surface" section and warns (`mcp_full_sensitive`) about `:full` on sensitive or masked resources.
- **MCP.** `tools/call` answers a tool the token's scopes hide as an unknown tool. `run_action` runs only the member, collection and batch actions the resource declares, and uses a method the action declares rather than the one the caller asks for.
- **Frames.** A frame form or `data-method` link that isn't a GET is sent, with the session's CSRF token, only to an admin page; anything else is refused, including paths with encoded separators (also inherited from the page URL) or control characters.
- **CSV exports without a `csv` block.** An API export of such a resource takes the attribute columns of its `index` block, or the secure default columns when it has no table index, instead of ActiveAdmin's id and every content column. Columns that an index block computes are no longer exported. The secure default columns leave out encrypted, filtered, masked and binary columns; columns an index block names are the host's choice and aren't filtered, and masked values are exported raw when `mask_csv` is off. Under `strict_defaults` such an export answers `422` unless a table index block supplies the columns. The table index decides the columns whatever `as` view is requested. Classic exports keep their columns. Declare a `csv` block to choose the columns.
- With `mask_csv` on, a masked key nested inside a json column is masked in any export, classic included.
- The CSV formula escaping flag is per request, so concurrent classic and API exports no longer share it.
- **Filter options and conditions.** The options of a filter on a plain column list only values from rows the user may read. A filter hidden by `if:` or `unless:` answers `404` for its options, and the API refuses its `q` keys with `400`. Option cache keys include the user id. A bounded `distinct` scope that doesn't project the column or its primary key offers no options.

### Fixed

- Filter and form option lists that read request params (such as other filters' values) are no longer served from the option cache across different params.
- A native view whose API answers 501 reopens in the frame or iframe the action allows, keeping its dialog or sheet and its query, instead of failing.
- A sort picked in the table view is checked against the table's columns when another index view is shown.
- `openapi/core.yaml` ships in the gem; the OpenAPI document failed to build from an installed gem without it.
- `config.mount_path` is normalized: a trailing slash (`"/api/"`) or a root mount (`""`) no longer breaks prefix checks such as contract lookup and CSV export detection.
- Switching resources no longer shows the previous resource's rows while the next index loads.
- A scope group's label isn't announced twice by screen readers.

## 0.1.0

First public release. The gem and the client are early: interfaces may change before 1.0.

### Added

- A JSON API (`application/vnd.reactiveadmin+json`) served through your ActiveAdmin controllers, so filtering, scoping, sorting, pagination, authentication, authorization and the write path match the classic pages.
- Typed manifests, index, show and form payloads: Arbre component trees become typed nodes, Formtastic forms become typed form schemas (including `has_many` nested rows), and views that can't be represented natively fall back to sanitized HTML or an embedded classic page.
- A generated OpenAPI 3.1 document, filtered to what the requesting admin may access.
- An MCP server (`{mount}/_mcp`) whose tools call the same API, with bearer-token authentication and read and write scopes.
- A registration DSL (`reactive do ... end`) for option sources, masking, query params and API guards, and a menu overlay DSL.
- Security controls: explicit exposure (`config.expose = :listed`), API guards (`api false`, `:deny`, `:read_only`, `:session_only`, custom guards), attribute masking, summarized and tokenized JSON values, rate limits, optimistic locking for edits, and audit notifications that carry ids and no record data.
- Marking a resource as sensitive (`config.sensitive_resources`, `reactive { sensitive true }`) so that typeahead, option and label lookups that return its records publish a `lookup.reactiveadmin` event.
- `rake reactiveadmin:doctor`, `reactiveadmin:legacy` and `reactiveadmin:styles` to measure how much of an admin renders natively and what still depends on classic ActiveAdmin.
- A React client (Vite, TypeScript, Tailwind CSS, shadcn/ui, TanStack Table, React Query, orval) with filter bars, scope tabs, batch and member actions, typeahead and date controls, a JSON editor, a command menu, light and dark themes, and Storybook stories checked with axe.
- Serving the client at the classic admin's URLs, chosen per person by a cookie (`config.ui`, `reactiveadmin_ui_toggle`, `rake reactiveadmin:client:build`).
- An end-to-end crawl (`pnpm crawl`, `pnpm crawl:dummy`) that visits every screen the manifest describes.
- CI for the gem (Standard Ruby, an RSpec matrix over the default, custom and Pundit authorization adapters on SQLite and PostgreSQL) and for the client (contract drift, types, lint, tests, builds, Storybook, accessibility, crawl).

### Naming

The sensitive-data feature was named after one kind of sensitive data during development. It is now generic, and there is no alias for the old names:

- `config.phi_resources` is now `config.sensitive_resources`.
- `reactive { phi true }` and `reactive { phi false }` are now `reactive { sensitive true }` and `reactive { sensitive false }`.
- The `phi` option stored in a registration's `reactive_options` is now `sensitive`.
- The internal `ReactiveAdmin::LookupAudit.phi?` is now `sensitive?`.
- The OpenAPI descriptions of the JSON value endpoint now say that it is audited as a sensitive-data view. The `lookup.reactiveadmin` notification and its payload are unchanged.
