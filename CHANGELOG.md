# Changelog

All notable changes to this project are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project aims to follow [Semantic Versioning](https://semver.org/) from 1.0.

## Unreleased

### Security

These close gaps in the API and change what some clients get. Review them before you upgrade.

- **CSV exports without a `csv` block.** An API export of such a resource takes the attribute columns of its `index` block, or the secure default columns when it has no table index, instead of ActiveAdmin's id and every content column. Encrypted, filtered, masked and binary columns, and columns that an index block computes, are no longer exported. Under `strict_defaults` such an export answers `422`. Classic exports are unchanged. Declare a `csv` block to choose the columns.
- **GET actions that act.** A GET member, collection or page action that renders no page (it redirects or sends data) is now treated as a write: a bearer token needs the write scope, the write audit records it, `api :read_only` refuses it, and MCP's `run_action` asks for confirmation. Read-scope tokens lose these actions. List an action that only reads in `reactive { safe_gets :name }`. `rake reactiveadmin:doctor` reports them as `get_action_write`.
- **MCP.** `tools/call` answers a tool the token's scopes hide as an unknown tool. `run_action` runs only the member, collection and batch actions the resource declares, and uses a method the action declares rather than the one the caller asks for.
- **Filter options and conditions.** The options of a filter on a plain column list only values from rows the user may read. A filter hidden by `if:` or `unless:` answers `404` for its options, and the API refuses its `q` keys with `400`. Option cache keys include the user id.
- **Writes carry only their form.** A create or update with params that no field of the form accounts for answers `422` with code `invalid` and the param names in `base`. Disabled fields are dropped in nested rows too. Set `config.reject_unknown_params = false` to leave unknown params to `permit_params`.
- **Frames.** A frame form or `data-method` link that isn't a GET is sent, with the session's CSRF token, only to an admin page; anything else is refused.
- The CSV formula escaping flag is per request, so concurrent classic and API exports no longer share it.

### Changed

- **Custom actions in the contract.** `core.yaml` declares GET member actions (`runMemberActionGet`, answering `ActionGetResponse`: a form, page content, options or a redirect's result), lets action writes answer `ActionWriteResponse` (a result or a re-rendered form), and declares their `501 unsupported`. The OpenAPI document gives member, collection and page actions the same responses.
- The minimum Rails version is now 8.1.

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
