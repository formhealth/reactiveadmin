# Roll out the new admin

reactiveadmin can serve the React client at your classic admin's own URLs. `/admin/authors/123` opens the classic page or the new one, depending on a cookie in the browser. People switch with one click, and you decide who can.

The server stays out of the decision. A small Rack middleware answers a page load with the client's shell when the browser's `reactiveadmin_ui` cookie says `new`. The client then checks with the API whether this user can use it and whether it has a screen for the URL, and sends the browser back to classic when it doesn't.

## How it works

The middleware serves the shell when all of these are true. Otherwise the request goes to the classic admin, untouched.

- The cookie `reactiveadmin_ui` is `new`.
- The request is a `GET` or `HEAD` for a page load: `Sec-Fetch-Dest: document`, or, where the browser sends none, an `Accept` header that includes `text/html` and no `X-Requested-With: XMLHttpRequest`.
- The path is the admin namespace (`/admin`) or below it, and has no file extension (`posts.csv` is a download, not a page).
- The URL has no `classic=1` (the per-request escape hatch) or `embed=1` (the iframe fallback).
- A client build is installed.

The shell is the same static page for everyone, so the middleware knows nothing about resources, guards, users or authorization. Every record still comes through the API with its authorization, exposure, `api` guards and audit.

The client decides the rest, on load:

| Situation | The client |
| --- | --- |
| `_session` says `ui.available` is false | Clears the cookie and loads the same URL with `classic=1`. |
| `_session` answers 401 (signed out) | Loads the same URL with `classic=1`, where the host asks the user to sign in. |
| The manifest has no screen for the URL: an unlisted resource or page, an action the resource lacks, a nested resource, a member action | Loads the same URL with `classic=1`. |
| A resource, page or action that an `api` guard refuses (`api_denied`) | Loads the same URL with `classic=1`. |
| Anything else | Renders. |

After signing in, the user lands on that one classic page, because the host remembers the URL it sent them from, `classic=1` included. Their next page load is the new admin again.

The cookie is plain and readable by scripts, with `Path=/` and `SameSite=Lax` (and `Secure` over HTTPS). It holds a preference and nothing else. Setting it by hand does no more than choosing the new admin through the account menu.

### Why a cookie

A browser can't add a header to a page load, and a request that is a link click or a typed URL carries nothing but what the browser decides to send. A cookie is the one thing it sends back on its own. The server doesn't sign or store it: the choice has no authority, because the API authorizes every request itself. `ui.available` is a gate on the interface, not a security boundary.

## Steps

### 1. Build the client

The client is a Vite build. Build it when you deploy, not at runtime. The host needs no Node.js in production.

```sh
bin/rails reactiveadmin:client:build
```

The task builds from this repository's `apps/standalone` (it needs Node.js 24 and pnpm, which Bundler's git checkout doesn't install for you) and writes the files to `public/reactiveadmin/`. Add the task to your image build, after `bundle install` and before the app starts:

- To change the directory, set `config.ui.client_assets`, or pass `OUT=path` (it must be inside the app).
- To read the sources from somewhere else, set `REACTIVEADMIN_CLIENT_SRC`.
- To build without Rails, run `RA_OUT_DIR=/path RA_ASSET_PREFIX=/reactiveadmin/ pnpm --filter standalone build:host`.

The output holds hashed files under `assets/` and a `manifest.json`. The middleware reads the manifest on each request, so a new build takes effect without a restart. Without a build, the middleware does nothing.

### 2. Configure

```ruby
ReactiveAdmin.configure do |config|
  config.ui.available = ->(user) { user.admin? }
  config.ui.default = :classic
end
```

Use any check you like, such as a feature flag. It runs for every `GET /api/admin/_session`, so keep it cheap. If it raises, the user counts as unavailable.

| Option | Default | Purpose |
| --- | --- | --- |
| `ui.available` | nobody | `->(user) { boolean }`. Who may use the new admin and switch between the two. Reported in `_session`. |
| `ui.default` | `:classic` | `:classic`, `:new`, or `->(user) { mode }`. The UI to start an available user in, until they choose. Reported in `_session`. |
| `ui.enabled` | `true` | Set to `false` to take the middleware out of the request path. |
| `ui.client_assets` | `public/reactiveadmin` | The directory of the build. A path, or a callable that returns one. |
| `ui.asset_prefix` | `"/reactiveadmin"` | The URL prefix of the built files. |

Restart Rails. With `available` unset, no one is offered the switch and anyone who sets the cookie is sent back to classic.

### 3. Add the switch to the classic dashboard

Render the panel where people will see it, such as the dashboard:

```ruby
ActiveAdmin.register_page "Dashboard" do
  content do
    text_node reactiveadmin_ui_toggle
    # ...
  end
end
```

In an ERB partial, use `<%= reactiveadmin_ui_toggle %>`. The panel renders only for available users, on classic pages outside the client's frames, and only when a build is installed. Its button runs the build's `uiToggle` script, which sets the cookie and loads the same page again. The script is a separate entry of the client build, so the host serves it like the other files. It carries the request's CSP nonce.

In the new admin, people switch back from the account menu ("Use classic admin") and from the welcome page. Both appear only when `GET /api/admin/_session` reports `ui.available`. A switch to classic stores `reactiveadmin_ui=classic`, not an absence, so a `default` of `:new` doesn't pull the person back.

### 4. Ramp up

1. Turn the flag on for your team. They try the new admin from the dashboard.
2. Widen the flag. Users who haven't chosen keep the classic admin, because `default` is `:classic`.
3. To move everyone you've made available, set `config.ui.default = :new`. A person's own choice still wins.
4. When the classic admin is retired, drop the switch and serve the client alone.

### How `ui.default` takes effect

The server never writes the cookie, so the default can only apply where script runs before the first page. That is the panel's `uiToggle` script on the classic page: with `default` set to `new`, a browser that has no `reactiveadmin_ui` cookie and no `classic=1` in the URL gets `new` stored and the page reloads into the client. Put `reactiveadmin_ui_toggle` on the pages people land on (the dashboard, or a shared layout partial). A person who never loads a page with the panel stays in classic until they choose.

## Serve the files

The shell loads the build from `ui.asset_prefix`. Three ways to serve it:

- **Your static file server.** Files in `public/reactiveadmin/` are served by Rails (`config.public_file_server.enabled`) or by your proxy, before the gem sees the request.
- **The gem.** When nothing else answers, the gem serves the directory at the prefix. Hashed files under `assets/` are cached for a year, and `manifest.json` isn't.
- **A CDN.** Set `ui.asset_prefix` to the absolute URL and build with the same value, then upload the build.

The files are public and hold no data or secrets. The shell is never cached (`Cache-Control: no-store`), and carries your app's default response headers (`X-Frame-Options` and the like).

### Content Security Policy

The middleware sits innermost in the stack, so your `ActionDispatch::ContentSecurityPolicy` middleware still adds its header to the shell. The shell's script tag carries the request's nonce when Rails generates one (`content_security_policy_nonce_generator`), and works with `script-src 'self'` without one. The client also needs the style and font sources your classic admin already allows. The shell has no inline script.

## Escape hatches

| To | Do this |
| --- | --- |
| See one page classic | Add `?classic=1` to the URL. The client's "Open in classic admin" links do. |
| Embed a classic page | Add `?embed=1`. The client's iframes do. |
| Switch a person back | They choose "Use classic admin", or you make `ui.available` false for them: the client clears their cookie on the next load. |
| Turn it off for everyone | Set `config.ui.enabled = false`, or delete the build directory. Restart Rails for the setting. |

The shell links to the classic page for people without JavaScript.

## Audit and analytics

There is no server event for a switch: the server doesn't take part in it. The cookie arrives with every request under the admin, so log it with your own request logging (`request.cookies["reactiveadmin_ui"]`), or add it to the tracking you already do for page views. The client has no analytics hook to call.

## Limits

- The client reaches the API at `{mount_path}/admin`. Namespaces other than `admin` aren't supported by the client yet.
- The shell is served before Rails routes the request, so your controllers' callbacks and page-view tracking for ActiveAdmin don't run for it. They do run for the client's API requests, which go through the same controllers, and those are audited as usual.
- The shell's title is "Admin" until the client sets the site's title.
- During development, the client runs on its own dev server at the root (`/authors`), proxying to Rails. Set `VITE_ROUTER_BASE` or `VITE_ADMIN_PATH` to change that. The shell sets both itself.
