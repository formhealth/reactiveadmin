# ReactiveAdmin

ReactiveAdmin serves your existing [ActiveAdmin](https://activeadmin.info) registrations as a JSON API with an OpenAPI description and an MCP server, and it ships a React admin client that renders them. Your ActiveAdmin resources stay the source of truth: ReactiveAdmin reuses their controllers, filters, scopes, forms, actions and authorization, and adds the API and the UI on top.

Website and docs: <https://formhealth.github.io/reactiveadmin/>, with a [demo](https://formhealth.github.io/reactiveadmin/demo/) that runs on sample data and a [Storybook](https://formhealth.github.io/reactiveadmin/storybook/) of the client's components.

## Status

Version 0.2.1. This is early software: interfaces may change before 1.0. See the [changelog](CHANGELOG.md).

## Requirements

| Tool | Version |
| --- | --- |
| Ruby | 3.4 or later |
| Rails | 8.1 or later |
| ActiveAdmin | 3.5 or later in the 3.x line (ActiveAdmin 4 isn't supported yet) |
| Node.js | 24, only to build the client from a source checkout (`.nvmrc`) |
| pnpm | 8.14.1, likewise (`corepack enable`) |

The released gem ships the client prebuilt, so a host installed from RubyGems needs no Node.js. Only a source checkout builds it.

The client bundles its own React 19.2 or later, so a host that runs React 18 elsewhere is unaffected. React 18 isn't supported: see [Custom components](docs/guide/custom-views.md#register-a-custom-component).

## Install

```sh
bundle add reactiveadmin
```

The gem ships a prebuilt client, so the host needs no Node.js.

## Quick start

```sh
bin/rails generate reactiveadmin:install
```

The generator writes `config/initializers/reactive_admin.rb` with secure defaults (`config.expose = :listed`, `implicit_defaults = :secure`), adds `ReactiveAdmin.routes(self)` after `ActiveAdmin.routes(self)` in `config/routes.rb`, and prints the next steps. Running it again changes nothing. With `expose = :listed`, the API serves only the resources you place in `ReactiveAdmin.menu` or list in `config.exposed_resources`; see [Security](docs/guide/security.md#exposure).

With your app on port 3003 and a signed-in classic admin session, `http://localhost:3003/api/admin/_manifest` lists every resource the API serves. Add `reactive do ... end` blocks to resources that need hints; see the [DSL reference](docs/guide/dsl.md).

## Build and serve the client

For development, run the client against your app:

```sh
pnpm install
pnpm dev   # http://localhost:5174, proxying to localhost:3003
```

In production the gem serves the prebuilt client at your classic admin's URLs, switched per person by a cookie, once you set `config.ui.available`. [Roll out the new admin](docs/guide/rollout.md) covers the configuration and ramp-up. From a source checkout, build the client first:

```sh
bin/rails reactiveadmin:client:build
```

## Documentation

- [Overview](docs/guide/overview.md): why the project exists, what it reuses from ActiveAdmin, and where it stops
- [Getting started](docs/guide/getting-started.md)
- [Configuration](docs/guide/configuration.md)
- [DSL reference](docs/guide/dsl.md)
- [ActiveAdmin support](docs/guide/activeadmin-support.md)
- [Custom views](docs/guide/custom-views.md)
- [Doctor](docs/guide/doctor.md): measure how much of your admin renders natively
- [OpenAPI](docs/guide/openapi.md)
- [MCP server](docs/guide/mcp.md)
- [Security](docs/guide/security.md)
- [Rolling out the new admin](docs/guide/rollout.md)
- [Testing](docs/guide/testing.md): the end-to-end crawl, contract examples for your request specs, and fixtures for Storybook
- [Roadmap](ROADMAP.md)
- [Contributing](CONTRIBUTING.md)

## Security notes

ReactiveAdmin keeps ActiveAdmin's authentication and authorization and adds guards of its own, but it exposes your data through a new API surface. Before you serve a resource that holds sensitive data, read the [security guide](docs/guide/security.md): set `config.expose = :listed`, declare explicit `index` and `show` blocks, mask credentials, and subscribe to the audit events. Report vulnerabilities privately; see [SECURITY.md](SECURITY.md).

## License

[MIT](LICENSE)
