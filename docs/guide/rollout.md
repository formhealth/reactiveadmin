# Roll out the new admin

ReactiveAdmin can serve the React client at your classic admin's own URLs. `/admin/authors/123` opens the classic page or the new one, depending on a cookie in the browser. People switch with one click, and you decide who can.

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

### 1. Build the client (source checkouts only)

The gem from RubyGems ships a prebuilt client and serves it with no build step, under any `ui.asset_prefix`, as long as you set no `ui.client_assets`. Skip to step 2.

From a git checkout, build the client when you deploy, not at runtime; the host still needs no Node.js in production. A build of your own in `public/reactiveadmin` (this step's default output) is served over the packaged one, and so is `ui.client_assets`.

```sh
bin/rails reactiveadmin:client:build
```

The task builds from this repository's `apps/standalone` (it needs Node.js 24 and pnpm, which Bundler's git checkout doesn't install for you) and writes the files to `public/reactiveadmin/`. Add the task to your image build, after `bundle install` and before the app starts:

- To change the directory, set `config.ui.client_assets`, or pass `OUT=path` (it must be inside the app).
- To read the sources from somewhere else, set `REACTIVEADMIN_CLIENT_SRC`.
- To build without Rails, run `RA_OUT_DIR=/path pnpm --filter standalone build:host`.

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

Between steps, [watch the rollout](#watch-the-rollout) to see which resources are ready.

### How `ui.default` takes effect

The server never writes the cookie, so the default can only apply where script runs before the first page. That is the panel's `uiToggle` script on the classic page: with `default` set to `new`, a browser that has no `reactiveadmin_ui` cookie and no `classic=1` in the URL gets `new` stored and the page reloads into the client. Put `reactiveadmin_ui_toggle` on the pages people land on (the dashboard, or a shared layout partial). A person who never loads a page with the panel stays in classic until they choose.

## Serve the files

The shell loads the build from `ui.asset_prefix`. Three ways to serve it:

- **Your static file server.** Files in `public/reactiveadmin/` are served by Rails (`config.public_file_server.enabled`) or by your proxy, before the gem sees the request.
- **The gem.** When nothing else answers, the gem serves the directory at the prefix. Hashed files under `assets/` are cached for a year, and `manifest.json` isn't.
- **A CDN.** Upload the build (the packaged one is in the gem's `vendor/client`) and set `ui.asset_prefix` to its absolute URL. A build refers to its own files relatively, so it needs no rebuild for the CDN.

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

## Watch the rollout

Three signals tell you whether a resource is ready to leave classic: what the server fell back to (`degraded.reactiveadmin`), what crashed in the browser (`client_error.reactiveadmin`), and what the doctor measures. `rake reactiveadmin:readiness` puts them side by side.

### Report client errors

In production, when an error boundary catches a crash, the client posts a report to `POST {mount_path}/admin/_client_errors`. Set `config.ui.client_errors = false` to turn this off: the endpoint then answers 404, and the client, which reads the setting from `_session`, sends nothing. In development it logs to the console instead. The report holds names and nothing else:

| Field | Holds |
| --- | --- |
| `error_name` | The error's class name, such as `TypeError`. Never its message. |
| `boundary` | Which boundary caught it: `app`, `route`, `frame`, `iframe` or `node:<type>`. |
| `components` | Component names from React's stack, innermost first, up to 20. |
| `route` | The matched route pattern, such as `/:resource/:id/edit`. Never the URL, its ids or its query. |
| `resource` | The resource or page key. |
| `client_version` | The gem version the client was built with. |
| `request_id` | The `X-Request-Id` of the last API response the client saw, to find the request before the crash in your logs. |

The server keeps a field only if it has the shape of a name: an identifier, a pattern made of known route words and `:params`, a key of a resource the user may see. It drops anything else, so text or a value in one of them doesn't reach your reporter. A report without a usable `error_name` answers 400. Names are as your build leaves them, so a minified build reports short component names.

The endpoint needs a signed-in session (a bearer token answers 403), the CSRF token like any write, and the user's read access to the admin. It answers 204. It is rate limited per user in the `client_error` bucket (10 a minute by default), before the authorization check, and the client sends each distinct failure once per page load, at most five. The limit counts in `Rails.cache`; with a store that can't count, such as the null store, or one that fails, the endpoint fails open and doesn't limit at all.

The server passes the report to `config.error_reporter` as a `ReactiveAdmin::ClientError`, which is shaped like a `ScrubbedError`: `original_class` is the JavaScript error name, the backtrace lists the component names, and the message names only the error and the route. The context holds `resource`, `action` (`"client"`), `request_id` (the report's own), `client_request_id`, `error_class`, `boundary`, `route` and `client_version`.

It also publishes `client_error.reactiveadmin` with the same keys, `components`, and the signed-in `user_id`:

```ruby
ActiveSupport::Notifications.subscribe("client_error.reactiveadmin") do |*, payload|
  StatsD.increment("reactiveadmin.client_error", tags: ["resource:#{payload[:resource]}", "route:#{payload[:route]}", "version:#{payload[:client_version]}"])
end
```

A `client_version` that differs from the gem's `ReactiveAdmin::VERSION` means a browser is running an older client build against a newer server, or the other way round.

### Count events for the readiness report

The gem doesn't store events. To show recent `degraded` and `client_error` counts in the readiness report, record them where you already keep metrics, then give the gem a way to read them back. This sketch counts per day in a shared cache (Redis or Memcached, so that every process adds to the same number). Those stores keep `increment` counters raw, so read them with `raw: true`, or a counter can read as a miss and count as zero:

```ruby
%w[degraded client_error].each do |name|
  ActiveSupport::Notifications.subscribe("#{name}.reactiveadmin") do |*, payload|
    next if ReactiveAdmin::Degradation.synthetic?(payload)

    Rails.cache.increment("reactiveadmin:#{name}:#{payload[:resource]}:#{Date.current}", 1, expires_in: 8.days)
  end
end

ReactiveAdmin.configure do |config|
  config.event_counts = lambda do |event, resource|
    name = event.delete_suffix(".reactiveadmin")
    (0...7).sum { |days_ago| Rails.cache.read("reactiveadmin:#{name}:#{resource}:#{Date.current - days_ago}", raw: true).to_i }
  end
end
```

`synthetic?` skips events that aren't a user's screen: the doctor's own samples, which the readiness task runs first and which carry `synthetic: true`, and OpenAPI builds (`action: "openapi"`). Without it, running the report counts its own sampling. Store `payload[:resource]` as it comes. The two events name the resource differently (`degraded` by model name, such as `Post`, and `client_error` by route key, such as `posts`), and `event_counts` is called with the same form for each. The window is yours: the lambda decides what "recent" means. A lambda that returns `nil` or raises counts as "not recorded".

### Check readiness

```sh
bin/rails reactiveadmin:readiness
```

The task runs the [doctor](doctor.md) and adds a verdict per resource and page. Set `doctor_user` so it can sample. `FORMAT=json` prints the data, and `SAMPLE=0` reads code only.

| Mode | Meaning |
| --- | --- |
| `native` | Every view is typed, and nothing was left out. |
| `degraded` | It renders natively, but has html leaves or filters that couldn't be built. |
| `fallback` | An action renders through a frame or iframe, or a sample failed to render. |

Each row has a checklist, and a resource is ready when no check fails:

- **Typed views.** No action renders through a frame or iframe.
- **Samples render.** The doctor's index, show and form samples (or the page) succeeded. `unknown` without a `doctor_user`, or when no sample had anything to inspect (an empty table, no record to show); the detail names the sections it couldn't inspect.
- **No html leaves.** Everything on the screens is a typed node.
- **All filters built.** No declared filter was skipped.
- **No degraded events.** `config.event_counts` reports zero. `unknown` until you set it.
- **No client errors.** The same, for `client_error.reactiveadmin`.

An `unknown` check doesn't block a resource, and it doesn't pass either: the output counts them next to `ready`. The report also lists what the gem can't see. Who still uses classic, and whether operators can do their work in the new admin, are questions for your request logs (the `reactiveadmin_ui` cookie) and for the people using it.

## Limits

- The client reaches the API at `{mount_path}/admin`. Namespaces other than `admin` aren't supported by the client yet.
- The shell is served before Rails routes the request, so your controllers' callbacks and page-view tracking for ActiveAdmin don't run for it. They do run for the client's API requests, which go through the same controllers, and those are audited as usual.
- The shell's title is "Admin" until the client sets the site's title.
- During development, the client runs on its own dev server at the root (`/authors`), proxying to Rails. Set `VITE_ROUTER_BASE` or `VITE_ADMIN_PATH` to change that. The shell sets both itself.
