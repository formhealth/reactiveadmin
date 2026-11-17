# Getting started

ReactiveAdmin serves the ActiveAdmin resources in your Rails app as a JSON API, and it ships a React client that renders them. Your ActiveAdmin registrations stay the source of truth. This guide walks you through adding the gem to an existing app and running the client against it.

## Requirements

- Ruby 3.4 or later.
- Rails 8.1 or later.
- ActiveAdmin 3.5. ActiveAdmin 4 isn't supported yet.
- Node.js 24 and pnpm only to build the client from source; the released gem ships it prebuilt.

## Install the gem

Add the gem from RubyGems:

```sh
bundle add reactiveadmin
```

To work against a local checkout instead, use a path:

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

## Run the install generator

```sh
bin/rails generate reactiveadmin:install
```

In a terminal, the generator asks four questions. Each has a default and a matching flag, so scripts, CI and agents can run it without prompts (`--yes` takes every default).

| Question | Flag | Choices (default first) |
| --- | --- | --- |
| How should ReactiveAdmin start? | `--preset` | `guided`, `quick`, `strict` |
| Attributes to mask everywhere in the API | `--mask=a,b`, `--no-mask` | the secrets it finds in `db/schema.rb` |
| Turn on the MCP endpoint for AI agents? | `--mcp` | `off`, `read_only`, `full` |
| Who may switch to the new admin? | `--ui` | `nobody`, `admins`, `everyone` |

The presets decide what the API serves:

- **guided** sets `config.expose = :listed` and writes `app/admin/menu.rb`, a `ReactiveAdmin.menu` that lists every registration in `app/admin`. The API serves only what stays in it, so you prune it. The initializer lists every setting with its default and a `TODO(setup)` note on each one to decide, so you can work through it yourself or hand it to an agent.
- **quick** sets `config.expose = :all`: everything ActiveAdmin registers is served, with the secure defaults. The initializer is short and there's no menu.
- **strict** is guided with the menu's lines commented out and `config.strict_defaults = true`, so a section without a block shows no columns. Until you uncomment lines, the API serves only the namespace's root page (the dashboard) and anything marked `reactive { expose true }` or placed by a menu hint.

The rest of the generator:

- **Masking.** It reads `db/schema.rb` and proposes `config.masked_attributes` for secrets and identity numbers (tokens, keys, dates of birth, SSNs) that Rails' `filter_parameters` doesn't already cover. It names contact details such as emails and phone numbers without proposing them, since operators usually need to see them.
- **MCP.** `read_only` and `full` turn on `config.mcp.enabled` and set `config.mcp.default`, and leave a `TODO(setup)` for the bearer tokens agents sign in with. `full` warns that agents can then write wherever your policy allows.
- **The new admin.** `admins` and `everyone` set `config.ui.available` and add the switch (`text_node reactiveadmin_ui_toggle`) to the `content` block of `app/admin/dashboard.rb`.
- **Routes.** It adds `ReactiveAdmin.routes(self)` after `ActiveAdmin.routes(self)` in `config/routes.rb`.
- **Authorization.** When Pundit or CanCanCan is bundled but ActiveAdmin doesn't use its adapter, it warns, since ReactiveAdmin authorizes through ActiveAdmin's `config.authorization_adapter`. It doesn't change `config/initializers/active_admin.rb`.
- **Namespace.** It serves the namespace `config/initializers/active_admin.rb` sets, or `--namespace NAME`. It writes nothing for the root namespace, or for an assignment it can't read, until you pass `--namespace`.
- **A boot check.** It boots the app and prints how many resources and pages the API serves (`--skip-check` skips it), then the next steps.

Running it again changes nothing: it keeps an existing initializer (`reactive_admin.rb` or `reactiveadmin.rb`) and menu, and doesn't mount the routes or add the switch twice.

### Set it up by hand

To skip the generator, create `config/initializers/reactive_admin.rb`:

```ruby
ReactiveAdmin.configure do |config|
  config.namespace = :admin
  config.mount_path = "/api"
end
```

`namespace` names the ActiveAdmin namespace to serve. `mount_path` is the prefix for the API. With these values, the API lives under `/api/admin`. See [Configuration](configuration.md) for every option.

Then, in `config/routes.rb`, call `ReactiveAdmin.routes(self)` after `ActiveAdmin.routes(self)`:

```ruby
Rails.application.routes.draw do
  ActiveAdmin.routes(self)
  ReactiveAdmin.routes(self)
end
```

The gem redraws your ActiveAdmin routes under the mount path. It answers in its own format, so the classic admin is unaffected.

## Check the mount

Start Rails on port 3003:

```sh
bin/rails server -p 3003
```

To check the mount, sign in to the classic admin at `http://localhost:3003/admin` and open `http://localhost:3003/api/admin/_manifest`. The manifest lists every resource the API serves.

## Understand authentication and authorization

ReactiveAdmin doesn't add its own login. It uses the ActiveAdmin setup you already have:

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
