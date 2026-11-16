# Changelog

All notable changes to this project are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project aims to follow [Semantic Versioning](https://semver.org/) from 1.0.

## Unreleased

### Added

- **MCP agent workflow tools.** `count_records` returns the total and per-scope counts for filters and a scope, through the index's own guards, with no rows. `update_record` takes `dry_run: true` and returns each field's `from` and `to` without saving; it is the API's `PATCH ... dry_run`, validated inside a rolled-back transaction, with masked values hidden and no `write` audit event. It previews only plain attributes the form offers a control for, and in-memory nested rows, and `dry_run` is refused anywhere but update. `prompts/list` and `prompts/get` serve three runbooks (`find_record`, `review_recent_changes`, `bulk_update`), offered only when the token can use the tools they name, and `initialize` advertises the `prompts` capability.

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

### Added

- A unified audit envelope: every audit event is also published as `audit.reactiveadmin` with one schema (kind, user, resource, action, record ids, channel, client id, request id, correlation id, outcome, time, details), and `ReactiveAdmin.on_audit { |event| ... }` subscribes to it. The existing events are unchanged.
- MCP writes carry the tool call's `correlation_id`, `channel: "mcp"` and the token's `client_id` in the envelope.
- Batch-action write events carry the selected ids as `record_ids`.
- `config.audit_views` (default `false`) publishes a `view` envelope for API show and edit reads.
- Switching between the classic and new admin publishes a `ui_switch` envelope.

### Fixed

- Filter and form option lists that read request params (such as other filters' values) are no longer served from the option cache across different params.

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
