# Getting started

reactiveadmin serves the ActiveAdmin resources in your Rails app as a JSON API, and it ships a React client that renders them. Your ActiveAdmin registrations stay the source of truth. This guide walks you through adding the gem to an existing app and running the client against it.

## Requirements

- Ruby 3.4 or later.
- Rails 7.2 or later.
- ActiveAdmin 3.5, or any 3.x release. The gem doesn't support ActiveAdmin 4 yet.
- Node.js and pnpm, for the client.

## Install the gem

Add the gem to your app's `Gemfile`. Use a path while you develop against a local checkout:

```ruby
gem "reactiveadmin", path: "../reactiveadmin/gem"
```

To pull it from GitHub instead, point Bundler at the gemspec:

```ruby
gem "reactiveadmin", github: "formhealth/reactiveadmin", glob: "gem/*.gemspec"
```

Then install the bundle:

```sh
bundle install
```

## Configure the namespace and mount path

Create `config/initializers/reactive_admin.rb`:

```ruby
ReactiveAdmin.configure do |config|
  config.namespace = :admin
  config.mount_path = "/api"
end
```

`namespace` names the ActiveAdmin namespace to serve. `mount_path` is the prefix for the API. With these values, the API lives under `/api/admin`. See [Configuration](configuration.md) for every option.

## Mount the routes

In `config/routes.rb`, call `ReactiveAdmin.routes(self)` after `ActiveAdmin.routes(self)`:

```ruby
Rails.application.routes.draw do
  ActiveAdmin.routes(self)
  ReactiveAdmin.routes(self)
end
```

The gem redraws your ActiveAdmin routes under the mount path. It answers in its own format, so the classic admin is unaffected.

Start Rails on port 3003:

```sh
bin/rails server -p 3003
```

To check the mount, sign in to the classic admin at `http://localhost:3003/admin` and open `http://localhost:3003/api/admin/_manifest`. The manifest lists every resource the API serves.

## Understand authentication and authorization

reactiveadmin doesn't add its own login. It uses the ActiveAdmin setup you already have:

- **Authentication** runs through `config.authentication_method`. A request that fails authentication returns `401` with a JSON body, not a redirect.
- **Authorization** runs through `config.authorization_adapter`, the same adapter that protects your classic pages. The default adapter and `ActiveAdmin::PunditAdapter` both work. Each endpoint checks the same permission the classic page checks.
- **Sessions** use the session cookie. The client and the API share an origin, so the cookie is sent with every request. In development, the Vite proxy keeps the origin the same.
- **CSRF** protection is on for writes. The client fetches a token from `GET /api/admin/_session` and sends it as the `X-CSRF-Token` header. See [Security](security.md) for details.

## Run the standalone client

The client lives in `apps/standalone`. From the repository root, install dependencies and start the dev server:

```sh
pnpm install
pnpm dev
```

Open `http://localhost:5174/admin` and sign in. Vite proxies `/api`, `/admin`, `/assets`, and `/packs` to `localhost:3003`, so the session cookie works without changes.

To regenerate the API client after you change `openapi/core.yaml`, run:

```sh
pnpm gen
```

Don't edit files in `apps/standalone/src/api/generated` by hand.

### Run with mocks

You can run the client without Rails. MSW serves fixtures from `apps/standalone/src/mocks`:

```sh
pnpm dev:mocks
```

Mocks cover the manifest, index, show, forms, and writes. Writes don't persist.

### Set the sign-in URL

When the API returns `401`, the client shows a "Sign in" link. In development it points to `http://localhost:3003/sign_in`. Set `VITE_SIGN_IN_URL` to change it:

```sh
VITE_SIGN_IN_URL=http://localhost:3003/admin/login pnpm dev
```

## Work with Storybook

Storybook renders the node renderers and the page views against the MSW mocks:

```sh
pnpm --filter standalone storybook
```

Open `http://localhost:6006`. Stories live next to their components as `*.stories.tsx`. Use the toolbar to switch between light and dark themes.

## Next steps

- Add `reactive do ... end` blocks to resources that need hints. See [DSL](dsl.md).
- Check how much of your admin the API covers. See [Doctor](doctor.md).
- Read [ActiveAdmin support](activeadmin-support.md) to learn which constructs work today.
- Serve the client at your classic admin's URLs, and let people switch. See [Roll out the new admin](rollout.md).
