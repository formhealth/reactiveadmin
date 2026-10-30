# reactiveadmin

reactiveadmin serves your existing [ActiveAdmin](https://activeadmin.info) registrations as a JSON API with an OpenAPI description and an MCP server, and it ships a React admin client that renders them. Your ActiveAdmin resources stay the source of truth: reactiveadmin reuses their controllers, filters, scopes, forms, actions and authorization, and adds the API and the UI on top.

## Status

Version 0.1.0. This is early software: the gem and the client aren't published to RubyGems or npm, and their interfaces may change before 1.0. See the [changelog](CHANGELOG.md).

## Requirements

| Tool | Version |
| --- | --- |
| Ruby | 3.4 or later |
| Rails | 7.2 or later |
| ActiveAdmin | 3.5 or later in the 3.x line (ActiveAdmin 4 isn't supported yet) |
| Node.js | 24, to build the client (`.nvmrc`) |
| pnpm | 8.14.1 (`corepack enable`) |

The host app doesn't need Node.js at runtime. Build the client once at deploy time.

## Install

The gem installs from GitHub. Point Bundler at the gemspec in the `gem/` directory:

```ruby
gem "reactiveadmin", github: "formhealth/reactiveadmin", glob: "gem/*.gemspec"
```

## Quick start

```ruby
# config/initializers/reactive_admin.rb
ReactiveAdmin.configure do |config|
  config.namespace = :admin
  config.mount_path = "/api"
end

# config/routes.rb
Rails.application.routes.draw do
  ActiveAdmin.routes(self)
  ReactiveAdmin.routes(self)
end
```

With your app on port 3003 and a signed-in classic admin session, `http://localhost:3003/api/admin/_manifest` lists every resource the API serves. Add `reactive do ... end` blocks to resources that need hints; see the [DSL reference](docs/guide/dsl.md).

## Build and serve the client

For development, run the client against your app:

```sh
pnpm install
pnpm dev   # http://localhost:5174, proxying to localhost:3003
```

For production, build the client and let the gem serve it at your classic admin's URLs, switched per person by a cookie:

```sh
bin/rails reactiveadmin:client:build
```

[Roll out the new admin](docs/guide/rollout.md) covers the build, configuration and ramp-up.

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
- [Testing](docs/guide/testing.md): the end-to-end crawl
- [Contributing](CONTRIBUTING.md)

## Security notes

reactiveadmin keeps ActiveAdmin's authentication and authorization and adds guards of its own, but it exposes your data through a new API surface. Before you serve a resource that holds sensitive data, read the [security guide](docs/guide/security.md): set `config.expose = :listed`, declare explicit `index` and `show` blocks, mask credentials, and subscribe to the audit events. Report vulnerabilities privately; see [SECURITY.md](SECURITY.md).

## License

[MIT](LICENSE)
