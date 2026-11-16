# Changelog

All notable changes to this project are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project aims to follow [Semantic Versioning](https://semver.org/) from 1.0.

## Unreleased

### Security

These close gaps in the API and change what some clients get. Review them before you upgrade.

- **Mutating GET actions.** GET and HEAD actions stay reads. Declare a GET action that changes data with `reactive { unsafe_gets :name }`: it then needs the write scope, is write-audited, is refused by `api :read_only`, and needs MCP confirmation in `run_action`.
- **MCP.** `tools/call` answers a tool the token's scopes hide as an unknown tool. `run_action` runs only the member, collection and batch actions the resource declares, and uses a method the action declares rather than the one the caller asks for.

### Added

- A unified audit envelope: every audit event is also published as `audit.reactiveadmin` with one schema (kind, user, resource, action, record ids, channel, client id, request id, correlation id, outcome, time, details), and `ReactiveAdmin.on_audit { |event| ... }` subscribes to it. The existing events are unchanged.
- MCP writes carry the tool call's `correlation_id`, `channel: "mcp"` and the token's `client_id` in the envelope.
- Batch-action write events carry the selected ids as `record_ids`.
- `config.audit_views` (default `false`) publishes a `view` envelope for API show and edit reads.
- Switching between the classic and new admin publishes a `ui_switch` envelope.

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
