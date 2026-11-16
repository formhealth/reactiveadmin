# Roadmap

This page describes where reactiveadmin is heading. It's a statement of direction, not a commitment to dates. Track the details in the linked [issues](https://github.com/formhealth/reactiveadmin/issues) and [pull requests](https://github.com/formhealth/reactiveadmin/pulls).

## In progress

- **Security hardening:** limit API CSV export to index columns ([#42](https://github.com/formhealth/reactiveadmin/pull/42)), MCP tool visibility, declared actions, and `unsafe_gets` for mutating GET actions ([#43](https://github.com/formhealth/reactiveadmin/pull/43)), scope filter options and honor filter conditions ([#44](https://github.com/formhealth/reactiveadmin/pull/44)), hold API writes to the fields of their form ([#45](https://github.com/formhealth/reactiveadmin/pull/45)), and send frame writes only to admin pages ([#46](https://github.com/formhealth/reactiveadmin/pull/46)).
- **Correctness and CI:** fix stale index rows, the packaged contract and strict contract checks ([#24](https://github.com/formhealth/reactiveadmin/pull/24)); test Rails 7.2 and audit dependencies ([#23](https://github.com/formhealth/reactiveadmin/pull/23)).
- **Refactors:** the custom-action contract, the generated client and the adapter boundary ([#26](https://github.com/formhealth/reactiveadmin/pull/26)).
- **Install generator:** `rails g reactiveadmin:install` ([#47](https://github.com/formhealth/reactiveadmin/issues/47)).
- **Packaging:** publish the gem and the client.
- **MCP:** per-resource opt-in, and agent tools.
- **Audit:** a unified audit event envelope.
- **Extensibility:** typed hooks for each resource.
- **Testing and rollout:** crawl as a host tool, rollout telemetry, and `record_fixtures`.

## Later

- User table customization: show or hide columns, order, width and density.
- Table keyboard navigation and a `?` help screen.
- Row-hover prefetch.
- ActiveAdmin 4 support.
- Changesets for release notes.
- React 18 support.
- Deferred: a compliance report.
- Deferred: a CI gate for host apps.

## Suggest a change

[Open an issue](https://github.com/formhealth/reactiveadmin/issues/new) to propose or discuss an item. See [Contributing](CONTRIBUTING.md).
